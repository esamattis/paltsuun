import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(MeetingStore.self) private var store
    @Environment(CalendarSync.self) private var calendarSync
    @Environment(ReminderController.self) private var reminders
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let upcoming = store.upcomingMeetings(limit: 6)
        if upcoming.isEmpty {
            Text("No upcoming meetings")
        } else {
            Section("Upcoming") {
                ForEach(upcoming) { meeting in
                    Button(title(for: meeting)) {
                        if let url = meeting.url {
                            NSWorkspace.shared.open(url)
                        } else {
                            showCalendar()
                        }
                    }
                }
            }
        }

        Divider()

        let next = store.meetings.first(where: reminders.canShow)
        Button("Show Next Countdown") {
            if let next { reminders.show(next) }
        }
        .keyboardShortcut("s")
        .disabled(next == nil)
        Button("Open Calendar…", action: showCalendar)
            .keyboardShortcut("o")
        if calendarSync.hasConnectedSources {
            Button(calendarSync.isSyncing ? "Syncing Calendars…" : "Sync Calendars Now") {
                Task { await calendarSync.syncNow() }
            }
            .keyboardShortcut("r")
            .disabled(calendarSync.isSyncing)
        } else {
            Button("Connect Google Calendar…", action: showSettings)
        }

        Divider()

        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")

        Divider()

        Button("Quit Paltsuun") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func title(for meeting: Meeting) -> String {
        let format: Date.FormatStyle = Calendar.current.isDateInToday(meeting.start)
            ? .dateTime.hour().minute()
            : .dateTime.weekday(.abbreviated).hour().minute()
        return "\(meeting.start.formatted(format))  \(meeting.title)"
    }

    private func showCalendar() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate()
    }

    private func showSettings() {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.activate()
    }
}

struct MenuBarLabel: View {
    let reminders: ReminderController
    @Environment(\.openSettings) private var openSettings
    private static var didLaunch = false

    var body: some View {
        Group {
            if let meeting = reminders.current {
                Text(Countdown.string(for: meeting.start.timeIntervalSince(reminders.now)))
                    .monospacedDigit()
            } else {
                Image(systemName: "calendar.badge.clock")
            }
        }
        .onAppear(perform: openSettingsIfUnconfigured)
    }

    /// The label is the only view shown at launch, so it opens Settings when Google Calendar
    /// hasn't been set up yet.
    private func openSettingsIfUnconfigured() {
        guard !Self.didLaunch else { return }
        Self.didLaunch = true
        guard !GoogleCalendarSource.hasClientID else { return }
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.activate()
    }
}
