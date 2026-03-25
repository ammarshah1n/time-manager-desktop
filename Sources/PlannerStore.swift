import Foundation
import Observation

@Observable
final class PlannerStore {
    private let storageURL: URL

    var tasks: [TaskItem]
    var contexts: [ContextItem]
    var schedule: [ScheduleBlock]
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
            tasks = loaded.tasks
            contexts = loaded.contexts
            schedule = loaded.schedule
            selectedTaskID = loaded.selectedTaskID
            selectedContextID = loaded.selectedContextID
            promptText = loaded.promptText
            chat = loaded.chat
        } else {
            let sample = ShellData.sample
            tasks = sample.tasks
            contexts = sample.contexts
            schedule = sample.schedule
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
        chat.append(PromptMessage(role: "Assistant", text: "Ranking task priority and building a time box next."))
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
