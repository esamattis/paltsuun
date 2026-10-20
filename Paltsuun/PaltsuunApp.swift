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
