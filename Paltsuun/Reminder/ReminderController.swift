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
    /// How long the toast about new meetings stays on screen.
    static let newMeetingsDisplayDuration: TimeInterval = 8
    /// How long the message about meetings without a link stays on screen before it can be dismissed.
    static let noLinkDismissDelay: TimeInterval = 3

    private(set) var now = Date()
    /// Meetings with a countdown on screen, by reminder key.
    private(set) var reminders: [String: Meeting] = [:]
    /// Ongoing meetings and the rest of today's meetings while their overview is on screen,
    /// by reminder key. Meetings that have a countdown in `reminders` are left out.
    private(set) var overview: [String: Meeting] = [:]
    /// When the overview of today's meetings disappears.
    private(set) var overviewUntil: Date?
    /// Meetings in the toast about new meetings, earliest first.
    private(set) var newMeetings: [Meeting] = []
    /// When the toast about new meetings disappears.
    private(set) var newMeetingsUntil: Date?
    /// Started meetings without a link, shown in a big message until the user dismisses it.
    private(set) var noLinkMeetings: [Meeting] = []
    /// When the message about meetings without a link appeared.
    private(set) var noLinkShownAt: Date?
    /// The meeting starting closest to now, shown in the menu bar.
    private(set) var current: Meeting?

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var panels: [String: ReminderPanel] = [:]
    /// Meetings seen counting down, so the link is opened only when we witness the start.
    @ObservationIgnored private var armed: [String: Date] = [:]
    @ObservationIgnored private var opened: [String: Date] = [:]
    /// Started meetings without a link, whose countdown gave way to the big message.
    @ObservationIgnored private var startedWithoutLink: [String: Date] = [:]
    @ObservationIgnored private var dismissed: [String: Date] = [:]
    /// Meetings whose countdown was shown manually, before the lead time.
    @ObservationIgnored private var shown: [String: Date] = [:]
    @ObservationIgnored private var overviewPanels: [String: ReminderPanel] = [:]
    @ObservationIgnored private var overviewDismissed: Set<String> = []
    @ObservationIgnored private var newMeetingsPanel: ReminderPanel?
    @ObservationIgnored private var noLinkPanel: ReminderPanel?

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

    /// Briefly shows ongoing meetings and small countdowns for the rest of today's meetings.
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

    /// Briefly shows a toast about meetings added to a calendar. A repeating meeting is shown
    /// once, as its next occurrence. Meetings that have ended or were declined are left out.
    func announce(_ meetings: [Meeting]) {
        let now = Date()
        var seen: Set<String> = []
        let upcoming = meetings
            .filter { $0.end > now && !$0.isDeclined }
            .sorted { $0.start < $1.start }
            .filter { seen.insert($0.seriesID ?? $0.id).inserted }
        guard !upcoming.isEmpty else { return }
        // Replace a toast already on screen, since the new one may be a different size.
        newMeetingsPanel?.close()
        newMeetingsPanel = nil
        newMeetings = upcoming
        newMeetingsUntil = now.addingTimeInterval(Self.newMeetingsDisplayDuration)
        tick()
    }

    func dismissNewMeetings() {
        newMeetingsUntil = nil
        tick()
    }

    /// Seconds until the countdown of a started meeting disappears, or nil before the start.
    func closesIn(_ meeting: Meeting) -> TimeInterval? {
        let elapsed = now.timeIntervalSince(meeting.start)
        guard elapsed >= 0 else { return nil }
        return startedDisplayDuration(for: Self.key(for: meeting)) - elapsed
    }

    /// The message about meetings without a link has been on screen long enough to be dismissed.
    var canDismissNoLink: Bool {
        guard let noLinkShownAt else { return false }
        return now.timeIntervalSince(noLinkShownAt) >= Self.noLinkDismissDelay
    }

    func dismissNoLink() {
        guard canDismissNoLink else { return }
        noLinkMeetings = []
        noLinkShownAt = nil
        tick()
    }

    private func tick() {
        let now = Date()
        self.now = now
        let lead = leadTime
        let meetings = store.meetings.filter { !$0.isDeclined && dismissed[Self.key(for: $0)] == nil }

        var started = false
        var startedWithoutLink: [Meeting] = []
        for meeting in meetings {
            let key = Self.key(for: meeting)
            let remaining = meeting.start.timeIntervalSince(now)
            if remaining > 0, remaining <= lead || shown[key] != nil {
                armed[key] = meeting.start
            } else if remaining <= 0, armed.removeValue(forKey: key) != nil,
                      -remaining < Self.startedDisplayDuration
            {
                started = true
                if let url = meeting.url {
                    if AppSettings.autoOpenLink {
                        opened[key] = meeting.start
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    self.startedWithoutLink[key] = meeting.start
                    startedWithoutLink.append(meeting)
                }
            }
        }
        // Once, even when several meetings start together.
        if started { AppSettings.playStartSound() }
        if !startedWithoutLink.isEmpty {
            // Replace a message already on screen, since the new one may be a different size.
            noLinkPanel?.close()
            noLinkPanel = nil
            noLinkMeetings = (noLinkMeetings + startedWithoutLink).sorted { $0.start < $1.start }
            noLinkShownAt = now
        }
        prune(before: now.addingTimeInterval(-24 * 60 * 60))

        let visible = meetings.filter { meeting in
            let remaining = meeting.start.timeIntervalSince(now)
            if remaining > 0 { return remaining <= lead || shown[Self.key(for: meeting)] != nil }
            return -remaining < startedDisplayDuration(for: Self.key(for: meeting))
        }
        let reminders = Dictionary(visible.map { (Self.key(for: $0), $0) }) { first, _ in first }
        if self.reminders != reminders { self.reminders = reminders }
        let next = visible.min { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
        if current != next { current = next }

        var overview: [String: Meeting] = [:]
        if let overviewUntil, now < overviewUntil {
            let calendar = Calendar.current
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            for meeting in meetings where meeting.end > now && meeting.start < endOfDay {
                let key = Self.key(for: meeting)
                if reminders[key] == nil, !overviewDismissed.contains(key) { overview[key] = meeting }
            }
        } else {
            overviewUntil = nil
        }
        if self.overview != overview { self.overview = overview }

        if let newMeetingsUntil, now >= newMeetingsUntil { self.newMeetingsUntil = nil }
        if newMeetingsUntil == nil, !newMeetings.isEmpty { newMeetings = [] }

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
        if newMeetings.isEmpty, let newMeetingsPanel {
            newMeetingsPanel.fadeOut()
            self.newMeetingsPanel = nil
        }
        for key in Self.keysWithoutPanel(reminders, panels) {
            panels[key] = present(ReminderView(controller: self, key: key))
        }
        for key in Self.keysWithoutPanel(overview, overviewPanels) {
            overviewPanels[key] = present(OverviewView(controller: self, key: key))
        }
        if !newMeetings.isEmpty, newMeetingsPanel == nil {
            newMeetingsPanel = present(NewMeetingsView(controller: self))
        }
        if noLinkMeetings.isEmpty, let noLinkPanel {
            noLinkPanel.fadeOut()
            self.noLinkPanel = nil
        } else if !noLinkMeetings.isEmpty, noLinkPanel == nil {
            let panel = ReminderPanel(rootView: NoLinkView(controller: self))
            panel.isMovableByWindowBackground = false
            panel.placeInCenter()
            // Key, so Return and Escape reach it.
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            noLinkPanel = panel
        }
    }

    private func present(_ view: some View) -> ReminderPanel {
        let panel = ReminderPanel(rootView: view)
        let shown = Array(panels.values) + Array(overviewPanels.values) + [newMeetingsPanel].compactMap(\.self)
        panel.place(avoiding: shown.map(\.frame))
        panel.orderFrontRegardless()
        return panel
    }

    /// Earliest first, so countdowns appearing together are stacked in start order.
    private static func keysWithoutPanel(_ meetings: [String: Meeting], _ panels: [String: ReminderPanel]) -> [String] {
        meetings.filter { panels[$0.key] == nil }
            .sorted { ($0.value.start, $0.key) < ($1.value.start, $1.key) }
            .map(\.key)
    }

    /// How long a started meeting's countdown stays on screen.
    private func startedDisplayDuration(for key: String) -> TimeInterval {
        if startedWithoutLink[key] != nil { return 0 }
        return opened[key] != nil ? Self.openedDisplayDuration : Self.startedDisplayDuration
    }

    private func prune(before date: Date) {
        armed = armed.filter { $0.value >= date }
        opened = opened.filter { $0.value >= date }
        startedWithoutLink = startedWithoutLink.filter { $0.value >= date }
        dismissed = dismissed.filter { $0.value >= date }
        shown = shown.filter { $0.value >= date }
    }

    /// Includes the start time so a rescheduled meeting reminds again.
    private static func key(for meeting: Meeting) -> String {
        "\(meeting.providerID)|\(meeting.id)|\(meeting.start.timeIntervalSince1970)"
    }
}
