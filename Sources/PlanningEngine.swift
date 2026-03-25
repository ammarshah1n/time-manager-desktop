import Foundation

struct RankedTask: Identifiable, Hashable {
    let task: TaskItem
    let score: Int
    let band: String
    let reasons: [String]

    var id: String { task.id }
}

enum PlanningEngine {
    static func rank(tasks: [TaskItem], now: Date = .now) -> [RankedTask] {
        tasks
            .map { task in
                let duePressure = dueDatePressure(task.dueDate, now: now)
                let confidenceGap = max(0, 5 - task.confidence) * 12
                let importanceWeight = task.importance * 18
                let effortWeight = min(task.estimateMinutes, 120) / 8
                let sourceWeight = sourceWeight(task.source)
                let total = importanceWeight + duePressure + confidenceGap + effortWeight + sourceWeight

                let reasons = [
                    "Importance \(importanceWeight)",
                    "Confidence gap \(confidenceGap)",
                    "Effort weight \(effortWeight)",
                    "Source \(task.source.rawValue) \(sourceWeight)",
                    duePressure > 0 ? "Deadline pressure \(duePressure)" : nil
                ]
                .compactMap { $0 }

                return RankedTask(task: task, score: total, band: band(for: total), reasons: reasons)
            }
            .sorted { $0.score > $1.score }
    }

    static func buildSchedule(tasks: [RankedTask], now: Date = .now) -> [ScheduleBlock] {
        let calendar = Calendar.current
        let start = roundedToNextHalfHour(now, calendar: calendar)
        let formatter = DateFormatter.timeRange

        var cursor = start
        return tasks.prefix(3).enumerated().map { index, ranked in
            let duration = durationMinutes(for: ranked.task.estimateMinutes)
            let blockStart = cursor
            let blockEnd = calendar.date(byAdding: .minute, value: duration, to: cursor) ?? cursor
            let titlePrefix = index == 0 ? "Do now" : ranked.band

            cursor = calendar.date(byAdding: .minute, value: duration + 10, to: blockEnd) ?? blockEnd

            return ScheduleBlock(
                id: "block-\(ranked.task.id)",
                title: "\(titlePrefix): \(ranked.task.title)",
                timeRange: formatter.string(from: blockStart, to: blockEnd),
                note: ranked.reasons.joined(separator: " · ")
            )
        }
    }

    private static func band(for score: Int) -> String {
        switch score {
        case 120...:
            return "Do now"
        case 95..<120:
            return "Today"
        case 70..<95:
            return "This week"
        default:
            return "Later"
        }
    }

    private static func dueDatePressure(_ dueDate: Date?, now: Date) -> Int {
        guard let dueDate else { return 0 }
        let delta = max(0, Calendar.current.dateComponents([.day], from: now, to: dueDate).day ?? 0)
        switch delta {
        case 0:
            return 55
        case 1:
            return 42
        case 2...3:
            return 28
        case 4...7:
            return 16
        default:
            return 6
        }
    }

    private static func sourceWeight(_ source: TaskSource) -> Int {
        switch source {
        case .seqta:
            return 16
        case .transcript:
            return 12
        case .tickTick:
            return 10
        case .chat:
            return 8
        }
    }

    private static func durationMinutes(for estimate: Int) -> Int {
        let rounded = Int(((Double(estimate) / 15.0).rounded(.toNearestOrAwayFromZero))) * 15
        return max(25, rounded)
    }

    private static func roundedToNextHalfHour(_ date: Date, calendar: Calendar) -> Date {
        let minute = calendar.component(.minute, from: date)
        let adjustment = minute < 30 ? 30 - minute : 60 - minute
        let start = calendar.date(byAdding: .minute, value: adjustment, to: date) ?? date
        return calendar.date(bySetting: .second, value: 0, of: start) ?? start
    }
}

private extension DateFormatter {
    static var timeRange: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }

    func string(from start: Date, to end: Date) -> String {
        "\(string(from: start)) - \(string(from: end))"
    }
}
