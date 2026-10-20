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
