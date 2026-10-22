import Foundation

/// A calendar event, independent of the calendar provider it came from.
struct Meeting: Identifiable, Codable, Hashable {
    /// Must be unique across all providers.
    var id: String
    /// `CalendarProvider.id` of the provider owning this meeting.
    var providerID: String
    var title: String
    var start: Date
    var end: Date
    var url: URL?
    /// The user has declined the invitation. Declined meetings are shown but never reminded of.
    var isDeclined = false
    /// Shared by all occurrences of a repeating event, nil for single events.
    var seriesID: String?

    /// Parses user input into a meeting link. Adds `https://` when no scheme is given.
    static func parseLink(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }
}

extension Meeting {
    private enum CodingKeys: String, CodingKey {
        case id, providerID, title, start, end, url, isDeclined, seriesID
    }

    /// `isDeclined` and `seriesID` are optional so files written before they existed still load.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        providerID = try container.decode(String.self, forKey: .providerID)
        title = try container.decode(String.self, forKey: .title)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        isDeclined = try container.decodeIfPresent(Bool.self, forKey: .isDeclined) ?? false
        seriesID = try container.decodeIfPresent(String.self, forKey: .seriesID)
    }
}
