import SwiftUI

struct MonthGridView: View {
    let month: Date
    @Binding var selectedDate: Date
    let meetingsOn: (Date) -> [Meeting]
    let onCreate: (Date) -> Void
    let onEdit: (Meeting) -> Void

    private let calendar = Calendar.current
    private static let maxVisibleMeetings = 3

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        let days = calendar.monthGrid(for: month)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)

            Divider()

            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                        dayCell(day)
                        if day != days[week * 7 + 6] { Divider() }
                    }
                }
                if week < 5 { Divider() }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let meetings = meetingsOn(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)

        return VStack(alignment: .leading, spacing: 2) {
            Text(day.formatted(.dateTime.day()))
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : inMonth ? Color.primary : Color.secondary)
                .frame(minWidth: 22, minHeight: 22)
                .background(isToday ? Color.accentColor : .clear, in: Circle())

            ForEach(meetings.prefix(Self.maxVisibleMeetings)) { meeting in
                MeetingChip(meeting: meeting)
                    .onTapGesture { onEdit(meeting) }
            }
            if meetings.count > Self.maxVisibleMeetings {
                Text("+\(meetings.count - Self.maxVisibleMeetings) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .opacity(inMonth ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onCreate(day) }
        .onTapGesture { selectedDate = calendar.startOfDay(for: day) }
    }
}

private struct MeetingChip: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 4) {
            Text(meeting.start.formatted(date: .omitted, time: .shortened))
                .foregroundStyle(.secondary)
            Text(meeting.title.isEmpty ? "Untitled" : meeting.title)
                .strikethrough(meeting.isDeclined)
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(meeting.isDeclined ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
        .opacity(meeting.isDeclined ? 0.6 : 1)
        .contentShape(Rectangle())
        .help(meeting.title)
    }
}

extension Calendar {
    /// Six full weeks covering the month containing `month`.
    func monthGrid(for month: Date) -> [Date] {
        let firstOfMonth = dateInterval(of: .month, for: month)!.start
        let offset = (component(.weekday, from: firstOfMonth) - firstWeekday + 7) % 7
        let gridStart = date(byAdding: .day, value: -offset, to: firstOfMonth)!
        return (0..<42).map { date(byAdding: .day, value: $0, to: gridStart)! }
    }
}
