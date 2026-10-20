import Foundation
import Observation

/// Keeps the local mirrors of remote calendars up to date by syncing them periodically.
@Observable
final class CalendarSync {
    static let pollInterval: Duration = .seconds(15 * 60)
    /// Wait before retrying after a failed sync, e.g. when the network isn't up yet after wake.
    static let retryInterval: Duration = .seconds(60)

    let providers: [SyncedCalendarProvider]
    private(set) var isSyncing = false
    /// Last sync error per provider ID.
    private(set) var errors: [String: String] = [:]

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var displayedRange: DateInterval?
    @ObservationIgnored private var syncedInterval: DateInterval?
    @ObservationIgnored private var currentSync: Task<Bool, Never>?

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

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let succeeded = await self?.syncNow() ?? false
                try? await Task.sleep(for: succeeded ? Self.pollInterval : Self.retryInterval)
            }
        }
    }

    /// Syncs meetings in `range` (e.g. the month shown in the calendar) if they aren't yet.
    func setDisplayedRange(_ range: DateInterval) {
        displayedRange = range
        guard hasConnectedSources else { return }
        if let syncedInterval, syncedInterval.start <= range.start, syncedInterval.end >= range.end { return }
        Task { await syncNow() }
    }

    /// Syncs all connected calendars. Returns false if any of them failed.
    /// If a sync is already running, waits for it and returns its result.
    @discardableResult
    func syncNow() async -> Bool {
        if let currentSync { return await currentSync.value }
        let task = Task { await performSync() }
        currentSync = task
        isSyncing = true
        let succeeded = await task.value
        currentSync = nil
        isSyncing = false
        return succeeded
    }

    private func performSync() async -> Bool {
        let interval = syncInterval()
        var succeeded = true
        for provider in providers where provider.source.isConnected {
            do {
                try await provider.sync(in: interval)
                errors[provider.id] = nil
            } catch {
                errors[provider.id] = error.localizedDescription
                succeeded = false
            }
        }
        if succeeded { syncedInterval = interval }
        await store.refresh()
        return succeeded
    }

    func connect(_ provider: SyncedCalendarProvider) async throws {
        try await provider.source.connect()
        errors[provider.id] = nil
        syncedInterval = nil
        // A sync that started before connecting doesn't include this provider.
        if let currentSync { _ = await currentSync.value }
        await syncNow()
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
