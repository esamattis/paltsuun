import Foundation

/// A source of meetings, e.g. a local store, Google Calendar or CalDAV.
protocol CalendarProvider: AnyObject {
    var id: String { get }
    var displayName: String { get }

    /// Returns timed meetings overlapping `interval`. All-day events should be left out.
    func fetchMeetings(in interval: DateInterval) async throws -> [Meeting]
}

/// A provider whose meetings can be created, changed and deleted from the app.
protocol EditableCalendarProvider: CalendarProvider {
    func save(_ meeting: Meeting) async throws
    func delete(_ meeting: Meeting) async throws
}

/// A calendar service, e.g. Google Calendar, whose events are mirrored locally by
/// `SyncedCalendarProvider`. The service is the source of truth for its events.
protocol RemoteCalendarSource: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var isConnected: Bool { get }
    /// The signed-in account, if known.
    var accountName: String? { get }

    /// Signs in, e.g. with an OAuth flow in the browser.
    func connect() async throws
    func disconnect() async
    /// Returns all timed events overlapping `interval`. Meeting IDs must be prefixed so they
    /// are unique across providers, and `providerID` must be the source's `id`.
    func fetchEvents(in interval: DateInterval) async throws -> [Meeting]
}
