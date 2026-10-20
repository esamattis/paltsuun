import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(CalendarSync.self) private var calendarSync
    @State private var month = Date()
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var draft: MeetingDraft?

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            MonthGridView(
                month: month,
                selectedDate: $selectedDate,
                meetingsOn: { store.meetings(on: $0) },
                onCreate: newMeeting(on:),
                onEdit: edit
            )
            Divider()
            DayAgendaView(
                date: selectedDate,
                meetings: store.meetings(on: selectedDate),
                onCreate: { newMeeting(on: selectedDate) },
                isEditable: store.isEditable,
                onEdit: edit,
                onDelete: delete
            )
            .frame(width: 300)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = [store.lastError, calendarSync.lastError].compactMap(\.self).joined(separator: "\n").nilIfEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.yellow.opacity(0.25))
            }
        }
        .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous month")
                Button("Today") {
                    month = Date()
                    selectedDate = calendar.startOfDay(for: Date())
                }
                .keyboardShortcut("t")
                Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                    .help("Next month")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if calendarSync.hasConnectedSources {
                    Button { Task { await calendarSync.syncNow() } } label: { Image(systemName: "arrow.clockwise") }
                        .keyboardShortcut("r")
                        .help("Sync calendars")
                        .disabled(calendarSync.isSyncing)
                }
                Button { newMeeting(on: selectedDate) } label: { Image(systemName: "plus") }
                    .keyboardShortcut("n")
                    .help("New meeting")
            }
        }
        .sheet(item: $draft) { draft in
            MeetingEditorView(draft: draft)
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(HideToTrayOnMinimize())
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            updateDisplayedRange()
        }
        .onChange(of: month) { updateDisplayedRange() }
    }

    private func changeMonth(by value: Int) {
        month = calendar.date(byAdding: .month, value: value, to: month)!
    }

    private func updateDisplayedRange() {
        let days = calendar.monthGrid(for: month)
        let range = DateInterval(start: days.first!, end: calendar.date(byAdding: .day, value: 1, to: days.last!)!)
        store.setDisplayedRange(range)
        calendarSync.setDisplayedRange(range)
    }

    private func newMeeting(on day: Date) {
        selectedDate = calendar.startOfDay(for: day)
        guard let meeting = store.newMeeting(start: defaultStart(on: day)) else { return }
        draft = MeetingDraft(meeting: meeting, isNew: true)
    }

    /// Next half hour for today, 9:00 for other days.
    private func defaultStart(on day: Date) -> Date {
        let now = Date()
        guard calendar.isDate(day, inSameDayAs: now) else {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        }
        let minute = calendar.component(.minute, from: now)
        let startOfHour = calendar.dateInterval(of: .hour, for: now)!.start
        return startOfHour.addingTimeInterval(minute < 30 ? 30 * 60 : 60 * 60)
    }

    private func edit(_ meeting: Meeting) {
        draft = MeetingDraft(meeting: meeting, isNew: false)
    }

    private func delete(_ meeting: Meeting) {
        Task { try? await store.delete(meeting) }
    }
}

/// Makes the window's minimize button close the window, leaving the app in the menu bar.
private struct HideToTrayOnMinimize: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { MinimizeInterceptor() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class MinimizeInterceptor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let button = window?.standardWindowButton(.miniaturizeButton) else { return }
            button.target = self
            button.action = #selector(hideToTray)
        }

        @objc private func hideToTray() {
            window?.performClose(nil)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
