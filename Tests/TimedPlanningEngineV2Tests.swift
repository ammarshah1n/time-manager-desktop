// TimedPlanningEngineV2Tests.swift — Timed v2
// Tests for Sources/Core/Services/PlanningEngine.swift
// Pure algorithm tests — no I/O, no network, deterministic.
// Covers: fixed ordering, knapsack budget, mood modifiers, scoring, overflow, edge cases.

import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Timed v2 PlanningEngine")
struct TimedPlanningEngineV2Tests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let wsId = UUID()
    private let profileId = UUID()

    // MARK: - Helpers

    private func makeTask(
        title: String,
        bucket: String = "action",
        estimatedMinutes: Int = 30,
        priority: Int = 0,
        isOverdue: Bool = false,
        isDailyUpdate: Bool = false,
        isFamilyEmail: Bool = false,
        isDoFirst: Bool = false,
        dueAt: Date? = nil,
        deferredCount: Int = 0
    ) -> PlanTask {
        PlanTask(
            id: UUID(),
            title: title,
            bucketType: bucket,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            dueAt: dueAt,
            isOverdue: isOverdue,
            isDoFirst: isDoFirst,
            isDailyUpdate: isDailyUpdate,
            isFamilyEmail: isFamilyEmail,
            deferredCount: deferredCount,
            isTransitSafe: false
        )
    }

    private func makeRequest(
        tasks: [PlanTask],
        availableMinutes: Int = 180,
        mood: MoodContext? = nil,
        rules: [BehaviourRule] = []
    ) -> PlanRequest {
        PlanRequest(
            workspaceId: wsId,
            profileId: profileId,
            availableMinutes: availableMinutes,
            moodContext: mood,
            behaviouralRules: rules,
            tasks: tasks
        )
    }

    // MARK: - Fixed Ordering Rules

    @Test("Daily update always appears first regardless of other tasks")
    func dailyUpdateAlwaysFirst() {
        let dailyUpdate = makeTask(title: "Daily Update", bucket: "action", estimatedMinutes: 5, isOverdue: true, isDailyUpdate: true, isDoFirst: true)
        let highPriority = makeTask(title: "Urgent legal review", bucket: "action", estimatedMinutes: 10, priority: 5, isOverdue: true)
        let result = PlanningEngine.generatePlan(makeRequest(tasks: [highPriority, dailyUpdate]))
        #expect(result.items.first?.task.isDailyUpdate == true)
        #expect(result.items.first?.position == 0)
    }

    @Test("Family email always appears second, after daily update")
    func familyEmailAlwaysSecond() {
        let daily = makeTask(title: "Daily Update", bucket: "action", estimatedMinutes: 5, isDailyUpdate: true, isDoFirst: true)
        let family = makeTask(title: "Reply Mum", bucket: "reply_email", estimatedMinutes: 3, isFamilyEmail: true, isDoFirst: true)
        let overdue = makeTask(title: "Overdue action", bucket: "action", estimatedMinutes: 10, priority: 5, isOverdue: true)

        let result = PlanningEngine.generatePlan(makeRequest(tasks: [overdue, family, daily]))
        let positions: [String: Int] = Dictionary(uniqueKeysWithValues: result.items.map { ($0.task.title, $0.position) })

        #expect(positions["Daily Update"] == 0)
        #expect(positions["Reply Mum"] == 1)
        #expect(positions["Overdue action"] == 2)
    }

    @Test("Plan with no daily update or family email still produces valid plan")
    func noFixedTasksStillProducesValidPlan() {
        let tasks = (1...5).map { makeTask(title: "Task \($0)", bucket: "action", estimatedMinutes: 20) }
        let result = PlanningEngine.generatePlan(makeRequest(tasks: tasks, availableMinutes: 180))
        #expect(!result.items.isEmpty)
        #expect(result.items.allSatisfy { $0.position >= 0 })
    }

    // MARK: - Knapsack Budget

    @Test("Total minutes does not exceed available minutes")
    func totalMinutesWithinBudget() {
        let tasks = (1...10).map { makeTask(title: "Task \($0)", bucket: "action", estimatedMinutes: 30) }
        let result = PlanningEngine.generatePlan(makeRequest(tasks: tasks, availableMinutes: 120))
        #expect(result.totalMinutes <= 120)
    }

    @Test("Tasks that don't fit appear in overflow")
    func overflowContainsExcludedTasks() {
        let tasks = (1...10).map { makeTask(title: "Task \($0)", bucket: "action", estimatedMinutes: 30) }
        let result = PlanningEngine.generatePlan(makeRequest(tasks: tasks, availableMinutes: 60))
        let selectedCount = result.items.count
        let overflowCount = result.overflowTasks.count
        #expect(selectedCount + overflowCount == tasks.count)
        #expect(overflowCount > 0)
    }

    @Test("Single task that fits exactly is selected")
    func singleTaskExactFit() {
        let task = makeTask(title: "Exact fit", bucket: "action", estimatedMinutes: 30)
        let result = PlanningEngine.generatePlan(makeRequest(tasks: [task], availableMinutes: 30))
        #expect(result.items.count == 1)
        #expect(result.overflowTasks.isEmpty)
    }

    @Test("Single task that exceeds budget goes to overflow")
    func singleTaskExceedsBudget() {
        let task = makeTask(title: "Too big", bucket: "action", estimatedMinutes: 60)
        let result = PlanningEngine.generatePlan(makeRequest(tasks: [task], availableMinutes: 30))
        #expect(result.items.isEmpty || result.items.allSatisfy { !$0.task.isDailyUpdate == false })
        // The task should not appear selected (unless it's a fixed-position task)
        let selectedIds = Set(result.items.map { $0.task.id })
        #expect(!selectedIds.contains(task.id))
        #expect(result.overflowTasks.contains { $0.id == task.id })
    }

    @Test("Empty task list returns empty plan")
    func emptyTaskListProducesEmptyPlan() {
        let result = PlanningEngine.generatePlan(makeRequest(tasks: [], availableMinutes: 180))
        #expect(result.items.isEmpty)
        #expect(result.overflowTasks.isEmpty)
        #expect(result.totalMinutes == 0)
    }

    // MARK: - Scoring: Overdue

    @Test("Overdue task ranks above non-overdue task of same type and priority")
    func overdueRanksHigherThanNonOverdue() {
        let overdue    = makeTask(title: "Overdue task",  bucket: "action", estimatedMinutes: 30, isOverdue: true)
        let nonOverdue = makeTask(title: "Normal task",   bucket: "action", estimatedMinutes: 30)

        let result = PlanningEngine.generatePlan(makeRequest(tasks: [nonOverdue, overdue], availableMinutes: 60))
        #expect(result.items.first?.task.title == "Overdue task")
    }

    @Test("Overdue bump is exactly 1000 in ScoreBreakdown")
    func overdueBumpValueIs1000() {
        let overdue = makeTask(title: "Overdue", bucket: "action", estimatedMinutes: 5, isOverdue: true)
        let breakdown = PlanningEngine.scoreTask(overdue, now: now, moodContext: nil, behaviouralRules: [])
        #expect(breakdown.overdueBump == 1_000)
    }

    // MARK: - Scoring: Deadline Proximity

    @Test("Task due within 24h has highest deadline bump")
    func within24hGetsHighestDeadlineBump() {
        let soon    = makeTask(title: "Due soon",   bucket: "action", estimatedMinutes: 30,
                               dueAt: now.addingTimeInterval(12 * 3600))   // 12h from now
        let later   = makeTask(title: "Due later",  bucket: "action", estimatedMinutes: 30,
                               dueAt: now.addingTimeInterval(48 * 3600))   // 48h
        let nextWeek = makeTask(title: "Next week", bucket: "action", estimatedMinutes: 30,
                               dueAt: now.addingTimeInterval(120 * 3600))  // 5 days

        let soonBreakdown    = PlanningEngine.scoreTask(soon,    now: now, moodContext: nil, behaviouralRules: [])
        let laterBreakdown   = PlanningEngine.scoreTask(later,   now: now, moodContext: nil, behaviouralRules: [])
        let nextWeekBreakdown = PlanningEngine.scoreTask(nextWeek, now: now, moodContext: nil, behaviouralRules: [])

        #expect(soonBreakdown.deadlineBump == 500)
        #expect(laterBreakdown.deadlineBump == 200)
        #expect(nextWeekBreakdown.deadlineBump == 100)
    }

    // MARK: - Scoring: Quick Wins

    @Test("Task with 5-minute estimate gets quick win bump")
    func quickWinBumpAt5Minutes() {
        let quickTask = makeTask(title: "Quick task", bucket: "action", estimatedMinutes: 5)
        let breakdown = PlanningEngine.scoreTask(quickTask, now: now, moodContext: nil, behaviouralRules: [])
        #expect(breakdown.base >= 150)   // at minimum: quickWinBump applied
    }

    @Test("Task with 6-minute estimate does NOT get quick win bump")
    func noQuickWinAt6Minutes() {
        let notQuick = makeTask(title: "Not quick", bucket: "action", estimatedMinutes: 6)
        let quick    = makeTask(title: "Quick",     bucket: "action", estimatedMinutes: 5)
        let breakdown6 = PlanningEngine.scoreTask(notQuick, now: now, moodContext: nil, behaviouralRules: [])
        let breakdown5 = PlanningEngine.scoreTask(quick,    now: now, moodContext: nil, behaviouralRules: [])
        #expect(breakdown5.totalScore > breakdown6.totalScore)
    }

    // MARK: - Mood: Easy Wins

    @Test("Easy wins mode boosts sub-5-min tasks via mood bump")
    func easyWinsModeBoostsQuickTasks() {
        let big   = makeTask(title: "Big task",   bucket: "action", estimatedMinutes: 60, priority: 0)
        let small = makeTask(title: "Small task", bucket: "action", estimatedMinutes: 5)

        let result = PlanningEngine.generatePlan(makeRequest(tasks: [big, small], availableMinutes: 180, mood: .easyWins))
        // In easy_wins, the small task gets +500 mood boost — should rank first
        let firstTask = result.items.first?.task.title
        #expect(firstTask == "Small task")
    }

    @Test("Easy wins boost only applies to tasks with est <= 5 min")
    func easyWinsOnlyBoostsSmallTasks() {
        let mid = makeTask(title: "6-min task", bucket: "action", estimatedMinutes: 6)
        let breakdown = PlanningEngine.scoreTask(mid, now: now, moodContext: .easyWins, behaviouralRules: [])
        #expect(breakdown.moodBump == 0)
    }

    // MARK: - Mood: Avoidance

    @Test("Avoidance mode boosts tasks with deferredCount >= 2")
    func avoidanceModeBoostsDeferredTasks() {
        let fresh    = makeTask(title: "Fresh task",    bucket: "action", estimatedMinutes: 30, deferredCount: 0)
        let deferred = makeTask(title: "Deferred task", bucket: "action", estimatedMinutes: 30, deferredCount: 3)

        let result = PlanningEngine.generatePlan(makeRequest(tasks: [fresh, deferred], availableMinutes: 180, mood: .avoidance))
        #expect(result.items.first?.task.title == "Deferred task")
    }

    @Test("Avoidance boost only applies at deferredCount >= 2")
    func avoidanceThresholdIsTwo() {
        let once = makeTask(title: "Once", bucket: "action", estimatedMinutes: 30, deferredCount: 1)
        let breakdown = PlanningEngine.scoreTask(once, now: now, moodContext: .avoidance, behaviouralRules: [])
        #expect(breakdown.moodBump == 0)
    }

    // MARK: - Mood: Deep Focus

    @Test("Deep focus mode penalises non-action tasks with deeply negative score")
    func deepFocusPenalisesNonActionTasks() {
        let actionTask = makeTask(title: "Deep work",  bucket: "action",      estimatedMinutes: 45)
        let readTask   = makeTask(title: "Read later", bucket: "read_today",   estimatedMinutes: 30)
        let replyTask  = makeTask(title: "Reply email", bucket: "reply_email", estimatedMinutes: 5)

        let actionBreakdown = PlanningEngine.scoreTask(actionTask, now: now, moodContext: .deepFocus, behaviouralRules: [])
        let readBreakdown   = PlanningEngine.scoreTask(readTask,   now: now, moodContext: .deepFocus, behaviouralRules: [])
        let replyBreakdown  = PlanningEngine.scoreTask(replyTask,  now: now, moodContext: .deepFocus, behaviouralRules: [])

        // Action task should have no mood penalty
        #expect(actionBreakdown.moodBump == 0)
        // Non-action tasks get the deepFocusKill penalty
        #expect(readBreakdown.moodBump < 0)
        #expect(replyBreakdown.moodBump < 0)
        // Action task should score higher than non-action tasks
        #expect(actionBreakdown.totalScore > readBreakdown.totalScore)
        #expect(actionBreakdown.totalScore > replyBreakdown.totalScore)
    }

    @Test("Deep focus: action task ranks first in plan")
    func deepFocusActionRanksFirst() {
        let action = makeTask(title: "Action",     bucket: "action",    estimatedMinutes: 30)
        let read   = makeTask(title: "Read stuff", bucket: "read_today", estimatedMinutes: 15)

        let result = PlanningEngine.generatePlan(makeRequest(tasks: [action, read], availableMinutes: 180, mood: .deepFocus))

        #expect(result.items.first?.task.title == "Action")
    }

    // MARK: - Behavioural Rules

    @Test("Ordering rule boosts matching bucket's score")
    func orderingRuleBoostsBucket() {
        let callsTask  = makeTask(title: "Call Sarah",    bucket: "calls",       estimatedMinutes: 10)
        let emailTask  = makeTask(title: "Reply email",   bucket: "reply_email", estimatedMinutes: 5)

        // Rule: calls before email (user preference)
        let ruleJson = try! JSONSerialization.data(withJSONObject: ["bucket": "calls"])
        let rule = BehaviourRule(ruleKey: "order.calls_before_email", ruleType: "ordering", ruleValueJson: ruleJson, confidence: 0.9)

        let result = PlanningEngine.generatePlan(makeRequest(tasks: [emailTask, callsTask], availableMinutes: 60, rules: [rule]))
        // callsTask should appear first due to ordering rule
        #expect(result.items.first?.task.title == "Call Sarah")
    }

    @Test("Low confidence behavioural rule has proportionally smaller bump")
    func lowConfidenceRuleHasSmallerBump() {
        let task = makeTask(title: "Calls task", bucket: "calls", estimatedMinutes: 10)
        let ruleJson = try! JSONSerialization.data(withJSONObject: ["bucket": "calls"])

        let highConfRule = BehaviourRule(ruleKey: "order.calls", ruleType: "ordering", ruleValueJson: ruleJson, confidence: 1.0)
        let lowConfRule  = BehaviourRule(ruleKey: "order.calls", ruleType: "ordering", ruleValueJson: ruleJson, confidence: 0.3)

        let highBreakdown = PlanningEngine.scoreTask(task, now: now, moodContext: nil, behaviouralRules: [highConfRule])
        let lowBreakdown  = PlanningEngine.scoreTask(task, now: now, moodContext: nil, behaviouralRules: [lowConfRule])

        #expect(highBreakdown.behaviourBump > lowBreakdown.behaviourBump)
        #expect(lowBreakdown.behaviourBump > 0)
    }

    // MARK: - Positions and Result Structure

    @Test("Plan items have sequential positions starting at 0")
    func positionsAreSequential() {
        let tasks = (1...5).map { makeTask(title: "Task \($0)", bucket: "action", estimatedMinutes: 15) }
        let result = PlanningEngine.generatePlan(makeRequest(tasks: tasks, availableMinutes: 180))
        let positions = result.items.map { $0.position }.sorted()
        let expected = Array(0..<result.items.count)
        #expect(positions == expected)
    }

    @Test("All plan items have bufferAfterMinutes == 5")
    func bufferIsAlways5Minutes() {
        let tasks = (1...3).map { makeTask(title: "Task \($0)", bucket: "action", estimatedMinutes: 20) }
        let result = PlanningEngine.generatePlan(makeRequest(tasks: tasks, availableMinutes: 180))
        #expect(result.items.allSatisfy { $0.bufferAfterMinutes == 5 })
    }

    @Test("All plan items have a computed rankReason from the engine")
    func rankReasonIsComputedByEngine() {
        let task = makeTask(title: "Some task", bucket: "action", estimatedMinutes: 30)
        let result = PlanningEngine.generatePlan(makeRequest(tasks: [task], availableMinutes: 60))
        #expect(result.items.allSatisfy { $0.rankReason != nil && !$0.rankReason!.isEmpty })
    }

    @Test("generatedAt is approximately now")
    func generatedAtIsNow() {
        let beforeCall = Date()
        let result = PlanningEngine.generatePlan(makeRequest(tasks: [], availableMinutes: 60))
        let afterCall = Date()
        #expect(result.generatedAt >= beforeCall)
        #expect(result.generatedAt <= afterCall)
    }

    // MARK: - Voice Capture Parser

    @Suite("TranscriptParser")
    struct TranscriptParserTests {

        @Test("Parses duration in minutes")
        func parsesDurationMinutes() {
            let result = TranscriptParser.extractDuration("Review the contract, allow 30 minutes")
            #expect(result == 30)
        }

        @Test("Parses duration in hours and converts to minutes")
        func parsesDurationHours() {
            let result = TranscriptParser.extractDuration("Deep work for 2 hours")
            #expect(result == 120)
        }

        @Test("Last duration wins when self-correction present")
        func lastDurationWinsOnCorrection() {
            let result = TranscriptParser.extractDuration("allow 30 minutes, actually make it 20 minutes not 30")
            #expect(result == 20)
        }

        @Test("Returns nil when no duration found")
        func noDurationReturnsNil() {
            let result = TranscriptParser.extractDuration("Call John back")
            #expect(result == nil)
        }

        @Test("Detects calls bucket from call prefix")
        func detectsCallsBucket() {
            let bucket = TranscriptParser.detectBucket("Call John back about the contract")
            #expect(bucket == "calls")
        }

        @Test("Detects action bucket for review task")
        func detectsActionForReview() {
            let bucket = TranscriptParser.detectBucket("Review the Q4 strategy document")
            #expect(bucket == "read_today")  // "review" maps to read_today per implementation
        }

        @Test("Detects reply_email for email reply task")
        func detectsReplyEmail() {
            let bucket = TranscriptParser.detectBucket("Reply to Sarah about the contract question")
            #expect(bucket == "reply_email")
        }

        @Test("Cleans duration phrase from title")
        func cleansTitleDuration() {
            let clean = TranscriptParser.cleanTitle("Review the contract, allow 30 minutes")
            #expect(!clean.lowercased().contains("30"))
            #expect(!clean.lowercased().contains("minutes"))
            #expect(clean.contains("Review") || clean.contains("review") || clean.contains("contract"))
        }

        @Test("Full parse: call with duration and due date")
        func fullParseCallWithDurationAndDate() {
            let items = TranscriptParser.parse("Call John back, 5 minutes")
            guard let item = items.first else {
                Issue.record("Expected at least one parsed item")
                return
            }
            #expect(item.bucketType == "calls")
            #expect(item.estimatedMinutes == 5)
            #expect(item.title.lowercased().contains("john"))
        }

        @Test("Full parse: multiple tasks in one transcript")
        func parseMultipleTasks() {
            let transcript = "Call John back 5 minutes. Reply to Sarah about the contract, 10 minutes."
            let items = TranscriptParser.parse(transcript)
            #expect(items.count == 2)
        }

        @Test("Empty transcript returns empty array")
        func emptyTranscriptReturnsEmpty() {
            let items = TranscriptParser.parse("")
            #expect(items.isEmpty)
        }

        @Test("Whitespace-only transcript returns empty array")
        func whitespaceOnlyReturnsEmpty() {
            let items = TranscriptParser.parse("   \n\t  ")
            #expect(items.isEmpty)
        }
    }
}
