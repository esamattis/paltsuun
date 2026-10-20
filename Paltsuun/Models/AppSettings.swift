import Foundation

enum AppSettings {
    static let leadMinutesKey = "reminderLeadMinutes"
    static let autoOpenLinkKey = "autoOpenMeetingLink"

    static let defaultLeadMinutes = 5
    static let leadMinuteChoices = [1, 2, 3, 5, 10, 15]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            leadMinutesKey: defaultLeadMinutes,
            autoOpenLinkKey: true,
        ])
    }

    /// How long before a meeting the countdown is shown.
    static var leadTime: TimeInterval {
        TimeInterval(max(1, UserDefaults.standard.integer(forKey: leadMinutesKey)) * 60)
    }

    static var autoOpenLink: Bool {
        UserDefaults.standard.bool(forKey: autoOpenLinkKey)
    }
}

enum Countdown {
    static func string(for remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "Now" }
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
