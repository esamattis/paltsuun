import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: MeetingStore
    let calendarSync: CalendarSync
    let reminders: ReminderController
    let activityMonitor: ActivityMonitor

    override init() {
        AppSettings.registerDefaults()
        let google = SyncedCalendarProvider(source: GoogleCalendarSource())
        store = MeetingStore(providers: [LocalCalendarProvider(), google])
        calendarSync = CalendarSync(providers: [google], store: store)
        let reminders = ReminderController(store: store)
        self.reminders = reminders
        activityMonitor = ActivityMonitor { reminders.showToday() }
        calendarSync.onNewMeetings = { reminders.announce($0) }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.startPolling()
        calendarSync.start()
        reminders.start()
        activityMonitor.start()
        if AppSettings.awayTime != nil {
            reminders.showToday()
        }

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            // The closing window is still visible here, so check on the next run loop pass.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Self.hideDockIconIfNoWindows() }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// With no regular windows open the app lives only in the menu bar.
    private static func hideDockIconIfNoWindows() {
        let hasWindows = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled) && !(window is NSPanel)
        }
        if !hasWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
