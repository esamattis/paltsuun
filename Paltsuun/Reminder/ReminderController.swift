import AppKit
import Observation

/// Watches the store and shows a floating countdown for each meeting that is about to start.
@Observable
final class ReminderController {
    /// How long a started meeting stays on screen.
    static let startedDisplayDuration: TimeInterval = 30
    /// How long a started meeting stays on screen after its link was opened automatically.
    static let openedDisplayDuration: TimeInterval = 5

    private(set) var now = Date()
    /// Meetings with a countdown on screen, by reminder key.
    private(set) var reminders: [String: Meeting] = [:]
    /// The meeting starting closest to now, shown in the menu bar.
    private(set) var current: Meeting?

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var panels: [String: ReminderPanel] = [:]
    /// Meetings seen counting down, so the link is opened only when we witness the start.
    @ObservationIgnored private var armed: [String: Date] = [:]
    @ObservationIgnored private var opened: [String: Date] = [:]
    @ObservationIgnored private var dismissed: [String: Date] = [:]

    init(store: MeetingStore) {
        self.store = store
    }

    var leadTime: TimeInterval { AppSettings.leadTime }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    /// Hides the meeting's countdown. Its link isn't opened automatically either.
    func dismiss(_ meeting: Meeting) {
        let key = Self.key(for: meeting)
        dismissed[key] = meeting.start
        armed[key] = nil
        tick()
    }

    private func tick() {
        let now = Date()
        self.now = now
        let lead = leadTime
        let meetings = store.meetings.filter { !$0.isDeclined && dismissed[Self.key(for: $0)] == nil }

        for meeting in meetings {
            let key = Self.key(for: meeting)
            let remaining = meeting.start.timeIntervalSince(now)
            if remaining > 0, remaining <= lead {
                armed[key] = meeting.start
            } else if remaining <= 0, armed.removeValue(forKey: key) != nil,
                      -remaining < Self.startedDisplayDuration,
                      AppSettings.autoOpenLink, let url = meeting.url
            {
                opened[key] = meeting.start
                NSWorkspace.shared.open(url)
            }
        }
        prune(before: now.addingTimeInterval(-24 * 60 * 60))

        let visible = meetings.filter { meeting in
            let remaining = meeting.start.timeIntervalSince(now)
            if remaining > 0 { return remaining <= lead }
            let limit = opened[Self.key(for: meeting)] != nil ? Self.openedDisplayDuration : Self.startedDisplayDuration
            return -remaining < limit
        }
        let reminders = Dictionary(visible.map { (Self.key(for: $0), $0) }) { first, _ in first }
        if self.reminders != reminders { self.reminders = reminders }
        let next = visible.min { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
        if current != next { current = next }

        updatePanels()
    }

    /// Closes the panels of meetings no longer shown and opens one for each new meeting.
    private func updatePanels() {
        for (key, panel) in panels where reminders[key] == nil {
            panel.close()
            panels[key] = nil
        }
        // Earliest first, so countdowns appearing together are stacked in start order.
        let new = reminders.filter { panels[$0.key] == nil }.sorted { ($0.value.start, $0.key) < ($1.value.start, $1.key) }
        for (key, _) in new {
            let panel = ReminderPanel(rootView: ReminderView(controller: self, key: key))
            panel.place(avoiding: panels.values.map(\.frame))
            panel.orderFrontRegardless()
            panels[key] = panel
        }
    }

    private func prune(before date: Date) {
        armed = armed.filter { $0.value >= date }
        opened = opened.filter { $0.value >= date }
        dismissed = dismissed.filter { $0.value >= date }
    }

    /// Includes the start time so a rescheduled meeting reminds again.
    private static func key(for meeting: Meeting) -> String {
        "\(meeting.providerID)|\(meeting.id)|\(meeting.start.timeIntervalSince1970)"
    }
}
