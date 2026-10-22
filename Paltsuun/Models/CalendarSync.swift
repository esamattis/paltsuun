import Foundation
import Observation

/// Keeps the local mirrors of remote calendars up to date by syncing them every
/// `AppSettings.syncInterval`, and keeps a log of the syncs.
@Observable
final class CalendarSync {
    /// Wait before retrying after a failed sync, e.g. when the network isn't up yet after wake.
    static let retryInterval: TimeInterval = 60
    /// The log keeps this many of the latest entries.
    static let logLimit = 500

    let providers: [SyncedCalendarProvider]
    private(set) var isSyncing = false
    /// Last sync error per provider ID.
    private(set) var errors: [String: String] = [:]
    /// Syncs of each provider, newest first.
    private(set) var log: [SyncLogEntry] = []
    /// When the next scheduled sync runs.
    private(set) var nextSync: Date?

    /// Called with meetings that were added to a remote calendar since the previous sync.
    @ObservationIgnored var onNewMeetings: (([Meeting]) -> Void)?

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var displayedRange: DateInterval?
    @ObservationIgnored private var syncedInterval: DateInterval?
    @ObservationIgnored private var currentSync: Task<Bool, Never>?
    /// When the last sync finished and whether it succeeded.
    @ObservationIgnored private var lastAttempt: (date: Date, succeeded: Bool)?

    init(providers: [SyncedCalendarProvider], store: MeetingStore) {
        self.providers = providers
        self.store = store
    }

    var hasConnectedSources: Bool {
        providers.contains { $0.source.isConnected }
    }

    var lastError: String? {
        let messages = providers.compactMap { provider in
            errors[provider.id].map { "\(provider.displayName): \($0)" }
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    /// Starts syncing periodically. Call again when the sync interval changes.
    func start() {
        pollTask?.cancel()
        scheduleNextSync()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.nextSync?.timeIntervalSinceNow else { return }
                if delay > 0 {
                    // Checks at least once a minute, so a sync due during system sleep runs soon after wake.
                    try? await Task.sleep(for: .seconds(min(delay, 60)))
                } else {
                    await self?.syncNow(.scheduled)
                }
            }
        }
    }

    /// Syncs meetings in `range` (e.g. the month shown in the calendar) if they aren't yet.
    func setDisplayedRange(_ range: DateInterval) {
        displayedRange = range
        guard hasConnectedSources else { return }
        if let syncedInterval, syncedInterval.start <= range.start, syncedInterval.end >= range.end { return }
        Task { await syncNow(.calendarRange) }
    }

    /// Syncs all connected calendars. Returns false if any of them failed.
    /// If a sync is already running, waits for it and returns its result.
    @discardableResult
    func syncNow(_ trigger: SyncLogEntry.Trigger = .manual) async -> Bool {
        if let currentSync { return await currentSync.value }
        let task = Task { await performSync(trigger) }
        currentSync = task
        isSyncing = true
        let succeeded = await task.value
        currentSync = nil
        isSyncing = false
        lastAttempt = (Date(), succeeded)
        scheduleNextSync()
        return succeeded
    }

    func clearLog() {
        log = []
    }

    private func performSync(_ trigger: SyncLogEntry.Trigger) async -> Bool {
        let interval = syncInterval()
        var succeeded = true
        var newMeetings: [Meeting] = []
        for provider in providers where provider.source.isConnected {
            let started = Date()
            let result: SyncLogEntry.Result
            do {
                let changes = try await provider.sync(in: interval)
                errors[provider.id] = nil
                newMeetings += changes.new
                result = .synced(changes)
            } catch {
                errors[provider.id] = error.localizedDescription
                succeeded = false
                result = .failed(error.localizedDescription)
            }
            let entry = SyncLogEntry(
                date: started, duration: Date().timeIntervalSince(started),
                provider: provider.displayName, trigger: trigger, result: result
            )
            log.insert(entry, at: 0)
            log.removeLast(max(0, log.count - Self.logLimit))
        }
        if succeeded { syncedInterval = interval }
        await store.refresh()
        if !newMeetings.isEmpty { onNewMeetings?(newMeetings) }
        return succeeded
    }

    private func scheduleNextSync() {
        guard let lastAttempt else {
            nextSync = Date()
            return
        }
        nextSync = lastAttempt.date.addingTimeInterval(lastAttempt.succeeded ? AppSettings.syncInterval : Self.retryInterval)
    }

    func connect(_ provider: SyncedCalendarProvider) async throws {
        try await provider.source.connect()
        errors[provider.id] = nil
        syncedInterval = nil
        // A sync that started before connecting doesn't include this provider.
        if let currentSync { _ = await currentSync.value }
        await syncNow(.connected)
    }

    func disconnect(_ provider: SyncedCalendarProvider) async {
        await provider.source.disconnect()
        provider.clear()
        errors[provider.id] = nil
        await store.refresh()
    }

    /// Covers the recent past and the next few months, plus whatever the calendar shows.
    private func syncInterval() -> DateInterval {
        let day: TimeInterval = 24 * 60 * 60
        let now = Date()
        var start = now.addingTimeInterval(-7 * day)
        var end = now.addingTimeInterval(90 * day)
        if let displayedRange {
            start = min(start, displayedRange.start)
            end = max(end, displayedRange.end)
        }
        return DateInterval(start: start, end: end)
    }
}

/// One provider's part of a sync, shown in the sync log.
struct SyncLogEntry: Identifiable {
    enum Trigger: String {
        case scheduled = "Scheduled"
        case manual = "Manual"
        case calendarRange = "Calendar view"
        case connected = "Connected"
    }

    enum Result {
        case synced(SyncChanges)
        case failed(String)
    }

    let id = UUID()
    let date: Date
    let duration: TimeInterval
    let provider: String
    let trigger: Trigger
    let result: Result

    var changes: SyncChanges? {
        if case .synced(let changes) = result { changes } else { nil }
    }
}
