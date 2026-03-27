import Charts
import SwiftUI

struct DailyOverviewPriority: Identifiable {
    let taskID: String
    let title: String
    let subject: String
    let urgencyColor: Color

    var id: String { taskID }
}

struct DailyOverviewDeadline: Identifiable {
    let bucket: String
    let label: String
    let titles: [String]
    let color: Color

    var id: String { bucket }
}

struct DailyOverviewCard: View {
    let date: Date
    let priorities: [DailyOverviewPriority]
    let totalScheduledHours: Double
    let deadlines: [DailyOverviewDeadline]
    let todayPomodoroCount: Int
    let currentStudyStreak: Int
    let pomodoroTrend: [PomodoroDayStat]
    let tintColor: Color
    let onGenerateDayPlan: () async -> Void
    let onExportPDF: () async -> Void

    @AppStorage("timed.dailyOverviewCollapsed") private var isCollapsed = false
    @State private var isGenerating = false
    @State private var isExportingPDF = false
    @State private var launchPrompt: String

    init(
        date: Date,
        priorities: [DailyOverviewPriority],
        totalScheduledHours: Double,
        deadlines: [DailyOverviewDeadline],
        todayPomodoroCount: Int,
        currentStudyStreak: Int,
        pomodoroTrend: [PomodoroDayStat],
        tintColor: Color,
        onGenerateDayPlan: @escaping () async -> Void,
        onExportPDF: @escaping () async -> Void
    ) {
        self.date = date
        self.priorities = priorities
        self.totalScheduledHours = totalScheduledHours
        self.deadlines = deadlines
        self.todayPomodoroCount = todayPomodoroCount
        self.currentStudyStreak = currentStudyStreak
        self.pomodoroTrend = pomodoroTrend
        self.tintColor = tintColor
        self.onGenerateDayPlan = onGenerateDayPlan
        self.onExportPDF = onExportPDF
        _launchPrompt = State(
            initialValue: Self.launchPrompt(
                topPriorityTitle: priorities.first?.title,
                subject: priorities.first?.subject
            )
        )
    }

    var body: some View {
        TimedCard(title: "Today", icon: "sun.max.fill", accent: tintColor) {
            VStack(alignment: .leading, spacing: 14) {
                headerRow

                if !isCollapsed {
                    VStack(alignment: .leading, spacing: 14) {
                        pomodoroSection
                        prioritiesSection
                        statsRow
                        deadlineSection
                        promptSection
                        actionRow
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isCollapsed)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("Top priorities, deadlines, and your planning brief.")
                    .timedScaledFont(12, weight: .medium)
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Button {
                isCollapsed.toggle()
            } label: {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand today card" : "Collapse today card")
        }
    }

    private var prioritiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top 3 priorities")
                .timedScaledFont(12, weight: .semibold)
                .foregroundStyle(.white.opacity(0.62))
                .textCase(.uppercase)

            if priorities.isEmpty {
                Text("No active priorities yet. Import work to generate a day plan.")
                    .timedScaledFont(13)
                    .foregroundStyle(.white.opacity(0.64))
            } else {
                ForEach(priorities) { priority in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(priority.urgencyColor)
                            .frame(width: 9, height: 9)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(priority.title)
                                .timedScaledFont(14, weight: .semibold)
                                .foregroundStyle(.white)

                            Text(priority.subject)
                                .timedScaledFont(11, weight: .medium)
                                .foregroundStyle(.white.opacity(0.56))
                        }
                    }
                }
            }
        }
    }

    private var pomodoroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("🍅 \(todayPomodoroCount) today")
                    .timedScaledFont(13, weight: .semibold)
                    .foregroundStyle(.white)

                Text("🔥 \(currentStudyStreak) day streak")
                    .timedScaledFont(13, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.82))
            }

            Chart {
                ForEach(pomodoroTrend) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Pomodoros", point.count)
                    )
                    .foregroundStyle(tintColor.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { plotArea in
                plotArea
                    .background(.clear)
            }
            .frame(height: 84)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            overviewPill(
                title: "Planned today",
                value: formattedHours,
                tint: tintColor
            )

            overviewPill(
                title: "Deadlines",
                value: deadlines.isEmpty ? "Clear" : "\(deadlines.count)",
                tint: deadlines.isEmpty ? Color.white.opacity(0.24) : Color.orange
            )
        }
    }

    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if deadlines.isEmpty {
                Text("No deadlines due today or tomorrow.")
                    .timedScaledFont(13)
                    .foregroundStyle(.white.opacity(0.64))
            } else {
                ForEach(deadlines) { deadline in
                    Text(deadlineText(deadline))
                        .timedScaledFont(12, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(deadline.color.opacity(0.24))
                        )
                        .overlay(
                            Capsule()
                                .stroke(deadline.color.opacity(0.5), lineWidth: 1)
                        )
                }
            }
        }
    }

    private var promptSection: some View {
        Text(launchPrompt)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
    }

    private var actionRow: some View {
        HStack {
            Button {
                Task {
                    isGenerating = true
                    await onGenerateDayPlan()
                    isGenerating = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }

                    Text(isGenerating ? "Generating..." : "Generate Day Plan")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || priorities.isEmpty)

            Button {
                Task {
                    isExportingPDF = true
                    await onExportPDF()
                    isExportingPDF = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isExportingPDF {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "doc.richtext")
                    }

                    Text(isExportingPDF ? "Exporting..." : "Export PDF")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isExportingPDF)

            Spacer()
        }
    }

    private func overviewPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
    }

    private func deadlineText(_ deadline: DailyOverviewDeadline) -> String {
        let headline = deadline.label + ": "
        if deadline.titles.count <= 2 {
            return headline + deadline.titles.joined(separator: ", ")
        }

        let firstTwo = deadline.titles.prefix(2).joined(separator: ", ")
        let remainder = deadline.titles.count - 2
        return headline + firstTwo + " +\(remainder)"
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }

    private var formattedHours: String {
        if totalScheduledHours == 0 {
            return "0h"
        }

        if totalScheduledHours.rounded() == totalScheduledHours {
            return "\(Int(totalScheduledHours))h"
        }

        return totalScheduledHours.formatted(.number.precision(.fractionLength(1))) + "h"
    }

    private static func launchPrompt(topPriorityTitle: String?, subject: String?) -> String {
        let focus = topPriorityTitle ?? "your highest-leverage task"
        let subjectLabel = subject ?? "today"
        let templates = [
            "Start with \(focus) before you let smaller admin work steal the morning.",
            "Protect the first deep block for \(focus) and keep the rest of \(subjectLabel) lighter.",
            "Win the day by finishing the hardest part of \(focus) before lunch.",
            "Use your best energy on \(focus), then clear the lower-stakes tasks around it."
        ]
        return templates.randomElement() ?? "Protect your best energy for \(focus) first."
    }
}
