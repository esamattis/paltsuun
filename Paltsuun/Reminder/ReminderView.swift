import AppKit
import SwiftUI

struct ReminderView: View {
    let controller: ReminderController
    /// The reminder key of the meeting this view counts down to.
    let key: String

    var body: some View {
        if let meeting = controller.reminders[key] {
            ReminderCard(
                meeting: meeting,
                remaining: meeting.start.timeIntervalSince(controller.now),
                leadTime: controller.leadTime,
                onDismiss: { controller.dismiss(meeting) }
            )
        }
    }
}

struct ReminderCard: View {
    let meeting: Meeting
    let remaining: TimeInterval
    let leadTime: TimeInterval
    var onDismiss: (() -> Void)?

    private var seconds: Int { Int(remaining.rounded(.up)) }

    /// Alternate between two shades every second during the last 10 seconds.
    private var isFlashing: Bool { remaining > 0 && remaining <= 10 && seconds % 2 == 0 }

    private var subtitle: String {
        let time = meeting.start.formatted(date: .omitted, time: .shortened)
        guard let host = meeting.url?.host() else { return time }
        return "\(time) · \(host)"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(Countdown.string(for: remaining))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))

            Text(meeting.title.isEmpty ? "Untitled meeting" : meeting.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(subtitle)
                .font(.callout)
                .opacity(0.8)
                .lineLimit(1)

            Button {
                if let url = meeting.url { NSWorkspace.shared.open(url) }
            } label: {
                Label(meeting.url == nil ? "No meeting link" : "Join meeting", systemImage: "video.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(JoinButtonStyle())
            .focusEffectDisabled()
            .disabled(meeting.url == nil)
            .padding(.top, 10)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(width: 320)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Urgency.color(remaining: remaining, leadTime: leadTime, flashing: isFlashing).gradient)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(.white.opacity(0.18), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .focusEffectDisabled()
                .help("Dismiss")
                .padding(10)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: seconds)
    }
}

private struct JoinButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .background(.white.opacity(configuration.isPressed ? 0.4 : 0.22), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Green when there is plenty of time, through amber and orange to red at start time.
enum Urgency {
    private typealias RGB = (red: Double, green: Double, blue: Double)

    /// Fraction of the lead time remaining, and the color at that point.
    private static let stops: [(fraction: Double, color: RGB)] = [
        (1.0, (0.13, 0.60, 0.36)),
        (0.6, (0.82, 0.56, 0.04)),
        (0.3, (0.89, 0.37, 0.09)),
        (0.1, (0.85, 0.15, 0.22)),
        (0.0, (0.72, 0.04, 0.14)),
    ]
    private static let flash: RGB = (1.0, 0.30, 0.34)

    static func color(remaining: TimeInterval, leadTime: TimeInterval, flashing: Bool = false) -> Color {
        if flashing { return color(flash) }
        let fraction = min(max(remaining / leadTime, 0), 1)
        for (upper, lower) in zip(stops, stops.dropFirst()) where fraction >= lower.fraction {
            let t = (fraction - lower.fraction) / (upper.fraction - lower.fraction)
            return color((
                lower.color.red + (upper.color.red - lower.color.red) * t,
                lower.color.green + (upper.color.green - lower.color.green) * t,
                lower.color.blue + (upper.color.blue - lower.color.blue) * t
            ))
        }
        return color(stops.last!.color)
    }

    private static func color(_ rgb: RGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

#Preview {
    let meeting = Meeting(
        id: "preview", providerID: "local", title: "Weekly planning",
        start: .now + 75, end: .now + 1875, url: URL(string: "https://meet.google.com/abc-defg-hij")
    )
    return HStack {
        ReminderCard(meeting: meeting, remaining: 280, leadTime: 300)
        ReminderCard(meeting: meeting, remaining: 120, leadTime: 300)
        ReminderCard(meeting: meeting, remaining: 20, leadTime: 300)
    }
    .padding()
}
