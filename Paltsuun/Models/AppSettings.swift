import AppKit

enum AppSettings {
    static let leadMinutesKey = "reminderLeadMinutes"
    static let autoOpenLinkKey = "autoOpenMeetingLink"
    static let startSoundKey = "meetingStartSound"

    static let defaultLeadMinutes = 5
    static let leadMinuteChoices = [1, 2, 3, 5, 10, 15]
    static let defaultStartSound = "Glass"
    /// macOS system sounds. An empty name means no sound.
    static let startSoundChoices = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            leadMinutesKey: defaultLeadMinutes,
            autoOpenLinkKey: true,
            startSoundKey: defaultStartSound,
        ])
    }

    /// How long before a meeting the countdown is shown.
    static var leadTime: TimeInterval {
        TimeInterval(max(1, UserDefaults.standard.integer(forKey: leadMinutesKey)) * 60)
    }

    static var autoOpenLink: Bool {
        UserDefaults.standard.bool(forKey: autoOpenLinkKey)
    }

    /// Sound played when a meeting starts, or empty for none.
    static var startSound: String {
        UserDefaults.standard.string(forKey: startSoundKey) ?? ""
    }

    static func playStartSound(named name: String = startSound) {
        guard !name.isEmpty, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.stop()
        sound.play()
    }
}

enum Countdown {
    static func string(for remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "Now" }
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
