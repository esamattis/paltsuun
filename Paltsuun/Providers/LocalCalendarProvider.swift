import Foundation

/// Stores meetings in a JSON file in Application Support.
final class LocalCalendarProvider: EditableCalendarProvider {
    let id = "local"
    let displayName = "Local"

    private let fileURL: URL
    private var meetings: [Meeting]

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Paltsuun/meetings.json")
    }

    init(fileURL: URL = LocalCalendarProvider.defaultFileURL) {
        self.fileURL = fileURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        meetings = (try? Data(contentsOf: fileURL)).flatMap { try? decoder.decode([Meeting].self, from: $0) } ?? []
    }

    func fetchMeetings(in interval: DateInterval) async throws -> [Meeting] {
        meetings.filter { $0.end >= interval.start && $0.start < interval.end }
    }

    func save(_ meeting: Meeting) async throws {
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index] = meeting
        } else {
            meetings.append(meeting)
        }
        try persist()
    }

    func delete(_ meeting: Meeting) async throws {
        meetings.removeAll { $0.id == meeting.id }
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meetings).write(to: fileURL, options: .atomic)
    }
}
