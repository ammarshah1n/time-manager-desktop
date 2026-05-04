import Dependencies
import Foundation

struct ConversationToolResult {
    let toolUseId: String
    let content: String
    let endsConversation: Bool
}

@MainActor
final class ConversationTools {
    @Dependency(\.supabaseClient) private var supabase

    private let publishTasks: ([TimedTask]) -> Void
    private var replansThisTurn = 0
    private static let maxReplansPerTurn = 1

    init(publishTasks: @escaping ([TimedTask]) -> Void = { _ in }) {
        self.publishTasks = publishTasks
    }

    /// Called by the AI client at the start of each user turn. Resets
    /// per-turn counters that throttle expensive tool calls.
    func resetTurnCounters() {
        replansThisTurn = 0
    }

    static func schemas() -> [[String: Any]] {
        [
            [
                "name": "add_task",
                "description": "Add one task to Timed's in-app task list. This does not contact anyone or perform the work.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "bucket": ["type": "string", "enum": ["action", "reply", "calls", "readToday", "readThisWeek", "transit", "waiting", "ccFyi"]],
                        "isDoFirst": ["type": "boolean"],
                        "estimatedMinutes": ["type": "integer"],
                        "urgency": ["type": "integer"],
                        "importance": ["type": "integer"],
                        "notes": ["type": "string"],
                    ],
                    "required": ["title", "bucket"],
                ],
            ],
            [
                "name": "update_task",
                "description": "Update fields on an existing Timed task.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "taskId": ["type": "string"],
                        "title": ["type": "string"],
                        "bucket": ["type": "string"],
                        "isDoFirst": ["type": "boolean"],
                        "estimatedMinutes": ["type": "integer"],
                        "urgency": ["type": "integer"],
                        "importance": ["type": "integer"],
                        "notes": ["type": "string"],
                    ],
                    "required": ["taskId"],
                ],
            ],
            [
                "name": "move_to_bucket",
                "description": "Move an existing Timed task to a different bucket.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "taskId": ["type": "string"],
                        "newBucket": ["type": "string"],
                    ],
                    "required": ["taskId", "newBucket"],
                ],
            ],
            [
                "name": "mark_done",
                "description": "Mark an in-app Timed task as done.",
                "input_schema": [
                    "type": "object",
                    "properties": ["taskId": ["type": "string"]],
                    "required": ["taskId"],
                ],
            ],
            [
                "name": "snooze_task",
                "description": "Hide an in-app Timed task from stale attention until the given ISO-8601 time.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "taskId": ["type": "string"],
                        "untilISO8601": ["type": "string"],
                    ],
                    "required": ["taskId", "untilISO8601"],
                ],
            ],
            [
                "name": "request_dish_me_up_replan",
                "description": "Ask Timed's existing planning engine for a new in-app plan for the given available minutes.",
                "input_schema": [
                    "type": "object",
                    "properties": ["availableMinutes": ["type": "integer"]],
                    "required": ["availableMinutes"],
                ],
            ],
            [
                "name": "end_conversation",
                "description": "End the orb conversation when the session is naturally complete.",
                "input_schema": ["type": "object", "properties": [:]],
            ],
        ]
    }

    func dispatch(toolUseId: String, name: String, input: [String: Any]) async -> ConversationToolResult {
        do {
            let content: String
            let ends: Bool
            switch name {
            case "add_task":
                content = try await addTask(input)
                ends = false
            case "update_task":
                content = try await updateTask(input)
                ends = false
            case "move_to_bucket":
                content = try await moveTask(input)
                ends = false
            case "mark_done":
                content = try await markDone(input)
                ends = false
            case "snooze_task":
                content = try await snoozeTask(input)
                ends = false
            case "request_dish_me_up_replan":
                content = try await requestReplan(input)
                ends = false
            case "end_conversation":
                content = "ok, ending the conversation"
                ends = true
            default:
                content = "unknown tool: \(name)"
                ends = false
            }
            return ConversationToolResult(toolUseId: toolUseId, content: content, endsConversation: ends)
        } catch {
            return ConversationToolResult(toolUseId: toolUseId, content: "tool failed: \(error.localizedDescription)", endsConversation: false)
        }
    }

    // MARK: - Validation helpers

    private static let maxTitleChars = 280
    private static let maxNotesChars = 2_000
    private static let maxEstimatedMinutes = 480
    private static let urgencyRange = 1...5
    private static let importanceRange = 1...5

    private func clean(_ string: String, maxChars: Int) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxChars))
    }

    private func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func addTask(_ input: [String: Any]) async throws -> String {
        guard let rawTitle = input["title"] as? String,
              let bucketString = input["bucket"] as? String,
              let bucket = parseBucket(bucketString) else {
            return "missing title or bucket"
        }
        let title = clean(rawTitle, maxChars: Self.maxTitleChars)
        if title.isEmpty { return "title cannot be empty" }
        let estimatedMinutes = clamp(int(input["estimatedMinutes"]) ?? 15, to: 1...Self.maxEstimatedMinutes)
        let urgency = clamp(int(input["urgency"]) ?? 3, to: Self.urgencyRange)
        let importance = clamp(int(input["importance"]) ?? 3, to: Self.importanceRange)
        let notes = clean((input["notes"] as? String) ?? "voice", maxChars: Self.maxNotesChars)

        let workspaceId = await MainActor.run { AuthService.shared.activeOrPrimaryWorkspaceId }
        var tasks = try await DataBridge.shared.loadTasks(workspaceId: workspaceId)
        let task = TimedTask(
            id: UUID(),
            title: title,
            sender: "Voice",
            estimatedMinutes: estimatedMinutes,
            bucket: bucket,
            emailCount: 0,
            receivedAt: Date(),
            isDoFirst: bool(input["isDoFirst"]) ?? false,
            urgency: urgency,
            importance: importance,
            context: notes
        )
        tasks.append(task)
        try await DataBridge.shared.saveTasks(tasks, workspaceId: workspaceId)
        publishTasks(tasks)
        return "added task \(task.id.uuidString): \(task.title)"
    }

    private func updateTask(_ input: [String: Any]) async throws -> String {
        guard let id = uuid(input["taskId"]) else { return "invalid task id" }
        let workspaceId = await MainActor.run { AuthService.shared.activeOrPrimaryWorkspaceId }
        let eventContext = await DataBridge.shared.taskBehaviourEventContext(workspaceId: workspaceId)
        var tasks = try await DataBridge.shared.loadTasks(workspaceId: workspaceId)
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return "task not found — no change applied"
        }

        let oldTask = tasks[index]
        var task = oldTask
        let title = (input["title"] as? String).map { clean($0, maxChars: Self.maxTitleChars) }
        let bucket = (input["bucket"] as? String).flatMap(parseBucket)
        if let estimatedMinutes = int(input["estimatedMinutes"]) {
            task.estimatedMinutes = clamp(estimatedMinutes, to: 1...Self.maxEstimatedMinutes)
        }
        if let isDoFirst = bool(input["isDoFirst"]) { task.isDoFirst = isDoFirst }
        if let urgency = int(input["urgency"]) { task.urgency = clamp(urgency, to: Self.urgencyRange) }
        if let importance = int(input["importance"]) { task.importance = clamp(importance, to: Self.importanceRange) }
        if let notes = input["notes"] as? String { task.context = clean(notes, maxChars: Self.maxNotesChars) }
        if title?.isEmpty == true { return "title cannot be empty — no change applied" }
        if title != nil || bucket != nil {
            task = rebuilt(task, title: title, bucket: bucket)
        }
        tasks[index] = task
        try await DataBridge.shared.saveTasks(tasks, workspaceId: workspaceId)
        if let eventContext {
            try? await DataBridge.shared.logEstimateOverride(
                task: task,
                oldMinutes: oldTask.estimatedMinutes,
                newMinutes: task.estimatedMinutes,
                context: eventContext
            )
            try? await DataBridge.shared.logTaskBucketChanged(task: task, oldBucket: oldTask.bucket, context: eventContext)
        }
        publishTasks(tasks)
        return "updated task \(id.uuidString)"
    }

    private func moveTask(_ input: [String: Any]) async throws -> String {
        guard let id = uuid(input["taskId"]),
              let newBucketString = input["newBucket"] as? String,
              let bucket = parseBucket(newBucketString) else {
            return "invalid task id or bucket"
        }
        let tasksBefore = try await DataBridge.shared.loadTasks()
        guard tasksBefore.contains(where: { $0.id == id }) else {
            return "task not found — no change applied"
        }
        let tasks = try await DataBridge.shared.moveBucket(id: id, to: bucket)
        publishTasks(tasks)
        return "moved task \(id.uuidString) to \(bucket.rawValue)"
    }

    private func markDone(_ input: [String: Any]) async throws -> String {
        guard let id = uuid(input["taskId"]) else { return "invalid task id" }
        let tasksBefore = try await DataBridge.shared.loadTasks()
        guard tasksBefore.contains(where: { $0.id == id }) else {
            return "task not found — no change applied"
        }
        let tasks = try await DataBridge.shared.markDone(id: id)
        publishTasks(tasks)
        return "marked task \(id.uuidString) done"
    }

    private func snoozeTask(_ input: [String: Any]) async throws -> String {
        guard let id = uuid(input["taskId"]),
              let rawUntil = input["untilISO8601"] as? String,
              let until = ISO8601DateFormatter().date(from: rawUntil) else {
            return "invalid task id or snooze date"
        }
        let tasksBefore = try await DataBridge.shared.loadTasks()
        guard tasksBefore.contains(where: { $0.id == id }) else {
            return "task not found — no change applied"
        }
        let tasks = try await DataBridge.shared.snooze(id: id, until: until)
        publishTasks(tasks)
        return "snoozed task \(id.uuidString) until \(rawUntil)"
    }

    private func requestReplan(_ input: [String: Any]) async throws -> String {
        guard replansThisTurn < Self.maxReplansPerTurn else {
            return "already replanned this turn — ask the principal first before another replan"
        }
        replansThisTurn += 1
        let minutes = clamp(int(input["availableMinutes"]) ?? 60, to: 5...480)
        let plan = try await supabase.generateDishMeUp(minutes)
        let sequence = plan.plan.enumerated().map { index, item in
            "\(index + 1). \(item.title) (\(item.estimatedMinutes)m): \(item.reason)"
        }.joined(separator: "\n")
        return "new plan for \(minutes)m:\n\(plan.sessionFraming)\n\(sequence)"
    }

    private func parseBucket(_ value: String) -> TaskBucket? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "reply", "reply_email", "email": .reply
        case "action": .action
        case "calls", "call": .calls
        case "readtoday", "read_today", "read today": .readToday
        case "readthisweek", "read_this_week", "read this week": .readThisWeek
        case "transit": .transit
        case "waiting": .waiting
        case "ccfyi", "cc_fyi", "cc / fyi": .ccFyi
        default: TaskBucket(rawValue: value)
        }
    }

    private func uuid(_ value: Any?) -> UUID? {
        guard let string = value as? String else { return nil }
        return UUID(uuidString: string)
    }

    private func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let string = value as? String { return Bool(string) }
        return nil
    }

    private func rebuilt(_ task: TimedTask, title: String?, bucket: TaskBucket?) -> TimedTask {
        TimedTask(
            id: task.id,
            title: title ?? task.title,
            sender: task.sender,
            estimatedMinutes: task.estimatedMinutes,
            bucket: bucket ?? task.bucket,
            emailCount: task.emailCount,
            receivedAt: task.receivedAt,
            sectionId: task.sectionId,
            parentTaskId: task.parentTaskId,
            sortOrder: task.sortOrder,
            manualImportance: task.manualImportance,
            notes: task.notes,
            isPlanningUnit: task.isPlanningUnit,
            priority: task.priority,
            replyMedium: task.replyMedium,
            dueToday: task.dueToday,
            isDoFirst: task.isDoFirst,
            isTransitSafe: task.isTransitSafe,
            waitingOn: task.waitingOn,
            askedDate: task.askedDate,
            expectedByDate: task.expectedByDate,
            isDone: task.isDone,
            estimateUncertainty: task.estimateUncertainty,
            planScore: task.planScore,
            scheduledStartTime: task.scheduledStartTime,
            urgency: task.urgency,
            importance: task.importance,
            energyRequired: task.energyRequired,
            context: task.context,
            skipCount: task.skipCount,
            snoozedUntil: task.snoozedUntil
        )
    }
}
