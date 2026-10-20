import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: MeetingStore
    let calendarSync: CalendarSync
    let reminders: ReminderController

    override init() {
        AppSettings.registerDefaults()
        let google = SyncedCalendarProvider(source: GoogleCalendarSource())
        store = MeetingStore(providers: [LocalCalendarProvider(), google])
        calendarSync = CalendarSync(providers: [google], store: store)
        reminders = ReminderController(store: store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.startPolling()
        calendarSync.start()
        reminders.start()

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
