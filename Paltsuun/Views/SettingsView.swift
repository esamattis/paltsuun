import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(CalendarSync.self) private var calendarSync

    var body: some View {
        Form {
            GeneralSection()
            ForEach(calendarSync.providers, id: \.id) { provider in
                SyncedCalendarSection(provider: provider)
            }
        }
        .formStyle(.grouped)
        // The window is sized to fit the form, so the scroller is never needed.
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { NSApp.setActivationPolicy(.regular) }
    }
}

private struct GeneralSection: View {
    @AppStorage(AppSettings.leadMinutesKey) private var leadMinutes = AppSettings.defaultLeadMinutes
    @AppStorage(AppSettings.autoOpenLinkKey) private var autoOpenLink = true
    @AppStorage(AppSettings.startSoundKey) private var startSound = AppSettings.defaultStartSound
    @AppStorage(AppSettings.awayMinutesKey) private var awayMinutes = AppSettings.defaultAwayMinutes
    @AppStorage(AppSettings.overviewSecondsKey) private var overviewSeconds = AppSettings.defaultOverviewSeconds
    @AppStorage(AppSettings.syncMinutesKey) private var syncMinutes = AppSettings.defaultSyncMinutes
    @Environment(CalendarSync.self) private var calendarSync
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Section("General") {
            Picker("Remind me", selection: $leadMinutes) {
                ForEach(AppSettings.leadMinuteChoices, id: \.self) { minutes in
                    Text("\(minutes) min before").tag(minutes)
                }
            }
            Toggle("Open link when meeting starts", isOn: $autoOpenLink)
            LabeledContent("Sound when meeting starts") {
                HStack {
                    Picker("Sound when meeting starts", selection: $startSound) {
                        Text("None").tag("")
                        Divider()
                        ForEach(AppSettings.startSoundChoices, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Test") { AppSettings.playStartSound(named: startSound) }
                        .disabled(startSound.isEmpty)
                }
            }
            Picker(selection: $awayMinutes) {
                Text("Never").tag(0)
                Divider()
                ForEach(AppSettings.awayMinuteChoices, id: \.self) { minutes in
                    Text(Self.format(minutes: minutes)).tag(minutes)
                }
            } label: {
                Text("Show today's meetings when back after")
                Text("Also shown briefly when Paltsuun starts.")
            }
            Picker("Show today's meetings for", selection: $overviewSeconds) {
                ForEach(AppSettings.overviewSecondChoices, id: \.self) { seconds in
                    Text("\(seconds) s").tag(seconds)
                }
            }
            .disabled(awayMinutes == 0)
            Picker("Check calendars for changes every", selection: $syncMinutes) {
                ForEach(AppSettings.syncMinuteChoices, id: \.self) { minutes in
                    Text(Self.format(minutes: minutes)).tag(minutes)
                }
            }
            .onChange(of: syncMinutes) { calendarSync.start() }
            Toggle("Start at login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    LaunchAtLogin.setEnabled(enabled)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            ))
        }
    }

    private static func format(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
    }
}

private struct SyncedCalendarSection: View {
    @Environment(CalendarSync.self) private var calendarSync
    @Environment(\.openWindow) private var openWindow
    let provider: SyncedCalendarProvider

    @State private var connectTask: Task<Void, Never>?
    @State private var connectError: String?

    var body: some View {
        Section(provider.displayName) {
            if provider.source.isConnected {
                LabeledContent("Account", value: provider.source.accountName ?? "Connected")
                LabeledContent("Last synced") {
                    if calendarSync.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(provider.lastSync.map { Self.format($0) } ?? "Never")
                    }
                }
                if let error = calendarSync.errors[provider.id] {
                    errorText(error)
                }
                HStack {
                    Button("Disconnect") {
                        Task { await calendarSync.disconnect(provider) }
                    }
                    Spacer()
                    Button("Show Log…") {
                        openWindow(id: "sync-log")
                        NSApp.activate()
                    }
                    Button("Sync Now") {
                        Task { await calendarSync.syncNow() }
                    }
                    .disabled(calendarSync.isSyncing)
                }
            } else {
                if provider.source is GoogleCalendarSource {
                    GoogleClientFields()
                }
                if let connectError {
                    errorText(connectError)
                }
                HStack {
                    if connectTask != nil {
                        ProgressView().controlSize(.small)
                        Text("Waiting for sign-in in the browser…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { connectTask?.cancel() }
                    } else {
                        Spacer()
                        Button("Connect…", action: connect)
                    }
                }
            }
        }
    }

    private func connect() {
        connectError = nil
        connectTask = Task {
            do {
                try await calendarSync.connect(provider)
                // Come back from the browser.
                NSApp.activate()
            } catch is CancellationError {
            } catch {
                connectError = error.localizedDescription
            }
            connectTask = nil
        }
    }

    private func errorText(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
    }

    private static func format(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// The user's own OAuth client, see README.
private struct GoogleClientFields: View {
    @AppStorage(GoogleCalendarSource.clientIDKey) private var clientID = ""
    @AppStorage(GoogleCalendarSource.clientSecretKey) private var clientSecret = ""

    var body: some View {
        Text("Create an OAuth client of type **Desktop app** in Google Cloud Console, with the Google Calendar API enabled, and enter its credentials here.")
            .font(.callout)
            .foregroundStyle(.secondary)
        Link("Open Google Cloud Console", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
            .font(.callout)
        TextField("Client ID", text: $clientID, prompt: Text("….apps.googleusercontent.com"))
        SecureField("Client secret", text: $clientSecret)
    }
}
