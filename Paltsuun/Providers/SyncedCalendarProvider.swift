import Foundation
import Observation

/// Read-only local mirror of a `RemoteCalendarSource`, stored as JSON in Application Support.
///
/// Meetings are served from the mirror, so they're available offline and between syncs.
/// `sync(in:)` replaces every mirrored meeting in the interval with what the source returns,
/// so meetings changed or deleted in the remote calendar are changed or deleted here too.
@Observable
final class SyncedCalendarProvider: CalendarProvider {
    /// Mirrored meetings that ended longer ago than this are dropped on sync.
    static let retention: TimeInterval = 90 * 24 * 60 * 60

    let source: any RemoteCalendarSource
    private(set) var lastSync: Date?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var meetings: [Meeting]
    /// The interval covered by the last sync, to tell new meetings from ones that came into range.
    @ObservationIgnored private var syncedInterval: DateInterval?

    var id: String { source.id }
    var displayName: String { source.displayName }

    init(source: any RemoteCalendarSource, fileURL: URL? = nil) {
        self.source = source
        self.fileURL = fileURL ?? URL.applicationSupportDirectory.appending(path: "Paltsuun/synced-\(source.id).json")
        let mirror = (try? Data(contentsOf: self.fileURL)).flatMap { try? Self.decoder.decode(Mirror.self, from: $0) }
        meetings = mirror?.meetings ?? []
        lastSync = mirror?.lastSync
        syncedInterval = mirror?.syncedInterval
    }

    func fetchMeetings(in interval: DateInterval) async throws -> [Meeting] {
        meetings.filter { Self.meeting($0, overlaps: interval) }
    }

    /// Replaces the mirrored meetings in `interval` with the source's events and returns what changed.
    func sync(in interval: DateInterval) async throws -> SyncChanges {
        let fetched = try await source.fetchEvents(in: interval)
        // Disconnected while the request was running.
        guard source.isConnected else { return SyncChanges() }

        let previous = Dictionary(meetings.map { ($0.id, $0) }) { first, _ in first }
        let fetchedIDs = Set(fetched.map(\.id))
        var changes = SyncChanges(eventCount: fetched.count)
        for meeting in fetched.sorted(by: { $0.start < $1.start }) {
            if let old = previous[meeting.id] {
                if old != meeting { changes.changed.append(meeting) }
            } else {
                changes.added.append(meeting)
                // Meetings coming into the synced range as it moves forward aren't new.
                if let syncedInterval, Self.meeting(meeting, overlaps: syncedInterval) {
                    changes.new.append(meeting)
                }
            }
        }
        changes.removed = meetings
            .filter { Self.meeting($0, overlaps: interval) && !fetchedIDs.contains($0.id) }
            .sorted { $0.start < $1.start }

        let cutoff = Date().addingTimeInterval(-Self.retention)
        // A meeting moved into the interval from outside it is replaced too.
        meetings = meetings.filter {
            !Self.meeting($0, overlaps: interval) && !fetchedIDs.contains($0.id) && $0.end > cutoff
        } + fetched
        lastSync = Date()
        syncedInterval = interval
        try persist()
        return changes
    }

    /// Forgets all mirrored meetings, e.g. after disconnecting.
    func clear() {
        meetings = []
        lastSync = nil
        syncedInterval = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Same rule as Google Calendar's `timeMin`/`timeMax`: ends after the start, starts before the end.
    private static func meeting(_ meeting: Meeting, overlaps interval: DateInterval) -> Bool {
        meeting.end > interval.start && meeting.start < interval.end
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Mirror(lastSync: lastSync, syncedInterval: syncedInterval, meetings: meetings)).write(to: fileURL, options: .atomic)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private struct Mirror: Codable {
        var lastSync: Date?
        var syncedInterval: DateInterval?
        var meetings: [Meeting]
    }
}

/// What a sync changed in a `SyncedCalendarProvider`'s mirror. Meetings are in start order.
struct SyncChanges {
    /// Events the source returned.
    var eventCount = 0
    var added: [Meeting] = []
    var changed: [Meeting] = []
    var removed: [Meeting] = []
    /// Added meetings inside the interval covered by the previous sync, so they were created
    /// or the user was invited since then. The other added meetings came into the synced range.
    var new: [Meeting] = []

    var isEmpty: Bool {
        added.isEmpty && changed.isEmpty && removed.isEmpty
    }
}
