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

    var id: String { source.id }
    var displayName: String { source.displayName }

    init(source: any RemoteCalendarSource, fileURL: URL? = nil) {
        self.source = source
        self.fileURL = fileURL ?? URL.applicationSupportDirectory.appending(path: "Paltsuun/synced-\(source.id).json")
        let mirror = (try? Data(contentsOf: self.fileURL)).flatMap { try? Self.decoder.decode(Mirror.self, from: $0) }
        meetings = mirror?.meetings ?? []
        lastSync = mirror?.lastSync
    }

    func fetchMeetings(in interval: DateInterval) async throws -> [Meeting] {
        meetings.filter { Self.meeting($0, overlaps: interval) }
    }

    func sync(in interval: DateInterval) async throws {
        let fetched = try await source.fetchEvents(in: interval)
        // Disconnected while the request was running.
        guard source.isConnected else { return }
        let cutoff = Date().addingTimeInterval(-Self.retention)
        meetings = meetings.filter { !Self.meeting($0, overlaps: interval) && $0.end > cutoff } + fetched
        lastSync = Date()
        try persist()
    }

    /// Forgets all mirrored meetings, e.g. after disconnecting.
    func clear() {
        meetings = []
        lastSync = nil
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
        try encoder.encode(Mirror(lastSync: lastSync, meetings: meetings)).write(to: fileURL, options: .atomic)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private struct Mirror: Codable {
        var lastSync: Date?
        var meetings: [Meeting]
    }
}
