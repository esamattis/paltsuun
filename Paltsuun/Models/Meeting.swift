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

    /// Parses user input into a meeting link. Adds `https://` when no scheme is given.
    static func parseLink(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }
}
