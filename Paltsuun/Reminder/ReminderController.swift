import AppKit
import Observation

/// Watches the store and shows the floating countdown when a meeting is about to start.
@Observable
final class ReminderController {
    /// How long a started meeting stays on screen.
    static let startedDisplayDuration: TimeInterval = 30
    /// How long a started meeting stays on screen after its link was opened automatically.
    static let openedDisplayDuration: TimeInterval = 5

    private(set) var now = Date()
    private(set) var current: Meeting?

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var panel: ReminderPanel?
    /// Meetings seen counting down, so the link is opened only when we witness the start.
    @ObservationIgnored private var armed: [String: Date] = [:]
    @ObservationIgnored private var opened: [String: Date] = [:]

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

    private func tick() {
        let now = Date()
        self.now = now
        let lead = leadTime

        for meeting in store.meetings {
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

        let visible = store.meetings.filter { meeting in
            let remaining = meeting.start.timeIntervalSince(now)
            if remaining > 0 { return remaining <= lead }
            let limit = opened[Self.key(for: meeting)] != nil ? Self.openedDisplayDuration : Self.startedDisplayDuration
            return -remaining < limit
        }
        let next = visible.min { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
        if current != next { current = next }

        if next != nil {
            showPanel()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func showPanel() {
        let panel = panel ?? ReminderPanel(rootView: ReminderView(controller: self))
        self.panel = panel
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func prune(before date: Date) {
        armed = armed.filter { $0.value >= date }
        opened = opened.filter { $0.value >= date }
    }

    /// Includes the start time so a rescheduled meeting reminds again.
    private static func key(for meeting: Meeting) -> String {
        "\(meeting.providerID)|\(meeting.id)|\(meeting.start.timeIntervalSince1970)"
    }
}
