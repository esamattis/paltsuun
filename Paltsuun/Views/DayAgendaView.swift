import AppKit
import SwiftUI

struct DayAgendaView: View {
    let date: Date
    let meetings: [Meeting]
    let onCreate: () -> Void
    let onEdit: (Meeting) -> Void
    let onDelete: (Meeting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(date.formatted(.dateTime.weekday(.wide)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(date.formatted(.dateTime.day().month(.wide)))
                        .font(.title2.weight(.semibold))
                }
                Spacer()
                Button(action: onCreate) {
                    Image(systemName: "plus")
                }
                .help("New meeting on this day")
            }
            .padding()

            Divider()

            if meetings.isEmpty {
                ContentUnavailableView {
                    Label("No Meetings", systemImage: "calendar")
                } actions: {
                    Button("Add Meeting", action: onCreate)
                }
            } else {
                List(meetings) { meeting in
                    AgendaRow(meeting: meeting)
                        .contentShape(Rectangle())
                        .onTapGesture { onEdit(meeting) }
                        .contextMenu {
                            Button("Edit…") { onEdit(meeting) }
                            if let url = meeting.url {
                                Button("Open Meeting Link") { NSWorkspace.shared.open(url) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { onDelete(meeting) }
                        }
                }
            }
        }
    }
}

private struct AgendaRow: View {
    let meeting: Meeting

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title.isEmpty ? "Untitled" : meeting.title)
                    .font(.headline)
                Text("\(meeting.start.formatted(date: .omitted, time: .shortened)) – \(meeting.end.formatted(date: .omitted, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let url = meeting.url {
                    Label(url.host() ?? url.absoluteString, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
