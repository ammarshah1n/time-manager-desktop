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
    var bucketEstimates: [String: Double] = [:]  // bucket.rawValue -> corrected mean minutes
    var calendarBlocks: [CalendarBlock] = []      // today's calendar events — meetings subtract from available time
    var workStartHour: Int = 9                    // user's preferred work window start (0–23)
    var workEndHour: Int = 18                     // user's preferred work window end (0–23)
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
    let scheduledSlotStart: Date?  // from TimeSlotAllocator — nil if no slot assigned
}

struct ScoreBreakdown: Sendable {
    let base: Int
    let overdueBump: Int
    let deadlineBump: Int
    let moodBump: Int
    let behaviourBump: Int
    let timingBump: Int
    let thompsonBump: Int
    let workHourPenalty: Int
    let totalScore: Int
}

struct PlanResult: Sendable {
    let items: [PlanItem]
    let totalMinutes: Int
    let overflowTasks: [PlanTask]  // tasks that didn't fit, sorted by score desc
    let generatedAt: Date
    // Allocation metadata from TimeSlotAllocator
    let totalFreeMinutes: Int          // total free time in work window
    let freeTimeGapCount: Int          // number of free-time blocks
    let utilizationPercent: Double     // how loaded the plan is (0–100)
    let warningMessage: String?        // over-scheduling warning if applicable
    let deferredTaskIds: [UUID]        // task IDs that didn't fit
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
    static let outsideWorkHour = -400   // penalty for tasks placed outside user's work window
}

private let bufferPerTask = 5  // minutes added between tasks in budget calculation

// MARK: - PlanningEngine

enum PlanningEngine {

    // MARK: - Public API

    /// Generates a daily plan synchronously.
    /// Pure — no I/O, no async, no external dependencies.
    static func generatePlan(_ request: PlanRequest) -> PlanResult {
        // Subtract calendar block (meeting) time from available minutes
        let meetingMinutes = calendarBlockMinutesToday(request.calendarBlocks)
        let effectiveAvailable = max(0, request.availableMinutes - meetingMinutes)
        TimedLogger.planning.info("Generating plan: \(request.tasks.count) tasks, \(request.availableMinutes) min declared, \(meetingMinutes) min in meetings, \(effectiveAvailable) min effective, mood=\(request.moodContext?.rawValue ?? "none", privacy: .public)")
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
        var scored: [(task: PlanTask, breakdown: ScoreBreakdown)] = effectiveTasks.map { task in
            let breakdown = scoreTask(task, now: now, moodContext: request.moodContext, behaviouralRules: request.behaviouralRules, bucketStats: request.bucketStats, bucketEstimates: request.bucketEstimates, availableMinutes: effectiveAvailable, workStartHour: request.workStartHour, workEndHour: request.workEndHour)
            return (task, breakdown)
        }

        // 1b. Cap overdue dominance: only top 3 overdue tasks get full bump.
        //     Sort by total score desc first so the "top 3" are the highest-scoring overdue items.
        scored.sort { $0.breakdown.totalScore > $1.breakdown.totalScore }
        var overdueCount = 0
        for i in scored.indices {
            if scored[i].task.isOverdue {
                overdueCount += 1
                if overdueCount > 3 {
                    // Reduce the overdue bump for excess overdue tasks
                    let breakdown = scored[i].breakdown
                    let reducedOverdue = 200  // Down from 1000
                    let newTotal = breakdown.totalScore - (breakdown.overdueBump - reducedOverdue)
                    scored[i] = (task: scored[i].task, breakdown: ScoreBreakdown(
                        base: breakdown.base, overdueBump: reducedOverdue,
                        deadlineBump: breakdown.deadlineBump, moodBump: breakdown.moodBump,
                        behaviourBump: breakdown.behaviourBump, timingBump: breakdown.timingBump,
                        thompsonBump: breakdown.thompsonBump, workHourPenalty: breakdown.workHourPenalty,
                        totalScore: newTotal
                    ))
                }
            }
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

        // 3. Build full task list for allocator: fixed-position tasks first, then pool by score
        pool.sort { $0.breakdown.totalScore > $1.breakdown.totalScore }

        var allScoredForAllocator: [(task: PlanTask, breakdown: ScoreBreakdown)] = []
        if let f = fixedFirst { allScoredForAllocator.append(f) }
        if let s = fixedSecond { allScoredForAllocator.append(s) }
        allScoredForAllocator.append(contentsOf: pool)

        let allocatorTasks: [SlotTaskInput] = allScoredForAllocator.map { entry in
            let corrected = request.bucketEstimates[entry.task.bucketType].map { Int($0) } ?? entry.task.estimatedMinutes
            return SlotTaskInput(
                id: entry.task.id,
                estimatedMinutes: corrected,
                bucketType: entry.task.bucketType,
                priorityScore: Double(entry.breakdown.totalScore),
                isLocked: false,
                lockedStartTime: nil,
                prepForMeetingId: nil
            )
        }

        // 4. Compute work window dates
        let calendar = Calendar.current
        let today = Date()
        let workStart = calendar.date(bySettingHour: request.workStartHour, minute: 0, second: 0, of: today)!
        let workEnd = calendar.date(bySettingHour: request.workEndHour, minute: 0, second: 0, of: today)!

        // 5. Call TimeSlotAllocator
        let allocation = TimeSlotAllocator.buildDayPlan(
            calendarBlocks: request.calendarBlocks,
            tasks: allocatorTasks,
            workStart: workStart,
            workEnd: workEnd
        )

        // Also compute free-time gap stats for the result
        let freeTimeStats = TimeSlotAllocator.computeFreeTime(
            calendarBlocks: request.calendarBlocks,
            workStart: workStart,
            workEnd: workEnd
        )

        // 6. Map allocation results back to PlanItems, ordered by slotStart
        let scoredById = Dictionary(uniqueKeysWithValues: allScoredForAllocator.map { ($0.task.id, $0) })
        let scheduledSlots = allocation.scheduled.sorted { $0.slotStart < $1.slotStart }

        let items: [PlanItem] = scheduledSlots.enumerated().compactMap { (index, slot) -> PlanItem? in
            guard let entry = scoredById[slot.taskId] else { return nil }
            return PlanItem(
                task: entry.task,
                position: index,
                estimatedMinutes: entry.task.estimatedMinutes,
                bufferAfterMinutes: bufferPerTask,
                rankReason: computeReason(entry.task, breakdown: entry.breakdown, moodContext: request.moodContext),
                scoreBreakdown: entry.breakdown,
                scheduledSlotStart: slot.slotStart
            )
        }

        // 7. Compute actual total
        let totalMinutes = items.reduce(0) { $0 + $1.estimatedMinutes }

        // 8. Build overflow list from deferred IDs, sorted by score desc
        let deferredSet = Set(allocation.deferred)
        let overflowSorted = allScoredForAllocator
            .filter { deferredSet.contains($0.task.id) }
            .sorted { $0.breakdown.totalScore > $1.breakdown.totalScore }
            .map(\.task)

        let result = PlanResult(
            items: items,
            totalMinutes: totalMinutes,
            overflowTasks: overflowSorted,
            generatedAt: now,
            totalFreeMinutes: allocation.totalFreeMinutes,
            freeTimeGapCount: freeTimeStats.gapCount,
            utilizationPercent: allocation.utilizationPercent * 100.0,
            warningMessage: allocation.warningMessage,
            deferredTaskIds: allocation.deferred
        )
        TimedLogger.planning.info("Plan generated: \(result.items.count) tasks selected, \(result.totalMinutes) min planned, \(result.overflowTasks.count) overflow, \(Int(result.utilizationPercent))% utilization")
        return result
    }

    // MARK: - Scoring

    /// Computes a composite score for a task. Pure function.
    static func scoreTask(
        _ task: PlanTask,
        now: Date,
        moodContext: MoodContext?,
        behaviouralRules: [BehaviourRule],
        bucketStats: [BucketCompletionStat] = [],
        bucketEstimates: [String: Double] = [:],
        availableMinutes: Int = 120,
        workStartHour: Int = 9,
        workEndHour: Int = 18
    ) -> ScoreBreakdown {

        // Hard overrides for fixed-position tasks
        if task.isDailyUpdate {
            return ScoreBreakdown(base: Score.fixedFirst, overdueBump: 0, deadlineBump: 0, moodBump: 0, behaviourBump: 0, timingBump: 0, thompsonBump: 0, workHourPenalty: 0, totalScore: Score.fixedFirst)
        }
        if task.isFamilyEmail {
            return ScoreBreakdown(base: Score.fixedSecond, overdueBump: 0, deadlineBump: 0, moodBump: 0, behaviourBump: 0, timingBump: 0, thompsonBump: 0, workHourPenalty: 0, totalScore: Score.fixedSecond)
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

        // Duration penalty — adaptive to session length (harsher in short sessions)
        let effectiveMinutes = bucketEstimates[task.bucketType].map { Int($0) } ?? task.estimatedMinutes
        let penaltyRate = availableMinutes < 45 ? -3 : availableMinutes < 90 ? -2 : -1
        let durationPenalty = effectiveMinutes * penaltyRate

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

        // Work-hour window enforcement: penalise tasks when current hour is outside preferred work window
        let workHourPenalty: Int
        let currentHourForWork = Calendar.current.component(.hour, from: now)
        if currentHourForWork < workStartHour || currentHourForWork >= workEndHour {
            workHourPenalty = Score.outsideWorkHour
        } else {
            workHourPenalty = 0
        }

        let total = base + overdueBump + deadlineBump + moodBump + behaviourBump + timingBump + thompsonBump + workHourPenalty

        return ScoreBreakdown(
            base: base,
            overdueBump: overdueBump,
            deadlineBump: deadlineBump,
            moodBump: moodBump,
            behaviourBump: behaviourBump,
            timingBump: timingBump,
            thompsonBump: thompsonBump,
            workHourPenalty: workHourPenalty,
            totalScore: total
        )
    }

    // MARK: - Thompson Sampling

    /// Computes a score bump via Beta-distributed Thompson sampling for this bucket+hour.
    /// Uses Gaussian approximation (Box-Muller) of Beta(alpha, beta) posterior.
    /// Returns 0 if fewer than `thompsonMinSamples` observations exist.
    private static func thompsonBump(
        bucketType: String,
        currentHour: Int,
        stats: [BucketCompletionStat]
    ) -> Int {
        let hourRange = hourToRange(currentHour)
        guard let stat = stats.first(where: { $0.bucketType == bucketType && $0.hourRange == hourRange }) else { return 0 }
        let total = stat.completions + stat.deferrals
        guard total >= Score.thompsonMinSamples else { return 0 }

        // Beta(alpha, beta) sampling via Gaussian approximation
        let alpha = Double(stat.completions) + 1.0
        let beta = Double(stat.deferrals) + 1.0
        let mu = alpha / (alpha + beta)
        let variance = (alpha * beta) / ((alpha + beta) * (alpha + beta) * (alpha + beta + 1.0))
        let sigma = sqrt(variance)

        // Box-Muller transform for Gaussian sample
        let u1 = Double.random(in: 0.001..<1.0)
        let u2 = Double.random(in: 0.001..<1.0)
        let z = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        let sample = min(1.0, max(0.0, mu + sigma * z))

        return Int(sample * Double(Score.thompsonMax))
    }

    private static func hourToRange(_ hour: Int) -> String {
        switch hour {
        case 6..<12:  return "06-12"
        case 12..<16: return "12-16"
        case 16..<20: return "16-20"
        default:      return "20-06"
        }
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

    // MARK: - Calendar block helpers

    /// Computes total meeting/event minutes from today's calendar blocks.
    /// Only counts non-focus blocks (meetings, admin, transit) as they consume available time.
    private static func calendarBlockMinutesToday(_ blocks: [CalendarBlock]) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return 0 }

        return blocks
            .filter { block in
                block.startTime >= today && block.startTime < tomorrow
                    && block.category != .focus  // focus blocks are user's own work time
                    && block.category != .break   // breaks don't eat task budget
            }
            .reduce(0) { total, block in
                total + max(0, Int(block.endTime.timeIntervalSince(block.startTime) / 60))
            }
    }
}
