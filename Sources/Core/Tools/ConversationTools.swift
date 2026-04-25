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

    init(publishTasks: @escaping ([TimedTask]) -> Void = { _ in }) {
        self.publishTasks = publishTasks
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

    private func addTask(_ input: [String: Any]) async throws -> String {
        guard let title = input["title"] as? String,
              let bucketString = input["bucket"] as? String,
              let bucket = parseBucket(bucketString) else {
            return "missing title or bucket"
        }
        var tasks = try await DataBridge.shared.loadTasks()
        let task = TimedTask(
            id: UUID(),
            title: title,
            sender: "Voice",
            estimatedMinutes: int(input["estimatedMinutes"]) ?? 15,
            bucket: bucket,
            emailCount: 0,
            receivedAt: Date(),
            isDoFirst: bool(input["isDoFirst"]) ?? false,
            urgency: int(input["urgency"]) ?? 3,
            importance: int(input["importance"]) ?? 3,
            context: (input["notes"] as? String) ?? "voice"
        )
        tasks.append(task)
        try await DataBridge.shared.saveTasks(tasks)
        publishTasks(tasks)
        return "added task \(task.id.uuidString): \(task.title)"
    }

    private func updateTask(_ input: [String: Any]) async throws -> String {
        guard let id = uuid(input["taskId"]) else { return "invalid task id" }
        var tasks = try await DataBridge.shared.loadTasks()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return "task not found" }

        var task = tasks[index]
        let title = input["title"] as? String
        let bucket = (input["bucket"] as? String).flatMap(parseBucket)
        if let estimatedMinutes = int(input["estimatedMinutes"]) { task.estimatedMinutes = estimatedMinutes }
        if let isDoFirst = bool(input["isDoFirst"]) { task.isDoFirst = isDoFirst }
        if let urgency = int(input["urgency"]) { task.urgency = urgency }
        if let importance = int(input["importance"]) { task.importance = importance }
        if let notes = input["notes"] as? String { task.context = notes }
        if title != nil || bucket != nil {
            task = rebuilt(task, title: title, bucket: bucket)
        }
        tasks[index] = task
        try await DataBridge.shared.saveTasks(tasks)
        publishTasks(tasks)
        return "updated task \(id.uuidString)"
    }

    private func moveTask(_ input: [String: Any]) async throws -> String {
        guard let id = uuid(input["taskId"]),
              let newBucketString = input["newBucket"] as? String,
              let bucket = parseBucket(newBucketString) else {
            return "invalid task id or bucket"
        }
        let tasks = try await DataBridge.shared.moveBucket(id: id, to: bucket)
        publishTasks(tasks)
        return "moved task \(id.uuidString) to \(bucket.rawValue)"
    }

    private func markDone(_ input: [String: Any]) async throws -> String {
        guard let id = uuid(input["taskId"]) else { return "invalid task id" }
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
        let tasks = try await DataBridge.shared.snooze(id: id, until: until)
        publishTasks(tasks)
        return "snoozed task \(id.uuidString) until \(rawUntil)"
    }

    private func requestReplan(_ input: [String: Any]) async throws -> String {
        let minutes = int(input["availableMinutes"]) ?? 60
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
