import Foundation
import Observation

@MainActor
@Observable
final class PlannerStore {
    private let storageURL: URL
    @ObservationIgnored private var seqtaWatcher: SeqtaFileWatcher?

    var tasks: [TaskItem] = []
    var contexts: [ContextItem] = []
    var schedule: [ScheduleBlock] = []
    var rankedTasks: [RankedTask] = []
    var selectedTaskID: String?
    var selectedContextID: String?
    var promptText = ""
    var studyPromptText = ""
    var chat: [PromptMessage] = []
    var studyChat: [PromptMessage] = []
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
        syncChatsFromCodexMemoryIfAvailable()
        bootstrapCodexMemoryPackIfNeeded()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            startSeqtaBackgroundSync()
        }
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
            studyChat: studyChat,
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
            studyChat = snapshot.studyChat
            promptBoostSubject = snapshot.promptBoostSubject
            dismissedScheduleTaskIDs = Set(snapshot.dismissedScheduleTaskIDs)
        } else {
            let sample = ShellData.empty
            tasks = sample.tasks
            contexts = sample.contexts
            schedule = sample.schedule
            chat = sample.chat
            studyChat = sample.studyChat
            selectedTaskID = sample.tasks.first?.id
            selectedContextID = sample.contexts.first?.id
            promptText = ""
            studyPromptText = ""
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
        await submitPlanningPrompt()
    }

    func submitPlanningPrompt() async {
        let rawPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPrompt.isEmpty else { return }
        promptText = ""
        let now = Date.now

        if let quizSubject = extractQuizSubject(from: rawPrompt) {
            await startQuiz(subject: quizSubject)
            return
        }

        let autonomousContext = AutonomousContextProvider.build(question: rawPrompt, now: now)
        upsertTaskHints(autonomousContext.taskHints)

        if rawPrompt.lowercased().contains("ticktick") {
            importRelevantTickTickTasks(now: now)
        }

        rebuildPlan(now: now)
        aiErrorText = nil
        appendPlannerMessage(PromptMessage(role: .user, text: rawPrompt), subject: SubjectCatalog.matchingSubject(in: rawPrompt))
        isRunningPrompt = true

        let response = await CodexBridge().run(
            request: CodexRunRequest(
                prompt: buildPlanningPrompt(
                    for: rawPrompt,
                    now: now,
                    autonomousContext: autonomousContext,
                    intent: PromptIntentClassifier.classify(rawPrompt)
                ),
                autonomousMode: TimedPreferences.autonomousModeEnabled,
                workingRoot: TimedPreferences.workingRoot,
                additionalRoots: TimedPreferences.codexAdditionalRoots
            )
        )
        isRunningPrompt = false

        guard let response else {
            aiErrorText = "Could not reach Timed AI — check Codex is installed"
            appendPlannerMessage(PromptMessage(role: .assistant, text: aiErrorText ?? "Timed AI error"), subject: SubjectCatalog.matchingSubject(in: rawPrompt))
            save()
            return
        }

        let actions = CodexBridge.extractTaskActions(response: response, taskTitles: tasks.map(\.title))
        applySuggestedActions(actions)
        let subjectConfidences = CodexBridge.extractSubjectConfidences(response: response, knownSubjects: SubjectCatalog.supported)
        applySubjectConfidences(subjectConfidences)
        if let boostSubject = CodexBridge.extractProminentSubject(response: response, knownSubjects: SubjectCatalog.supported) {
            promptBoostSubject = boostSubject
        }
        rebuildPlan(now: now)
        appendPlannerMessage(PromptMessage(role: .assistant, text: response), subject: promptBoostSubject ?? SubjectCatalog.matchingSubject(in: rawPrompt))
        save()
    }

    func submitStudyPrompt() async {
        let rawPrompt = studyPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPrompt.isEmpty else { return }
        studyPromptText = ""

        if rawPrompt.lowercased() == "end quiz" {
            endQuiz()
            return
        }

        if let quizSubject = extractQuizSubject(from: rawPrompt) {
            await startQuiz(subject: quizSubject)
            return
        }

        if isQuizMode {
            await continueQuiz(with: rawPrompt)
            return
        }

        let now = Date.now
        let autonomousContext = AutonomousContextProvider.build(question: rawPrompt, now: now)
        let activeTask = selectedTask
        let subject = activeTask?.subject ?? SubjectCatalog.matchingSubject(in: rawPrompt) ?? "English"
        let studyContexts = groundedStudyContexts(for: activeTask, subject: subject)

        appendStudyMessage(PromptMessage(role: .user, text: rawPrompt), subject: subject)
        aiErrorText = nil
        isRunningPrompt = true

        let response = await CodexBridge().run(
            request: CodexRunRequest(
                prompt: buildStudyPrompt(
                    for: rawPrompt,
                    task: activeTask,
                    subject: subject,
                    contexts: studyContexts,
                    autonomousContext: autonomousContext
                ),
                autonomousMode: TimedPreferences.autonomousModeEnabled,
                workingRoot: TimedPreferences.workingRoot,
                additionalRoots: TimedPreferences.codexAdditionalRoots
            )
        )

        isRunningPrompt = false

        guard let response else {
            aiErrorText = "Could not reach Timed AI — check Codex is installed"
            appendStudyMessage(PromptMessage(role: .assistant, text: aiErrorText ?? "Timed AI error"), subject: subject)
            save()
            return
        }

        let subjectConfidences = CodexBridge.extractSubjectConfidences(response: response, knownSubjects: SubjectCatalog.supported)
        applySubjectConfidences(subjectConfidences)
        if let boostSubject = CodexBridge.extractProminentSubject(response: response, knownSubjects: SubjectCatalog.supported) {
            promptBoostSubject = boostSubject
            rebuildPlan(now: now)
        } else {
            save()
        }
        appendStudyMessage(PromptMessage(role: .assistant, text: response), subject: subject)
        save()
    }

    func startQuiz(subject: String) async {
        let normalizedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingContexts = groundedStudyContexts(for: selectedTask, subject: normalizedSubject)

        guard !matchingContexts.isEmpty else {
            appendStudyMessage(
                PromptMessage(role: .assistant, text: "No grounded study context is loaded for \(normalizedSubject). Import your transcript, notes, or feedback first."),
                subject: normalizedSubject
            )
            save()
            return
        }

        isQuizMode = true
        activeQuizSubject = normalizedSubject
        if let taskForSubject = tasks.first(where: { $0.subject.caseInsensitiveCompare(normalizedSubject) == .orderedSame }) {
            selectedTaskID = taskForSubject.id
        }
        aiErrorText = nil
        isRunningPrompt = true
        appendStudyMessage(
            PromptMessage(role: .student, text: "Quiz me on \(normalizedSubject).", isQuiz: true),
            subject: normalizedSubject
        )

        let response = await CodexBridge().run(
            request: CodexRunRequest(
                prompt: buildQuizPrompt(
                    subject: normalizedSubject,
                    contexts: matchingContexts,
                    latestStudentReply: nil
                ),
                autonomousMode: TimedPreferences.autonomousModeEnabled,
                workingRoot: TimedPreferences.workingRoot,
                additionalRoots: TimedPreferences.codexAdditionalRoots
            )
        )
        isRunningPrompt = false

        guard let response else {
            aiErrorText = "Could not reach Timed AI — check Codex is installed"
            appendStudyMessage(PromptMessage(role: .assistant, text: aiErrorText ?? "Timed AI error"), subject: normalizedSubject)
            save()
            return
        }

        appendStudyMessage(PromptMessage(role: .tutor, text: response, isQuiz: true), subject: normalizedSubject)
        save()
    }

    func endQuiz() {
        isQuizMode = false
        activeQuizSubject = nil
        appendStudyMessage(PromptMessage(role: .assistant, text: "Quiz ended. Back to study mode."))
        save()
    }

    func markTaskCompleted(_ task: TaskItem, now: Date = .now) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted = true
        tasks[index].completedAt = now
        dismissedScheduleTaskIDs.insert(task.id)
        rebuildPlan(now: now)
    }

    func recordStudyDebrief(taskID: String, confidence: Int, covered: String, blockers: String, at: Date = .now) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }

        tasks[index].confidence = max(1, min(5, confidence))
        let task = tasks[index]
        let trimmedCovered = covered.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBlockers = blockers.trimmingCharacters(in: .whitespacesAndNewlines)

        let summaryText: String
        if !trimmedCovered.isEmpty {
            summaryText = trimmedCovered
        } else if !trimmedBlockers.isEmpty {
            summaryText = "Blockers: \(trimmedBlockers)"
        } else {
            summaryText = "Confidence updated to \(task.confidence)/5."
        }

        let detail = """
        Task: \(task.title)
        Subject: \(task.subject)
        Confidence now: \(task.confidence)/5
        Covered:
        \(trimmedCovered.isEmpty ? "Nothing entered." : trimmedCovered)

        Blockers:
        \(trimmedBlockers.isEmpty ? "None." : trimmedBlockers)
        """

        let context = ContextItem(
            id: StableID.makeContextID(source: .chat, title: "\(task.title)-debrief", createdAt: at),
            title: "\(task.title) debrief",
            kind: "Debrief",
            subject: task.subject,
            summary: summaryText,
            detail: detail,
            createdAt: at
        )

        contexts.removeAll { $0.id == context.id }
        contexts.insert(context, at: 0)
        contexts.sort { $0.createdAt > $1.createdAt }
        selectedContextID = context.id
        appendStudyMessage(
            PromptMessage(role: .assistant, text: "Debrief saved for \(task.title). Confidence is now \(task.confidence)/5."),
            subject: task.subject
        )
        CodexMemoryInsights.recordDebrief(
            task: task,
            confidence: task.confidence,
            covered: trimmedCovered,
            blockers: trimmedBlockers,
            at: at
        )
        rebuildPlan(now: at)
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
        appendPlannerMessage(PromptMessage(role: .assistant, text: "\(result.message)\(extra)"))
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

        let task = calibratedTask(draft.makeTask())
        if tasks.contains(where: { $0.id == task.id }) {
            return "That task already exists."
        }

        tasks.insert(task, at: 0)
        rebuildPlan()
        return nil
    }

    func syncObsidianVault() {
        let result = ObsidianVaultImporter.sync(vaultPath: TimedPreferences.obsidianVaultPath)
        contexts.removeAll { $0.kind == "Obsidian" }
        contexts.insert(contentsOf: result.contexts, at: 0)
        contexts.sort { $0.createdAt > $1.createdAt }
        lastImportMessages = [result.message]
        appendPlannerMessage(PromptMessage(role: .assistant, text: result.message))
        if selectedContext == nil {
            selectedContextID = contexts.first?.id
        }
        rebuildPlan()
    }

    func importCodexMemorySchoolPack(now: Date = .now, automatic: Bool = false) {
        guard TimedPreferences.codexMemoryEnabled else {
            if !automatic {
                let message = "Codex memory import is disabled in Settings."
                lastImportMessages = [message]
                chat.append(PromptMessage(role: .assistant, text: message))
                save()
            }
            return
        }

        let pack = CodexMemorySchoolPack.load(now: now)
        var importedTasks = 0
        var importedContexts = 0

        for task in pack.tasks.map(calibratedTask) {
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = task
            } else {
                tasks.insert(task, at: 0)
                importedTasks += 1
            }
        }

        for context in pack.contexts {
            if let index = contexts.firstIndex(where: { $0.id == context.id }) {
                contexts[index] = context
            } else {
                contexts.insert(context, at: 0)
                importedContexts += 1
            }
        }

        contexts.sort { $0.createdAt > $1.createdAt }
        promptBoostSubject = pack.focusSubject
        selectedTaskID = pack.preferredTaskID ?? selectedTaskID
        selectedContextID = pack.preferredContextID ?? selectedContextID

        let message = automatic
            ? "Auto-loaded Codex memory school pack with \(importedTasks) task(s) and \(importedContexts) context item(s)."
            : "\(pack.message) Imported \(importedTasks) task(s) and \(importedContexts) context item(s)."

        lastImportMessages = [message]
        appendPlannerMessage(PromptMessage(role: .assistant, text: message), subject: pack.focusSubject)
        rebuildPlan(now: now)
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
            let task = calibratedTask(draft.makeTask())
            guard !tasks.contains(where: { $0.id == task.id }) else { continue }
            tasks.insert(task, at: 0)
        }

        lastImportMessages = batch.messages
        if !batch.messages.isEmpty {
            appendPlannerMessage(PromptMessage(role: .assistant, text: batch.messages.joined(separator: "\n")))
        }
        rebuildPlan()
    }

    private func continueQuiz(with answer: String) async {
        guard let activeQuizSubject else { return }
        let matchingContexts = groundedStudyContexts(for: selectedTask, subject: activeQuizSubject)
        appendStudyMessage(PromptMessage(role: .student, text: answer, isQuiz: true), subject: activeQuizSubject)
        isRunningPrompt = true

        let response = await CodexBridge().run(
            request: CodexRunRequest(
                prompt: buildQuizPrompt(
                    subject: activeQuizSubject,
                    contexts: matchingContexts,
                    latestStudentReply: answer
                ),
                autonomousMode: TimedPreferences.autonomousModeEnabled,
                workingRoot: TimedPreferences.workingRoot,
                additionalRoots: TimedPreferences.codexAdditionalRoots
            )
        )

        isRunningPrompt = false
        guard let response else {
            aiErrorText = "Could not reach Timed AI — check Codex is installed"
            appendStudyMessage(PromptMessage(role: .assistant, text: aiErrorText ?? "Timed AI error"), subject: activeQuizSubject)
            save()
            return
        }

        appendStudyMessage(PromptMessage(role: .tutor, text: response, isQuiz: true), subject: activeQuizSubject)
        save()
    }

    private func buildPlanningPrompt(
        for question: String,
        now: Date,
        autonomousContext: AutonomousContextBundle,
        intent: PromptIntent
    ) -> String {
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

        let fileLines = autonomousContext.fileHits.prefix(6).map { hit in
            "- \(hit.path) (\(hit.source))"
        }.joined(separator: "\n")

        let memoryLines = autonomousContext.memoryHits.prefix(5).map { hit in
            "- [\(hit.source)] \(hit.title): \(hit.excerpt)"
        }.joined(separator: "\n")

        let taskHintLines = autonomousContext.taskHints.map { hint in
            let due = hint.dueDate.map { dateFormatter.string(from: $0) } ?? "Unknown"
            return "- \(hint.title) | Subject: \(hint.subject) | Due: \(due)"
        }.joined(separator: "\n")

        let systemInstruction: String
        switch intent {
        case .planner:
            systemInstruction = """
            You are Timed, a study planner for a school student. You wrap the local Codex CLI and may inspect local files, OneDrive-synced folders, TickTick exports, ~/.codex-mem/codex-mem.db, and Codex chat logs when useful. If the context below is ambiguous, you may explicitly use terminal commands through Codex to inspect those local sources. Respond in concise plain English. Mention at least one task by its exact title. If you suggest a specific next action for a task, format that line exactly as [task title]: [action]. If you infer subject confidence from memory or feedback, format that line exactly as [subject confidence]: [1-5].
            """
        case .lookup:
            systemInstruction = """
            You are Timed, a local autonomous Codex wrapper for a school student. Use the file paths, OneDrive hints, TickTick hints, ~/.codex-mem/codex-mem.db, and Codex memory below to answer the question directly. If the context below is ambiguous, you may explicitly use terminal commands through Codex to inspect those local sources. Respond in concise plain English. If you suggest a next action for a current task, format that line exactly as [task title]: [action]. If you infer subject confidence from memory or feedback, format that line exactly as [subject confidence]: [1-5].
            """
        }

        return """
        System instruction:
        \(systemInstruction)

        Current date and time:
        \(dateFormatter.string(from: now))

        Full ranked task list:
        \(taskLines)

        Current task hints extracted from the user's message:
        \(taskHintLines.isEmpty ? "- None detected" : taskHintLines)

        Top 3 relevant context summaries:
        \(contextLines.isEmpty ? "- None loaded" : contextLines)

        Relevant local file and OneDrive hits:
        \(fileLines.isEmpty ? "- None found" : fileLines)

        Relevant Codex memory hits:
        \(memoryLines.isEmpty ? "- None found" : memoryLines)

        User question:
        \(question)
        """
    }

    private func buildStudyPrompt(
        for question: String,
        task: TaskItem?,
        subject: String,
        contexts: [ContextItem],
        autonomousContext: AutonomousContextBundle
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        let taskLine: String
        if let task {
            let dueDate = task.dueDate.map { dateFormatter.string(from: $0) } ?? "No due date"
            taskLine = "- \(task.title) | Subject: \(task.subject) | Due: \(dueDate) | Estimate: \(task.estimateMinutes)m | Confidence: \(task.confidence)/5 | Importance: \(task.importance)/5 | Notes: \(task.notes)"
        } else {
            taskLine = "- No task selected"
        }

        let subjectTasks = tasks
            .filter { !$0.isCompleted && $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
            .sorted { lhs, rhs in
                if let lhsDue = lhs.dueDate, let rhsDue = rhs.dueDate {
                    return lhsDue < rhsDue
                }
                return lhs.title < rhs.title
            }
            .map { task in
                let dueDate = task.dueDate.map { dateFormatter.string(from: $0) } ?? "No due date"
                return "- \(task.title) | Due: \(dueDate) | Estimate: \(task.estimateMinutes)m | Confidence: \(task.confidence)/5 | Importance: \(task.importance)/5"
            }
            .joined(separator: "\n")

        let contextDetails = contexts.prefix(6).map { context in
            """
            [\(context.kind)] \(context.title)
            \(context.detail)
            """
        }.joined(separator: "\n\n")

        let fileLines = autonomousContext.fileHits.prefix(6).map { hit in
            "- \(hit.path) (\(hit.source))"
        }.joined(separator: "\n")

        let memoryLines = autonomousContext.memoryHits.prefix(5).map { hit in
            "- [\(hit.source)] \(hit.title): \(hit.excerpt)"
        }.joined(separator: "\n")

        return """
        System instruction:
        You are Timed study mode for a school student. You wrap the local Codex CLI in autonomous mode. You may inspect local files, OneDrive-synced folders, TickTick exports, ~/.codex-mem/codex-mem.db, and Codex chat logs when needed. Only rely on real imported study context, exact file hits, and exact memory hits below. Do not invent extra study material. If the student asks for a quiz, ask one question at a time unless they explicitly ask for a worksheet. If the student asks for a practice sheet or a Word document that mirrors a school formative, you may create files in the working directory and must report the exact output path. Respond in concise plain English.

        Current date and time:
        \(dateFormatter.string(from: .now))

        Selected task:
        \(taskLine)

        Other active tasks for this subject:
        \(subjectTasks.isEmpty ? "- None" : subjectTasks)

        Grounded study context for \(subject):
        \(contextDetails.isEmpty ? "No imported context is loaded for this subject." : contextDetails)

        Relevant local file and OneDrive hits:
        \(fileLines.isEmpty ? "- None found" : fileLines)

        Relevant Codex memory hits:
        \(memoryLines.isEmpty ? "- None found" : memoryLines)

        Student request:
        \(question)
        """
    }

    private func buildQuizPrompt(subject: String, contexts: [ContextItem], latestStudentReply: String?) -> String {
        let material = contexts.map { context in
            """
            [\(context.kind)] \(context.title)
            \(context.detail)
            """
        }.joined(separator: "\n\n")

        let transcript = studyChat
            .filter(\.isQuiz)
            .suffix(8)
            .map { "\($0.role.displayName): \($0.text)" }
            .joined(separator: "\n")

        let memoryLines = CodexMemorySearchProvider.search(question: subject, limit: 4).map { hit in
            "- [\(hit.source)] \(hit.title): \(hit.excerpt)"
        }.joined(separator: "\n")

        return """
        You are a study tutor. Ask the student one question at a time based on the material below. Wait for their answer before proceeding. Keep questions concise. After their answer, give brief feedback.

        Subject:
        \(subject)

        Material:
        \(material)

        Recent quiz transcript:
        \(transcript.isEmpty ? "None yet." : transcript)

        Related Codex memory hits:
        \(memoryLines.isEmpty ? "- None found" : memoryLines)

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

    func groundedStudyContexts(for task: TaskItem?, subject: String? = nil) -> [ContextItem] {
        let resolvedSubject = subject ?? task?.subject
        guard let resolvedSubject else { return [] }

        let subjectContexts = sortedContexts.filter {
            $0.subject.caseInsensitiveCompare(resolvedSubject) == .orderedSame &&
            !$0.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if let task {
            let taskKeywords = Set(task.title.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            return subjectContexts.sorted { lhs, rhs in
                groundedStudyScore(for: lhs, taskKeywords: taskKeywords) >
                    groundedStudyScore(for: rhs, taskKeywords: taskKeywords)
            }
        }

        return subjectContexts
    }

    private func groundedStudyScore(for context: ContextItem, taskKeywords: Set<String>) -> Int {
        let haystack = "\(context.title) \(context.summary) \(context.detail)".lowercased()
        var total = taskKeywords.reduce(into: 0) { partialResult, keyword in
            if haystack.contains(keyword) {
                partialResult += 5
            }
        }

        if context.kind.caseInsensitiveCompare(ImportSource.transcript.rawValue) == .orderedSame {
            total += 20
        }

        total += max(0, 48 - Int(Date.now.timeIntervalSince(context.createdAt) / 3600))
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

    private func applySubjectConfidences(_ values: [String: Int]) {
        guard !values.isEmpty else { return }
        for index in tasks.indices {
            if let confidence = values[tasks[index].subject] {
                tasks[index].confidence = confidence
            }
        }
    }

    private func upsertTaskHints(_ hints: [TaskHint]) {
        guard !hints.isEmpty else { return }

        for hint in hints {
            if let index = tasks.firstIndex(where: {
                $0.title.caseInsensitiveCompare(hint.title) == .orderedSame ||
                ($0.subject.caseInsensitiveCompare(hint.subject) == .orderedSame && $0.title.lowercased().contains(hint.subject.lowercased()))
            }) {
                tasks[index].dueDate = hint.dueDate ?? tasks[index].dueDate
                if tasks[index].notes.isEmpty {
                    tasks[index].notes = hint.notes
                }
                if tasks[index].confidence == 3 {
                    tasks[index].confidence = inferredConfidence(for: tasks[index])
                }
                continue
            }

            let task = calibratedTask(TaskItem(
                id: StableID.makeTaskID(source: .chat, title: hint.title),
                title: hint.title,
                list: "Prompt captured",
                source: .chat,
                subject: hint.subject,
                estimateMinutes: hint.subject == "Maths" ? 90 : 45,
                confidence: 3,
                importance: 5,
                dueDate: hint.dueDate,
                notes: hint.notes,
                energy: hint.subject == "Maths" ? .high : .medium,
                isCompleted: false,
                completedAt: nil
            ))

            tasks.insert(task, at: 0)
        }
    }

    private func importRelevantTickTickTasks(now: Date) {
        let tickTickTasks = TickTickAutonomousImport.recentRelevantTasks(now: now)
        guard !tickTickTasks.isEmpty else { return }

        var insertedCount = 0
        for task in tickTickTasks {
            let calibrated = calibratedTask(task)
            guard !tasks.contains(where: { $0.id == calibrated.id }) else { continue }
            tasks.append(calibrated)
            insertedCount += 1
        }

        if insertedCount > 0 {
            appendPlannerMessage(PromptMessage(role: .assistant, text: "Imported \(insertedCount) relevant TickTick task(s) from your recent CSV export."))
        }
    }

    private func startSeqtaBackgroundSync() {
        SeqtaBackgroundSync.ensureLaunchAgentInstalled()
        seqtaWatcher = SeqtaFileWatcher { [weak self] in
            DispatchQueue.main.async {
                self?.refreshSeqtaSnapshotIfAvailable()
            }
        }
        refreshSeqtaSnapshotIfAvailable()
    }

    private func refreshSeqtaSnapshotIfAvailable(now: Date = .now) {
        let seqtaTasks = SeqtaBackgroundSync.loadTasks(now: now)
        guard !seqtaTasks.isEmpty else { return }

        var insertedCount = 0
        var updatedCount = 0

        for task in seqtaTasks.map(calibratedTask) {
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                let merged = mergeSeqtaTask(existing: tasks[index], incoming: task)
                if merged != tasks[index] {
                    tasks[index] = merged
                    updatedCount += 1
                }
                continue
            }

            tasks.insert(task, at: 0)
            insertedCount += 1
        }

        guard insertedCount > 0 || updatedCount > 0 else { return }
        let message = "Seqta background sync updated \(insertedCount) new task(s) and \(updatedCount) existing task(s)."
        lastImportMessages = [message]
        appendPlannerMessage(PromptMessage(role: .assistant, text: message))
        rebuildPlan(now: now)
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

    private func calibratedTask(_ task: TaskItem) -> TaskItem {
        var mutable = task
        mutable.confidence = inferredConfidence(for: task)
        return mutable
    }

    private func inferredConfidence(for task: TaskItem) -> Int {
        guard task.confidence == 3 else { return task.confidence }
        return CodexMemoryInsights.inferredConfidence(
            subject: task.subject,
            title: task.title,
            fallback: task.confidence
        )
    }

    private func appendPlannerMessage(_ message: PromptMessage, subject: String? = nil) {
        chat.append(message)
        CodexMemorySync.recordMessage(message, channel: .planner, subject: subject)
    }

    private func appendStudyMessage(_ message: PromptMessage, subject: String? = nil) {
        studyChat.append(message)
        CodexMemorySync.recordMessage(message, channel: .study, subject: subject)
    }

    private func mergeSeqtaTask(existing: TaskItem, incoming: TaskItem) -> TaskItem {
        var merged = existing
        merged.title = incoming.title
        merged.list = incoming.list
        merged.source = incoming.source
        merged.subject = incoming.subject
        merged.estimateMinutes = incoming.estimateMinutes
        if !existing.isCompleted {
            merged.confidence = incoming.confidence
        }
        merged.importance = incoming.importance
        merged.dueDate = incoming.dueDate
        merged.notes = incoming.notes
        merged.energy = incoming.energy
        return merged
    }

    private func bootstrapCodexMemoryPackIfNeeded() {
        guard tasks.isEmpty else { return }
        importCodexMemorySchoolPack(automatic: true)
    }

    private func syncChatsFromCodexMemoryIfAvailable() {
        guard TimedPreferences.codexMemoryEnabled else { return }

        let remotePlannerChat = CodexMemorySync.loadConversation(channel: .planner)
        let remoteStudyChat = CodexMemorySync.loadConversation(channel: .study)

        let mergedPlannerChat = CodexMemorySync.merge(local: chat, remote: remotePlannerChat)
        let mergedStudyChat = CodexMemorySync.merge(local: studyChat, remote: remoteStudyChat)

        if mergedPlannerChat != chat || mergedStudyChat != studyChat {
            chat = mergedPlannerChat
            studyChat = mergedStudyChat
            save()
        }
    }
}
