import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(CalendarSync.self) private var calendarSync

    var body: some View {
        Form {
            ForEach(calendarSync.providers, id: \.id) { provider in
                SyncedCalendarSection(provider: provider)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { NSApp.setActivationPolicy(.regular) }
    }
}

private struct SyncedCalendarSection: View {
    @Environment(CalendarSync.self) private var calendarSync
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
