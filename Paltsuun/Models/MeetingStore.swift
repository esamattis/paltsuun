import Foundation
import Observation

enum MeetingStoreError: LocalizedError {
    case readOnly(String)
    case noEditableProvider

    var errorDescription: String? {
        switch self {
        case .readOnly(let provider): "Meetings from \(provider) can't be edited."
        case .noEditableProvider: "No calendar supports adding meetings."
        }
    }
}

/// Merges meetings from all providers and keeps them fresh by polling.
@Observable
final class MeetingStore {
    private(set) var meetings: [Meeting] = []
    private(set) var lastError: String?

    let providers: [any CalendarProvider]

    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var displayedRange: DateInterval?
    /// Last successful fetch per provider, kept when a later fetch fails.
    @ObservationIgnored private var cache: [String: [Meeting]] = [:]

    init(providers: [any CalendarProvider], pollInterval: Duration = .seconds(60)) {
        self.providers = providers
        self.pollInterval = pollInterval
    }

    var defaultEditableProvider: (any EditableCalendarProvider)? {
        providers.lazy.compactMap { $0 as? any EditableCalendarProvider }.first
    }

    func startPolling() {
        pollTask?.cancel()
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Makes sure meetings in `range` (e.g. the month shown in the calendar) are fetched too.
    func setDisplayedRange(_ range: DateInterval) {
        guard range != displayedRange else { return }
        displayedRange = range
        Task { await refresh() }
    }

    func refresh() async {
        let interval = fetchInterval()
        var errors: [String] = []
        for provider in providers {
            do {
                cache[provider.id] = try await provider.fetchMeetings(in: interval)
            } catch {
                errors.append("\(provider.displayName): \(error.localizedDescription)")
            }
        }
        meetings = cache.values.flatMap { $0 }.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func isEditable(_ meeting: Meeting) -> Bool {
        provider(for: meeting) is any EditableCalendarProvider
    }

    func newMeeting(start: Date, duration: TimeInterval = 30 * 60) -> Meeting? {
        guard let provider = defaultEditableProvider else { return nil }
        return Meeting(id: UUID().uuidString, providerID: provider.id, title: "", start: start, end: start + duration, url: nil)
    }

    func save(_ meeting: Meeting) async throws {
        try await editableProvider(for: meeting).save(meeting)
        await refresh()
    }

    func delete(_ meeting: Meeting) async throws {
        try await editableProvider(for: meeting).delete(meeting)
        await refresh()
    }

    func meetings(on day: Date, calendar: Calendar = .current) -> [Meeting] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return meetings.filter { $0.start < end && ($0.end > start || $0.start == start) }
    }

    /// Meetings that haven't ended yet, leaving out declined ones.
    func upcomingMeetings(after date: Date = Date(), limit: Int) -> [Meeting] {
        Array(meetings.filter { $0.end > date && !$0.isDeclined }.prefix(limit))
    }

    func providerName(for meeting: Meeting) -> String? {
        provider(for: meeting)?.displayName
    }

    private func provider(for meeting: Meeting) -> (any CalendarProvider)? {
        providers.first { $0.id == meeting.providerID }
    }

    private func editableProvider(for meeting: Meeting) throws -> any EditableCalendarProvider {
        guard let provider = provider(for: meeting) else { throw MeetingStoreError.noEditableProvider }
        guard let editable = provider as? any EditableCalendarProvider else {
            throw MeetingStoreError.readOnly(provider.displayName)
        }
        return editable
    }

    /// Always covers the near future needed for reminders, plus whatever the calendar shows.
    private func fetchInterval() -> DateInterval {
        let now = Date()
        var start = now.addingTimeInterval(-24 * 60 * 60)
        var end = now.addingTimeInterval(7 * 24 * 60 * 60)
        if let displayedRange {
            start = min(start, displayedRange.start)
            end = max(end, displayedRange.end)
        }
        return DateInterval(start: start, end: end)
    }
}
