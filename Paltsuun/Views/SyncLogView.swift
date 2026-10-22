import AppKit
import SwiftUI

/// Recent calendar syncs and the meetings each of them added, changed or removed.
struct SyncLogView: View {
    @Environment(CalendarSync.self) private var calendarSync
    @AppStorage(AppSettings.syncMinutesKey) private var syncMinutes = AppSettings.defaultSyncMinutes
    @State private var onlyChanges = false

    var body: some View {
        let entries = onlyChanges
            ? calendarSync.log.filter { $0.changes?.isEmpty == false || $0.changes == nil }
            : calendarSync.log
        List(entries) { entry in
            SyncLogRow(entry: entry)
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    onlyChanges ? "No Changes" : "No Syncs Yet",
                    systemImage: "calendar.badge.clock",
                    description: Text(calendarSync.hasConnectedSources ? "Syncs are listed here." : "Connect a calendar in Settings.")
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text(status)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Only changes and errors", isOn: $onlyChanges)
                    .toggleStyle(.checkbox)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { calendarSync.clearLog() } label: { Image(systemName: "trash") }
                    .help("Clear log")
                    .disabled(calendarSync.log.isEmpty)
                Button { Task { await calendarSync.syncNow() } } label: { Image(systemName: "arrow.clockwise") }
                    .keyboardShortcut("r")
                    .help("Sync calendars")
                    .disabled(calendarSync.isSyncing || !calendarSync.hasConnectedSources)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear { NSApp.setActivationPolicy(.regular) }
    }

    private var status: String {
        guard calendarSync.hasConnectedSources else { return "No calendars connected." }
        let interval = syncMinutes == 1 ? "every minute" : "every \(syncMinutes) minutes"
        if calendarSync.isSyncing { return "Syncing \(interval). Syncing now…" }
        guard let next = calendarSync.nextSync, next > Date() else { return "Syncing \(interval)." }
        return "Syncing \(interval). Next sync at \(next.formatted(date: .omitted, time: .standard))."
    }
}

private struct SyncLogRow: View {
    let entry: SyncLogEntry

    var body: some View {
        if let changes = entry.changes, !changes.isEmpty {
            DisclosureGroup {
                ForEach(changes.added) { MeetingChangeRow(meeting: $0, kind: changes.new.contains($0) ? .new : .added) }
                ForEach(changes.changed) { MeetingChangeRow(meeting: $0, kind: .changed) }
                ForEach(changes.removed) { MeetingChangeRow(meeting: $0, kind: .removed) }
            } label: {
                summary
            }
        } else {
            summary
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.date.formatted(date: .omitted, time: .standard))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            switch entry.result {
            case .synced(let changes):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(entry.provider): \(Self.describe(changes))")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text("\(entry.provider): \(message)")
                    .textSelection(.enabled)
            }
            Spacer()
            Text("\(entry.trigger.rawValue) · \(entry.duration.formatted(.number.precision(.fractionLength(1)))) s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func describe(_ changes: SyncChanges) -> String {
        let counts = [
            (changes.new.count, "new"),
            (changes.added.count - changes.new.count, "came into range"),
            (changes.changed.count, "changed"),
            (changes.removed.count, "removed"),
        ]
        .filter { $0.0 > 0 }
        .map { "\($0.0) \($0.1)" }
        let events = changes.eventCount == 1 ? "1 event" : "\(changes.eventCount) events"
        return ([events] + (counts.isEmpty ? ["no changes"] : counts)).joined(separator: ", ")
    }
}

private struct MeetingChangeRow: View {
    enum Kind: String {
        case new = "New"
        case added = "In range"
        case changed = "Changed"
        case removed = "Removed"

        var color: Color {
            switch self {
            case .new: .blue
            case .added: .secondary
            case .changed: .orange
            case .removed: .red
            }
        }
    }

    let meeting: Meeting
    let kind: Kind

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(kind.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(kind.color)
                .frame(width: 60, alignment: .leading)
            Text(meeting.title.isEmpty ? "Untitled meeting" : meeting.title)
                .strikethrough(kind == .removed)
            if meeting.isDeclined {
                Text("Declined").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(meeting.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
