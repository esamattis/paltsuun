//
//  PaltsuunApp.swift
//  Paltsuun
//
//  Created by Esa-Matti Suuronen on 20.10.2026.
//

import SwiftUI

@main
struct PaltsuunApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Paltsuun", id: "main") {
            ContentView()
                .environment(appDelegate.store)
                .environment(appDelegate.calendarSync)
                .environment(appDelegate.reminders)
        }
        .defaultSize(width: 1100, height: 720)
        // Start hidden in the menu bar. The calendar is opened from the menu bar menu.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Sync Log", id: "sync-log") {
            SyncLogView()
                .environment(appDelegate.calendarSync)
        }
        .defaultSize(width: 640, height: 480)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Quick Event", id: "quick-event") {
            QuickEventView()
                .environment(appDelegate.store)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(appDelegate.calendarSync)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.store)
                .environment(appDelegate.calendarSync)
                .environment(appDelegate.reminders)
        } label: {
            MenuBarLabel(reminders: appDelegate.reminders)
        }
    }
}
