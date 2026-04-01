// PlanningEngine.swift — Timed Core
// Pure Swift planning algorithm. No I/O. No async.
// See: ~/Timed-Brain/06 - Context/planning-algorithm-architecture.md
//
// Algorithm: bounded priority-ordered knapsack with hard sequencing constraints.
// NOT bin-packing. Tasks are ordered by composite score, then greedily added
// until available minutes are exhausted.

import Foundation
import os

// MARK: - Input Types

struct PlanRequest: Sendable {
    let workspaceId: UUID
    let profileId: UUID
    let availableMinutes: Int
    let moodContext: MoodContext?
    let behaviouralRules: [BehaviourRule]
    let tasks: [PlanTask]
    let bucketStats: [BucketCompletionStat]
}

enum MoodContext: String, Sendable {
    case easyWins = "easy_wins"
    case avoidance
    case deepFocus = "deep_focus"
}

struct BehaviourRule: Sendable {
    let ruleKey: String
    let ruleType: String  // "ordering" | "threshold" | "timing" | "category_pref"
    let ruleValueJson: Data
    let confidence: Float
}

struct PlanTask: Identifiable, Sendable {
    let id: UUID
    let title: String
    let bucketType: String
    let estimatedMinutes: Int
    let priority: Int
    let dueAt: Date?
    let isOverdue: Bool
    let isDoFirst: Bool
    let isDailyUpdate: Bool
    let isFamilyEmail: Bool
    let deferredCount: Int
    let isTransitSafe: Bool
}

// MARK: - Output Types

struct PlanItem: Sendable {
    let task: PlanTask
    let position: Int
    let estimatedMinutes: Int
    let bufferAfterMinutes: Int
    let rankReason: String?
    let scoreBreakdown: ScoreBreakdown
}

struct ScoreBreakdown: Sendable {
    let base: Int
    let overdueBump: Int
    let deadlineBump: Int
    let moodBump: Int
    let behaviourBump: Int
    let timingBump: Int
    let thompsonBump: Int
    let totalScore: Int
}

struct PlanResult: Sendable {
    let items: [PlanItem]
    let totalMinutes: Int
    let overflowTasks: [PlanTask]  // tasks that didn't fit, sorted by score desc
    let generatedAt: Date
}

// MARK: - Score Constants

private enum Score {
    static let fixedFirst   = 100_000   // daily_update email — always pos 0
    static let fixedSecond  =  99_000   // family_email — always pos 1
    static let overdueBump  =   1_000
    static let actionBump   =     400
    static let replyBump    =     350
    static let callsBump    =     250
    static let transitBump  =     150
    static let readBump     =     100
    static let deadline24h  =     500
    static let deadline72h  =     200
    static let deadline1w   =     100
    static let quickWinBump =     150   // estimatedMinutes <= 5
    static let durationPenalty = -2     // per minute
    static let moodEasyWins =    500    // boost if est <= 5
    static let moodAvoidance =   500    // boost if deferredCount >= 2
    static let deepFocusKill = -9_999   // non-action in deep_focus mode
    static let behaviourOrdering = 300  // ordering rule bump
    static let behaviourMood =   500    // mood-override bump (used by easy_wins/avoidance)
    static let timingMatch   =   200    // timing rule — current hour in preferred window
    static let timingMiss    =  -100    // timing rule — current hour outside preferred window
    static let thompsonMax   =   250    // max Thompson sampling bump when completion ratio is high
    static let thompsonMinSamples = 10  // minimum completions + deferrals before Thompson activates
}

private let bufferPerTask = 5  // minutes added between tasks in budget calculation

// MARK: - PlanningEngine

enum PlanningEngine {

    // MARK: - Public API

    /// Generates a daily plan synchronously.
    /// Pure — no I/O, no async, no external dependencies.
    static func generatePlan(_ request: PlanRequest) -> PlanResult {
        TimedLogger.planning.info("Generating plan: \(request.tasks.count) tasks, \(request.availableMinutes) min available, mood=\(request.moodContext?.rawValue ?? "none", privacy: .public)")
        let now = Date()

        // Quiet hours: if enabled and current hour < quietEnd, only include isDoFirst tasks
        let quietEnabled = UserDefaults.standard.bool(forKey: "prefs.quietHours.enabled")
        let quietEnd = UserDefaults.standard.integer(forKey: "prefs.quietHours.end")
        let currentHour = Calendar.current.component(.hour, from: now)
        let effectiveTasks: [PlanTask]
        if quietEnabled && currentHour < quietEnd {
            effectiveTasks = request.tasks.filter { $0.isDoFirst }
            TimedLogger.planning.info("Quiet hours active (until \(quietEnd):00) — \(effectiveTasks.count) Do First tasks only")
        } else {
            effectiveTasks = request.tasks
        }

        // 1. Score all tasks
        let scored: [(task: PlanTask, breakdown: ScoreBreakdown)] = effectiveTasks.map { task in
            let breakdown = scoreTask(task, now: now, moodContext: request.moodContext, behaviouralRules: request.behaviouralRules, bucketStats: request.bucketStats)
            return (task, breakdown)
        }

        // 2. Apply hard constraints — pull fixed-position tasks out of the pool
        var fixedFirst: (task: PlanTask, breakdown: ScoreBreakdown)?
        var fixedSecond: (task: PlanTask, breakdown: ScoreBreakdown)?
        var pool: [(task: PlanTask, breakdown: ScoreBreakdown)] = []

        for item in scored {
            if item.task.isDailyUpdate {
                fixedFirst = item
            } else if item.task.isFamilyEmail {
                fixedSecond = item
            } else {
                pool.append(item)
            }
        }

        // 3. Sort pool by score descending
        pool.sort { $0.breakdown.totalScore > $1.breakdown.totalScore }

        // 4. Greedy knapsack — fill available minutes
        var selected: [(task: PlanTask, breakdown: ScoreBreakdown)] = []
        var overflow: [PlanTask] = []
        var usedMinutes = 0

        // Reserve budget for fixed-position tasks
        if let f = fixedFirst {
            usedMinutes += f.task.estimatedMinutes + bufferPerTask
        }
        if let s = fixedSecond {
            usedMinutes += s.task.estimatedMinutes + bufferPerTask
        }

        for item in pool {
            let cost = item.task.estimatedMinutes + bufferPerTask
            if usedMinutes + item.task.estimatedMinutes <= request.availableMinutes {
                selected.append(item)
                usedMinutes += cost
            } else {
                overflow.append(item.task)
            }
        }

        // 5. Assemble ordered list: fixed positions first, then knapsack selection
        var ordered: [(task: PlanTask, breakdown: ScoreBreakdown)] = []
        if let f = fixedFirst { ordered.append(f) }
        if let s = fixedSecond { ordered.append(s) }
        ordered.append(contentsOf: selected)

        // 6. Build PlanItems with computed rank reason
        let items: [PlanItem] = ordered.enumerated().map { index, entry in
            PlanItem(
                task: entry.task,
                position: index,
                estimatedMinutes: entry.task.estimatedMinutes,
                bufferAfterMinutes: bufferPerTask,
                rankReason: computeReason(entry.task, breakdown: entry.breakdown, moodContext: request.moodContext),
                scoreBreakdown: entry.breakdown
            )
        }

        // 7. Compute actual total (sum of selected task minutes only, no trailing buffer)
        let totalMinutes = items.reduce(0) { $0 + $1.estimatedMinutes }

        // 8. Sort overflow by score desc for caller convenience
        let overflowSorted = overflow.sorted {
            let a = scoreTask($0, now: now, moodContext: request.moodContext, behaviouralRules: request.behaviouralRules, bucketStats: request.bucketStats).totalScore
            let b = scoreTask($1, now: now, moodContext: request.moodContext, behaviouralRules: request.behaviouralRules, bucketStats: request.bucketStats).totalScore
            return a > b
        }

        let result = PlanResult(
            items: items,
            totalMinutes: totalMinutes,
            overflowTasks: overflowSorted,
            generatedAt: now
        )
        TimedLogger.planning.info("Plan generated: \(result.items.count) tasks selected, \(result.totalMinutes) min planned, \(result.overflowTasks.count) overflow")
        return result
    }

    // MARK: - Scoring

    /// Computes a composite score for a task. Pure function.
    static func scoreTask(
        _ task: PlanTask,
        now: Date,
        moodContext: MoodContext?,
        behaviouralRules: [BehaviourRule],
        bucketStats: [BucketCompletionStat] = []
    ) -> ScoreBreakdown {

        // Hard overrides for fixed-position tasks
        if task.isDailyUpdate {
            return ScoreBreakdown(base: Score.fixedFirst, overdueBump: 0, deadlineBump: 0, moodBump: 0, behaviourBump: 0, timingBump: 0, thompsonBump: 0, totalScore: Score.fixedFirst)
        }
        if task.isFamilyEmail {
            return ScoreBreakdown(base: Score.fixedSecond, overdueBump: 0, deadlineBump: 0, moodBump: 0, behaviourBump: 0, timingBump: 0, thompsonBump: 0, totalScore: Score.fixedSecond)
        }

        // Base: bucket type + priority + duration penalty
        let bucketBase: Int
        switch task.bucketType {
        case "action":  bucketBase = Score.actionBump
        case "reply":   bucketBase = Score.replyBump
        case "calls":   bucketBase = Score.callsBump
        case "transit": bucketBase = Score.transitBump
        case "read":    bucketBase = Score.readBump
        default:        bucketBase = 0
        }

        // Priority is 0–5 scale from DB; multiply to give meaningful weight
        let priorityBase = task.priority * 80

        // Quick win bump
        let quickWin = task.estimatedMinutes <= 5 ? Score.quickWinBump : 0

        // Duration penalty (discourages padding plan with long tasks when shorter are available)
        let durationPenalty = task.estimatedMinutes * Score.durationPenalty

        let base = bucketBase + priorityBase + quickWin + durationPenalty

        // Overdue bump
        let overdueBump = task.isOverdue ? Score.overdueBump : 0

        // Deadline bump
        var deadlineBump = 0
        if let dueAt = task.dueAt {
            let hoursUntilDue = dueAt.timeIntervalSince(now) / 3600
            if hoursUntilDue <= 24 {
                deadlineBump = Score.deadline24h
            } else if hoursUntilDue <= 72 {
                deadlineBump = Score.deadline72h
            } else if hoursUntilDue <= 168 {
                deadlineBump = Score.deadline1w
            }
        }

        // Mood modifier (applied before knapsack per spec)
        var moodBump = 0
        if let mood = moodContext {
            switch mood {
            case .easyWins:
                if task.estimatedMinutes <= 5 {
                    moodBump = Score.moodEasyWins
                }
            case .avoidance:
                if task.deferredCount >= 2 {
                    moodBump = Score.moodAvoidance
                }
            case .deepFocus:
                if task.bucketType != "action" {
                    // Kill non-action tasks in deep focus — they won't make it past knapsack
                    moodBump = Score.deepFocusKill
                }
            }
        }

        // Behavioural rules — ordering
        var behaviourBump = 0
        for rule in behaviouralRules where rule.ruleType == "ordering" {
            // Decode rule to determine if it applies to this task.
            // Rule value JSON expected shape: {"bucket": "calls"} or {"ruleKey": "calls_before_email"}
            // Low-confidence rules are discounted.
            if let ruleDict = try? JSONSerialization.jsonObject(with: rule.ruleValueJson) as? [String: String] {
                let targetBucket = ruleDict["bucket"] ?? ruleDict["source_bucket"] ?? ""
                if !targetBucket.isEmpty && task.bucketType == targetBucket {
                    let confidenceWeight = Double(rule.confidence)
                    behaviourBump += Int(Double(Score.behaviourOrdering) * confidenceWeight)
                }
            }
        }

        // Behavioural rules — timing (energy curve from hour_of_day)
        var timingBump = 0
        for rule in behaviouralRules where rule.ruleType == "timing" {
            if let json = try? JSONSerialization.jsonObject(with: rule.ruleValueJson) as? [String: Any],
               let bucket = json["bucket_type"] as? String,
               let hours = json["preferred_hours"] as? [Int],
               bucket == task.bucketType {
                let currentHour = Calendar.current.component(.hour, from: now)
                if hours.contains(currentHour) {
                    timingBump += Int(Double(Score.timingMatch) * Double(rule.confidence))
                } else {
                    timingBump += Int(Double(Score.timingMiss) * Double(rule.confidence))
                }
            }
        }

        // Thompson sampling proxy — only activates with sufficient data
        let thompsonBump = Self.thompsonBump(
            bucketType: task.bucketType,
            currentHour: Calendar.current.component(.hour, from: now),
            stats: bucketStats
        )

        let total = base + overdueBump + deadlineBump + moodBump + behaviourBump + timingBump + thompsonBump

        return ScoreBreakdown(
            base: base,
            overdueBump: overdueBump,
            deadlineBump: deadlineBump,
            moodBump: moodBump,
            behaviourBump: behaviourBump,
            timingBump: timingBump,
            thompsonBump: thompsonBump,
            totalScore: total
        )
    }

    // MARK: - Thompson Sampling

    /// Computes a score bump based on historical completion rate for this bucket+hour.
    /// Uses simple completion ratio as a proxy until enough data accumulates for real Beta sampling.
    /// Returns 0 if fewer than `thompsonMinSamples` observations exist.
    static func thompsonBump(
        bucketType: String,
        currentHour: Int,
        stats: [BucketCompletionStat]
    ) -> Int {
        let hourRange: String
        switch currentHour {
        case 6...11:  hourRange = "06-12"
        case 12...15: hourRange = "12-16"
        case 16...19: hourRange = "16-20"
        default:      hourRange = "20-06"
        }

        guard let stat = stats.first(where: { $0.bucketType == bucketType && $0.hourRange == hourRange }) else {
            return 0
        }

        let total = stat.completions + stat.deferrals
        guard total >= Score.thompsonMinSamples else { return 0 }

        // Simple ratio proxy: completions / total, scaled to thompsonMax
        let ratio = Double(stat.completions) / Double(total)
        return Int(ratio * Double(Score.thompsonMax))
    }

    // MARK: - Reason computation

    private static func computeReason(_ task: PlanTask, breakdown: ScoreBreakdown, moodContext: MoodContext?) -> String {
        if task.isDoFirst { return "Do First" }
        if task.isOverdue { return "Overdue — \(task.deferredCount * 7)+ days" }
        if breakdown.deadlineBump >= 500 { return "Due today" }
        if breakdown.deadlineBump >= 200 { return "Due within 3 days" }
        if breakdown.moodBump > 0 {
            switch moodContext {
            case .easyWins:  return "Quick win (\(task.estimatedMinutes)m)"
            case .avoidance: return "Deferred \(task.deferredCount)× — clear it"
            default: break
            }
        }
        if breakdown.overdueBump > 0 { return "Overdue" }
        let bucket = task.bucketType.prefix(1).uppercased() + task.bucketType.dropFirst()
        return "\(bucket) — \(task.estimatedMinutes)m"
    }
}
