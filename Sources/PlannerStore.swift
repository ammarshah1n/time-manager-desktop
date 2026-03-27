import Foundation
import Observation

private enum FailedAIAction {
    case planning(String)
    case study(String)
    case quizStart(String)
    case quizReply(String)
}

@MainActor
@Observable
final class PlannerStore {
    private let storageURL: URL
    @ObservationIgnored private var seqtaWatcher: SeqtaFileWatcher?
    @ObservationIgnored private var deadlineMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var pendingCalibrationQueue: [String] = []
    @ObservationIgnored private var lastFailedAIAction: FailedAIAction?
    @ObservationIgnored private var toastDismissTask: Task<Void, Never>?
    @ObservationIgnored private var decompositionUndoStack: [[TaskItem]] = []

    var tasks: [TaskItem] = []
    var grades: [GradeEntry] = []
    var contexts: [ContextItem] = []
    var obsidianDocuments: [ContextDocument] = []
    var schedule: [ScheduleBlock] = []
    var subjectConfidences: [String: Int] = [:]
    var confidenceHistory: [String: [ConfidenceReading]] = [:]
    var quizQuestionsBySubject: [String: [QuizQuestion]] = [:]
    var pendingCalibrationSubject: String?
    var rankedTasks: [RankedTask] = []
    var selectedTaskID: String?
    var selectedContextID: String?
    var promptText = ""
    var studyPromptText = ""
    var chat: [PromptMessage] = []
    var studyChat: [PromptMessage] = []
    var isRunningPrompt = false
    var aiErrorText: String?
    var promptErrorState: PromptErrorState?
    var settingsIssue: SettingsIssueState?
    var toastState: ToastState?
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
    var isSyncingObsidianVault = false
    var pomodoroLog: [String: Int] = [:]
    var decomposingTaskIDs: Set<String> = []
    var canUndoDecomposition = false
    var lastWeeklyReview: Date?
    var showWeeklyReview = false

    init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        TimedPreferences.migrateLegacyValuesIfNeeded()
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let folderURL = baseURL.appendingPathComponent("Timed", isDirectory: true)
        self.storageURL = storageURL ?? folderURL.appendingPathComponent("planner-state.json")
        load()
        // Defer heavy init off the main thread to avoid blocking SwiftUI startup
        Task { @MainActor in
            self.syncChatsFromCodexMemoryIfAvailable()
            self.bootstrapCodexMemoryPackIfNeeded()
            self.scheduleCodexMemoryDeadlineDiscovery()
            if !Self.isRunningUnderTests {
                DeadlineAlertService.shared.requestAuthorizationIfNeeded()
                self.startDeadlineMonitor()
                self.startSeqtaBackgroundSync()
            }
        }
    }

    deinit {
        deadlineMonitorTask?.cancel()
        toastDismissTask?.cancel()
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

    func refreshWeeklyReviewState(now: Date = .now) {
        showWeeklyReview = shouldShowWeeklyReview(now: now)
    }

    func dismissWeeklyReview(now: Date = .now) {
        lastWeeklyReview = now
        showWeeklyReview = false
        save()
    }

    func weeklyReviewSummary(now: Date = .now) -> WeeklyReviewSummary {
        let calendar = Calendar.current
        let windowStart = weeklyReviewWindowStart(now: now, calendar: calendar)
        let completedTaskCount = tasks.filter { task in
            guard task.isCompleted, let completedAt = task.completedAt else { return false }
            return completedAt >= windowStart && completedAt <= now
        }.count
        let totalPomodoros = pomodoroTrend(referenceDate: now, days: 7).reduce(0) { $0 + $1.count }
        let confidenceDeltas = weeklyConfidenceDeltas(now: now, windowStart: windowStart)

        return WeeklyReviewSummary(
            completedTaskCount: completedTaskCount,
            totalPomodoros: totalPomodoros,
            confidenceDeltas: confidenceDeltas,
            topPriorities: Array(rankedTasksSnapshot(now: now).prefix(3))
        )
    }

    func save() {
        let snapshot = PlannerSnapshot(
            tasks: tasks,
            grades: grades,
            contexts: contexts,
            schedule: schedule,
            subjectConfidences: subjectConfidences,
            confidenceHistory: confidenceHistory,
            quizQuestionsBySubject: quizQuestionsBySubject,
            selectedTaskID: selectedTaskID,
            selectedContextID: selectedContextID,
            promptText: promptText,
            chat: chat,
            studyChat: studyChat,
            promptBoostSubject: promptBoostSubject,
            dismissedScheduleTaskIDs: Array(dismissedScheduleTaskIDs),
            obsidianDocuments: obsidianDocuments,
            pomodoroLog: pomodoroLog,
            lastWeeklyReview: lastWeeklyReview
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
            grades = snapshot.grades
            contexts = snapshot.contexts
            schedule = snapshot.schedule
            subjectConfidences = snapshot.subjectConfidences
            confidenceHistory = snapshot.confidenceHistory
            quizQuestionsBySubject = snapshot.quizQuestionsBySubject
            obsidianDocuments = snapshot.obsidianDocuments
            selectedTaskID = snapshot.selectedTaskID
            selectedContextID = snapshot.selectedContextID
            promptText = snapshot.promptText
            chat = snapshot.chat
            studyChat = snapshot.studyChat
            promptBoostSubject = snapshot.promptBoostSubject
            dismissedScheduleTaskIDs = Set(snapshot.dismissedScheduleTaskIDs)
            pomodoroLog = snapshot.pomodoroLog
            lastWeeklyReview = snapshot.lastWeeklyReview
        } else {
            let sample = ShellData.empty
            tasks = sample.tasks
            grades = []
            contexts = sample.contexts
            schedule = sample.schedule
            subjectConfidences = [:]
            confidenceHistory = [:]
            quizQuestionsBySubject = [:]
            obsidianDocuments = []
            chat = sample.chat
            studyChat = sample.studyChat
            selectedTaskID = sample.tasks.first?.id
            selectedContextID = sample.contexts.first?.id
            promptText = ""
            studyPromptText = ""
            pomodoroLog = [:]
            lastWeeklyReview = nil
        }

        migrateTaskIdentityIfNeeded()
        normalizeQuizQuestionState()
        syncConfidenceHistoryState()
        rebuildPlan()
        refreshWeeklyReviewState()
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
        syncSubjectConfidenceState()
        rankedTasks = rankedTasksSnapshot(now: now)

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

        refreshDeadlineState(now: now, rescheduleNotifications: true)
        save()
    }

    func submitPrompt() async {
        await submitPlanningPrompt()
    }

    func submitPlanningPrompt() async {
        let rawPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPrompt.isEmpty else { return }
        promptText = ""
        await runPlanningPrompt(rawPrompt, appendUserMessage: true)
    }

    private func runPlanningPrompt(_ rawPrompt: String, appendUserMessage: Bool) async {
        let now = Date.now

        if let quizSubject = extractQuizSubject(from: rawPrompt) {
            await startQuiz(subject: quizSubject, appendPromptMessage: appendUserMessage)
            return
        }

        let autonomousContext = AutonomousContextProvider.build(question: rawPrompt, now: now)
        upsertTaskHints(autonomousContext.taskHints)

        if rawPrompt.lowercased().contains("ticktick") {
            importRelevantTickTickTasks(now: now)
        }

        rebuildPlan(now: now)
        clearPromptError()
        if appendUserMessage {
            appendPlannerMessage(PromptMessage(role: .user, text: rawPrompt), subject: SubjectCatalog.matchingSubject(in: rawPrompt))
        }
        isRunningPrompt = true

        let result = await CodexBridge().run(
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

        guard let response = CodexBridge.response(from: result) else {
            handlePromptFailure(
                result: result,
                action: .planning(rawPrompt)
            )
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

    func generateDayPlanSummary(now: Date = .now) async -> UUID? {
        let topTasks = Array(rankedTasks.prefix(3))
        guard !topTasks.isEmpty else { return nil }

        aiErrorText = nil
        isRunningPrompt = true

        let result = await CodexBridge().run(
            request: CodexRunRequest(
                prompt: buildDayPlanPrompt(now: now, topTasks: topTasks),
                autonomousMode: TimedPreferences.autonomousModeEnabled,
                workingRoot: TimedPreferences.workingRoot,
                additionalRoots: TimedPreferences.codexAdditionalRoots
            )
        )

        isRunningPrompt = false

        guard let response = CodexBridge.response(from: result) else {
            aiErrorText = CodexBridge.handleFailureMessage(result) ?? "Timed AI failed before returning a response."
            appendPlannerMessage(PromptMessage(role: .assistant, text: aiErrorText ?? "Timed AI error"))
            save()
            return nil
        }

        let summary = dayPlanSummary(from: response)
        let message = PromptMessage(
            role: .assistant,
            text: summary,
            createdAt: .now,
            isPinned: true
        )

        pinPlannerMessage(message, subject: topTasks.first?.task.subject)
        save()
        return message.id
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

        await runStudyPrompt(rawPrompt, appendUserMessage: true)
    }

    private func runStudyPrompt(_ rawPrompt: String, appendUserMessage: Bool) async {
        let now = Date.now
        let autonomousContext = AutonomousContextProvider.build(question: rawPrompt, now: now)
        let activeTask = selectedTask
        let subject = activeTask?.subject ?? SubjectCatalog.matchingSubject(in: rawPrompt) ?? "English"
        let studyContexts = groundedStudyContexts(for: activeTask, subject: subject)

        if appendUserMessage {
            appendStudyMessage(PromptMessage(role: .user, text: rawPrompt), subject: subject)
        }
        clearPromptError()
        isRunningPrompt = true

        let result = await CodexBridge().run(
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

        guard let response = CodexBridge.response(from: result) else {
            handlePromptFailure(
                result: result,
                action: .study(rawPrompt)
            )
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

    func startQuiz(subject: String, appendPromptMessage: Bool = true) async {
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
        clearPromptError()
        isRunningPrompt = true
        if appendPromptMessage {
            appendStudyMessage(
                PromptMessage(role: .student, text: "Quiz me on \(normalizedSubject).", isQuiz: true),
                subject: normalizedSubject
            )
        }

        let result = await CodexBridge().run(
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

        guard let response = CodexBridge.response(from: result) else {
            handlePromptFailure(
                result: result,
                action: .quizStart(normalizedSubject)
            )
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

    func moveTask(from source: IndexSet, to destination: Int, orderedRootTaskIDs: [String]) {
        let orderedRoots = orderedRootTaskIDs.compactMap { rootTaskID in
            tasks.first(where: { $0.id == rootTaskID && $0.parentId == nil })
        }
        let sourceIndexes = source.sorted()
        guard !orderedRoots.isEmpty, !sourceIndexes.isEmpty else { return }

        var reorderedRoots = orderedRoots
        let movedRoots = sourceIndexes.map { reorderedRoots[$0] }
        for index in sourceIndexes.reversed() {
            reorderedRoots.remove(at: index)
        }

        let adjustedDestination = max(0, min(
            destination - sourceIndexes.filter { $0 < destination }.count,
            reorderedRoots.count
        ))
        reorderedRoots.insert(contentsOf: movedRoots, at: adjustedDestination)

        let movedRootIDs = Set(movedRoots.map(\.id))
        var rankOverrides: [String: Int] = [:]
        for (index, task) in reorderedRoots.enumerated() where task.manualRank != nil || movedRootIDs.contains(task.id) {
            rankOverrides[task.id] = index * 100
        }

        guard !rankOverrides.isEmpty else { return }
        for index in tasks.indices {
            guard let manualRank = rankOverrides[tasks[index].id] else { continue }
            tasks[index].manualRank = manualRank
        }

        rebuildPlan()
    }

    func resetManualRank(for taskID: String, now: Date = .now) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard tasks[index].manualRank != nil else { return }
        tasks[index].manualRank = nil
        rebuildPlan(now: now)
    }

    func children(of taskID: String) -> [TaskItem] {
        tasks.filter { $0.parentId == taskID }
    }

    func canBreakDown(task: TaskItem) -> Bool {
        task.parentId == nil &&
            children(of: task.id).isEmpty &&
            !decomposingTaskIDs.contains(task.id)
    }

    func decompose(task: TaskItem) async {
        await decompose(task: task) { prompt in
            await CodexBridge().send(prompt: prompt)
        }
    }

    func decompose(
        task: TaskItem,
        runner: @escaping (String) async -> CodexRunResult
    ) async {
        guard canBreakDown(task: task) else { return }

        decomposingTaskIDs.insert(task.id)
        defer {
            decomposingTaskIDs.remove(task.id)
        }

        let result = await runner(Self.decompositionPrompt(for: task))
        guard let response = CodexBridge.response(from: result) else {
            let message = CodexBridge.handleFailureMessage(result) ?? "Timed AI failed before returning subtasks."
            presentToast(
                title: "Breakdown failed",
                message: message,
                systemImage: "exclamationmark.triangle.fill",
                tone: .error
            )
            return
        }

        let parsedTitles = Self.parseSubtaskLines(from: response)
        guard !parsedTitles.isEmpty else {
            presentToast(
                title: "No subtasks found",
                message: "Timed couldn't parse a numbered subtask list for \(task.title).",
                systemImage: "list.number",
                tone: .error
            )
            return
        }

        let existingIDs = Set(tasks.map(\.id))
        let estimateMinutes = max(5, task.estimateMinutes / max(parsedTitles.count, 1))
        var seenTitles: Set<String> = []
        var newTasks: [TaskItem] = []

        for title in parsedTitles {
            let normalizedTitle = StableID.normalizedTaskIdentityTitle(from: title)
            guard !normalizedTitle.isEmpty else { continue }
            guard !seenTitles.contains(normalizedTitle) else { continue }
            seenTitles.insert(normalizedTitle)

            let subtaskID = StableID.makeSubtaskID(parentID: task.id, title: title)
            guard !existingIDs.contains(subtaskID) else { continue }

            newTasks.append(
                TaskItem(
                    id: subtaskID,
                    title: title,
                    list: task.list,
                    source: task.source,
                    subject: task.subject,
                    estimateMinutes: estimateMinutes,
                    confidence: task.confidence,
                    importance: task.importance,
                    dueDate: task.dueDate,
                    notes: "",
                    energy: task.energy,
                    parentId: task.id,
                    isCompleted: false,
                    completedAt: nil
                )
            )
        }

        guard !newTasks.isEmpty else {
            presentToast(
                title: "Already broken down",
                message: "Timed didn't find any new subtasks to add for \(task.title).",
                systemImage: "list.bullet.indent",
                tone: .info
            )
            return
        }

        decompositionUndoStack.append(tasks)
        canUndoDecomposition = true
        tasks.append(contentsOf: newTasks)
        rebuildPlan()

        presentToast(
            title: "Added subtasks",
            message: "\(newTasks.count) subtasks were added under \(task.title).",
            systemImage: "bolt.fill",
            tone: .info
        )
    }

    func undoLastDecomposition(now: Date = .now) {
        guard let snapshot = decompositionUndoStack.popLast() else { return }
        tasks = snapshot
        canUndoDecomposition = !decompositionUndoStack.isEmpty
        rebuildPlan(now: now)
        presentToast(
            title: "Subtasks removed",
            message: "The last breakdown batch was undone.",
            systemImage: "arrow.uturn.backward",
            tone: .info
        )
    }

    func updateTaskNotes(taskID: String, notes: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard tasks[index].notes != notes else { return }
        tasks[index].notes = notes
        save()
    }

    func recordPomodoro(at now: Date = .now) {
        let key = Self.pomodoroLogKey(for: now)
        pomodoroLog[key, default: 0] += 1
    }

    @discardableResult
    func recordPomodoro(for taskID: String, at now: Date = .now) -> Int {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return 0 }
        tasks[index].pomodoroCount += 1
        recordPomodoro(at: now)
        let updatedCount = tasks[index].pomodoroCount
        save()
        return updatedCount
    }

    func pomodoroCount(on date: Date = .now) -> Int {
        pomodoroLog[Self.pomodoroLogKey(for: date), default: 0]
    }

    func currentPomodoroStreak(referenceDate: Date = .now) -> Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: referenceDate)
        var streak = 0

        while pomodoroCount(on: day) > 0 {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }

        return streak
    }

    func pomodoroTrend(referenceDate: Date = .now, days: Int = 7) -> [PomodoroDayStat] {
        let safeDays = max(1, days)
        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: referenceDate)

        return (0..<safeDays).compactMap { offset in
            let delta = offset - (safeDays - 1)
            guard let day = calendar.date(byAdding: .day, value: delta, to: referenceDay) else {
                return nil
            }
            return PomodoroDayStat(date: day, count: pomodoroCount(on: day))
        }
    }

    private static func pomodoroLogKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        // Persist using the local school-day boundary instead of UTC.
        return String(format: "%04d-%02d-%02d", year, month, day)
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
        subjectConfidences[canonicalSubjectName(task.subject)] = normalizedConfidencePercent(task.confidence)
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

    func exportDailyPlanPDF(
        referenceDate: Date = .now,
        rankedTasks: [RankedTask],
        activePomodoroNote: String?
    ) async {
        let todaysSchedule = schedule
            .filter { Calendar.current.isDate($0.start, inSameDayAs: referenceDate) }
            .sorted { $0.start < $1.start }
        let topTasks = Array(rankedTasks.prefix(3)).map(\.task)

        do {
            let result = try PDFExporter.exportDailyPlan(
                date: referenceDate,
                tasks: topTasks,
                schedule: todaysSchedule,
                activePomodoroNote: activePomodoroNote
            )

            appendPlannerMessage(
                PromptMessage(
                    role: .assistant,
                    text: "Exported today’s PDF plan to \(result.fileURL.lastPathComponent)."
                )
            )
            presentToast(
                title: "PDF exported",
                message: result.fileURL.lastPathComponent,
                systemImage: "doc.richtext",
                tone: .info
            )
            save()
        } catch {
            let message = error.localizedDescription
            appendPlannerMessage(
                PromptMessage(
                    role: .assistant,
                    text: "PDF export failed: \(message)"
                )
            )
            presentToast(
                title: "PDF export failed",
                message: message,
                systemImage: "exclamationmark.triangle.fill",
                tone: .error
            )
            save()
        }
    }

    func dismissPromptError() {
        clearPromptError()
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        toastState = nil
    }

    func retryLastFailedAIAction() async {
        guard let lastFailedAIAction else { return }
        clearPromptError()

        switch lastFailedAIAction {
        case let .planning(prompt):
            await runPlanningPrompt(prompt, appendUserMessage: false)
        case let .study(prompt):
            await runStudyPrompt(prompt, appendUserMessage: false)
        case let .quizStart(subject):
            await startQuiz(subject: subject, appendPromptMessage: false)
        case let .quizReply(answer):
            await continueQuiz(with: answer, appendStudentMessage: false)
        }
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

    func importCurrentPayloadUsingAI(now: Date = .now) async {
        let trimmed = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existingIDs = Set(tasks.map(\.id))
        let batch = await ImportPipeline.parseImportWithAI(
            title: importTitle,
            source: importSource,
            text: trimmed,
            now: now,
            existingTaskIDs: existingIDs,
            workingRoot: TimedPreferences.workingRoot,
            additionalRoots: TimedPreferences.codexAdditionalRoots,
            autonomousMode: TimedPreferences.autonomousModeEnabled
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

    func addManualTask(
        _ draft: AddTaskDraft,
        parseNaturalLanguage: Bool = true,
        now: Date = .now
    ) -> String? {
        let resolvedDraft = parseNaturalLanguage
            ? draft.resolvingNaturalLanguage(now: now)
            : draft

        guard !resolvedDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Task title is required."
        }
        guard resolvedDraft.estimateMinutes > 0 else {
            return "Estimate must be greater than zero."
        }

        let task = calibratedTask(resolvedDraft.makeTask())
        if tasks.contains(where: { $0.id == task.id }) {
            return "That task already exists."
        }

        tasks.insert(task, at: 0)
        queueCalibrationIfNeeded(for: task)
        rebuildPlan()
        return nil
    }

    func suggestedAssessmentDateText(for subject: String) -> String {
        guard let dueDate = earliestDueDate(for: subject) else { return "" }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    func skipPendingCalibration() {
        advancePendingCalibrationQueue()
        save()
    }

    func submitConfidenceCalibration(_ draft: ConfidenceCalibrationDraft, now: Date = .now) async -> String? {
        let subject = canonicalSubjectName(draft.subject)
        guard !subject.isEmpty else { return "Subject is missing." }

        let result = await CodexBridge().run(
            request: CodexRunRequest(
                prompt: buildConfidenceCalibrationPrompt(for: draft, subject: subject, now: now),
                autonomousMode: TimedPreferences.autonomousModeEnabled,
                workingRoot: TimedPreferences.workingRoot,
                additionalRoots: TimedPreferences.codexAdditionalRoots
            )
        )

        guard let response = CodexBridge.response(from: result) else {
            return CodexBridge.handleFailureMessage(result) ?? "Timed AI failed before returning a response."
        }

        guard let calibration = decodeConfidenceCalibrationResponse(from: response) else {
            return "Timed couldn't parse the calibration result. Try again."
        }

        applyConfidenceCalibration(
            subject: subject,
            percentConfidence: calibration.confidence,
            hints: calibration.hints,
            draft: draft,
            now: now
        )
        return nil
    }

    func applyConfidenceCalibration(
        subject: String,
        percentConfidence: Int,
        hints: [String],
        draft: ConfidenceCalibrationDraft,
        now: Date = .now
    ) {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return }

        let normalizedPercent = normalizedConfidencePercent(percentConfidence)
        var seenHints: Set<String> = []
        let normalizedHints = hints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { hint in
                guard !hint.isEmpty else { return false }
                return seenHints.insert(hint).inserted
            }
            .prefix(3)
            .map { $0 }

        subjectConfidences[canonicalSubject] = normalizedPercent
        recordConfidence(subject: canonicalSubject, value: Double(normalizedPercent) / 100.0, date: now)

        let calibratedConfidence = confidenceStars(fromPercent: normalizedPercent)
        // Calibration hints are subject-level, so apply them to every task in that subject.
        for index in tasks.indices where tasks[index].subject.caseInsensitiveCompare(canonicalSubject) == .orderedSame {
            tasks[index].confidence = calibratedConfidence
            tasks[index].notes = mergedCalibrationNotes(
                existingNotes: tasks[index].notes,
                subject: canonicalSubject,
                hints: normalizedHints
            )
        }

        let context = ContextItem(
            id: StableID.makeContextID(source: .chat, title: "\(canonicalSubject)-confidence-calibration", createdAt: now),
            title: "\(canonicalSubject) confidence calibration",
            kind: "Calibration",
            subject: canonicalSubject,
            summary: normalizedHints.first ?? "Initial confidence calibrated to \(normalizedPercent)%.",
            detail: calibrationContextDetail(
                subject: canonicalSubject,
                percentConfidence: normalizedPercent,
                hints: normalizedHints,
                draft: draft
            ),
            createdAt: now
        )

        contexts.removeAll { $0.id == context.id }
        contexts.insert(context, at: 0)
        contexts.sort { $0.createdAt > $1.createdAt }
        selectedContextID = context.id
        advancePendingCalibrationQueue(resolving: canonicalSubject)
        rebuildPlan(now: now)
    }

    func syncObsidianVault(announce: Bool = true) {
        let vaultPath = TimedPreferences.obsidianVaultPath
        guard !vaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastImportMessages = ["No Obsidian vault path is configured."]
            if announce {
                appendPlannerMessage(PromptMessage(role: .assistant, text: "No Obsidian vault path is configured."))
                save()
            }
            return
        }

        isSyncingObsidianVault = true
        Task.detached(priority: .utility) {
            let result = ObsidianVaultImporter.sync(vaultPath: vaultPath)
            await MainActor.run {
                self.applyObsidianSyncResult(result, announce: announce)
            }
        }
    }

    func topDocuments(for subject: String, limit: Int = 3) -> [ContextDocument] {
        let normalizedSubject = canonicalSubjectName(subject)
        guard !normalizedSubject.isEmpty else { return [] }

        let keywords = SubjectCatalog.keywords(for: normalizedSubject)
            .map(SubjectCatalog.normalizedSubjectText)
            .filter { !$0.isEmpty }

        return obsidianDocuments
            .filter { $0.subject.caseInsensitiveCompare(normalizedSubject) == .orderedSame }
            .sorted { lhs, rhs in
                let lhsScore = documentScore(lhs, keywords: keywords)
                let rhsScore = documentScore(rhs, keywords: keywords)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                if lhs.importedAt != rhs.importedAt {
                    return lhs.importedAt > rhs.importedAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    func studyModeSubjects() -> [String] {
        let taskSubjects = tasks.map(\.subject)
        let gradeSubjects = grades.map(\.subject)
        let contextSubjects = contexts.map(\.subject)
        let documentSubjects = obsidianDocuments.map(\.subject)
        let quizSubjects = Array(quizQuestionsBySubject.keys)
        let discoveredSubjects = taskSubjects + gradeSubjects + contextSubjects + documentSubjects + quizSubjects + Array(subjectConfidences.keys)

        return Array(
            Set(
                discoveredSubjects.map(canonicalSubjectName).filter { !$0.isEmpty }
            )
        )
        .sorted { lhs, rhs in
            let lhsConfidence = subjectConfidencePercent(for: lhs)
            let rhsConfidence = subjectConfidencePercent(for: rhs)
            if lhsConfidence == rhsConfidence {
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            return lhsConfidence < rhsConfidence
        }
    }

    func subjectConfidenceValue(for subject: String) -> Int {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return 3 }

        if let storedValue = subjectConfidences[canonicalSubject] {
            return confidenceStars(fromPercent: storedValue)
        }

        return derivedConfidence(for: canonicalSubject)
    }

    func subjectConfidencePercent(for subject: String) -> Int {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return 60 }

        if let storedValue = subjectConfidences[canonicalSubject] {
            return normalizedConfidencePercent(storedValue)
        }

        return derivedConfidence(for: canonicalSubject) * 20
    }

    func recordConfidence(subject: String, value: Double, date: Date = .now) {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return }

        let reading = ConfidenceReading(date: date, value: normalizedConfidenceValue(value))
        let capped = cappedConfidenceReadings((confidenceHistory[canonicalSubject] ?? []) + [reading])
        confidenceHistory[canonicalSubject] = capped
        save()
    }

    func lastConfidenceReadings(for subject: String, limit: Int = 7) -> [ConfidenceReading] {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return [] }

        let readings = confidenceHistory[canonicalSubject] ?? []
        return Array(readings.sorted { $0.date < $1.date }.suffix(max(0, limit)))
    }

    func quizCards(for subject: String) -> [QuizQuestion] {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return [] }
        return quizQuestionsBySubject[canonicalSubject] ?? []
    }

    func dueQuizCards(for subject: String, now: Date = .now) -> [QuizQuestion] {
        quizCards(for: subject)
            .filter { SpacedRepetitionEngine.isDue($0, now: now) }
            .sorted { lhs, rhs in
                if lhs.nextDue != rhs.nextDue {
                    return lhs.nextDue < rhs.nextDue
                }
                return lhs.question.localizedCaseInsensitiveCompare(rhs.question) == .orderedAscending
            }
    }

    func dueQuizCardCount(for subject: String, now: Date = .now) -> Int {
        dueQuizCards(for: subject, now: now).count
    }

    func latestGrade(for subject: String) -> GradeEntry? {
        recentGrades(for: subject, limit: 1).first
    }

    func recentGrades(for subject: String, limit: Int = 3) -> [GradeEntry] {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return [] }

        return Array(
            grades
                .filter { canonicalSubjectName($0.subject).caseInsensitiveCompare(canonicalSubject) == .orderedSame }
                .sorted { lhs, rhs in
                    if lhs.date != rhs.date {
                        return lhs.date > rhs.date
                    }
                    return lhs.assessmentTitle.localizedCaseInsensitiveCompare(rhs.assessmentTitle) == .orderedAscending
                }
                .prefix(max(0, limit))
        )
    }

    func updateGrades(_ incomingGrades: [GradeEntry]) {
        guard !incomingGrades.isEmpty else { return }

        var deduplicatedByID: [String: GradeEntry] = Dictionary(
            uniqueKeysWithValues: grades.map {
                let canonical = canonicalGradeEntry($0)
                return (canonical.id, canonical)
            }
        )

        for grade in incomingGrades {
            let canonical = canonicalGradeEntry(grade)
            deduplicatedByID[canonical.id] = canonical
        }

        let updatedGrades = deduplicatedByID.values.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            if lhs.subject.caseInsensitiveCompare(rhs.subject) != .orderedSame {
                return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
            }
            return lhs.assessmentTitle.localizedCaseInsensitiveCompare(rhs.assessmentTitle) == .orderedAscending
        }

        guard updatedGrades != grades else { return }
        grades = updatedGrades
        save()
    }

    func nextQuizReviewDays(for subject: String, now: Date = .now) -> Int? {
        let upcoming = quizCards(for: subject)
            .filter { !SpacedRepetitionEngine.isDue($0, now: now) }
            .min { $0.nextDue < $1.nextDue }

        guard let upcoming else { return nil }
        return SpacedRepetitionEngine.daysUntilDue(upcoming, now: now)
    }

    func replaceQuizCards(for subject: String, with cards: [QuizQuestion]) {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return }
        quizQuestionsBySubject[canonicalSubject] = cards
        save()
    }

    @discardableResult
    func reviewQuizCard(for subject: String, question: QuizQuestion, quality: Int, now: Date = .now) -> QuizQuestion {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return question }

        let updatedQuestion = SpacedRepetitionEngine.review(question, quality: quality, now: now)
        var cards = quizQuestionsBySubject[canonicalSubject] ?? []

        if let index = cards.firstIndex(where: { $0.id == question.id }) {
            cards[index] = updatedQuestion
        } else {
            cards.append(updatedQuestion)
        }

        quizQuestionsBySubject[canonicalSubject] = cards
        save()
        return updatedQuestion
    }

    func transcriptStudyContexts(for subject: String, searchText: String = "", limit: Int = 6) -> [ContextItem] {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return [] }

        let normalizedSearch = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let contexts = groundedStudyContexts(for: nil, subject: canonicalSubject)
            .filter { $0.kind.caseInsensitiveCompare("Obsidian") != .orderedSame }
            .filter { context in
                guard !normalizedSearch.isEmpty else { return true }
                let haystack = "\(context.title) \(context.summary) \(context.detail)".lowercased()
                return haystack.contains(normalizedSearch)
            }

        return Array(contexts.prefix(limit))
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
                tasks[index] = preservingManualRank(from: tasks[index], to: task)
            } else {
                tasks.insert(task, at: 0)
                importedTasks += 1
                if !automatic {
                    queueCalibrationIfNeeded(for: task)
                }
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

    func applyDiscoveredDeadlines(_ deadlines: [DiscoveredDeadline], now: Date = .now) {
        guard !deadlines.isEmpty else { return }

        var insertedCount = 0
        var updatedCount = 0

        for deadline in deadlines {
            let discoveredTask = calibratedTask(deadline.makeTask())

            if let existingIndex = tasks.firstIndex(where: {
                StableID.normalizedTaskIdentityTitle(from: $0.title) ==
                    StableID.normalizedTaskIdentityTitle(from: deadline.title)
            }) {
                let existingTask = tasks[existingIndex]
                var updatedTask = existingTask
                updatedTask.subject = deadline.subject
                updatedTask.importance = max(existingTask.importance, deadline.importance)
                updatedTask.dueDate = deadline.dueDate ?? existingTask.dueDate
                updatedTask.estimateMinutes = max(existingTask.estimateMinutes, deadline.estimateMinutes)
                updatedTask.energy = deadline.energy == .high ? .high : existingTask.energy
                if existingTask.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updatedTask.notes = deadline.notes
                } else if !existingTask.notes.contains(deadline.query) {
                    updatedTask.notes = "\(existingTask.notes)\n\n\(deadline.notes)"
                }
                updatedTask.isAutoDiscovered = existingTask.isAutoDiscovered || discoveredTask.isAutoDiscovered
                tasks[existingIndex] = preservingManualRank(
                    from: existingTask,
                    to: calibratedTask(updatedTask)
                )
                updatedCount += 1
            } else {
                tasks.insert(discoveredTask, at: 0)
                insertedCount += 1
            }

            let matched = deadline.matchedMemoryTitles.isEmpty
                ? "no direct codex-mem hits"
                : deadline.matchedMemoryTitles.joined(separator: " | ")
            print("[PlannerStore] startup deadline \(deadline.title) <- \(matched)")
        }

        let message = "Codex memory deadline discovery inserted \(insertedCount) task(s) and updated \(updatedCount) existing task(s)."
        lastImportMessages = [message]
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

    private func clearPromptError() {
        aiErrorText = nil
        promptErrorState = nil
        lastFailedAIAction = nil
    }

    private func handlePromptFailure(result: CodexRunResult, action: FailedAIAction) {
        let fallback = "Timed AI failed before returning a response."
        let message = CodexBridge.handleFailureMessage(result) ?? fallback
        aiErrorText = message
        promptErrorState = PromptErrorState(message: message)
        lastFailedAIAction = action
    }

    private func presentToast(
        title: String,
        message: String,
        systemImage: String,
        tone: ToastTone,
        autoDismissAfter seconds: Double = 5
    ) {
        toastDismissTask?.cancel()
        toastState = ToastState(
            title: title,
            message: message,
            systemImage: systemImage,
            tone: tone
        )

        toastDismissTask = Task { [weak self] in
            let nanoseconds = UInt64(max(seconds, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.toastState = nil
            }
        }
    }

    private func presentSeqtaSyncFailure(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settingsIssue = SettingsIssueState(message: trimmed)
        lastImportMessages = [trimmed]
        presentToast(
            title: "Seqta sync failed",
            message: trimmed,
            systemImage: "gear.badge.xmark",
            tone: .error
        )
    }

    private func buildConfidenceCalibrationPrompt(
        for draft: ConfidenceCalibrationDraft,
        subject: String,
        now: Date
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        let activeTasks = tasks
            .filter { !$0.isCompleted && $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
            .prefix(4)
            .map { task in
                let dueDate = task.dueDate.map { dateFormatter.string(from: $0) } ?? "No due date"
                return "- \(task.title) | Due: \(dueDate) | Notes: \(task.notes.isEmpty ? "None" : task.notes)"
            }
            .joined(separator: "\n")

        return """
        You are calibrating an initial subject confidence score for a Year 11 student using self-assessment answers.
        Return JSON only. No markdown. No explanation.

        Required shape:
        {"confidence": 0-100 integer, "hints": ["hint 1", "hint 2", "hint 3"]}

        Rules:
        - Confidence must be slightly pessimistic, realistic, and integer 0-100.
        - Hints must be specific to the subject and the student's weak points.
        - Return exactly 3 hints.
        - Each hint should be one sentence and actionable.

        Current date:
        \(dateFormatter.string(from: now))

        Subject:
        \(subject)

        Active tasks for this subject:
        \(activeTasks.isEmpty ? "- None loaded" : activeTasks)

        Self-assessment answers:
        - Confidence rating (1-5): \(Int(draft.confidence.rounded()))
        - Most recent thing covered: \(draft.recentTopic.trimmingCharacters(in: .whitespacesAndNewlines))
        - Least sure about: \(draft.leastSureAbout.trimmingCharacters(in: .whitespacesAndNewlines))
        - Assessment timing: \(draft.assessmentDate.trimmingCharacters(in: .whitespacesAndNewlines))
        - Available resources: \(draft.resources.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private func applyImport(_ batch: ImportBatch) {
        if let context = batch.context {
            contexts.removeAll { $0.id == context.id }
            contexts.insert(context, at: 0)
            contexts.sort { $0.createdAt > $1.createdAt }
            selectedContextID = context.id
        }

        var createdCount = 0
        var updatedCount = 0
        var skippedCount = 0

        for draft in batch.taskDrafts {
            let task = calibratedTask(draft.makeTask())

            if let index = matchingImportedTaskIndex(for: task) {
                let merged = task.source == .seqta
                    ? mergeSeqtaTask(existing: tasks[index], incoming: task)
                    : mergeDuplicateTasks(existing: tasks[index], incoming: task)
                if merged != tasks[index] {
                    tasks[index] = merged
                    updatedCount += 1
                } else {
                    skippedCount += 1
                }
                continue
            }

            tasks.insert(task, at: 0)
            createdCount += 1
            queueCalibrationIfNeeded(for: task)
        }

        if !batch.taskDrafts.isEmpty, batch.taskDrafts.allSatisfy({ $0.source == .seqta }) {
            print("[SeqtaImport] tasks found=\(batch.taskDrafts.count) tasks created=\(createdCount) tasks updated=\(updatedCount) tasks skipped=\(skippedCount)")
        }

        lastImportMessages = batch.messages
        if !batch.messages.isEmpty {
            appendPlannerMessage(PromptMessage(role: .assistant, text: batch.messages.joined(separator: "\n")))
        }
        rebuildPlan()
    }

    private func decodeConfidenceCalibrationResponse(from response: String) -> ConfidenceCalibrationResponse? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String

        if
            let start = trimmed.firstIndex(of: "{"),
            let end = trimmed.lastIndex(of: "}")
        {
            candidate = String(trimmed[start...end])
        } else {
            candidate = trimmed
        }

        guard let data = candidate.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ConfidenceCalibrationResponse.self, from: data)
    }

    private func calibrationContextDetail(
        subject: String,
        percentConfidence: Int,
        hints: [String],
        draft: ConfidenceCalibrationDraft
    ) -> String {
        let hintsText = hints.isEmpty
            ? "No hints returned."
            : hints.map { "- \($0)" }.joined(separator: "\n")

        return """
        Subject: \(subject)
        Calibrated confidence: \(percentConfidence)%

        Most recent thing covered:
        \(draft.recentTopic.trimmingCharacters(in: .whitespacesAndNewlines))

        Least sure about:
        \(draft.leastSureAbout.trimmingCharacters(in: .whitespacesAndNewlines))

        Assessment timing:
        \(draft.assessmentDate.trimmingCharacters(in: .whitespacesAndNewlines))

        Available resources:
        \(draft.resources.trimmingCharacters(in: .whitespacesAndNewlines))

        Study hints:
        \(hintsText)
        """
    }

    private func mergedCalibrationNotes(existingNotes: String, subject: String, hints: [String]) -> String {
        guard !hints.isEmpty else { return existingNotes }

        let hintSection = """
        Study hints for \(subject):
        \(hints.map { "- \($0)" }.joined(separator: "\n"))
        """
        let trimmedExisting = existingNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedExisting.contains(hintSection) else { return trimmedExisting }
        guard !trimmedExisting.isEmpty else { return hintSection }
        return "\(trimmedExisting)\n\n\(hintSection)"
    }

    private func queueCalibrationIfNeeded(for task: TaskItem) {
        let subject = canonicalSubjectName(task.subject)
        guard !subject.isEmpty else { return }
        guard subjectConfidences[subject] == nil else { return }
        guard pendingCalibrationSubject != subject else { return }
        guard !pendingCalibrationQueue.contains(subject) else { return }
        pendingCalibrationQueue.append(subject)
        if pendingCalibrationSubject == nil {
            pendingCalibrationSubject = pendingCalibrationQueue.removeFirst()
        }
    }

    private func advancePendingCalibrationQueue(resolving resolvedSubject: String? = nil) {
        if
            let resolvedSubject,
            pendingCalibrationSubject?.caseInsensitiveCompare(resolvedSubject) != .orderedSame
        {
            pendingCalibrationQueue.removeAll { $0.caseInsensitiveCompare(resolvedSubject) == .orderedSame }
            return
        }

        pendingCalibrationSubject = pendingCalibrationQueue.isEmpty ? nil : pendingCalibrationQueue.removeFirst()
    }

    private func earliestDueDate(for subject: String) -> Date? {
        tasks
            .filter { !$0.isCompleted && $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
            .compactMap(\.dueDate)
            .min()
    }

    private func continueQuiz(with answer: String, appendStudentMessage: Bool = true) async {
        guard let activeQuizSubject else { return }
        let matchingContexts = groundedStudyContexts(for: selectedTask, subject: activeQuizSubject)
        if appendStudentMessage {
            appendStudyMessage(PromptMessage(role: .student, text: answer, isQuiz: true), subject: activeQuizSubject)
        }
        clearPromptError()
        isRunningPrompt = true

        let result = await CodexBridge().run(
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
        guard let response = CodexBridge.response(from: result) else {
            handlePromptFailure(
                result: result,
                action: .quizReply(answer)
            )
            save()
            return
        }

        appendStudyMessage(PromptMessage(role: .tutor, text: response, isQuiz: true), subject: activeQuizSubject)
        save()
    }

    private func applyObsidianSyncResult(_ result: ObsidianSyncResult, announce: Bool) {
        isSyncingObsidianVault = false
        obsidianDocuments = result.documents
        contexts.removeAll { $0.kind == "Obsidian" }
        contexts.insert(contentsOf: result.contexts, at: 0)
        contexts.sort { $0.createdAt > $1.createdAt }
        lastImportMessages = [result.message]
        if announce {
            appendPlannerMessage(PromptMessage(role: .assistant, text: result.message))
        }
        if selectedContext == nil {
            selectedContextID = contexts.first?.id
        }
        rebuildPlan()
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

    private func buildDayPlanPrompt(now: Date, topTasks: [RankedTask]) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short

        let todayBlocks = schedule
            .filter { Calendar.current.isDateInToday($0.start) }
            .sorted { $0.start < $1.start }

        let dueSoonTasks = tasks
            .filter { !$0.isCompleted }
            .filter { task in
                guard let dueDate = task.dueDate else { return false }
                return Calendar.current.isDateInToday(dueDate) || Calendar.current.isDateInTomorrow(dueDate)
            }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate < rhsDate
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.title < rhs.title
                }
            }

        let taskLines = topTasks.map { ranked in
            let dueDate = ranked.task.dueDate.map { formatter.string(from: $0) } ?? "No due date"
            return "- \(ranked.task.title) | Subject: \(ranked.task.subject) | Band: \(ranked.band) | Due: \(dueDate) | Estimate: \(ranked.task.estimateMinutes)m | Suggested action: \(ranked.suggestedNextAction)"
        }.joined(separator: "\n")

        let blockLines = todayBlocks.map { block in
            "- \(block.timeRange) | \(block.title) | \(block.isApproved ? "Approved" : "Pending")"
        }.joined(separator: "\n")

        let deadlineLines = dueSoonTasks.map { task in
            let dueDate = task.dueDate.map { formatter.string(from: $0) } ?? "No due date"
            return "- \(task.title) | Subject: \(task.subject) | Due: \(dueDate)"
        }.joined(separator: "\n")

        let totalHours = todayBlocks.reduce(0.0) { partialResult, block in
            partialResult + block.end.timeIntervalSince(block.start) / 3600
        }

        return """
        System instruction:
        You are Timed, a study planning assistant for a school student. Write exactly 2 sentences in plain English. Mention at least one task by its exact title. Sentence 1 should say what to tackle first and why. Sentence 2 should explain how to use today's scheduled hours and mention any task due today or tomorrow. No bullet points, no headings, no preamble.

        Current date and time:
        \(formatter.string(from: now))

        Top priorities:
        \(taskLines)

        Today's schedule blocks:
        \(blockLines.isEmpty ? "- No blocks scheduled today." : blockLines)

        Total scheduled hours today:
        \(totalHours.formatted(.number.precision(.fractionLength(1))))

        Tasks due today or tomorrow:
        \(deadlineLines.isEmpty ? "- None." : deadlineLines)
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

    private func documentScore(_ document: ContextDocument, keywords: [String]) -> Int {
        let titleText = SubjectCatalog.normalizedSubjectText(document.title)
        let pathText = SubjectCatalog.normalizedSubjectText(document.path)
        let contentText = SubjectCatalog.normalizedSubjectText(document.content)

        var total = 0
        for keyword in keywords {
            total += occurrenceCount(of: keyword, in: titleText) * 8
            total += occurrenceCount(of: keyword, in: pathText) * 5
            total += occurrenceCount(of: keyword, in: contentText)
        }

        total += max(0, 72 - Int(Date.now.timeIntervalSince(document.importedAt) / 3600))
        return total
    }

    private func occurrenceCount(of pattern: String, in text: String) -> Int {
        guard !pattern.isEmpty, !text.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex

        while let range = text.range(of: pattern, options: [], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }

        return count
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
        guard let resolvedSubject = canonicalSubject(subject ?? task?.subject ?? ""), !resolvedSubject.isEmpty else { return [] }

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

    func applySubjectConfidences(_ values: [String: Int]) {
        guard !values.isEmpty else { return }
        for (subject, confidence) in values {
            let canonicalSubject = canonicalSubjectName(subject)
            guard !canonicalSubject.isEmpty else { continue }

            let normalizedPercent = normalizedConfidencePercent(confidence)
            subjectConfidences[canonicalSubject] = normalizedPercent
            let calibratedConfidence = confidenceStars(fromPercent: normalizedPercent)

            for index in tasks.indices where tasks[index].subject.caseInsensitiveCompare(canonicalSubject) == .orderedSame {
                tasks[index].confidence = calibratedConfidence
            }
        }
    }

    func recordQuizSession(subject: String, summary: QuizSessionSummary) {
        let canonicalSubject = canonicalSubjectName(subject)
        guard !canonicalSubject.isEmpty else { return }
        let normalizedPercent = normalizedConfidencePercent(summary.updatedConfidencePercent)
        subjectConfidences[canonicalSubject] = normalizedPercent

        let calibratedConfidence = confidenceStars(fromPercent: normalizedPercent)
        for index in tasks.indices where tasks[index].subject.caseInsensitiveCompare(canonicalSubject) == .orderedSame {
            tasks[index].confidence = calibratedConfidence
        }

        let deltaPrefix = summary.confidenceDeltaPercent >= 0 ? "+" : ""
        let averageQualityText = String(format: "%.1f", summary.averageQuality)
        appendStudyMessage(
            PromptMessage(
                role: .assistant,
                text: "Study session finished for \(canonicalSubject): \(summary.correctCount)/\(summary.attemptedCount) correct. Average recall \(averageQualityText)/5. Confidence delta \(deltaPrefix)\(summary.confidenceDeltaPercent)%."
            ),
            subject: canonicalSubject
        )
        rebuildPlan()
    }

    private func upsertTaskHints(_ hints: [TaskHint]) {
        guard !hints.isEmpty else { return }

        for hint in hints {
            if let index = tasks.firstIndex(where: {
                $0.title.caseInsensitiveCompare(hint.title) == .orderedSame ||
                ($0.subject.caseInsensitiveCompare(hint.subject) == .orderedSame && $0.title.lowercased().contains(hint.subject.lowercased()))
            }) {
                let existingTask = tasks[index]
                var updatedTask = existingTask
                updatedTask.dueDate = hint.dueDate ?? existingTask.dueDate
                if updatedTask.notes.isEmpty {
                    updatedTask.notes = hint.notes
                }
                if updatedTask.confidence == 3 {
                    updatedTask.confidence = inferredConfidence(for: updatedTask)
                }
                tasks[index] = preservingManualRank(from: existingTask, to: updatedTask)
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
            queueCalibrationIfNeeded(for: task)
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
            queueCalibrationIfNeeded(for: calibrated)
        }

        if insertedCount > 0 {
            appendPlannerMessage(PromptMessage(role: .assistant, text: "Imported \(insertedCount) relevant TickTick task(s) from your recent CSV export."))
        }
    }

    private func startSeqtaBackgroundSync() {
        let bootstrapResult = SeqtaBackgroundSync.ensureLaunchAgentInstalled()
        switch bootstrapResult {
        case .success:
            settingsIssue = nil
        case let .failure(message):
            presentSeqtaSyncFailure(message)
        }
        seqtaWatcher = SeqtaFileWatcher { [weak self] in
            DispatchQueue.main.async {
                self?.refreshSeqtaSnapshotIfAvailable()
            }
        }
        refreshSeqtaSnapshotIfAvailable()
    }

    private func refreshSeqtaSnapshotIfAvailable(now: Date = .now) {
        let seqtaTasks = SeqtaBackgroundSync.loadTasks(now: now)
        let seqtaGrades = SeqtaBackgroundSync.loadGrades(now: now)
        guard !seqtaTasks.isEmpty || !seqtaGrades.isEmpty else { return }

        let totalFound = seqtaTasks.count
        var insertedCount = 0
        var updatedCount = 0
        var skippedCount = 0

        for task in seqtaTasks.map(calibratedTask) {
            if let index = matchingImportedTaskIndex(for: task) {
                let merged = mergeSeqtaTask(existing: tasks[index], incoming: task)
                if merged != tasks[index] {
                    tasks[index] = merged
                    updatedCount += 1
                } else {
                    skippedCount += 1
                }
                continue
            }

            tasks.insert(task, at: 0)
            insertedCount += 1
            queueCalibrationIfNeeded(for: task)
        }

        let gradeCountBeforeUpdate = grades.count
        updateGrades(seqtaGrades)
        let insertedGradeCount = max(0, grades.count - gradeCountBeforeUpdate)

        print("[SeqtaBackgroundSync] tasks found=\(totalFound) tasks created=\(insertedCount) tasks updated=\(updatedCount) tasks skipped=\(skippedCount) grades imported=\(seqtaGrades.count)")

        guard insertedCount > 0 || updatedCount > 0 || insertedGradeCount > 0 else { return }
        let message = "Seqta background sync updated \(insertedCount) new task(s), \(updatedCount) existing task(s), and \(insertedGradeCount) grade entr\(insertedGradeCount == 1 ? "y" : "ies")."
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

    private static func decompositionPrompt(for task: TaskItem) -> String {
        "Break this task into 3-5 concrete subtasks. Task: \(task.title). Subject: \(task.subject). Return as a numbered list, one per line, no preamble."
    }

    static func parseSubtaskLines(from response: String) -> [String] {
        response
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let rawLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawLine.isEmpty else { return nil }
                guard rawLine.range(of: #"^\s*\d+[\.\)]\s*"#, options: .regularExpression) != nil else {
                    return nil
                }
                let stripped = rawLine.replacingOccurrences(
                    of: #"^\s*\d+[\.\)]\s*"#,
                    with: "",
                    options: .regularExpression
                )
                let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
    }

    private func calibratedTask(_ task: TaskItem) -> TaskItem {
        var mutable = task
        mutable.subject = canonicalSubjectName(task.subject)
        mutable.confidence = inferredConfidence(for: mutable)
        return mutable
    }

    private func rankedTasksSnapshot(now: Date) -> [RankedTask] {
        let subjectImportance = rankingSubjectImportance()
        let confidenceOverrides = rankingConfidenceOverrides()

        return PlanningEngine.rank(
            tasks: tasks,
            contexts: contexts,
            now: now,
            promptBoostSubject: promptBoostSubject,
            subjectImportance: subjectImportance,
            confidenceOverride: confidenceOverrides
        ).map { ranked in
            RankedTask(
                task: ranked.task,
                score: ranked.score,
                band: ranked.band,
                reasons: ranked.reasons,
                suggestedNextAction: suggestedNextActionsByTaskID[ranked.task.id] ?? ranked.suggestedNextAction
            )
        }
    }

    private func shouldShowWeeklyReview(now: Date) -> Bool {
        let reviewWeekStart = startOfReviewWeek(containing: now)
        guard let lastWeeklyReview else { return true }
        return lastWeeklyReview < reviewWeekStart
    }

    private func weeklyReviewWindowStart(now: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
    }

    private func startOfReviewWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysSinceSunday = max(0, weekday - 1)
        // Treat the review as due from the most recent Sunday onward, so a missed Sunday launch still surfaces it on Monday.
        return calendar.date(byAdding: .day, value: -daysSinceSunday, to: startOfDay) ?? startOfDay
    }

    private func weeklyConfidenceDeltas(now: Date, windowStart: Date) -> [WeeklyReviewConfidenceDelta] {
        confidenceHistory.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .compactMap { subject in
                let readings = (confidenceHistory[subject] ?? [])
                    .sorted { $0.date < $1.date }
                guard let latest = readings.last(where: { $0.date <= now }) else { return nil }
                // If there isn't a reading before the weekly window starts, fall back to the oldest in-window reading.
                let baseline = readings.last(where: { $0.date <= windowStart }) ?? readings.first
                guard let baseline else { return nil }
                return WeeklyReviewConfidenceDelta(
                    subject: subject,
                    startingValue: baseline.value,
                    latestValue: latest.value
                )
            }
    }

    private func rankingSubjectImportance() -> [String: Double] {
        // STORY-003 writes subject-level urgency into auto-discovered codex-mem tasks.
        // Rebuild the map from those tasks so ranking stays deterministic across reloads.
        var values: [String: Double] = [:]

        for task in tasks where task.source == .codexMem || task.isAutoDiscovered {
            let subject = task.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subject.isEmpty else { continue }
            values[subject] = max(values[subject] ?? 1.0, subjectImportanceMultiplier(for: task.importance))
        }

        return values
    }

    private func rankingConfidenceOverrides() -> [String: Double] {
        var values: [String: Double] = [:]

        for (subject, confidence) in subjectConfidences {
            let canonicalSubject = canonicalSubjectName(subject)
            guard !canonicalSubject.isEmpty else { continue }
            values[canonicalSubject] = Double(confidenceStars(fromPercent: confidence))
        }

        for task in tasks where task.source == .codexMem || task.isAutoDiscovered {
            let subject = canonicalSubjectName(task.subject)
            guard !subject.isEmpty else { continue }
            values[subject] = min(values[subject] ?? 5.0, Double(task.confidence))
        }

        return values
    }

    private func subjectImportanceMultiplier(for importance: Int) -> Double {
        max(1.0, Double(importance) / 5.0)
    }

    private func inferredConfidence(for task: TaskItem) -> Int {
        let canonicalSubject = canonicalSubjectName(task.subject)
        if let storedValue = subjectConfidences[canonicalSubject] {
            return confidenceStars(fromPercent: storedValue)
        }
        guard task.confidence == 3 else { return task.confidence }
        return CodexMemoryInsights.inferredConfidence(
            subject: canonicalSubject,
            title: task.title,
            fallback: task.confidence
        )
    }

    private func syncSubjectConfidenceState() {
        var nextValues: [String: Int] = [:]
        for (subject, confidence) in subjectConfidences {
            let canonicalSubject = canonicalSubjectName(subject)
            guard !canonicalSubject.isEmpty else { continue }
            nextValues[canonicalSubject] = normalizedConfidencePercent(confidence)
        }
        subjectConfidences = nextValues
    }

    private func syncConfidenceHistoryState() {
        var nextValues: [String: [ConfidenceReading]] = [:]

        for (subject, readings) in confidenceHistory {
            let canonicalSubject = canonicalSubjectName(subject)
            guard !canonicalSubject.isEmpty else { continue }

            let normalizedReadings = readings.map { reading in
                ConfidenceReading(date: reading.date, value: normalizedConfidenceValue(reading.value))
            }
            nextValues[canonicalSubject, default: []].append(contentsOf: normalizedReadings)
        }

        confidenceHistory = nextValues.mapValues { readings in
            cappedConfidenceReadings(readings)
        }
    }

    private func normalizeQuizQuestionState() {
        var normalizedDecks: [String: [QuizQuestion]] = [:]

        for (subject, questions) in quizQuestionsBySubject {
            let canonicalSubject = canonicalSubjectName(subject)
            guard !canonicalSubject.isEmpty else { continue }

            normalizedDecks[canonicalSubject] = questions.map { question in
                question.updated(
                    easeFactor: max(1.3, question.easeFactor),
                    interval: max(1, question.interval),
                    nextDue: question.nextDue
                )
            }
        }

        quizQuestionsBySubject = normalizedDecks
    }

    private func derivedConfidence(for subject: String) -> Int {
        let matchingTasks = tasks.filter {
            !$0.isCompleted && $0.subject.caseInsensitiveCompare(subject) == .orderedSame
        }

        if let lowestConfidence = matchingTasks.map(\.confidence).min() {
            return clampedConfidence(lowestConfidence)
        }

        let archivedTasks = tasks.filter { $0.subject.caseInsensitiveCompare(subject) == .orderedSame }
        if let fallbackConfidence = archivedTasks.map(\.confidence).min() {
            return clampedConfidence(fallbackConfidence)
        }

        return 3
    }

    private func clampedConfidence(_ value: Int) -> Int {
        max(1, min(5, value))
    }

    private func normalizedConfidencePercent(_ value: Int) -> Int {
        if value <= 5 {
            return max(0, min(100, value * 20))
        }
        return max(0, min(100, value))
    }

    private func normalizedConfidenceValue(_ value: Double) -> Double {
        if value > 1 {
            return max(0, min(1, value / 100.0))
        }
        return max(0, min(1, value))
    }

    private func cappedConfidenceReadings(_ readings: [ConfidenceReading], limit: Int = 30) -> [ConfidenceReading] {
        Array(
            readings
                .sorted { $0.date < $1.date }
                .suffix(max(0, limit))
        )
    }

    private func confidenceStars(fromPercent percent: Int) -> Int {
        let normalizedPercent = normalizedConfidencePercent(percent)
        guard normalizedPercent > 0 else { return 1 }
        return max(1, min(5, Int(ceil(Double(normalizedPercent) / 20.0))))
    }

    private func canonicalSubject(_ subject: String?) -> String? {
        let canonical = canonicalSubjectName(subject ?? "")
        return canonical.isEmpty ? nil : canonical
    }

    private func canonicalSubjectName(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return SubjectCatalog.matchingSubject(in: trimmed) ?? trimmed
    }

    private func appendPlannerMessage(_ message: PromptMessage, subject: String? = nil) {
        chat.append(message)
        CodexMemorySync.recordMessage(message, channel: .planner, subject: subject)
    }

    private func pinPlannerMessage(_ message: PromptMessage, subject: String? = nil) {
        for index in chat.indices where chat[index].isPinned {
            chat[index].isPinned = false
        }
        appendPlannerMessage(message, subject: subject)
    }

    private func appendStudyMessage(_ message: PromptMessage, subject: String? = nil) {
        studyChat.append(message)
        CodexMemorySync.recordMessage(message, channel: .study, subject: subject)
    }

    private func dayPlanSummary(from response: String) -> String {
        let trimmed = response
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No day plan was generated." }

        let sentences = trimmed
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sentences.isEmpty else { return trimmed }
        return sentences
            .prefix(2)
            .map { sentence in
                if let last = sentence.last, ".!?".contains(last) {
                    return sentence
                }
                return sentence + "."
            }
            .joined(separator: " ")
    }

    private func mergeSeqtaTask(existing: TaskItem, incoming: TaskItem) -> TaskItem {
        var merged = existing
        merged.title = incoming.title
        merged.list = incoming.list
        merged.source = incoming.source
        merged.subject = incoming.subject
        merged.estimateMinutes = incoming.estimateMinutes
        merged.parentId = existing.parentId ?? incoming.parentId
        if !existing.isCompleted {
            merged.confidence = incoming.confidence
        }
        merged.importance = incoming.importance
        merged.dueDate = incoming.dueDate
        merged.notes = incoming.notes
        merged.energy = incoming.energy
        merged.pomodoroCount = max(existing.pomodoroCount, incoming.pomodoroCount)
        return preservingManualRank(from: existing, to: merged)
    }

    private func canonicalGradeEntry(_ grade: GradeEntry) -> GradeEntry {
        GradeEntry(
            subject: canonicalSubjectName(grade.subject),
            assessmentTitle: grade.assessmentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            mark: max(0, grade.mark),
            outOf: max(1, grade.outOf),
            date: grade.date
        )
    }

    private func matchingImportedTaskIndex(for incoming: TaskItem) -> Int? {
        if let exactIndex = tasks.firstIndex(where: { $0.id == incoming.id }) {
            return exactIndex
        }

        let incomingTitle = StableID.normalizedTaskIdentityTitle(from: incoming.title)
        let incomingSubject = incoming.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingParentID = incoming.parentId

        return tasks.firstIndex { existing in
            guard existing.parentId == incomingParentID else { return false }
            let existingTitle = StableID.normalizedTaskIdentityTitle(from: existing.title)
            let existingSubject = existing.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let sameSubject: Bool
            if existingSubject.isEmpty || incomingSubject.isEmpty {
                sameSubject = true
            } else {
                sameSubject = existingSubject.caseInsensitiveCompare(incomingSubject) == .orderedSame
            }

            guard sameSubject else { return false }
            return existingTitle == incomingTitle ||
                existingTitle.contains(incomingTitle) ||
                incomingTitle.contains(existingTitle)
        }
    }

    private static var isRunningUnderTests: Bool {
        let processInfo = ProcessInfo.processInfo

        if processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }

        if processInfo.processName.contains("swiftpm-testing-helper") {
            return true
        }

        return processInfo.arguments.contains { argument in
            argument.contains(".xctest") || argument.contains("swiftpm-testing-helper")
        }
    }

    private func migrateTaskIdentityIfNeeded() {
        guard !tasks.isEmpty else { return }

        var migratedTasks: [TaskItem] = []
        var selectedTaskReplacement = selectedTaskID
        var taskIDMap: [String: String] = [:]

        for task in tasks where task.parentId == nil {
            taskIDMap[task.id] = StableID.makeTaskID(source: task.source, title: task.title)
        }

        for task in tasks {
            let canonicalParentID = task.parentId.flatMap { taskIDMap[$0] ?? $0 }
            let canonicalID: String
            if let canonicalParentID {
                canonicalID = StableID.makeSubtaskID(parentID: canonicalParentID, title: task.title)
            } else {
                canonicalID = taskIDMap[task.id] ?? StableID.makeTaskID(source: task.source, title: task.title)
            }
            taskIDMap[task.id] = canonicalID

            var canonicalTask = task
            canonicalTask = withTaskIdentity(
                task: canonicalTask,
                id: canonicalID,
                parentId: canonicalParentID
            )

            if let existingIndex = migratedTasks.firstIndex(where: { $0.id == canonicalID }) {
                migratedTasks[existingIndex] = mergeDuplicateTasks(existing: migratedTasks[existingIndex], incoming: canonicalTask)
            } else {
                migratedTasks.append(canonicalTask)
            }

            if selectedTaskID == task.id {
                selectedTaskReplacement = canonicalID
            }
        }

        let migratedSchedule = schedule.compactMap { block -> ScheduleBlock? in
            guard let canonicalTaskID = taskIDMap[block.taskID] else { return block }
            var migratedBlock = block
            migratedBlock.taskID = canonicalTaskID
            return migratedBlock
        }

        tasks = migratedTasks
        schedule = deduplicatedScheduleBlocks(migratedSchedule)
        dismissedScheduleTaskIDs = Set(dismissedScheduleTaskIDs.compactMap { taskIDMap[$0] ?? $0 })
        selectedTaskID = selectedTaskReplacement
    }

    private func mergeDuplicateTasks(existing: TaskItem, incoming: TaskItem) -> TaskItem {
        var merged = existing

        if merged.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.subject = incoming.subject
        }
        if merged.parentId == nil {
            merged.parentId = incoming.parentId
        }
        merged.estimateMinutes = max(existing.estimateMinutes, incoming.estimateMinutes)
        merged.importance = max(existing.importance, incoming.importance)
        merged.dueDate = [existing.dueDate, incoming.dueDate].compactMap { $0 }.min()

        if merged.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.notes = incoming.notes
        } else if incoming.notes != merged.notes && !incoming.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.notes = [merged.notes, incoming.notes].joined(separator: "\n")
        }

        if existing.energy != .high {
            merged.energy = incoming.energy == .high ? .high : existing.energy
        }
        merged.isCompleted = existing.isCompleted || incoming.isCompleted
        merged.completedAt = [existing.completedAt, incoming.completedAt].compactMap { $0 }.max()
        merged.isAutoDiscovered = existing.isAutoDiscovered || incoming.isAutoDiscovered
        merged.pomodoroCount = max(existing.pomodoroCount, incoming.pomodoroCount)

        return preservingManualRank(from: existing, to: merged)
    }

    private func withTaskIdentity(task: TaskItem, id: String, parentId: String?) -> TaskItem {
        TaskItem(
            id: id,
            title: task.title,
            list: task.list,
            source: task.source,
            subject: task.subject,
            estimateMinutes: task.estimateMinutes,
            confidence: task.confidence,
            importance: task.importance,
            dueDate: task.dueDate,
            manualRank: task.manualRank,
            notes: task.notes,
            energy: task.energy,
            parentId: parentId,
            isCompleted: task.isCompleted,
            completedAt: task.completedAt,
            isAutoDiscovered: task.isAutoDiscovered,
            pomodoroCount: task.pomodoroCount
        )
    }

    // A manual drag order only survives while the task keeps the same deadline.
    private func preservingManualRank(from existing: TaskItem, to updated: TaskItem) -> TaskItem {
        var task = updated
        if deadlineChanged(from: existing.dueDate, to: updated.dueDate) {
            task.manualRank = nil
        } else if task.manualRank == nil {
            task.manualRank = existing.manualRank
        }
        return task
    }

    private func deadlineChanged(from existing: Date?, to updated: Date?) -> Bool {
        switch (existing, updated) {
        case (nil, nil):
            return false
        case let (lhs?, rhs?):
            return lhs != rhs
        default:
            return true
        }
    }

    private func deduplicatedScheduleBlocks(_ blocks: [ScheduleBlock]) -> [ScheduleBlock] {
        var seenTaskIDs: Set<String> = []
        var deduplicated: [ScheduleBlock] = []

        for block in blocks.sorted(by: { $0.start < $1.start }) {
            guard !seenTaskIDs.contains(block.taskID) else { continue }
            seenTaskIDs.insert(block.taskID)
            deduplicated.append(block)
        }

        return deduplicated
    }

    private func bootstrapCodexMemoryPackIfNeeded() {
        guard tasks.isEmpty else { return }
        importCodexMemorySchoolPack(automatic: true)
    }

    private func startDeadlineMonitor() {
        deadlineMonitorTask?.cancel()
        deadlineMonitorTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.refreshDeadlineState(now: .now, rescheduleNotifications: false)
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func refreshDeadlineState(now: Date = .now, rescheduleNotifications: Bool) {
        guard !Self.isRunningUnderTests else { return }
        DeadlineAlertService.shared.refresh(
            tasks: tasks,
            now: now,
            shouldRescheduleNotifications: rescheduleNotifications
        )
    }

    private func scheduleCodexMemoryDeadlineDiscovery() {
        guard TimedPreferences.codexMemoryEnabled else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        Task {
            let deadlines = await CodexMemorySchoolPack.discoverDeadlines()
            applyDiscoveredDeadlines(deadlines)
        }
    }

    private func syncChatsFromCodexMemoryIfAvailable() {
        guard TimedPreferences.codexMemoryEnabled else { return }
        guard !Self.isRunningUnderTests else { return }

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let remotePlannerChat = CodexMemorySync.loadConversation(channel: .planner)
            let remoteStudyChat = CodexMemorySync.loadConversation(channel: .study)

            await MainActor.run {
                let mergedPlannerChat = CodexMemorySync.merge(local: self.chat, remote: remotePlannerChat)
                let mergedStudyChat = CodexMemorySync.merge(local: self.studyChat, remote: remoteStudyChat)

                if mergedPlannerChat != self.chat || mergedStudyChat != self.studyChat {
                    self.chat = mergedPlannerChat
                    self.studyChat = mergedStudyChat
                    self.save()
                }
            }
        }
    }
}
