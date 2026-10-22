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
                closesIn: controller.closesIn(meeting),
                onDismiss: { controller.dismiss(meeting) }
            )
        }
    }
}

/// An ongoing meeting or a small countdown in the overview of today's meetings.
struct OverviewView: View {
    let controller: ReminderController
    /// The reminder key of the meeting this view shows.
    let key: String

    var body: some View {
        if let meeting = controller.overview[key] {
            let closesIn = controller.overviewUntil.map { $0.timeIntervalSince(controller.now) }
            if meeting.start <= controller.now {
                OngoingCard(
                    meeting: meeting,
                    closesIn: closesIn,
                    onJoin: { controller.dismissFromOverview(meeting) },
                    onDismiss: { controller.dismissFromOverview(meeting) }
                )
            } else {
                OverviewCard(
                    meeting: meeting,
                    remaining: meeting.start.timeIntervalSince(controller.now),
                    closesIn: closesIn,
                    onDismiss: { controller.dismissFromOverview(meeting) }
                )
            }
        }
    }
}

/// A toast about meetings added to a calendar since the previous sync.
struct NewMeetingsView: View {
    let controller: ReminderController

    var body: some View {
        if !controller.newMeetings.isEmpty {
            NewMeetingsCard(
                meetings: controller.newMeetings,
                closesIn: controller.newMeetingsUntil.map { $0.timeIntervalSince(controller.now) },
                onDismiss: controller.dismissNewMeetings
            )
        }
    }
}

/// A big message about started meetings without a link, until the user dismisses it.
struct NoLinkView: View {
    let controller: ReminderController

    var body: some View {
        if !controller.noLinkMeetings.isEmpty {
            NoLinkCard(
                meetings: controller.noLinkMeetings,
                dismissIn: controller.noLinkShownAt.map {
                    ReminderController.noLinkDismissDelay - controller.now.timeIntervalSince($0)
                } ?? 0,
                onDismiss: controller.dismissNoLink
            )
        }
    }
}

struct ReminderCard: View {
    let meeting: Meeting
    let remaining: TimeInterval
    let leadTime: TimeInterval
    /// Seconds until the card disappears, once the meeting has started.
    var closesIn: TimeInterval?
    var onDismiss: (() -> Void)?

    private var seconds: Int { Int(remaining.rounded(.up)) }

    /// Alternate between two shades every second during the last 10 seconds.
    private var isFlashing: Bool { remaining > 0 && remaining <= 10 && seconds % 2 == 0 }

    var body: some View {
        VStack(spacing: 4) {
            Text(Countdown.string(for: remaining))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))

            Text(meeting.displayTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(meeting.reminderSubtitle)
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
        .padding(20)
        .frame(width: 320)
        .card(
            color: Urgency.color(remaining: remaining, leadTime: leadTime, flashing: isFlashing),
            cornerRadius: 22, closesIn: closesIn, onDismiss: onDismiss
        )
        .animation(.easeInOut(duration: 0.4), value: seconds)
    }
}

/// A smaller countdown in a calm color, without the join button.
struct OverviewCard: View {
    static let color = Color(red: 0.25, green: 0.33, blue: 0.44)

    let meeting: Meeting
    let remaining: TimeInterval
    /// Seconds until the card disappears.
    var closesIn: TimeInterval?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 2) {
            Text(Countdown.string(for: remaining))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))

            Text(meeting.displayTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(meeting.reminderSubtitle)
                .font(.caption)
                .opacity(0.8)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 240)
        .card(color: Self.color, cornerRadius: 16, closesIn: closesIn, onDismiss: onDismiss)
        .animation(.easeInOut(duration: 0.4), value: Int(remaining.rounded(.up)))
    }
}

/// A meeting that is going on, with a join button when it has a link.
struct OngoingCard: View {
    static let color = Color(red: 0.42, green: 0.22, blue: 0.56)

    let meeting: Meeting
    /// Seconds until the card disappears.
    var closesIn: TimeInterval?
    var onJoin: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 2) {
            Label("In progress", systemImage: "record.circle")
                .font(.caption.weight(.semibold))
                .opacity(0.85)
                .padding(.bottom, 2)

            Text(meeting.displayTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(meeting.ongoingSubtitle)
                .font(.caption)
                .opacity(0.8)
                .lineLimit(1)

            if let url = meeting.url {
                Button {
                    NSWorkspace.shared.open(url)
                    onJoin?()
                } label: {
                    Label("Join meeting", systemImage: "video.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(JoinButtonStyle())
                .focusEffectDisabled()
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 240)
        .card(color: Self.color, cornerRadius: 16, closesIn: closesIn, onDismiss: onDismiss)
    }
}

/// Tells that meetings without a link have started. Its button can be used only after
/// `dismissIn` seconds, with a click, Return or Escape.
struct NoLinkCard: View {
    static let color = Color(red: 0.72, green: 0.04, blue: 0.14)

    let meetings: [Meeting]
    let dismissIn: TimeInterval
    let onDismiss: () -> Void

    private var canDismiss: Bool { dismissIn <= 0 }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 44))
            Text(meetings.count == 1 ? "Meeting started" : "\(meetings.count) meetings started")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            ForEach(meetings) { meeting in
                Text(meeting.displayTitle)
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Text(meetings.count == 1 ? "It has no meeting link." : "They have no meeting links.")
                .font(.title3)
                .opacity(0.8)

            Button(action: onDismiss) {
                Text(canDismiss ? "OK" : "OK (\(Int(dismissIn.rounded(.up))))")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(JoinButtonStyle())
            .focusEffectDisabled()
            .keyboardShortcut(.defaultAction)
            .disabled(!canDismiss)
            .frame(width: 200)
            .padding(.top, 14)
        }
        .padding(36)
        .frame(width: 560)
        .background {
            // Escape dismisses too.
            Button("", action: onDismiss)
                .keyboardShortcut(.cancelAction)
                .disabled(!canDismiss)
                .opacity(0)
        }
        .card(color: Self.color, cornerRadius: 28, onDismiss: nil)
    }
}

/// Lists new meetings with their dates, without countdowns.
struct NewMeetingsCard: View {
    static let color = Color(red: 0.20, green: 0.36, blue: 0.62)
    static let maxShown = 3

    let meetings: [Meeting]
    /// Seconds until the toast disappears.
    var closesIn: TimeInterval?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(meetings.count == 1 ? "New meeting" : "\(meetings.count) new meetings", systemImage: "calendar.badge.plus")
                .font(.subheadline.weight(.semibold))
                .opacity(0.85)
            ForEach(meetings.prefix(Self.maxShown)) { meeting in
                VStack(alignment: .leading, spacing: 1) {
                    Text(meeting.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(meeting.newMeetingSubtitle)
                        .font(.caption)
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            if meetings.count > Self.maxShown {
                Text("and \(meetings.count - Self.maxShown) more")
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 30)
        .padding(.vertical, 12)
        .frame(width: 280, alignment: .leading)
        .card(color: Self.color, cornerRadius: 16, closesIn: closesIn, onDismiss: onDismiss)
    }
}

private extension Meeting {
    var displayTitle: String {
        title.isEmpty ? "Untitled meeting" : title
    }

    var reminderSubtitle: String {
        let time = start.formatted(date: .omitted, time: .shortened)
        guard let host = url?.host() else { return time }
        return "\(time) · \(host)"
    }

    /// The start and end times, and the link's host.
    var ongoingSubtitle: String {
        let times = "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
        guard let host = url?.host() else { return times }
        return "\(times) · \(host)"
    }

    /// The day, time and whether the meeting repeats.
    var newMeetingSubtitle: String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(start) ? "Today"
            : calendar.isDateInTomorrow(start) ? "Tomorrow"
            : start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let time = "\(day) \(start.formatted(date: .omitted, time: .shortened))"
        return seriesID == nil ? time : "\(time) · Repeats"
    }
}

private extension View {
    /// White content on a rounded card of `color`, with a dismiss button in the corner.
    /// When the card disappears by itself, the seconds left are shown beside the button.
    func card(color: Color, cornerRadius: CGFloat, closesIn: TimeInterval? = nil, onDismiss: (() -> Void)?) -> some View {
        foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color.gradient)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    if let closesIn, closesIn > 0 {
                        Text("\(Int(closesIn.rounded(.up)))s")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .opacity(0.7)
                            .help("Disappears automatically")
                    }
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
                    }
                }
                .padding(cornerRadius / 2 - 1)
            }
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
        ReminderCard(meeting: meeting, remaining: -4, leadTime: 300, closesIn: 26)
        OverviewCard(meeting: meeting, remaining: 2 * 60 * 60 + 75, closesIn: 8)
        OngoingCard(meeting: meeting, closesIn: 8)
        NewMeetingsCard(meetings: [meeting], closesIn: 6)
        NoLinkCard(meetings: [meeting], dismissIn: 2, onDismiss: {})
    }
    .padding()
}
