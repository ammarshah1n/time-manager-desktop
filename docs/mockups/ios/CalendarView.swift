// CalendarView.swift — Timed iOS Mockup
// Screen 2: Weekly calendar with colored time blocks, current-time line, tap-to-expand.
// Drag-and-drop from Inbox is simulated via the TimeBlockSheet — not implemented here.

import SwiftUI

// Layout constants
private let kHourHeight:     CGFloat = 64
private let kTimeColWidth:   CGFloat = 44
private let kHeaderHeight:   CGFloat = 62
private let kFirstHour:      Int     = 6
private let kLastHour:       Int     = 22  // exclusive — grid ends at 22:00

struct CalendarView: View {
    @State private var blocks      = MockTimeBlock.samples
    @State private var weekOffset  = 0          // 0 = current week
    @State private var selectedBlock: MockTimeBlock?

    // Mon … Sun for the displayed week
    var weekDates: [Date] {
        let cal  = Calendar.current
        let today = cal.startOfDay(for: Date())
        // weekday: 1=Sun … 7=Sat  →  daysFromMonday: 0=Mon … 6=Sun
        let weekday       = cal.component(.weekday, from: today)
        let daysFromMon   = (weekday + 5) % 7
        let monday        = cal.date(byAdding: .day, value: -daysFromMon + weekOffset * 7, to: today)!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    }

    // Index of today in weekDates (nil if today not in this week)
    var todayIndex: Int? {
        let cal = Calendar.current
        return weekDates.firstIndex { cal.isDateInToday($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayHeader(dates: weekDates, todayIndex: todayIndex)
                Divider()
                ScrollView(.vertical, showsIndicators: false) {
                    TimeGrid(
                        blocks: blocks,
                        todayIndex: todayIndex,
                        onTap: { selectedBlock = $0 }
                    )
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(weekTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        withAnimation(.easeInOut(duration: 0.2)) { weekOffset = 0 }
                    }
                    .disabled(weekOffset == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 2) {
                        Button { withAnimation { weekOffset -= 1 } } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                        }
                        Button { withAnimation { weekOffset += 1 } } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
            }
            .sheet(item: $selectedBlock) { block in
                BlockDetailSheet(block: block)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(20)
            }
        }
    }

    private var weekTitle: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let fmtYear = DateFormatter(); fmtYear.dateFormat = "MMM d, yyyy"
        let cal = Calendar.current
        if cal.component(.year, from: first) == cal.component(.year, from: Date()) {
            return "\(fmt.string(from: first)) – \(fmt.string(from: last))"
        }
        return fmtYear.string(from: first)
    }
}

// MARK: - Day Header

struct DayHeader: View {
    let dates: [Date]
    let todayIndex: Int?

    private let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    private let numFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d";   return f }()

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: kTimeColWidth)

            ForEach(Array(dates.enumerated()), id: \.offset) { idx, date in
                let isToday = idx == todayIndex

                VStack(spacing: 4) {
                    Text(dayFmt.string(from: date).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isToday ? Color.blue : Color.secondary)

                    ZStack {
                        if isToday {
                            Circle().fill(Color.blue).frame(width: 28, height: 28)
                        }
                        Text(numFmt.string(from: date))
                            .font(.system(size: 16, weight: isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? .white : .primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: kHeaderHeight)
            }
        }
    }
}

// MARK: - Time Grid

struct TimeGrid: View {
    let blocks: [MockTimeBlock]
    let todayIndex: Int?
    let onTap: (MockTimeBlock) -> Void

    private var totalHours: Int { kLastHour - kFirstHour }
    private var gridHeight: CGFloat { CGFloat(totalHours) * kHourHeight }

    private var currentTimeOffset: CGFloat? {
        let cal = Calendar.current
        let now = Date()
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        guard h >= kFirstHour && h < kLastHour else { return nil }
        return CGFloat(Double(h - kFirstHour) + Double(m) / 60.0) * kHourHeight
    }

    var body: some View {
        GeometryReader { geo in
            let colWidth = (geo.size.width - kTimeColWidth) / 7

            ZStack(alignment: .topLeading) {
                // Hour lines + labels
                VStack(spacing: 0) {
                    ForEach(kFirstHour...kLastHour, id: \.self) { hour in
                        HStack(alignment: .top, spacing: 0) {
                            Text(hourLabel(hour))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
                                .frame(width: kTimeColWidth - 6, alignment: .trailing)
                                .offset(y: -7)
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 0.5)
                        }
                        .frame(height: kHourHeight)
                    }
                }

                // Half-hour ticks
                VStack(spacing: 0) {
                    ForEach(kFirstHour..<kLastHour, id: \.self) { _ in
                        VStack(spacing: 0) {
                            Color.clear.frame(height: kHourHeight / 2)
                            HStack(spacing: 0) {
                                Color.clear.frame(width: kTimeColWidth)
                                Rectangle()
                                    .fill(Color(.systemGray6))
                                    .frame(height: 0.5)
                            }
                            Color.clear.frame(height: kHourHeight / 2)
                        }
                    }
                }

                // Today column highlight
                if let tidx = todayIndex {
                    Rectangle()
                        .fill(Color.blue.opacity(0.03))
                        .frame(width: colWidth)
                        .frame(height: gridHeight)
                        .offset(x: kTimeColWidth + CGFloat(tidx) * colWidth, y: 0)
                }

                // Time blocks
                ForEach(blocks) { block in
                    let y = CGFloat(block.startHour - Double(kFirstHour)) * kHourHeight
                    let h = max(CGFloat(block.durationHours) * kHourHeight - 2, 28)
                    let x = kTimeColWidth + CGFloat(block.weekdayIndex) * colWidth + 2

                    TimeBlockCell(block: block)
                        .frame(width: colWidth - 4, height: h)
                        .offset(x: x, y: y)
                        .onTapGesture { onTap(block) }
                }

                // Current time indicator (today column only)
                if let yOffset = currentTimeOffset {
                    CurrentTimeLine(
                        xStart: kTimeColWidth + CGFloat(todayIndex ?? 0) * colWidth,
                        width: colWidth
                    )
                    .offset(y: yOffset - 5)
                    .zIndex(20)
                }
            }
            .frame(width: geo.size.width, height: gridHeight + kHourHeight)
        }
        .frame(height: gridHeight + kHourHeight)
    }

    private func hourLabel(_ h: Int) -> String {
        if h == 0  { return "12am" }
        if h == 12 { return "12pm" }
        return h < 12 ? "\(h)am" : "\(h - 12)pm"
    }
}

// MARK: - Time Block Cell

struct TimeBlockCell: View {
    let block: MockTimeBlock

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(block.color.opacity(0.14))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(block.color)
                    .frame(width: 3)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.emailSubject)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(block.color)
                        .lineLimit(2)
                    Text(block.startTimeLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(block.color.opacity(0.75))
                }
                .padding(.leading, 6)
                .padding(.top, 4)
                .padding(.trailing, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Current Time Line

struct CurrentTimeLine: View {
    let xStart: CGFloat
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: xStart - 5)
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(Color.red)
                .frame(width: width, height: 1.5)
        }
    }
}

// MARK: - Block Detail Sheet

struct BlockDetailSheet: View {
    let block: MockTimeBlock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Accent header
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(block.color)
                        .frame(width: 4, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(block.emailSubject)
                            .font(.title3).fontWeight(.semibold)
                        Text("from \(block.sender)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                // Times
                HStack(spacing: 0) {
                    TimeStat(label: "Start",    value: block.startTimeLabel)
                    Spacer()
                    TimeStat(label: "End",      value: block.endTimeLabel)
                    Spacer()
                    TimeStat(label: "Duration", value: block.durationLabel)
                }

                // Actions
                VStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Start Focus Timer", systemImage: "timer")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 13))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 10) {
                        OutlineButton(label: "Reschedule", icon: "calendar.badge.clock") { dismiss() }
                        DestructiveButton(label: "Remove",      icon: "trash")             { dismiss() }
                    }
                }

                Spacer()
            }
            .padding(22)
            .navigationTitle("Time Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct TimeStat: View {
    let label: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 19, weight: .medium))
        }
    }
}

private struct OutlineButton: View {
    let label: String; let icon: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.primary)
        }
    }
}

private struct DestructiveButton: View {
    let label: String; let icon: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color(.systemRed).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    CalendarView()
}
