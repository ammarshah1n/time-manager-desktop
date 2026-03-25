import Foundation
import Observation

@MainActor
@Observable
final class PlannerStore {
    private let storageURL: URL

    var tasks: [TaskItem] = []
    var contexts: [ContextItem] = []
    var schedule: [ScheduleBlock] = []
    var rankedTasks: [RankedTask] = []
    var selectedTaskID: String?
    var selectedContextID: String?
    var promptText = ""
    var chat: [PromptMessage] = []
    var isRunningPrompt = false
    var aiErrorText: String?
    var promptBoostSubject: String?
    var suggestedNextActionsByTaskID: [String: String] = [:]
    var scheduleOverflowCount = 0
    var lastImportMessages: [String] = []
    var pendingImportBatch: ImportBatch?
    var dismissedScheduleTaskIDs: Set<String> = []
    var isQuizMode = false
    var activeQuizSubject: String?
    var importTitle = "Imported context"
    var importSource: ImportSource = .transcript
    var importText = ""

    init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let folderURL = baseURL.appendingPathComponent("Timed", isDirectory: true)
        self.storageURL = storageURL ?? folderURL.appendingPathComponent("planner-state.json")
        load()
    }

    var selectedTask: TaskItem? {
        tasks.first(where: { $0.id == selectedTaskID }) ?? tasks.first
    }

    var selectedContext: ContextItem? {
        contexts.first(where: { $0.id == selectedContextID }) ?? contexts.first
    }

    var completedToday: [TaskItem] {
        tasks
            .filter { task in
                guard let completedAt = task.completedAt else { return false }
                return task.isCompleted && Calendar.current.isDateInToday(completedAt)
            }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var sortedContexts: [ContextItem] {
        contexts.sorted { $0.createdAt > $1.createdAt }
    }

    func save() {
        let snapshot = PlannerSnapshot(
            tasks: tasks,
            contexts: contexts,
            schedule: schedule,
            selectedTaskID: selectedTaskID,
            selectedContextID: selectedContextID,
            promptText: promptText,
            chat: chat,
            promptBoostSubject: promptBoostSubject,
            dismissedScheduleTaskIDs: Array(dismissedScheduleTaskIDs)
        )

        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.pretty.encode(snapshot)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            aiErrorText = "Could not save Timed data."
        }
    }

    func load() {
        if
            let data = try? Data(contentsOf: storageURL),
            let snapshot = try? JSONDecoder(iso8601: true).decode(PlannerSnapshot.self, from: data)
        {
            tasks = snapshot.tasks
            contexts = snapshot.contexts
            schedule = snapshot.schedule
            selectedTaskID = snapshot.selectedTaskID
            selectedContextID = snapshot.selectedContextID
            promptText = snapshot.promptText
            chat = snapshot.chat
            promptBoostSubject = snapshot.promptBoostSubject
            dismissedScheduleTaskIDs = Set(snapshot.dismissedScheduleTaskIDs)
        } else {
            let sample = ShellData.sample
            tasks = sample.tasks
            contexts = sample.contexts
            schedule = sample.schedule
            chat = sample.chat
            selectedTaskID = sample.tasks.first?.id
            selectedContextID = sample.contexts.first?.id
            promptText = "What should I do now?"
        }

        rebuildPlan()
    }

    func selectTask(_ task: TaskItem) {
        selectedTaskID = task.id
        save()
    }

    func selectContext(_ context: ContextItem) {
        selectedContextID = context.id
        save()
    }

    func rebuildPlan(now: Date = .now) {
        rankedTasks = PlanningEngine.rank(
            tasks: tasks,
            contexts: contexts,
            now: now,
            promptBoostSubject: promptBoostSubject
        ).map { ranked in
            RankedTask(
                task: ranked.task,
                score: ranked.score,
                band: ranked.band,
                reasons: ranked.reasons,
                suggestedNextAction: suggestedNextActionsByTaskID[ranked.task.id] ?? ranked.suggestedNextAction
            )
        }

        let currentApprovals = Dictionary(uniqueKeysWithValues: schedule.map { ($0.taskID, $0.isApproved) })
        let schedulable = rankedTasks.filter { !dismissedScheduleTaskIDs.contains($0.task.id) }
        let rebuiltSchedule = PlanningEngine.buildSchedule(tasks: schedulable, now: now, windowMinutes: 180)
        scheduleOverflowCount = max(0, schedulable.count - rebuiltSchedule.count)
        schedule = rebuiltSchedule.map { block in
            var mutable = block
            mutable.isApproved = currentApprovals[block.taskID] ?? block.isApproved
            return mutable
        }

        if selectedTask == nil {
            selectedTaskID = rankedTasks.first?.task.id
        }
        if selectedContext == nil {
            selectedContextID = sortedContexts.first?.id
        }

        save()
    }

    func submitPrompt() async {
        let rawPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPrompt.isEmpty else { return }

        if rawPrompt.lowercased() == "end quiz" {
            endQuiz()
            promptText = ""
            return
        }

        if isQuizMode {
            await continueQuiz(with: rawPrompt)
            promptText = ""
            return
        }

        if let quizSubject = extractQuizSubject(from: rawPrompt) {
            await startQuiz(subject: quizSubject)
            promptText = ""
            return
        }

        aiErrorText = nil
        chat.append(PromptMessage(role: .user, text: rawPrompt))
        isRunningPrompt = true

        let response = await CodexBridge().run(prompt: buildPlanningPrompt(for: rawPrompt))
        isRunningPrompt = false

        guard let response else {
            aiErrorText = "Could not reach Timed AI — check Codex is installed"
            chat.append(PromptMessage(role: .assistant, text: aiErrorText ?? "Timed AI error"))
            save()
            return
        }

        let actions = CodexBridge.extractTaskActions(response: response, taskTitles: tasks.map(\.title))
        applySuggestedActions(actions)
        if let boostSubject = CodexBridge.extractProminentSubject(response: response, knownSubjects: SubjectCatalog.supported) {
            promptBoostSubject = boostSubject
        }
        rebuildPlan()
        chat.append(PromptMessage(role: .assistant, text: response))
        promptText = ""
        save()
    }

    func startQuiz(subject: String) async {
        let normalizedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingContexts = sortedContexts.filter { $0.subject.caseInsensitiveCompare(normalizedSubject) == .orderedSame }

        guard !matchingContexts.isEmpty else {
            chat.append(PromptMessage(role: .assistant, text: "No context is loaded for \(normalizedSubject). Import some notes first."))
            save()
            return
        }

        isQuizMode = true
        activeQuizSubject = normalizedSubject
        aiErrorText = nil
        isRunningPrompt = true
        chat.append(PromptMessage(role: .student, text: "Quiz me on \(normalizedSubject).", isQuiz: true))

        let response = await CodexBridge().run(prompt: buildQuizPrompt(subject: normalizedSubject, contexts: matchingContexts, latestStudentReply: nil))
        isRunningPrompt = false

        guard let response else {
            aiErrorText = "Could not reach Timed AI — check Codex is installed"
            chat.append(PromptMessage(role: .assistant, text: aiErrorText ?? "Timed AI error"))
            save()
            return
        }

        chat.append(PromptMessage(role: .tutor, text: response, isQuiz: true))
        save()
    }

    func endQuiz() {
        isQuizMode = false
        activeQuizSubject = nil
        chat.append(PromptMessage(role: .assistant, text: "Quiz ended. Back to planning mode."))
        save()
    }

    func markTaskCompleted(_ task: TaskItem, now: Date = .now) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted = true
        tasks[index].completedAt = now
        dismissedScheduleTaskIDs.insert(task.id)
        rebuildPlan(now: now)
    }

    func removeScheduleBlock(_ block: ScheduleBlock) {
        dismissedScheduleTaskIDs.insert(block.taskID)
        schedule.removeAll { $0.id == block.id }
        save()
    }

    func toggleScheduleApproval(_ block: ScheduleBlock) {
        guard let index = schedule.firstIndex(where: { $0.id == block.id }) else { return }
        schedule[index].isApproved.toggle()
        save()
    }

    func exportCalendar() async {
        let result = await CalendarExporter.exportApprovedBlocks(schedule)
        let extra = result.fallbackICSURL.map { " \($0.lastPathComponent)" } ?? ""
        chat.append(PromptMessage(role: .assistant, text: "\(result.message)\(extra)"))
        save()
    }

    func importCurrentPayload(now: Date = .now) {
        let trimmed = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existingIDs = Set(tasks.map(\.id))
        let batch = ImportPipeline.parseImport(
            title: importTitle,
            source: importSource,
            text: trimmed,
            now: now,
            existingTaskIDs: existingIDs
        )

        if batch.taskDrafts.isEmpty {
            applyImport(batch)
            importText = ""
            return
        }

        pendingImportBatch = batch
        lastImportMessages = batch.messages
    }

    func applyPendingImport() {
        guard let batch = pendingImportBatch else { return }
        applyImport(batch)
        pendingImportBatch = nil
        importText = ""
    }

    func discardPendingImport() {
        pendingImportBatch = nil
    }

    func addManualTask(_ draft: AddTaskDraft) -> String? {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Task title is required."
        }
        guard draft.estimateMinutes > 0 else {
            return "Estimate must be greater than zero."
        }

        let task = draft.makeTask()
        if tasks.contains(where: { $0.id == task.id }) {
            return "That task already exists."
        }

        tasks.insert(task, at: 0)
        rebuildPlan()
        return nil
    }

    func promptSuggestions(for subject: String?) -> [String] {
        let quizSubject = subject ?? selectedContext?.subject ?? selectedTask?.subject ?? "English"
        return [
            "What should I do now?",
            "Plan my next 3 hours",
            "Rank my tasks",
            "Quiz me on \(quizSubject)"
        ]
    }

    private func applyImport(_ batch: ImportBatch) {
        if let context = batch.context {
            contexts.removeAll { $0.id == context.id }
            contexts.insert(context, at: 0)
            contexts.sort { $0.createdAt > $1.createdAt }
            selectedContextID = context.id
        }

        for draft in batch.taskDrafts {
            let task = draft.makeTask()
            guard !tasks.contains(where: { $0.id == task.id }) else { continue }
            tasks.insert(task, at: 0)
        }

        lastImportMessages = batch.messages
        if !batch.messages.isEmpty {
            chat.append(PromptMessage(role: .assistant, text: batch.messages.joined(separator: "\n")))
        }
        rebuildPlan()
    }

    private func continueQuiz(with answer: String) async {
        guard let activeQuizSubject else { return }
        let matchingContexts = sortedContexts.filter { $0.subject.caseInsensitiveCompare(activeQuizSubject) == .orderedSame }
        chat.append(PromptMessage(role: .student, text: answer, isQuiz: true))
        isRunningPrompt = true

        let response = await CodexBridge().run(
            prompt: buildQuizPrompt(
                subject: activeQuizSubject,
                contexts: matchingContexts,
                latestStudentReply: answer
            )
        )

        isRunningPrompt = false
        guard let response else {
            aiErrorText = "Could not reach Timed AI — check Codex is installed"
            chat.append(PromptMessage(role: .assistant, text: aiErrorText ?? "Timed AI error"))
            save()
            return
        }

        chat.append(PromptMessage(role: .tutor, text: response, isQuiz: true))
        save()
    }

    private func buildPlanningPrompt(for question: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        let taskLines = rankedTasks.map { ranked in
            let dueDate = ranked.task.dueDate.map { dateFormatter.string(from: $0) } ?? "No due date"
            return "- Title: \(ranked.task.title) | Subject: \(ranked.task.subject) | Score: \(ranked.score) | Band: \(ranked.band) | Due: \(dueDate) | Estimate: \(ranked.task.estimateMinutes)m | Confidence: \(ranked.task.confidence)/5 | Importance: \(ranked.task.importance)/5 | Source: \(ranked.task.source.rawValue)"
        }.joined(separator: "\n")

        let contextLines = relevantContexts(for: question).prefix(3).map { context in
            "- \(context.subject): \(context.title) — \(context.summary)"
        }.joined(separator: "\n")

        return """
        System instruction:
        You are Timed, a study planner for a school student. You are not a coding assistant. Respond in concise plain English. Mention at least one task by its exact title. If you suggest a specific next action for a task, format that line exactly as [task title]: [action].

        Current date and time:
        \(dateFormatter.string(from: .now))

        Full ranked task list:
        \(taskLines)

        Top 3 relevant context summaries:
        \(contextLines.isEmpty ? "- None loaded" : contextLines)

        User question:
        \(question)
        """
    }

    private func buildQuizPrompt(subject: String, contexts: [ContextItem], latestStudentReply: String?) -> String {
        let material = contexts.map { context in
            """
            [\(context.title)]
            \(context.detail)
            """
        }.joined(separator: "\n\n")

        let transcript = chat
            .filter(\.isQuiz)
            .suffix(8)
            .map { "\($0.role.displayName): \($0.text)" }
            .joined(separator: "\n")

        return """
        You are a study tutor. Ask the student one question at a time based on the material below. Wait for their answer before proceeding. Keep questions concise. After their answer, give brief feedback.

        Subject:
        \(subject)

        Material:
        \(material)

        Recent quiz transcript:
        \(transcript.isEmpty ? "None yet." : transcript)

        Latest student answer:
        \(latestStudentReply ?? "Start the quiz now with the first question.")
        """
    }

    private func relevantContexts(for question: String) -> [ContextItem] {
        let focusSubject = SubjectCatalog.matchingSubject(in: question)
        let keywords = Set(question.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))

        return sortedContexts.sorted { lhs, rhs in
            score(context: lhs, focusSubject: focusSubject, keywords: keywords) >
                score(context: rhs, focusSubject: focusSubject, keywords: keywords)
        }
    }

    private func score(context: ContextItem, focusSubject: String?, keywords: Set<String>) -> Int {
        var total = 0
        if let focusSubject, context.subject.caseInsensitiveCompare(focusSubject) == .orderedSame {
            total += 30
        }

        let haystack = "\(context.title) \(context.summary) \(context.detail)".lowercased()
        total += keywords.reduce(into: 0) { partialResult, keyword in
            if haystack.contains(keyword) {
                partialResult += 4
            }
        }
        total += Int(context.createdAt.timeIntervalSinceNow / 3600 * -0.1) * -1
        return total
    }

    private func applySuggestedActions(_ actions: [String: String]) {
        guard !actions.isEmpty else { return }

        for task in tasks {
            if let action = actions[task.title] {
                suggestedNextActionsByTaskID[task.id] = action
            }
        }
    }

    private func extractQuizSubject(from prompt: String) -> String? {
        let lowered = prompt.lowercased()
        guard lowered.contains("quiz me on") else { return nil }
        if let subject = SubjectCatalog.matchingSubject(in: prompt) {
            return subject
        }

        let parts = prompt.components(separatedBy: "on")
        return parts.last?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
