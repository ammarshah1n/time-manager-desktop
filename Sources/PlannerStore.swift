import Foundation
import Observation

@MainActor
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
    var isRunningPrompt: Bool
    var importTitle: String
    var importSource: ImportSource
    var importText: String

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
            isRunningPrompt = false
            importTitle = "Imported context"
            importSource = .tickTick
            importText = ""
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
            isRunningPrompt = false
            importTitle = "Imported context"
            importSource = .tickTick
            importText = ""
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

    func submitPrompt() async {
        let rawPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPrompt.isEmpty else { return }

        chat.append(PromptMessage(role: "User", text: rawPrompt))
        isRunningPrompt = true
        rebuildPlan()

        let plannerPrompt = buildCodexPrompt(for: rawPrompt)
        let response = await CodexBridge().run(prompt: plannerPrompt)

        if let response {
            chat.append(PromptMessage(role: "Assistant", text: response))
        } else {
            chat.append(PromptMessage(role: "Assistant", text: fallbackResponse(for: rawPrompt)))
        }

        isRunningPrompt = false
        save()
    }

    func rebuildPlan() {
        rankedTasks = PlanningEngine.rank(tasks: tasks)
        schedule = PlanningEngine.buildSchedule(tasks: rankedTasks)
        save()
    }

    func importCurrentPayload() {
        let trimmed = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let contextID = UUID().uuidString
        contexts.insert(
            ContextItem(
                id: contextID,
                title: importTitle.isEmpty ? "\(importSource.rawValue) import" : importTitle,
                kind: importSource.rawValue,
                subject: inferredSubject(from: trimmed),
                summary: summaryLine(from: trimmed),
                detail: trimmed
            ),
            at: 0
        )
        selectedContextID = contextID

        if importSource == .seqta || importSource == .tickTick {
            let parsedTasks = importSource == .seqta ? seqtaTasks(from: trimmed) : tickTickTasks(from: trimmed)
            if !parsedTasks.isEmpty {
                tasks.insert(contentsOf: parsedTasks, at: 0)
            }
            rebuildPlan()
        }

        if importSource == .chat {
            chat.append(PromptMessage(role: "User", text: trimmed))
        }

        importText = ""
        save()
    }

    func exportCalendar() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let exportURL = downloads.appendingPathComponent("time-manager-plan.ics")
        let ics = CalendarExporter.makeICS(schedule: schedule)

        do {
            try ics.write(to: exportURL, atomically: true, encoding: .utf8)
            chat.append(PromptMessage(role: "Assistant", text: "Exported calendar blocks to \(exportURL.lastPathComponent)."))
        } catch {
            chat.append(PromptMessage(role: "Assistant", text: "Could not export calendar blocks."))
        }

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

    private func buildCodexPrompt(for prompt: String) -> String {
        let rankedSummary = rankedTasks.prefix(5).map { ranked in
            "- \(ranked.task.title) | score \(ranked.score) | \(ranked.band) | \(ranked.task.subject)"
        }.joined(separator: "\n")

        let contextSummary = selectedContext.map {
            """
            Selected context:
            - \($0.title)
            - \($0.summary)
            - \($0.detail)
            """
        } ?? "Selected context: none"

        return """
        You are my time-management planner inside a macOS desktop app.
        Keep the response short, direct, and actionable.

        User prompt:
        \(prompt)

        Ranked tasks:
        \(rankedSummary)

        \(contextSummary)

        Current time boxes:
        \(schedule.map { "- \($0.timeRange): \($0.title)" }.joined(separator: "\n"))

        Answer with:
        - the next action
        - the top ranked task
        - any context that should be loaded
        - a time box recommendation
        """
    }

    private func fallbackResponse(for prompt: String) -> String {
        let lowercased = prompt.lowercased()
        if lowercased.contains("quiz") {
            return "Loaded the matching context pack for a quiz response."
        }
        if let topTask = rankedTasks.first {
            return "Top task: \(topTask.task.title). Time box: \(schedule.first?.timeRange ?? "none")."
        }
        return "Captured the prompt and kept the current plan in place."
    }

    private func summaryLine(from text: String) -> String {
        let sanitized = text.replacingOccurrences(of: "\n", with: " ")
        let firstSentence = sanitized.split(separator: ".").first.map(String.init) ?? sanitized
        return String(firstSentence.prefix(140))
    }

    private func inferredSubject(from text: String) -> String {
        let lowered = text.lowercased()
        if lowered.contains("english") { return "English" }
        if lowered.contains("math") { return "Maths" }
        if lowered.contains("economics") { return "Economics" }
        if lowered.contains("society") || lowered.contains("culture") { return "Society and Culture" }
        if lowered.contains("seqta") { return "School" }
        return "Context"
    }

    private func seqtaTasks(from text: String) -> [TaskItem] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count > 10 else { return nil }
            let title = cleaned
                .replacingOccurrences(of: "•", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            return TaskItem(
                id: "seqta-\(UUID().uuidString)",
                title: title,
                list: "Seqta",
                source: .seqta,
                subject: inferredSubject(from: title),
                estimateMinutes: 45,
                confidence: 2,
                importance: 5,
                dueDate: nil,
                notes: "Imported from Seqta export.",
                energy: .medium
            )
        }
    }

    private func tickTickTasks(from text: String) -> [TaskItem] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count > 2 else { return nil }
            let title = cleaned
                .replacingOccurrences(of: "•", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            return TaskItem(
                id: "ticktick-\(UUID().uuidString)",
                title: title,
                list: "TickTick",
                source: .tickTick,
                subject: inferredSubject(from: title),
                estimateMinutes: 30,
                confidence: 3,
                importance: 4,
                dueDate: nil,
                notes: "Imported from TickTick.",
                energy: .medium
            )
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
