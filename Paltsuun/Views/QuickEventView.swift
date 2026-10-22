import SwiftUI

/// Adds a local meeting starting soon, opened from the menu bar menu. The start can be set
/// as a time from now with the slider or as a clock time, and each updates the other.
struct QuickEventView: View {
    static let defaultTitle = "Quick event"
    static let defaultMinutes = 15
    /// The farthest the slider reaches. Later times can still be entered as a clock time.
    static let maxSliderMinutes = 8 * 60

    @Environment(MeetingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var now = Date()
    @State private var start = Date()
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Title", text: $title, prompt: Text(Self.defaultTitle))
                    .focused($titleFocused)
                LabeledContent("Starts in") {
                    HStack {
                        Slider(value: sliderPosition, in: 0...1)
                            .labelsHidden()
                        Text(Self.format(start.timeIntervalSince(now)))
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                    }
                }
                LabeledContent("Starts at") {
                    HStack {
                        if !Calendar.current.isDate(start, inSameDayAs: now) {
                            Text("Tomorrow")
                                .foregroundStyle(.secondary)
                        }
                        DatePicker("Starts at", selection: clockTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(start <= now)
            }
            .padding()
        }
        .frame(width: 420)
        .fixedSize()
        .onAppear(perform: reset)
        .task {
            // Keeps the time from now current while the window is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
    }

    /// The slider is quadratic, so short times can be set precisely and long ones still fit.
    private var sliderPosition: Binding<Double> {
        Binding(
            get: {
                let minutes = start.timeIntervalSince(now) / 60
                return min(1, max(0, minutes / Double(Self.maxSliderMinutes)).squareRoot())
            },
            set: { position in
                now = Date()
                start = now + TimeInterval(Self.minutes(at: position) * 60)
            }
        )
    }

    /// The next time the entered hour and minute come, today or tomorrow.
    private var clockTime: Binding<Date> {
        Binding(
            get: { start },
            set: { date in
                let calendar = Calendar.current
                var components = calendar.dateComponents([.hour, .minute], from: date)
                components.second = 0
                now = Date()
                if let next = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) {
                    start = next
                }
            }
        )
    }

    /// Rounded to whole minutes, and to 5 and 15 minutes for longer times.
    private static func minutes(at position: Double) -> Int {
        let minutes = Double(maxSliderMinutes) * position * position
        let step = minutes < 60 ? 1.0 : minutes < 180 ? 5.0 : 15.0
        return max(1, Int((minutes / step).rounded() * step))
    }

    private static func format(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        guard minutes > 0 else { return "Now" }
        let hours = minutes / 60
        if hours == 0 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min"
    }

    private func reset() {
        title = ""
        errorMessage = nil
        now = Date()
        start = now + TimeInterval(Self.defaultMinutes * 60)
        titleFocused = true
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var meeting = store.newMeeting(start: start, provider: store.localProvider) else {
            errorMessage = MeetingStoreError.noEditableProvider.localizedDescription
            return
        }
        meeting.title = trimmed.isEmpty ? Self.defaultTitle : trimmed
        Task {
            do {
                try await store.save(meeting)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
