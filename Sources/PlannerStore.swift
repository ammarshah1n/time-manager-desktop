import Foundation
import Observation

@Observable
final class PlannerStore {
    private let storageURL: URL

    var tasks: [TaskItem]
    var contexts: [ContextItem]
    var schedule: [ScheduleBlock]
    var rankedTasks: [RankedTask]
    var selectedTaskID: String?
    var selectedContextID: String?
    var promptText: String
    var chat: [PromptMessage]

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let folderURL = baseURL.appendingPathComponent("TimeManagerDesktop", isDirectory: true)
        self.storageURL = folderURL.appendingPathComponent("planner-state.json")

        if let loaded = Self.load(from: storageURL) {
            let ranked = PlanningEngine.rank(tasks: loaded.tasks)
            let plannedSchedule = PlanningEngine.buildSchedule(tasks: ranked)
            tasks = loaded.tasks
            contexts = loaded.contexts
            rankedTasks = ranked
            schedule = plannedSchedule
            selectedTaskID = loaded.selectedTaskID
            selectedContextID = loaded.selectedContextID
            promptText = loaded.promptText
            chat = loaded.chat
        } else {
            let sample = ShellData.sample
            let ranked = PlanningEngine.rank(tasks: sample.tasks)
            let plannedSchedule = PlanningEngine.buildSchedule(tasks: ranked)
            tasks = sample.tasks
            contexts = sample.contexts
            rankedTasks = ranked
            schedule = plannedSchedule
            selectedTaskID = sample.tasks.first?.id
            selectedContextID = sample.contexts.first?.id
            promptText = "Rank my school work for tonight"
            chat = [PromptMessage(role: "Assistant", text: "Loaded. Give me a subject, a deadline, or a time window.")]
            save()
        }
    }

    var selectedTask: TaskItem? {
        tasks.first(where: { $0.id == selectedTaskID }) ?? tasks.first
    }

    var selectedContext: ContextItem? {
        contexts.first(where: { $0.id == selectedContextID }) ?? contexts.first
    }

    func selectTask(_ task: TaskItem) {
        selectedTaskID = task.id
        save()
    }

    func selectContext(_ context: ContextItem) {
        selectedContextID = context.id
        save()
    }

    func submitPrompt() {
        chat.append(PromptMessage(role: "User", text: promptText))
        let lowercased = promptText.lowercased()

        if lowercased.contains("plan") || lowercased.contains("rank") || lowercased.contains("box") {
            rebuildPlan()
            if let topTask = rankedTasks.first {
                chat.append(
                    PromptMessage(
                        role: "Assistant",
                        text: "Top task: \(topTask.task.title). Time box: \(schedule.first?.timeRange ?? "none")."
                    )
                )
            } else {
                chat.append(PromptMessage(role: "Assistant", text: "No tasks to rank yet."))
            }
        } else if lowercased.contains("quiz") {
            chat.append(PromptMessage(role: "Assistant", text: "Loaded the matching context pack for a quiz response."))
        } else {
            chat.append(PromptMessage(role: "Assistant", text: "Captured the prompt and kept the current plan in place."))
        }
        save()
    }

    func rebuildPlan() {
        rankedTasks = PlanningEngine.rank(tasks: tasks)
        schedule = PlanningEngine.buildSchedule(tasks: rankedTasks)
        save()
    }

    private func save() {
        let payload = PlannerSnapshot(
            tasks: tasks,
            contexts: contexts,
            schedule: schedule,
            selectedTaskID: selectedTaskID,
            selectedContextID: selectedContextID,
            promptText: promptText,
            chat: chat
        )

        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.pretty.encode(payload)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            // Persistence is best-effort for now; the shell still works without it.
        }
    }

    private static func load(from url: URL) -> PlannerSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder(iso8601: true).decode(PlannerSnapshot.self, from: data)
    }
}

private struct PlannerSnapshot: Codable {
    let tasks: [TaskItem]
    let contexts: [ContextItem]
    let schedule: [ScheduleBlock]
    let selectedTaskID: String?
    let selectedContextID: String?
    let promptText: String
    let chat: [PromptMessage]
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    convenience init(iso8601: Bool = true) {
        self.init()
        if iso8601 {
            dateDecodingStrategy = .iso8601
        }
    }
}
