import AppKit
import Observation
import SwiftUI

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
    /// The rest of today's meetings while their overview is on screen, by reminder key.
    /// Meetings that have a countdown in `reminders` are left out.
    private(set) var overview: [String: Meeting] = [:]
    /// The meeting starting closest to now, shown in the menu bar.
    private(set) var current: Meeting?

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var panels: [String: ReminderPanel] = [:]
    /// Meetings seen counting down, so the link is opened only when we witness the start.
    @ObservationIgnored private var armed: [String: Date] = [:]
    @ObservationIgnored private var opened: [String: Date] = [:]
    @ObservationIgnored private var dismissed: [String: Date] = [:]
    /// Meetings whose countdown was shown manually, before the lead time.
    @ObservationIgnored private var shown: [String: Date] = [:]
    @ObservationIgnored private var overviewPanels: [String: ReminderPanel] = [:]
    @ObservationIgnored private var overviewUntil: Date?
    @ObservationIgnored private var overviewDismissed: Set<String> = []

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

    /// Whether the countdown can be shown manually: the meeting hasn't started and isn't declined.
    func canShow(_ meeting: Meeting) -> Bool {
        !meeting.isDeclined && meeting.start > Date()
    }

    /// Shows the meeting's countdown now, even when the meeting is further away than the lead time.
    func show(_ meeting: Meeting) {
        guard canShow(meeting) else { return }
        let key = Self.key(for: meeting)
        shown[key] = meeting.start
        dismissed[key] = nil
        tick()
        panels[key]?.orderFrontRegardless()
    }

    /// Hides the meeting's countdown. Its link isn't opened automatically either.
    func dismiss(_ meeting: Meeting) {
        let key = Self.key(for: meeting)
        dismissed[key] = meeting.start
        armed[key] = nil
        shown[key] = nil
        tick()
    }

    /// Briefly shows small countdowns for the rest of today's meetings.
    func showToday() {
        overviewUntil = Date().addingTimeInterval(AppSettings.overviewDuration)
        overviewDismissed = []
        tick()
    }

    /// Hides the meeting from the overview of today's meetings. It still reminds as usual.
    func dismissFromOverview(_ meeting: Meeting) {
        overviewDismissed.insert(Self.key(for: meeting))
        tick()
    }

    private func tick() {
        let now = Date()
        self.now = now
        let lead = leadTime
        let meetings = store.meetings.filter { !$0.isDeclined && dismissed[Self.key(for: $0)] == nil }

        var started = false
        for meeting in meetings {
            let key = Self.key(for: meeting)
            let remaining = meeting.start.timeIntervalSince(now)
            if remaining > 0, remaining <= lead || shown[key] != nil {
                armed[key] = meeting.start
            } else if remaining <= 0, armed.removeValue(forKey: key) != nil,
                      -remaining < Self.startedDisplayDuration
            {
                started = true
                if AppSettings.autoOpenLink, let url = meeting.url {
                    opened[key] = meeting.start
                    NSWorkspace.shared.open(url)
                }
            }
        }
        // Once, even when several meetings start together.
        if started { AppSettings.playStartSound() }
        prune(before: now.addingTimeInterval(-24 * 60 * 60))

        let visible = meetings.filter { meeting in
            let remaining = meeting.start.timeIntervalSince(now)
            if remaining > 0 { return remaining <= lead || shown[Self.key(for: meeting)] != nil }
            let limit = opened[Self.key(for: meeting)] != nil ? Self.openedDisplayDuration : Self.startedDisplayDuration
            return -remaining < limit
        }
        let reminders = Dictionary(visible.map { (Self.key(for: $0), $0) }) { first, _ in first }
        if self.reminders != reminders { self.reminders = reminders }
        let next = visible.min { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
        if current != next { current = next }

        var overview: [String: Meeting] = [:]
        if let overviewUntil, now < overviewUntil {
            let calendar = Calendar.current
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            for meeting in meetings where meeting.start > now && meeting.start < endOfDay {
                let key = Self.key(for: meeting)
                if reminders[key] == nil, !overviewDismissed.contains(key) { overview[key] = meeting }
            }
        } else {
            overviewUntil = nil
        }
        if self.overview != overview { self.overview = overview }

        updatePanels()
    }

    /// Closes the panels of meetings no longer shown and opens one for each new meeting.
    private func updatePanels() {
        for (key, panel) in panels where reminders[key] == nil {
            panel.close()
            panels[key] = nil
        }
        for (key, panel) in overviewPanels where overview[key] == nil {
            panel.fadeOut()
            overviewPanels[key] = nil
        }
        for key in Self.keysWithoutPanel(reminders, panels) {
            panels[key] = present(ReminderView(controller: self, key: key))
        }
        for key in Self.keysWithoutPanel(overview, overviewPanels) {
            overviewPanels[key] = present(OverviewView(controller: self, key: key))
        }
    }

    private func present(_ view: some View) -> ReminderPanel {
        let panel = ReminderPanel(rootView: view)
        panel.place(avoiding: (Array(panels.values) + Array(overviewPanels.values)).map(\.frame))
        panel.orderFrontRegardless()
        return panel
    }

    /// Earliest first, so countdowns appearing together are stacked in start order.
    private static func keysWithoutPanel(_ meetings: [String: Meeting], _ panels: [String: ReminderPanel]) -> [String] {
        meetings.filter { panels[$0.key] == nil }
            .sorted { ($0.value.start, $0.key) < ($1.value.start, $1.key) }
            .map(\.key)
    }

    private func prune(before date: Date) {
        armed = armed.filter { $0.value >= date }
        opened = opened.filter { $0.value >= date }
        dismissed = dismissed.filter { $0.value >= date }
        shown = shown.filter { $0.value >= date }
    }

    /// Includes the start time so a rescheduled meeting reminds again.
    private static func key(for meeting: Meeting) -> String {
        "\(meeting.providerID)|\(meeting.id)|\(meeting.start.timeIntervalSince1970)"
    }
}
