import Foundation

enum PlanningEngine {
    static func rank(
        tasks: [TaskItem],
        contexts: [ContextItem] = [],
        now: Date = .now,
        promptBoostSubject: String? = nil
    ) -> [RankedTask] {
        let activeTasks = tasks.filter { !$0.isCompleted }
        let subjectCounts = Dictionary(grouping: activeTasks, by: \.subject).mapValues(\.count)

        return activeTasks
            .map { task in
                let duePressure = dueDatePressure(task.dueDate, now: now)
                let confidenceGap = max(0, 5 - task.confidence) * 12
                let importanceWeight = task.importance * 18
                let effortWeight = min(task.estimateMinutes, 120) / 8
                let sourceWeight = sourceWeight(task.source)
                let subjectPressure = max(0, (subjectCounts[task.subject] ?? 1) - 1) * 3
                let recencyBoost = recentContextBoost(for: task.subject, contexts: contexts, now: now)
                let promptBoost = promptBoostValue(task.subject, promptBoostSubject: promptBoostSubject)
                let total = importanceWeight + duePressure + confidenceGap + effortWeight + sourceWeight + subjectPressure + recencyBoost + promptBoost

                let reasons = [
                    "Importance \(importanceWeight)",
                    duePressure > 0 ? "Deadline pressure \(duePressure)" : nil,
                    "Confidence gap \(confidenceGap)",
                    "Effort weight \(effortWeight)",
                    "Source \(task.source.rawValue) \(sourceWeight)",
                    subjectPressure > 0 ? "Subject pressure \(subjectPressure)" : nil,
                    recencyBoost > 0 ? "Fresh context \(recencyBoost)" : nil,
                    promptBoost > 0 ? "Prompt boost \(promptBoost)" : nil
                ]
                .compactMap { $0 }

                return RankedTask(
                    task: task,
                    score: total,
                    band: band(for: total),
                    reasons: reasons,
                    suggestedNextAction: suggestedNextAction(for: task, scoreBand: band(for: total))
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.task.title < rhs.task.title
                }
                return lhs.score > rhs.score
            }
    }

    static func buildSchedule(
        tasks: [RankedTask],
        now: Date = .now,
        windowMinutes: Int = 180
    ) -> [ScheduleBlock] {
        let calendar = Calendar.current
        let start = roundedToNextQuarterHour(now, calendar: calendar)
        let formatter = DateFormatter.timeRange
        let lateNight = calendar.component(.hour, from: now) >= 21
        let sortedTasks = lateNight
            ? tasks.sorted { lhs, rhs in
                if lhs.task.energy == rhs.task.energy {
                    return lhs.score > rhs.score
                }
                return lhs.task.energy == .high && rhs.task.energy != .high
            }
            : tasks

        var scheduled: [ScheduleBlock] = []
        var cursor = start
        var usedMinutes = 0

        for ranked in sortedTasks {
            let duration = durationMinutes(for: ranked.task.estimateMinutes)
            guard usedMinutes + duration <= windowMinutes else { break }

            let blockStart = cursor
            let blockEnd = calendar.date(byAdding: .minute, value: duration, to: blockStart) ?? blockStart
            let block = ScheduleBlock(
                id: "block-\(ranked.task.id)",
                taskID: ranked.task.id,
                title: ranked.task.title,
                start: blockStart,
                end: blockEnd,
                timeRange: formatter.string(from: blockStart, to: blockEnd),
                note: ranked.reasons.joined(separator: " · "),
                isApproved: false
            )

            scheduled.append(block)
            usedMinutes += duration
            cursor = calendar.date(byAdding: .minute, value: duration + 10, to: blockStart) ?? blockEnd
        }

        return scheduled
    }

    private static func band(for score: Int) -> String {
        switch score {
        case 150...:
            return "Do now"
        case 115..<150:
            return "Today"
        case 80..<115:
            return "This week"
        default:
            return "Later"
        }
    }

    private static func dueDatePressure(_ dueDate: Date?, now: Date) -> Int {
        guard let dueDate else { return 0 }

        let hours = dueDate.timeIntervalSince(now) / 3600
        switch hours {
        case ..<0:
            return 65
        case 0..<24:
            return 55
        case 24..<48:
            return 42
        case 48..<96:
            return 28
        case 96..<168:
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

    private static func recentContextBoost(for subject: String, contexts: [ContextItem], now: Date) -> Int {
        let hasFreshContext = contexts.contains { context in
            context.subject.caseInsensitiveCompare(subject) == .orderedSame &&
                now.timeIntervalSince(context.createdAt) <= 48 * 3600
        }
        return hasFreshContext ? 8 : 0
    }

    private static func promptBoostValue(_ subject: String, promptBoostSubject: String?) -> Int {
        guard let promptBoostSubject else { return 0 }
        return promptBoostSubject.caseInsensitiveCompare(subject) == .orderedSame ? 20 : 0
    }

    private static func suggestedNextAction(for task: TaskItem, scoreBand: String) -> String {
        switch (scoreBand, task.source) {
        case ("Do now", .seqta):
            return "Start this immediately — it's a school assignment."
        case ("Do now", .tickTick):
            return "Start the first 25 minutes now and clear the hardest part first."
        case ("Today", .tickTick):
            return "Block 30 minutes this afternoon."
        case ("Today", .seqta):
            return "Schedule a focused school block before dinner."
        case ("This week", .transcript):
            return "Use this as revision support after urgent tasks are done."
        case ("Later", _):
            return "Park this for now and revisit after higher-pressure work."
        default:
            return "Take the next concrete step and keep it time-boxed."
        }
    }

    private static func durationMinutes(for estimate: Int) -> Int {
        let rounded = Int((Double(max(estimate, 5)) / 15.0).rounded(.up)) * 15
        return max(25, rounded)
    }

    private static func roundedToNextQuarterHour(_ date: Date, calendar: Calendar) -> Date {
        let minute = calendar.component(.minute, from: date)
        let remainder = minute % 15
        let adjustment = remainder == 0 ? 0 : 15 - remainder
        let adjusted = calendar.date(byAdding: .minute, value: adjustment, to: date) ?? date
        return calendar.date(bySetting: .second, value: 0, of: adjusted) ?? adjusted
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
