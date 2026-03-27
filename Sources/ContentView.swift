import AppKit
import Observation
import SwiftUI

private struct TaskLibraryEntry: Identifiable {
    let task: TaskItem
    let depth: Int

    var id: String { task.id }
}

struct ContentView: View {
    @State private var store = PlannerStore()
    @State private var focusTimer = FocusTimerModel()
    @FocusState private var focusedPanel: PlannerPanel?
    @AppStorage("timed.showLeft") private var showLeft = true
    @AppStorage("timed.showRight") private var showRight = false
    @AppStorage("timed.centerTab") private var centerTabRawValue = CenterTab.plan.rawValue
    @State private var selectedContextFilter = "All"
    @State private var selectedStudySubject = ""
    @State private var expandedStudySubject = ""
    @State private var isStudyMode = false
    @State private var contextTaskID: String?
    @State private var showAddTaskSheet = false
    @State private var addTaskDraft = AddTaskDraft()
    @State private var addTaskError: String?
    @State private var showCompletedToday = false
    @State private var selectedWeekDeadline: Date?
    @State private var dayPlan = SchoolDayPlan(targetDate: .now, lessons: [], message: "Loading school calendar...")
    @State private var isLoadingDayPlan = false
    @State private var showSearchPanel = false
    @State private var searchQuery = ""
    @State private var showKeyboardShortcutsHelp = false
    @State private var showCommandPalette = false
    @State private var showCalibrationPopover = false
    @State private var commandPaletteText = ""
    @State private var activeFocusBlock: ScheduleBlock?
    @State private var activeFocusTaskID: String?
    @State private var focusNow = Date.now
    @State private var showDebriefSheet = false
    @State private var activeQuizSession: QuizSessionModel?
    @State private var debriefConfidence = 3.0
    @State private var debriefCovered = ""
    @State private var debriefBlockers = ""
    @State private var didHandleInitialVaultSync = false
    @State private var deadlineNow = Date.now
    @State private var searchService = ContextSearchService()
    @State private var selectedTaskIndex = 0
    @State private var localKeyMonitor: Any?
    @State private var selectedSearchDocumentID: String?
    @State private var selectedSearchContextID: String?
    @State private var highlightedPlannerChatMessageID: UUID?
    @State private var highlightedStudyChatMessageID: UUID?
    private let focusTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let deadlineTicker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    @MainActor
    init(store: PlannerStore = PlannerStore(), focusTimer: FocusTimerModel = FocusTimerModel()) {
        _store = State(initialValue: store)
        _focusTimer = State(initialValue: focusTimer)
    }

    var body: some View {
        configuredRootView
    }

    private var layoutConfiguredView: AnyView {
        AnyView(
            rootView
                .frame(minWidth: 1360, minHeight: 900)
                .preferredColorScheme(.dark)
        )
    }

    private var toolbarConfiguredView: AnyView {
        AnyView(
            layoutConfiguredView
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(isStudyMode ? "Back to Planner" : "Study Mode", systemImage: isStudyMode ? "rectangle.3.offgrid" : "book.closed") {
                            toggleStudyMode()
                        }
                    }
                }
        )
    }

    private var sheetConfiguredView: AnyView {
        AnyView(
            toolbarConfiguredView
                .sheet(isPresented: $showAddTaskSheet) {
                    AddTaskSheet(
                        draft: $addTaskDraft,
                        errorMessage: $addTaskError,
                        onSave: { resolvedDraft in
                            if let error = store.addManualTask(resolvedDraft, parseNaturalLanguage: false) {
                                addTaskError = error
                                return
                            }
                            addTaskDraft = AddTaskDraft()
                            addTaskError = nil
                            showAddTaskSheet = false
                        }
                    )
                }
                .sheet(isPresented: $showSearchPanel) {
                    SearchPanelView(
                        store: store,
                        service: searchService,
                        query: $searchQuery,
                        onSelect: handleSearchSelection
                    )
                }
                .sheet(
                    isPresented: Binding(
                        get: { store.pendingImportBatch != nil },
                        set: { isPresented in
                            if !isPresented {
                                store.discardPendingImport()
                            }
                        }
                    )
                ) {
                    ImportReviewSheet(store: store)
                }
                .sheet(isPresented: $showCommandPalette) {
                    CommandPaletteSheet(
                        query: $commandPaletteText,
                        onRun: { query in
                            Task { await runCommandPalette(query) }
                        }
                    )
                }
                .sheet(isPresented: $showDebriefSheet) {
                    StudyDebriefSheet(
                        confidence: $debriefConfidence,
                        covered: $debriefCovered,
                        blockers: $debriefBlockers,
                        onSave: saveDebrief
                    )
                }
                .sheet(
                    isPresented: Binding(
                        get: { store.showWeeklyReview },
                        set: { isPresented in
                            if !isPresented, store.showWeeklyReview {
                                store.dismissWeeklyReview()
                            }
                        }
                    )
                ) {
                    WeeklyReviewView(
                        summary: store.weeklyReviewSummary(),
                        onDismiss: {
                            store.dismissWeeklyReview()
                        }
                    )
                }
        )
    }

    private var configuredRootView: some View {
        AnyView(
            sheetConfiguredView
                .focusedValue(\.timedKeyboardActions, keyboardActions)
                .focusedValue(\.timedRankedTaskSelection, TimedRankedTaskSelection(task: currentKeyboardSelectedTask))
                .popover(isPresented: $showKeyboardShortcutsHelp, arrowEdge: .top) {
                    KeyboardShortcutsHelpView()
                }
                .task {
                    await handleInitialVaultSyncIfNeeded()
                    await refreshDayPlan()
                }
                .onAppear {
                    if focusedPanel == nil {
                        focusedPanel = .center
                    }
                    installLocalKeyMonitor()
                    syncSelectedTaskIndex()
                }
                .onDisappear {
                    removeLocalKeyMonitor()
                }
                .onReceive(NotificationCenter.default.publisher(for: .timedSyncObsidianVaultRequested)) { _ in
                    store.syncObsidianVault()
                }
                .onChange(of: store.selectedTaskID) { _, _ in
                    syncSelectedTaskIndex()
                }
                .onChange(of: store.tasks) { _, _ in
                    searchService.invalidateIndex()
                    syncSelectedTaskIndex()
                }
                .onChange(of: store.contexts) { _, _ in
                    searchService.invalidateIndex()
                }
                .onChange(of: store.obsidianDocuments) { _, _ in
                    searchService.invalidateIndex()
                }
                .onChange(of: store.chat) { _, _ in
                    searchService.invalidateIndex()
                }
                .onChange(of: store.studyChat) { _, _ in
                    searchService.invalidateIndex()
                }
                .onChange(of: store.pendingCalibrationSubject) { _, newValue in
                    if newValue == nil {
                        showCalibrationPopover = false
                    }
                }
                .onChange(of: selectedCenterTab) { _, newTab in
                    if newTab == .day {
                        Task { await refreshDayPlan() }
                    }
                    if newTab == .plan {
                        syncSelectedTaskIndex()
                    }
                }
                .onChange(of: selectedWeekDeadline) { _, _ in
                    syncSelectedTaskIndex()
                }
                .onChange(of: showLeft) { _, _ in
                    normalizeFocusedPanel()
                }
                .onChange(of: isContextDrawerVisible) { _, _ in
                    normalizeFocusedPanel()
                }
                .onReceive(focusTicker) { tick in
                    guard let activeFocusBlock, !showDebriefSheet else { return }
                    focusNow = tick
                    if tick >= activeFocusBlock.end {
                        presentDebrief(for: activeFocusBlock)
                    }
                }
                .onReceive(deadlineTicker) { tick in
                    deadlineNow = tick
                }
        )
    }

    private var rootView: some View {
        ZStack {
            backgroundLayers
            mainSurface
            overlayLayers
        }
        .animation(.spring(response: 0.3), value: store.toastState?.id)
        .animation(.spring(response: 0.3), value: store.promptErrorState?.id)
    }

    private var backgroundLayers: some View {
        ZStack {
            WindowChromeConfigurator()
            TimedVisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color(red: 0.09, green: 0.10, blue: 0.14).opacity(0.10),
                    Color.black.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var mainSurface: some View {
        Group {
            if isStudyMode {
                StudyModeView(
                    store: store,
                    selectedSubject: $selectedStudySubject,
                    onStartQuiz: startStudyModeQuiz
                )
            } else {
                plannerSurface
            }
        }
        .padding(20)
        .opacity(isGlobalOverlayVisible ? 0.08 : 1)
        .allowsHitTesting(!isGlobalOverlayVisible)
    }

    private var plannerSurface: some View {
        VStack(spacing: 18) {
            header

            HStack(alignment: .top, spacing: 16) {
                if showLeft {
                    leftColumn
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                centerColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isContextDrawerVisible {
                    rightColumn
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 360)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.24), value: showLeft)
            .animation(.easeInOut(duration: 0.24), value: isContextDrawerVisible)
        }
    }

    @ViewBuilder
    private var overlayLayers: some View {
        if activeFocusBlock != nil {
            focusOverlay
        }

        if let activeQuizSession {
            QuizView(
                session: activeQuizSession,
                onClose: closeStudyOverlay,
                onEndSession: { summary in
                    finishStudyOverlay(summary: summary)
                }
            )
        }

        if let toast = store.toastState {
            VStack {
                HStack {
                    Spacer()
                    ToastNotificationView(toast: toast) {
                        store.dismissToast()
                    }
                    .padding(.top, 20)
                    .padding(.trailing, 20)
                }

                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var header: some View {
        TimedCard(title: "Workspace", icon: "calendar.badge.clock") {
            HStack(alignment: .top, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    TimedLogoMark(size: 54)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Timed.")
                            .font(.custom("Fraunces", size: 34))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        Text(headerDateString)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    HeaderActionButton(title: "Export", systemImage: "square.and.arrow.up") {
                        Task { await store.exportCalendar() }
                    }
                    HeaderActionButton(title: "Add Task", systemImage: "plus") {
                        showLeft = true
                        showAddTaskSheet = true
                    }
                    HeaderActionButton(title: "Sync Vault", systemImage: "books.vertical") {
                        store.syncObsidianVault()
                        if let task = contextDrawerTask ?? store.rankedTasks.first?.task {
                            selectTaskForContext(task)
                        }
                    }
                    HeaderActionButton(title: "Load Memory", systemImage: "tray.and.arrow.down") {
                        store.importCodexMemorySchoolPack()
                        if let task = contextDrawerTask ?? store.rankedTasks.first?.task {
                            selectTaskForContext(task)
                        }
                    }
                    HeaderActionButton(title: "Search", systemImage: "magnifyingglass") {
                        showSearchPanel = true
                    }
                    .keyboardShortcut("k", modifiers: [.command])
                    HeaderActionButton(title: "Command", systemImage: "command") {
                        showCommandPalette = true
                    }
                    HeaderActionButton(title: isContextDrawerVisible ? "Hide Context" : "Context", systemImage: "sidebar.trailing") {
                        toggleContextDrawer()
                    }
                    HeaderActionButton(title: showLeft ? "Hide Tasks" : "Tasks", systemImage: "sidebar.leading") {
                        showLeft.toggle()
                    }
                    SettingsLink {
                        settingsLinkLabel
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.22))
                }
            }
        }
    }

    private var leftColumn: some View {
        ZStack {
            TimedVisualEffectBackground(material: .sidebar, blendingMode: .withinWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.clear,
                    Color.black.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TimedSectionHeader(title: "Task Library")

                    if taskLibraryEntries.isEmpty {
                        EmptyStateView(
                            systemImage: "checklist",
                            title: "Add your first task with ⌘N",
                            subtitle: "Timed will rank it, schedule it, and pull the right study context after that.",
                            actionTitle: "Add Task"
                        ) {
                            showAddTaskSheet = true
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(taskLibraryEntries) { entry in
                                TaskLibraryCompactRow(
                                    title: entry.task.title,
                                    iconName: icon(for: entry.task.source),
                                    dueText: dueLabel(for: entry.task.dueDate),
                                    countdownText: deadlineCountdownText(for: entry.task.dueDate),
                                    urgencyColor: urgencyColor(for: entry.task),
                                    isSelected: contextTaskID == entry.task.id,
                                    isCompleted: entry.task.isCompleted,
                                    depth: entry.depth,
                                    action: {
                                        selectTaskForContext(entry.task)
                                    }
                                )
                            }
                        }
                        .animation(.spring(response: 0.3), value: taskLibraryEntries.map(\.id))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .overlay(panelFocusBorder(for: .left))
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 14)
        .focusable()
        .focused($focusedPanel, equals: .left)
        .onTapGesture {
            focusedPanel = .left
        }
    }

    private var centerColumn: some View {
        ZStack {
            TimedVisualEffectBackground(material: .fullScreenUI, blendingMode: .withinWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.clear,
                    Color.black.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                TimedSectionHeader(title: "Next Up")

                VStack(alignment: .leading, spacing: 12) {
                    if let pendingCalibrationSubject = store.pendingCalibrationSubject {
                        ConfidenceCalibrationBanner(
                            subject: pendingCalibrationSubject,
                            onAccept: {
                                showCalibrationPopover = true
                            },
                            onSkip: {
                                showCalibrationPopover = false
                                store.skipPendingCalibration()
                            }
                        )
                        .popover(isPresented: $showCalibrationPopover, arrowEdge: .top) {
                            ConfidenceCalibrationView(
                                subject: pendingCalibrationSubject,
                                suggestedAssessmentDate: store.suggestedAssessmentDateText(for: pendingCalibrationSubject),
                                onSubmit: { draft in
                                    await store.submitConfidenceCalibration(draft)
                                },
                                onCancel: {
                                    showCalibrationPopover = false
                                },
                                onComplete: {
                                    showCalibrationPopover = false
                                    if let task = preferredTask(for: pendingCalibrationSubject) {
                                        selectTaskForContext(task)
                                    }
                                }
                            )
                        }
                    }

                    if store.rankedTasks.isEmpty {
                        EmptyStateView(
                            systemImage: "sparkles.rectangle.stack",
                            title: "Add your first task with ⌘N",
                            subtitle: "Import work or add a task so Timed can rank what matters first."
                        )
                    } else {
                        ForEach(Array(store.rankedTasks.prefix(3))) { ranked in
                            NextUpTaskCard(
                                ranked: ranked,
                                iconName: icon(for: ranked.task.source),
                                isSelected: contextTaskID == ranked.task.id,
                                onStart: {
                                    selectTaskForContext(ranked.task)
                                },
                                onContext: {
                                    selectTaskForContext(ranked.task)
                                },
                                onComplete: {
                                    markTaskCompleteAndRefreshDrawer(ranked.task)
                                }
                            )
                        }
                        .animation(.spring(response: 0.3), value: store.rankedTasks.map(\.id))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                TimedSectionHeader(title: "Today's Plan")

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if store.schedule.isEmpty {
                            EmptyStateView(
                                systemImage: "calendar.badge.plus",
                                title: "Ask Timed to plan your day",
                                subtitle: "Approved blocks will land here once Timed builds the next few hours.",
                                actionTitle: "Plan my day"
                            ) {
                                store.promptText = "Plan my day"
                                Task { await store.submitPlanningPrompt() }
                            }
                        } else {
                            ForEach(store.schedule) { block in
                                scheduleRow(block)
                            }
                            .animation(.spring(response: 0.3), value: store.schedule.map(\.id))
                        }

                        if store.scheduleOverflowCount > 0 {
                            Text("\(store.scheduleOverflowCount) task(s) are still unscheduled.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }

                Divider()
                    .overlay(Color.white.opacity(0.08))

                TimedSectionHeader(title: "Command")

                VStack(alignment: .leading, spacing: 12) {
                    if let promptError = store.promptErrorState {
                        PromptErrorBanner(error: promptError) {
                            Task { await store.retryLastFailedAIAction() }
                        } onDismiss: {
                            store.dismissPromptError()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if focusTimer.isVisible {
                        FocusTimerWidget(
                            timer: focusTimer,
                            onTogglePause: focusTimer.togglePause,
                            onStop: { focusTimer.stop() }
                        )
                    }

                    if let breakPrompt = focusTimer.breakPrompt {
                        FocusBreakBanner(
                            prompt: breakPrompt,
                            onStartBreak: focusTimer.startSuggestedBreak,
                            onDismiss: { focusTimer.stop() }
                        )
                    }

                    if !commandMessages.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(commandMessages) { message in
                                    PromptBubble(message: message, isHighlighted: false)
                                }
                            }
                        }
                        .frame(minHeight: 72, maxHeight: 180)
                        .animation(.spring(response: 0.3), value: commandMessages.map(\.id))
                    }

                    HStack(alignment: .center, spacing: 12) {
                        TextField(
                            store.isQuizMode ? "Answer the quiz or type \"End quiz\"" : "Ask Timed to plan, rank, quiz, or find context",
                            text: activeCommandText
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(rowBackground)
                        .onSubmit {
                            Task { await submitActiveCommand() }
                        }

                        Button(store.isQuizMode ? "Send" : "Ask") {
                            Task { await submitActiveCommand() }
                        }
                        .buttonStyle(.borderedProminent)

                        if store.isQuizMode {
                            Button("End quiz") {
                                store.endQuiz()
                                if contextTaskID == nil {
                                    selectedStudySubject = ""
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    promptStatusLine(
                        defaultText: store.isQuizMode
                            ? "Quiz mode is grounded on the selected task and imported subject context."
                            : "Planning mode injects your ranked task list, memory hits, and local context."
                    )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .overlay(panelFocusBorder(for: .center))
        .shadow(color: .black.opacity(0.12), radius: 28, x: 0, y: 16)
        .focusable()
        .focused($focusedPanel, equals: .center)
        .onTapGesture {
            focusedPanel = .center
        }
        .onKeyPress(.upArrow) {
            handleRankedTaskMovement(delta: -1)
        }
        .onKeyPress(.downArrow) {
            handleRankedTaskMovement(delta: 1)
        }
        .onKeyPress(.return) {
            openFocusedRankedTask()
        }
    }

    private var rightColumn: some View {
        ZStack {
            TimedVisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.clear,
                    Color.black.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        TimedSectionHeader(title: store.isQuizMode ? "Context Drawer · Quiz" : "Context Drawer")
                            .padding(.horizontal, 0)
                            .padding(.vertical, 0)

                        Spacer()

                        if contextTaskID != nil || selectedSearchDocument != nil || selectedSearchContext != nil {
                            Button {
                                contextTaskID = nil
                                clearSearchPreview()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 18)
                        }
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 14) {
                        if let selectedSearchDocument {
                            TimedCard(title: "Note Preview", icon: "note.text") {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        badge(text: selectedSearchDocument.subject, emphasis: .secondary)
                                        Text("Obsidian")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }

                                    Text(selectedSearchDocument.path)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.48))
                                        .textSelection(.enabled)

                                    Text(selectedSearchDocument.content)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.78))
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        if let selectedSearchContext {
                            TimedCard(title: "Transcript Preview", icon: "text.book.closed") {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        if !selectedSearchContext.subject.isEmpty {
                                            badge(text: selectedSearchContext.subject, emphasis: .secondary)
                                        }

                                        Text(selectedSearchContext.kind)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }

                                    Text(selectedSearchContext.summary)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.78))

                                    Text(selectedSearchContext.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.64))
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        if store.isQuizMode {
                            TimedCard(title: "Quiz Mode", icon: "questionmark.circle") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(store.activeQuizSubject ?? activeStudySubject)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)

                                    Text("Timed is using grounded context for one-question-at-a-time tutoring.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.76))
                                }
                            }
                        }

                        if let contextDrawerTask {
                            TimedCard(title: "Task Detail", icon: icon(for: contextDrawerTask.source)) {
                                TaskDetailView(
                                    task: contextDrawerTask,
                                    canBreakDown: store.canBreakDown(task: contextDrawerTask),
                                    isBreakingDown: store.decomposingTaskIDs.contains(contextDrawerTask.id),
                                    onBreakDown: {
                                        Task { await store.decompose(task: contextDrawerTask) }
                                    },
                                    onStudy: {
                                        openStudyOverlay(for: contextDrawerTask)
                                    },
                                    onComplete: {
                                        markTaskCompleteAndRefreshDrawer(contextDrawerTask)
                                    },
                                    onSaveNotes: { notes in
                                        store.updateTaskNotes(taskID: contextDrawerTask.id, notes: notes)
                                    }
                                )
                                .id(contextDrawerTask.id)
                            }
                        }

                        if let contextDrawerSubject, !contextDrawerDocuments.isEmpty {
                            TimedCard(title: "Obsidian Notes", icon: "books.vertical") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Top notes for \(contextDrawerSubject)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.62))

                                    ForEach(contextDrawerDocuments) { document in
                                        ObsidianNoteSnippetCard(document: document)
                                    }
                                }
                            }
                        }

                        if contextDrawerContexts.isEmpty {
                            EmptyStateView(
                                systemImage: "doc.text.magnifyingglass",
                                title: "Select a task to see context",
                                subtitle: "Timed will surface notes, transcripts, vault matches, and memory linked to that task."
                            )
                        } else {
                            ForEach(contextDrawerContexts.prefix(4)) { context in
                                ContextSnippetCard(
                                    context: context,
                                    onQuiz: {
                                        openStudyOverlay(forSubject: context.subject)
                                    }
                                )
                            }
                            .animation(.spring(response: 0.3), value: contextDrawerContexts.map(\.id))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
            .scrollIndicators(.hidden)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .overlay(panelFocusBorder(for: .right))
        .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 14)
        .focusable()
        .focused($focusedPanel, equals: .right)
        .onTapGesture {
            focusedPanel = .right
        }
    }

    private var subjectHealthCard: some View {
        TimedCard(title: "Subject health", icon: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 10) {
                if subjectHealthRows.isEmpty {
                    Text("No active subjects yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    ForEach(subjectHealthRows) { row in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.subject)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.82))
                                Text("\(row.taskCount) tasks · avg confidence \(row.averageConfidence)/5")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.58))
                                Text(row.lastTouchedText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.46))
                            }
                            Spacer()
                            badge(text: row.status, emphasis: row.status == "Flagged" ? .primary : .secondary)
                        }
                    }
                }
            }
        }
    }

    private var contextPanelCard: some View {
        TimedCard(title: contextPanelTitle, icon: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                if selectedCenterTab != .study {
                    Picker("Subject filter", selection: $selectedContextFilter) {
                        ForEach(contextFilterOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if contextPanelItems.isEmpty {
                    EmptyStateView(
                        systemImage: "text.book.closed",
                        title: contextPanelEmptyState,
                        subtitle: "Timed only shows grounded context once a task or subject is active."
                    )
                } else {
                    ForEach(contextPanelItems) { context in
                        contextPanelRow(context)
                    }
                    .animation(.spring(response: 0.3), value: contextPanelItems.map(\.id))
                }
            }
        }
    }

    private func contextPanelRow(_ context: ContextItem) -> some View {
        TimedCard(title: context.title, icon: "book.closed") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(context.kind)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    Text(context.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Text(context.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 10) {
                    Button("View") {
                        store.selectContext(context)
                    }
                    .buttonStyle(.bordered)

                    Button("Study") {
                        openStudyOverlay(forSubject: context.subject)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .overlay(selectionBorder(isSelected: store.selectedContextID == context.id))
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }

    private var planTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DailyOverviewCard(
                    date: .now,
                    priorities: dailyOverviewPriorities,
                    totalScheduledHours: totalScheduledHoursToday,
                    deadlines: dailyOverviewDeadlines,
                    todayPomodoroCount: store.pomodoroCount(),
                    currentStudyStreak: store.currentPomodoroStreak(),
                    pomodoroTrend: store.pomodoroTrend(),
                    tintColor: dailyOverviewTint
                ) {
                    await generateDayPlanFromOverview()
                }

                if let dangerWeekMessage {
                    TimedCard(title: "Danger week", icon: "exclamationmark.triangle.fill") {
                        Text(dangerWeekMessage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                TimedCard(title: "Week strip", icon: "calendar") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(weekStripItems) { item in
                                Button {
                                    selectedWeekDeadline = Calendar.current.isDate(item.date, inSameDayAs: selectedWeekDeadline ?? .distantPast) ? nil : item.date
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(item.label)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("\(item.count) due")
                                            .font(.system(size: 13, weight: .bold))
                                        Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.58))
                                    }
                                    .frame(width: 120, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(item.color.opacity(selectedWeekDeadline != nil && !Calendar.current.isDate(item.date, inSameDayAs: selectedWeekDeadline!) ? 0.18 : 0.28))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.white.opacity(Calendar.current.isDate(item.date, inSameDayAs: selectedWeekDeadline ?? .distantPast) ? 0.24 : 0.08), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let topRankedTask = rankedTasksForPlan.first {
                    TimedCard(title: "Start here", icon: "bolt.fill") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(topRankedTask.task.title)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)

                                Text("\(topRankedTask.task.subject) · \(topRankedTask.task.estimateMinutes) min · score \(topRankedTask.score)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.62))

                                Text(topRankedTask.suggestedNextAction)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.86))
                            }

                            HStack(spacing: 10) {
                                Button("Start this now") {
                                    selectedStudySubject = topRankedTask.task.subject
                                    expandedStudySubject = topRankedTask.task.subject
                                    store.selectTask(topRankedTask.task)
                                    centerTabRawValue = CenterTab.study.rawValue
                                    showRight = true
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Mark complete") {
                                    completeTask(topRankedTask.task)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                TimedCard(title: "Ranked tasks", icon: "list.number") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(["Do now", "Today", "This week", "Later"], id: \.self) { band in
                            let tasksInBand = rankedTasksForPlan.filter { $0.band == band }
                            if !tasksInBand.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(band)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .textCase(.uppercase)

                                    ForEach(tasksInBand) { ranked in
                                        rankedTaskRow(ranked)
                                    }
                                }
                            }
                        }
                        .animation(.spring(response: 0.3), value: rankedTasksForPlan.map(\.id))

                        DisclosureGroup(isExpanded: $showCompletedToday) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(store.completedToday) { task in
                                    TimedCard(title: task.title, icon: "checkmark.circle.fill") {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(task.subject)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.62))
                                            Text(task.completedAt?.formatted(date: .omitted, time: .shortened) ?? "Completed")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.white.opacity(0.52))
                                        }
                                    }
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Text("Completed today")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                TimedCard(title: "Schedule", icon: "clock") {
                    VStack(alignment: .leading, spacing: 12) {
                        if store.schedule.isEmpty {
                            EmptyStateView(
                                systemImage: "calendar.badge.plus",
                                title: "Ask Timed to plan your day",
                                subtitle: "Your approved study blocks will appear here."
                            )
                        } else {
                            ForEach(store.schedule) { block in
                                scheduleRow(block)
                            }
                            .animation(.spring(response: 0.3), value: store.schedule.map(\.id))
                        }

                        if store.scheduleOverflowCount > 0 {
                            Text("\(store.scheduleOverflowCount) task(s) didn't fit — see full list.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var planningChatTab: some View {
        ScrollView {
            PromptConversationCard(
                title: "Chat",
                icon: "message",
                messages: orderedPlannerMessages,
                highlightedMessageID: highlightedPlannerChatMessageID,
                errorState: store.promptErrorState,
                onRetry: {
                    Task { await store.retryLastFailedAIAction() }
                },
                onDismissError: {
                    store.dismissPromptError()
                }
            )
        }
        .scrollIndicators(.hidden)
    }

    private var studyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TimedCard(title: "Selected study task", icon: "graduationcap") {
                    if let selectedStudyTask {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(selectedStudyTask.title)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text("\(selectedStudyTask.subject) · confidence \(selectedStudyTask.confidence)/5 · \(selectedStudyTask.estimateMinutes) min")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.62))
                                }
                                Spacer()
                                badge(text: selectedStudyTask.source.rawValue, emphasis: .secondary)
                            }

                            Text(selectedStudyTask.notes.isEmpty ? "No task notes yet." : selectedStudyTask.notes)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.76))

                            HStack(spacing: 10) {
                                Button("Study") {
                                    openStudyOverlay(for: selectedStudyTask)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Mark complete") {
                                    completeTask(selectedStudyTask)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        Text("Pick a task from the subject folders to load study mode.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                TimedCard(title: "Study actions", icon: "sparkles") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(studySuggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    store.studyPromptText = suggestion
                                    Task { await store.submitStudyPrompt() }
                                }
                                .buttonStyle(.bordered)
                                .tint(.white.opacity(0.18))
                            }
                        }
                    }
                }

                TimedCard(title: store.isQuizMode ? "Tutor chat" : "Study chat", icon: store.isQuizMode ? "questionmark.bubble" : "message") {
                    PromptConversationList(
                        messages: store.studyChat,
                        highlightedMessageID: highlightedStudyChatMessageID,
                        errorState: store.promptErrorState,
                        onRetry: {
                            Task { await store.retryLastFailedAIAction() }
                        },
                        onDismissError: {
                            store.dismissPromptError()
                        }
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var dayTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TimedCard(title: "Lessons", icon: "calendar.day.timeline.leading") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dayPlan.isTomorrow ? "Tomorrow" : "Today")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.62))
                                Text(dayPlan.targetDate.formatted(date: .complete, time: .omitted))
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            Button("Refresh") {
                                Task { await refreshDayPlan() }
                            }
                            .buttonStyle(.bordered)
                        }

                        if isLoadingDayPlan {
                            ProgressView("Loading Apple Calendar...")
                                .controlSize(.small)
                        } else if dayPlan.lessons.isEmpty {
                            Text(dayPlan.message)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                        } else {
                            ForEach(1...7, id: \.self) { lessonNumber in
                                if let lesson = dayPlan.lessons.first(where: { $0.lessonNumber == lessonNumber }) {
                                    lessonRow(lesson)
                                } else {
                                    emptyLessonRow(lessonNumber)
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var activePromptComposer: some View {
        Group {
            switch selectedCenterTab {
            case .study:
                studyPromptComposer
            case .plan, .chat, .day:
                planningPromptComposer
            }
        }
    }

    private var planningPromptComposer: some View {
        TimedCard(title: "Ask Timed", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    TextField("Ask Timed to rank, find, import, or plan", text: $store.promptText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(rowBackground)
                        .onSubmit {
                            Task { await store.submitPlanningPrompt() }
                        }

                    Button("Ask") {
                        Task { await store.submitPlanningPrompt() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                promptStatusLine(defaultText: "Planning mode uses ranked tasks, real imports, local files, Codex memory, and your vault.")
            }
        }
    }

    private var studyPromptComposer: some View {
        TimedCard(title: store.isQuizMode ? "Answer the tutor" : "Study with Timed", icon: store.isQuizMode ? "questionmark.circle" : "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    TextField(
                        store.isQuizMode ? "Type your answer or \"End quiz\"" : "Ask for a quiz, worksheet, drill, or explanation",
                        text: $store.studyPromptText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(rowBackground)
                    .onSubmit {
                        Task { await store.submitStudyPrompt() }
                    }

                    Button(store.isQuizMode ? "Send" : "Ask") {
                        Task { await store.submitStudyPrompt() }
                    }
                    .buttonStyle(.borderedProminent)

                    if store.isQuizMode {
                        Button("End quiz") {
                            store.endQuiz()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                promptStatusLine(defaultText: "Study mode loads the selected task, grounded subject context, Apple Calendar, local files, and Codex memory.")
            }
        }
    }

    @ViewBuilder
    private func promptStatusLine(defaultText: String) -> some View {
        HStack(spacing: 10) {
            if store.isRunningPrompt {
                ProgressView()
                    .controlSize(.small)
                Text("Asking Timed...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            } else {
                Text(defaultText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    private var settingsLinkLabel: some View {
        Label {
            HStack(spacing: 8) {
                Text("Settings")
                if store.settingsIssue != nil {
                    Circle()
                        .fill(Color.red.opacity(0.9))
                        .frame(width: 8, height: 8)
                }
            }
        } icon: {
            Image(systemName: "gearshape")
        }
        .labelStyle(.titleAndIcon)
        .help(store.settingsIssue?.message ?? "Open Settings")
    }

    private var isContextDrawerVisible: Bool {
        contextDrawerTask != nil || store.isQuizMode || selectedSearchDocument != nil || selectedSearchContext != nil
    }

    private var isGlobalOverlayVisible: Bool {
        activeFocusBlock != nil || activeQuizSession != nil
    }

    private var contextDrawerTask: TaskItem? {
        guard let contextTaskID else { return nil }
        return store.tasks.first(where: { $0.id == contextTaskID && !$0.isCompleted })
    }

    private var contextDrawerSubject: String? {
        if let selectedSearchDocument {
            return selectedSearchDocument.subject
        }
        if let selectedSearchContext, !selectedSearchContext.subject.isEmpty {
            return selectedSearchContext.subject
        }
        if let contextDrawerTask {
            return contextDrawerTask.subject
        }
        if store.isQuizMode {
            return store.activeQuizSubject ?? activeStudySubject
        }
        return nil
    }

    private var contextDrawerDocuments: [ContextDocument] {
        guard let contextDrawerSubject else { return [] }
        return store.topDocuments(for: contextDrawerSubject, limit: 3)
    }

    private var contextDrawerContexts: [ContextItem] {
        if let contextDrawerTask {
            return store.groundedStudyContexts(for: contextDrawerTask)
        }
        if store.isQuizMode {
            return store.groundedStudyContexts(for: nil, subject: store.activeQuizSubject ?? activeStudySubject)
        }
        return []
    }

    private var selectedSearchDocument: ContextDocument? {
        guard let selectedSearchDocumentID else { return nil }
        return store.obsidianDocuments.first(where: { $0.id == selectedSearchDocumentID })
    }

    private var selectedSearchContext: ContextItem? {
        guard let selectedSearchContextID else { return nil }
        return store.contexts.first(where: { $0.id == selectedSearchContextID })
    }

    private var commandMessages: [PromptMessage] {
        let activeMessages = store.isQuizMode ? store.studyChat : orderedPlannerMessages
        let pinnedMessages = activeMessages.filter(\.isPinned)
        let recentMessages = activeMessages.filter { !$0.isPinned }
        let trailingCount = max(0, 4 - pinnedMessages.count)
        return Array((pinnedMessages + Array(recentMessages.suffix(trailingCount))).prefix(4))
    }

    private var activeCommandText: Binding<String> {
        Binding(
            get: { store.isQuizMode ? store.studyPromptText : store.promptText },
            set: { newValue in
                if store.isQuizMode {
                    store.studyPromptText = newValue
                } else {
                    store.promptText = newValue
                }
            }
        )
    }

    private var keyboardActions: TimedKeyboardActions {
        TimedKeyboardActions(
            addTask: {
                showLeft = true
                showAddTaskSheet = true
            },
            toggleStudyMode: {
                toggleStudyMode()
            },
            startFocusTimer: {
                startFocusTimerForSelectedTask()
            },
            exportCalendar: {
                Task { await store.exportCalendar() }
            },
            focusSearch: {
                showSearchPanel = true
            },
            showKeyboardShortcuts: {
                showKeyboardShortcutsHelp = true
            },
            canUndoDecomposition: store.canUndoDecomposition,
            undoLastDecomposition: {
                store.undoLastDecomposition()
            }
        )
    }

    private var taskLibraryEntries: [TaskLibraryEntry] {
        taskLibraryOutlineEntries(from: taskLibrarySortedTasks(store.tasks.filter { $0.parentId == nil }))
    }

    private func taskLibraryOutlineEntries(from tasks: [TaskItem], depth: Int = 0) -> [TaskLibraryEntry] {
        var entries: [TaskLibraryEntry] = []

        for task in tasks {
            entries.append(TaskLibraryEntry(task: task, depth: depth))
            let children = taskLibrarySortedTasks(store.children(of: task.id))
            entries.append(contentsOf: taskLibraryOutlineEntries(from: children, depth: depth + 1))
        }

        return entries
    }

    private func taskLibrarySortedTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        let rankedOrder = Dictionary(uniqueKeysWithValues: store.rankedTasks.enumerated().map { ($0.element.task.id, $0.offset) })
        return tasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            let lhsRank = rankedOrder[lhs.id] ?? Int.max
            let rhsRank = rankedOrder[rhs.id] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if let lhsDue = lhs.dueDate, let rhsDue = rhs.dueDate, lhsDue != rhsDue {
                return lhsDue < rhsDue
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func submitActiveCommand() async {
        if store.isQuizMode {
            await store.submitStudyPrompt()
            return
        }

        await store.submitPlanningPrompt()
        if store.isQuizMode && contextTaskID == nil {
            if let quizTask = store.selectedTask {
                selectTaskForContext(quizTask)
            }
        }
    }

    private func handleInitialVaultSyncIfNeeded() async {
        guard !didHandleInitialVaultSync else { return }
        didHandleInitialVaultSync = true

        if shouldPromptForVaultSelection {
            promptForObsidianVault()
        }

        store.syncObsidianVault(announce: false)
    }

    private var shouldPromptForVaultSelection: Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return false }
        return TimedPreferences.shouldPromptForObsidianVault
    }

    private func promptForObsidianVault() {
        TimedPreferences.markObsidianVaultPromptHandled()

        let panel = NSOpenPanel()
        panel.title = "Choose Obsidian vault"
        panel.message = "Timed can import markdown notes by subject from your Obsidian vault."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            TimedPreferences.setObsidianVaultPath(url.path)
        }
    }

    private func toggleContextDrawer() {
        if isContextDrawerVisible {
            contextTaskID = nil
            clearSearchPreview()
            return
        }

        if let selectedTask = contextDrawerTask ?? store.selectedTask ?? store.rankedTasks.first?.task {
            selectTaskForContext(selectedTask)
        }
    }

    private func selectTaskForContext(_ task: TaskItem) {
        clearSearchPreview()
        selectedStudySubject = task.subject
        expandedStudySubject = task.subject
        contextTaskID = task.id
        syncSelectedTaskIndex(preferredTaskID: task.id)
        store.selectTask(task)
    }

    private func toggleStudyMode() {
        isStudyMode.toggle()
        if isStudyMode {
            prepareStudyModeSelection()
        }
    }

    private func prepareStudyModeSelection() {
        if let selectedTask = store.selectedTask, !selectedTask.isCompleted {
            selectedStudySubject = selectedTask.subject
            expandedStudySubject = selectedTask.subject
            return
        }

        if let firstSubject = store.studyModeSubjects().first {
            selectedStudySubject = firstSubject
            expandedStudySubject = firstSubject
        }
    }

    private func startStudyModeQuiz(for subject: String) {
        selectedStudySubject = subject
        expandedStudySubject = subject

        guard let task = preferredTask(for: subject) else { return }
        openStudyOverlay(for: task)
    }

    private func openStudyOverlay(for task: TaskItem) {
        if store.isQuizMode {
            store.endQuiz()
        }

        selectTaskForContext(task)
        if !isStudyMode {
            centerTabRawValue = CenterTab.study.rawValue
            showRight = true
        }

        activeQuizSession = QuizSessionModel(
            task: task,
            documents: store.topDocuments(for: task.subject, limit: 3),
            contexts: store.groundedStudyContexts(for: task),
            workingRoot: TimedPreferences.workingRoot,
            additionalRoots: TimedPreferences.codexAdditionalRoots,
            autonomousMode: TimedPreferences.autonomousModeEnabled,
            runner: { request in
                let result = await CodexBridge().run(request: request)
                return CodexBridge.response(from: result)
            },
            loadStoredQuestions: { subject in
                store.quizCards(for: subject)
            },
            loadDueQuestions: { subject, now in
                store.dueQuizCards(for: subject, now: now)
            },
            replaceStoredQuestions: { subject, questions in
                store.replaceQuizCards(for: subject, with: questions)
            },
            reviewStoredQuestion: { subject, question, quality, now in
                store.reviewQuizCard(for: subject, question: question, quality: quality, now: now)
            },
            nextReviewDays: { subject, now in
                store.nextQuizReviewDays(for: subject, now: now)
            }
        )
    }

    @discardableResult
    private func openStudyOverlay(forSubject subject: String) -> Bool {
        guard let task = preferredTask(for: subject) else { return false }
        openStudyOverlay(for: task)
        return true
    }

    private func preferredTask(for subject: String) -> TaskItem? {
        if let selectedTask = selectedStudyTask, selectedTask.subject.caseInsensitiveCompare(subject) == .orderedSame {
            return selectedTask
        }

        return studyTasks(for: subject).first ?? store.tasks.first {
            !$0.isCompleted && $0.subject.caseInsensitiveCompare(subject) == .orderedSame
        }
    }

    private func closeStudyOverlay() {
        activeQuizSession = nil
    }

    private func finishStudyOverlay(summary: QuizSessionSummary) {
        guard let activeQuizSession else { return }
        store.recordQuizSession(subject: activeQuizSession.subject, summary: summary)
        self.activeQuizSession = nil
    }

    private func markTaskCompleteAndRefreshDrawer(_ task: TaskItem) {
        if contextTaskID == task.id {
            contextTaskID = nil
        }
        completeTask(task)
    }

    private func startFocusTimer(for task: TaskItem) {
        selectTaskForContext(task)
        focusTimer.start(for: task) { completedTask in
            store.recordPomodoro(for: completedTask.id)
        }
    }

    private func completeTask(_ task: TaskItem) {
        if focusTimer.currentTask?.id == task.id {
            focusTimer.stop()
        }
        if selectedSearchDocument?.subject.caseInsensitiveCompare(task.subject) == .orderedSame {
            selectedSearchDocumentID = nil
        }
        store.markTaskCompleted(task)
    }

    private func dueLabel(for dueDate: Date?) -> String {
        guard let dueDate else { return "No date" }
        return dueDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private func deadlineCountdownText(for dueDate: Date?) -> String? {
        DeadlineCountdownFormatter.badgeText(for: dueDate, now: deadlineNow)
    }

    private func urgencyColor(for task: TaskItem) -> Color {
        guard !task.isCompleted else { return Color.white.opacity(0.18) }
        switch store.rankedTasks.first(where: { $0.task.id == task.id })?.band {
        case "Do now":
            return .red
        case "Today":
            return .orange
        case "This week":
            return .yellow
        case "Later":
            return .green
        default:
            return .white.opacity(0.28)
        }
    }

    private var orderedPlannerMessages: [PromptMessage] {
        store.chat.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private var dailyOverviewPriorities: [DailyOverviewPriority] {
        Array(store.rankedTasks.prefix(3)).map { ranked in
            DailyOverviewPriority(
                taskID: ranked.task.id,
                title: ranked.task.title,
                subject: ranked.task.subject,
                urgencyColor: urgencyColor(for: ranked.task)
            )
        }
    }

    private var totalScheduledHoursToday: Double {
        store.schedule
            .filter { Calendar.current.isDateInToday($0.start) }
            .reduce(0.0) { partialResult, block in
                partialResult + block.end.timeIntervalSince(block.start) / 3600
            }
    }

    private var dailyOverviewDeadlines: [DailyOverviewDeadline] {
        let activeTasks = store.tasks.filter { !$0.isCompleted }
        let dueToday = activeTasks
            .filter { task in
                guard let dueDate = task.dueDate else { return false }
                return Calendar.current.isDateInToday(dueDate)
            }
            .sorted(by: deadlineSortOrder)

        let dueTomorrow = activeTasks
            .filter { task in
                guard let dueDate = task.dueDate else { return false }
                return Calendar.current.isDateInTomorrow(dueDate)
            }
            .sorted(by: deadlineSortOrder)

        var badges: [DailyOverviewDeadline] = []
        if !dueToday.isEmpty {
            badges.append(
                DailyOverviewDeadline(
                    bucket: "today",
                    label: "Due today",
                    titles: dueToday.map(\.title),
                    color: .red
                )
            )
        }
        if !dueTomorrow.isEmpty {
            badges.append(
                DailyOverviewDeadline(
                    bucket: "tomorrow",
                    label: "Due tomorrow",
                    titles: dueTomorrow.map(\.title),
                    color: .orange
                )
            )
        }
        return badges
    }

    private var dailyOverviewTint: Color {
        subjectTintColor(for: store.rankedTasks.first?.task.subject)
    }

    private func deadlineSortOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
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

    private func subjectTintColor(for subject: String?) -> Color {
        let normalizedSubject = (subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedSubject {
        case "economics":
            return Color(red: 0.722, green: 0.525, blue: 0.043)
        case "english":
            return .blue
        case "maths", "mathematics":
            return .purple
        case "society and culture", "society & culture", "soc", "society/culture":
            return .green
        default:
            return Color.white.opacity(0.24)
        }
    }

    private func generateDayPlanFromOverview() async {
        highlightedPlannerChatMessageID = nil
        if let messageID = await store.generateDayPlanSummary() {
            highlightedPlannerChatMessageID = messageID
            centerTabRawValue = CenterTab.chat.rawValue
        }
    }

    private var centerTabSelection: Binding<CenterTab> {
        Binding(
            get: { selectedCenterTab },
            set: { centerTabRawValue = $0.rawValue }
        )
    }

    private var selectedCenterTab: CenterTab {
        CenterTab(rawValue: centerTabRawValue) ?? .plan
    }

    private func refreshDayPlan() async {
        isLoadingDayPlan = true
        dayPlan = await SchoolCalendarService.loadPlan()
        isLoadingDayPlan = false
    }

    private func runCommandPalette(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let lowered = trimmed.lowercased()
        commandPaletteText = ""
        showCommandPalette = false

        if lowered.hasPrefix("quiz ") {
            let subject = String(trimmed.dropFirst(5))
            if openStudyOverlay(forSubject: subject) == false {
                centerTabRawValue = CenterTab.study.rawValue
                selectedStudySubject = subject
                await store.startQuiz(subject: subject)
            }
            return
        }

        if lowered.hasPrefix("plan ") {
            store.rebuildPlan()
            centerTabRawValue = CenterTab.plan.rawValue
            return
        }

        if lowered.hasPrefix("done ") {
            let taskName = String(trimmed.dropFirst(5))
            if let task = store.tasks.first(where: { $0.title.localizedCaseInsensitiveContains(taskName) }) {
                completeTask(task)
            }
            centerTabRawValue = CenterTab.plan.rawValue
            return
        }

        if lowered == "import seqta" {
            showLeft = true
            store.importSource = .seqta
            return
        }

        if lowered == "sync vault" {
            store.syncObsidianVault()
            centerTabRawValue = CenterTab.study.rawValue
            showRight = true
            return
        }

        if lowered == "import memory" || lowered == "load memory" {
            store.importCodexMemorySchoolPack()
            centerTabRawValue = CenterTab.study.rawValue
            showRight = true
            return
        }

        if lowered.hasPrefix("add ") {
            addTaskDraft.title = String(trimmed.dropFirst(4))
            showLeft = true
            showAddTaskSheet = true
            return
        }

        store.promptText = trimmed
        centerTabRawValue = CenterTab.chat.rawValue
        await store.submitPlanningPrompt()
    }

    private func handleSearchSelection(_ result: SearchResult) {
        searchQuery = ""
        highlightedPlannerChatMessageID = nil
        highlightedStudyChatMessageID = nil

        switch result.type {
        case .task:
            guard let taskID = result.taskID,
                  let task = store.tasks.first(where: { $0.id == taskID && !$0.isCompleted }) else { return }
            selectTaskForContext(task)

        case .note:
            guard let documentID = result.documentID else { return }
            selectedSearchDocumentID = documentID
            selectedSearchContextID = nil
            contextTaskID = nil

            if let document = selectedSearchDocument {
                selectedStudySubject = document.subject
                expandedStudySubject = document.subject
            }

        case .transcript:
            guard let contextID = result.contextID else { return }
            selectedSearchContextID = contextID
            selectedSearchDocumentID = nil
            contextTaskID = nil

            if let context = selectedSearchContext {
                if !context.subject.isEmpty {
                    selectedStudySubject = context.subject
                    expandedStudySubject = context.subject
                }
                store.selectContext(context)
            }

        case .chat:
            guard let messageID = result.messageID else { return }
            clearSearchPreview()

            switch result.messageChannel ?? .planner {
            case .planner:
                centerTabRawValue = CenterTab.chat.rawValue
                highlightedPlannerChatMessageID = messageID
            case .study:
                centerTabRawValue = CenterTab.study.rawValue
                highlightedStudyChatMessageID = messageID
                if !result.subject.isEmpty {
                    selectedStudySubject = result.subject
                    expandedStudySubject = result.subject
                }
            }
        }
    }

    private func rankedTaskRow(_ ranked: RankedTask) -> some View {
        TimedCard(title: ranked.task.title, icon: icon(for: ranked.task.source)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(ranked.task.subject) · \(ranked.task.estimateMinutes) min · confidence \(ranked.task.confidence)/5")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))

                        if let dueDate = ranked.task.dueDate {
                            HStack(spacing: 8) {
                                Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.56))

                                if let countdownText = deadlineCountdownText(for: dueDate) {
                                    DeadlineCountdownBadge(text: countdownText)
                                }
                            }
                        }
                    }

                    Spacer()

                HStack(spacing: 8) {
                    Button {
                        startFocusTimer(for: ranked.task)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.94))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Start focus timer")

                    badge(text: ranked.band, emphasis: .secondary)
                    badge(text: "\(ranked.score)", emphasis: .primary)
                }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(ranked.reasons.prefix(2)), id: \.self) { reason in
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }

                Text(ranked.suggestedNextAction)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 10) {
                    Button {
                        openStudyOverlay(for: ranked.task)
                    } label: {
                        Label("Study", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        completeTask(ranked.task)
                    } label: {
                        Label("Complete", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .overlay(
            selectionBorder(
                isSelected: store.selectedTaskID == ranked.task.id,
                isFocused: focusedPanel == .center && selectedCenterTab == .plan && currentKeyboardSelectedTask?.id == ranked.task.id
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            focusedPanel = .center
            selectRankedTask(ranked.task)
        }
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }

    private func scheduleRow(_ block: ScheduleBlock) -> some View {
        TimedCard(title: block.title, icon: "calendar") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(block.timeRange)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    badge(text: block.isApproved ? "Approved" : "Pending", emphasis: block.isApproved ? .primary : .secondary)
                }

                Text(block.note)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 10) {
                    Button(block.isApproved ? "Unapprove" : "Approve") {
                        store.toggleScheduleApproval(block)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Start") {
                        beginFocus(with: block)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!block.isApproved)

                    Button("Remove") {
                        store.removeScheduleBlock(block)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }

    private func studyFolderRow(_ task: TaskItem) -> some View {
        TimedCard(title: task.title, icon: icon(for: task.source)) {
            VStack(alignment: .leading, spacing: 10) {
                if let dueDate = task.dueDate {
                    HStack(spacing: 8) {
                        Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.56))

                        if let countdownText = deadlineCountdownText(for: dueDate) {
                            DeadlineCountdownBadge(text: countdownText)
                        }
                    }
                }

                Text(task.notes.isEmpty ? "No notes yet." : task.notes)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    badge(text: "\(store.groundedStudyContexts(for: task).count) ctx", emphasis: .secondary)
                    badge(text: "\(task.confidence)/5", emphasis: .primary)
                }
            }
        }
        .overlay(selectionBorder(isSelected: selectedStudyTask?.id == task.id))
        .onTapGesture {
            selectedStudySubject = task.subject
            expandedStudySubject = task.subject
            store.selectTask(task)
            centerTabRawValue = CenterTab.study.rawValue
        }
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }

    private func lessonRow(_ lesson: SchoolLesson) -> some View {
        TimedCard(title: "Lesson \(lesson.lessonNumber)", icon: "book") {
            VStack(alignment: .leading, spacing: 8) {
                Text(lesson.subject ?? lesson.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Text(lesson.timeRange)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))

                if !lesson.location.isEmpty {
                    Text(lesson.location)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Text(lesson.calendarTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    private func emptyLessonRow(_ lessonNumber: Int) -> some View {
        TimedCard(title: "Lesson \(lessonNumber)", icon: "clock") {
            Text("No matching school calendar event.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.52))
        }
    }

    private var filteredContexts: [ContextItem] {
        if selectedContextFilter == "All" {
            return store.sortedContexts
        }

        return store.sortedContexts.filter { $0.subject == selectedContextFilter }
    }

    private var contextPanelItems: [ContextItem] {
        switch selectedCenterTab {
        case .study:
            return studyContexts
        case .plan, .chat, .day:
            return filteredContexts
        }
    }

    private var contextPanelTitle: String {
        selectedCenterTab == .study ? "Grounded context" : "Context"
    }

    private var contextPanelEmptyState: String {
        "Select a task to see context"
    }

    private var contextFilterOptions: [String] {
        let subjects = Array(Set(store.sortedContexts.map(\.subject))).sorted()
        return ["All"] + subjects
    }

    private var activeContextSubject: String? {
        if selectedContextFilter != "All" {
            return selectedContextFilter
        }
        return store.selectedContext?.subject
    }

    private var studySubjects: [String] {
        Array(Set(store.tasks.filter { !$0.isCompleted }.map(\.subject))).sorted()
    }

    private var activeStudySubject: String {
        if !selectedStudySubject.isEmpty {
            return selectedStudySubject
        }
        if !expandedStudySubject.isEmpty {
            return expandedStudySubject
        }
        if let selectedTask = store.selectedTask, !selectedTask.isCompleted {
            return selectedTask.subject
        }
        return studySubjects.first ?? ""
    }

    private func studyTasks(for subject: String) -> [TaskItem] {
        store.tasks
            .filter { !$0.isCompleted && $0.subject == subject }
            .sorted { lhs, rhs in
                if let lhsDue = lhs.dueDate, let rhsDue = rhs.dueDate {
                    return lhsDue < rhsDue
                }
                return lhs.title < rhs.title
            }
    }

    private var selectedStudyTask: TaskItem? {
        if let selectedTask = store.selectedTask, !selectedTask.isCompleted, selectedTask.subject == activeStudySubject {
            return selectedTask
        }
        return studyTasks(for: activeStudySubject).first
    }

    private var studyContexts: [ContextItem] {
        store.groundedStudyContexts(for: selectedStudyTask, subject: activeStudySubject)
    }

    private var studySuggestions: [String] {
        let subject = activeStudySubject.isEmpty ? "English" : activeStudySubject
        let taskTitle = selectedStudyTask?.title ?? "\(subject) task"
        return [
            "Quiz me on \(subject)",
            "What are the main weaknesses in \(taskTitle)?",
            "Make me a practice formative for \(taskTitle)",
            "Test me on the key concepts for \(subject)"
        ]
    }

    private var rankedTasksForPlan: [RankedTask] {
        guard let selectedWeekDeadline else { return store.rankedTasks }
        return store.rankedTasks.filter { ranked in
            guard let dueDate = ranked.task.dueDate else { return true }
            return dueDate <= Calendar.current.endOfDay(for: selectedWeekDeadline)
        }
    }

    private var weekStripItems: [WeekStripItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let count = store.tasks.filter { task in
                guard !task.isCompleted, let dueDate = task.dueDate else { return false }
                return calendar.isDate(dueDate, inSameDayAs: date)
            }.count

            return WeekStripItem(
                date: date,
                label: offset == 0 ? "Today" : offset == 1 ? "Tomorrow" : date.formatted(.dateTime.weekday(.abbreviated)),
                count: count,
                color: count >= 3 ? .red : count == 2 ? .orange : count == 1 ? .yellow : .green
            )
        }
    }

    private var dangerWeekMessage: String? {
        let dueTasks = store.tasks
            .filter { !$0.isCompleted && $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        guard dueTasks.count >= 3 else { return nil }
        let calendar = Calendar.current

        for startIndex in dueTasks.indices {
            guard let startDate = dueTasks[startIndex].dueDate else { continue }
            let windowTasks = dueTasks.filter { task in
                guard let dueDate = task.dueDate else { return false }
                let delta = calendar.dateComponents([.day], from: startDate, to: dueDate).day ?? 99
                return delta >= 0 && delta <= 3
            }

            let uniqueSubjects = Array(Set(windowTasks.map(\.subject))).sorted()
            guard uniqueSubjects.count >= 3 else { continue }

            let startLabel = startDate.formatted(date: .abbreviated, time: .omitted)
            let endLabel = (windowTasks.compactMap(\.dueDate).max() ?? startDate).formatted(date: .abbreviated, time: .omitted)
            let taskNames = windowTasks.prefix(3).map(\.title).joined(separator: " + ")
            return "\(taskNames) all land between \(startLabel) and \(endLabel). Start the earliest one today."
        }

        return nil
    }

    private var subjectHealthRows: [SubjectHealthRow] {
        let activeTasks = store.tasks.filter { !$0.isCompleted }
        let grouped = Dictionary(grouping: activeTasks, by: \.subject)
        return grouped.keys.sorted().map { subject in
            let tasks = grouped[subject] ?? []
            let averageConfidence = Int(Double(tasks.map(\.confidence).reduce(0, +)) / Double(max(tasks.count, 1)).rounded())
            let lastCompleted = store.tasks
                .filter { $0.subject == subject }
                .compactMap(\.completedAt)
                .max()
            let lastContext = store.sortedContexts
                .filter { $0.subject == subject }
                .map(\.createdAt)
                .max()
            let lastTouched = max(lastCompleted ?? .distantPast, lastContext ?? .distantPast)
            let daysSinceTouched = lastTouched == .distantPast ? 999 : Calendar.current.dateComponents([.day], from: lastTouched, to: .now).day ?? 0
            let status = averageConfidence <= 2 || daysSinceTouched >= 5 ? "Flagged" : "Healthy"

            return SubjectHealthRow(
                subject: subject,
                taskCount: tasks.count,
                averageConfidence: max(1, averageConfidence),
                lastTouchedText: lastTouched == .distantPast ? "No recent study signal." : "Last touched \(daysSinceTouched) day(s) ago.",
                status: status
            )
        }
    }

    private var headerDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: .now)
    }

    private var focusOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Focus mode")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .textCase(.uppercase)

                Text(activeFocusTask?.title ?? activeFocusBlock?.title ?? "Study block")
                    .font(.custom("Fraunces", size: 36))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 760)

                Text(focusRemainingText)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if let activeFocusBlock {
                    Text(activeFocusBlock.timeRange)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }

                if let context = activeFocusContext {
                    TimedCard(title: "Most relevant context", icon: "text.book.closed") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(context.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)

                            Text(context.summary)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.76))

                            Text(context.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(10)
                        }
                    }
                    .frame(maxWidth: 760)
                }

                HStack(spacing: 10) {
                    Button("End and debrief") {
                        if let activeFocusBlock {
                            presentDebrief(for: activeFocusBlock)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(32)
        }
    }

    private var activeFocusTask: TaskItem? {
        let focusTaskID = activeFocusBlock?.taskID ?? activeFocusTaskID
        guard let focusTaskID else { return nil }
        return store.tasks.first(where: { $0.id == focusTaskID })
    }

    private var activeFocusContext: ContextItem? {
        guard let activeFocusTask else { return nil }
        return store.groundedStudyContexts(for: activeFocusTask).first
    }

    private var focusRemainingText: String {
        guard let activeFocusBlock else { return "00:00" }
        let remaining = max(0, Int(activeFocusBlock.end.timeIntervalSince(focusNow)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func beginFocus(with block: ScheduleBlock) {
        activeFocusBlock = block
        activeFocusTaskID = block.taskID
        focusNow = .now
        debriefCovered = ""
        debriefBlockers = ""
        debriefConfidence = Double(store.tasks.first(where: { $0.id == block.taskID })?.confidence ?? 3)

        if let task = store.tasks.first(where: { $0.id == block.taskID }) {
            selectedStudySubject = task.subject
            expandedStudySubject = task.subject
            store.selectTask(task)
            centerTabRawValue = CenterTab.study.rawValue
            showRight = true
        }
    }

    private func presentDebrief(for block: ScheduleBlock) {
        activeFocusTaskID = block.taskID
        debriefConfidence = Double(store.tasks.first(where: { $0.id == block.taskID })?.confidence ?? 3)
        activeFocusBlock = nil
        showDebriefSheet = true
    }

    private func saveDebrief() {
        guard let activeFocusTaskID else {
            showDebriefSheet = false
            return
        }

        store.recordStudyDebrief(
            taskID: activeFocusTaskID,
            confidence: Int(debriefConfidence.rounded()),
            covered: debriefCovered,
            blockers: debriefBlockers,
            at: .now
        )
        centerTabRawValue = CenterTab.study.rawValue
        showRight = true
        showDebriefSheet = false
        self.activeFocusTaskID = nil
        debriefCovered = ""
        debriefBlockers = ""
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func clearSearchPreview() {
        selectedSearchDocumentID = nil
        selectedSearchContextID = nil
    }

    private func badge(text: String, emphasis: BadgeEmphasis) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(emphasis == .primary ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private func selectionBorder(isSelected: Bool, isFocused: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                isSelected
                    ? Color.white.opacity(isFocused ? 0.78 : 0.22)
                    : Color.clear,
                lineWidth: isFocused ? 2 : 1
            )
    }

    private func taskLibrarySort(lhs: TaskItem, rhs: TaskItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return rhs.isCompleted == false
        }
        return lhs.title < rhs.title
    }

    private func icon(for source: TaskSource) -> String {
        switch source {
        case .codexMem:
            return "brain"
        case .seqta:
            return "graduationcap"
        case .tickTick:
            return "checklist"
        case .transcript:
            return "doc.text"
        case .chat:
            return "message"
        }
    }

    private var keyboardNavigableTasks: [TaskItem] {
        rankedTasksForPlan.map(\.task)
    }

    private var currentKeyboardSelectedTask: TaskItem? {
        guard !keyboardNavigableTasks.isEmpty else { return nil }
        let safeIndex = min(max(selectedTaskIndex, 0), keyboardNavigableTasks.count - 1)
        return keyboardNavigableTasks[safeIndex]
    }

    private func syncSelectedTaskIndex(preferredTaskID: String? = nil) {
        let tasks = keyboardNavigableTasks
        guard !tasks.isEmpty else {
            selectedTaskIndex = 0
            return
        }

        let targetID = preferredTaskID ?? store.selectedTaskID

        if let targetID, let matchedIndex = tasks.firstIndex(where: { $0.id == targetID }) {
            selectedTaskIndex = matchedIndex
            return
        }

        selectedTaskIndex = min(selectedTaskIndex, tasks.count - 1)

        if let fallbackTask = tasks[safe: selectedTaskIndex], store.selectedTaskID != fallbackTask.id {
            store.selectTask(fallbackTask)
        }
    }

    @discardableResult
    private func handleRankedTaskMovement(delta: Int) -> KeyPress.Result {
        guard focusedPanel == .center, !isStudyMode, selectedCenterTab == .plan else {
            return .ignored
        }

        let tasks = keyboardNavigableTasks
        guard !tasks.isEmpty else { return .handled }

        let newIndex = min(max(selectedTaskIndex + delta, 0), tasks.count - 1)
        guard tasks.indices.contains(newIndex) else { return .handled }

        selectedTaskIndex = newIndex
        let task = tasks[newIndex]
        store.selectTask(task)
        return .handled
    }

    @discardableResult
    private func openFocusedRankedTask() -> KeyPress.Result {
        guard focusedPanel == .center, !isStudyMode, selectedCenterTab == .plan else {
            return .ignored
        }

        guard let task = currentKeyboardSelectedTask else {
            return .handled
        }

        selectTaskForContext(task)
        focusedPanel = .right
        return .handled
    }

    private func selectRankedTask(_ task: TaskItem) {
        if let index = keyboardNavigableTasks.firstIndex(where: { $0.id == task.id }) {
            selectedTaskIndex = index
        }
        store.selectTask(task)
    }

    private func startFocusTimerForSelectedTask() {
        guard let task = currentKeyboardSelectedTask ?? store.selectedTask ?? rankedTasksForPlan.first?.task else {
            return
        }
        focusedPanel = .center
        startFocusTimer(for: task)
    }

    private func panelFocusBorder(for panel: PlannerPanel) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(
                focusedPanel == panel
                    ? Color.white.opacity(0.28)
                    : Color.clear,
                lineWidth: 2
            )
    }

    private var orderedPanels: [PlannerPanel] {
        var panels: [PlannerPanel] = []
        if showLeft {
            panels.append(.left)
        }
        panels.append(.center)
        if isContextDrawerVisible {
            panels.append(.right)
        }
        return panels
    }

    private func normalizeFocusedPanel() {
        let panels = orderedPanels
        guard !panels.isEmpty else {
            focusedPanel = nil
            return
        }

        if let focusedPanel, panels.contains(focusedPanel) {
            return
        }

        focusedPanel = panels.contains(.center) ? .center : panels[0]
    }

    private func cycleFocusedPanel(backward: Bool) {
        guard !isStudyMode else { return }
        let panels = orderedPanels
        guard !panels.isEmpty else { return }

        let currentIndex = panels.firstIndex(of: focusedPanel ?? .center) ?? 0
        let nextIndex: Int

        if backward {
            nextIndex = currentIndex == 0 ? panels.count - 1 : currentIndex - 1
        } else {
            nextIndex = currentIndex == panels.count - 1 ? 0 : currentIndex + 1
        }

        focusedPanel = panels[nextIndex]
    }

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleLocalKeyEvent(event)
        }
    }

    private func removeLocalKeyMonitor() {
        guard let localKeyMonitor else { return }
        NSEvent.removeMonitor(localKeyMonitor)
        self.localKeyMonitor = nil
    }

    private func handleLocalKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard shouldHandleGlobalPlannerKeys else { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 48 {
            cycleFocusedPanel(backward: modifiers.contains(.shift))
            return nil
        }

        if modifiers.isEmpty, event.characters == "?" {
            showKeyboardShortcutsHelp = true
            return nil
        }

        return event
    }

    private var shouldHandleGlobalPlannerKeys: Bool {
        guard !showAddTaskSheet,
              !showSearchPanel,
              !showCommandPalette,
              !showDebriefSheet,
              activeQuizSession == nil,
              !isTextInputFocused
        else {
            return false
        }

        return true
    }

    private var isTextInputFocused: Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else { return false }
        return firstResponder is NSTextView
    }
}

private enum PlannerPanel: Hashable {
    case left
    case center
    case right
}

private enum CenterTab: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case chat = "Chat"
    case study = "Study"
    case day = "Day"

    var id: String { rawValue }
}

private enum BadgeEmphasis {
    case primary
    case secondary
}

private struct WeekStripItem: Identifiable {
    let date: Date
    let label: String
    let count: Int
    let color: Color

    var id: String { "\(date.timeIntervalSince1970)" }
}

private struct SubjectHealthRow: Identifiable {
    let subject: String
    let taskCount: Int
    let averageConfidence: Int
    let lastTouchedText: String
    let status: String

    var id: String { subject }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private struct HeaderActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .tint(.white.opacity(0.22))
    }
}

private struct PromptBubble: View {
    let message: PromptMessage
    let isHighlighted: Bool

    init(message: PromptMessage, isHighlighted: Bool = false) {
        self.message = message
        self.isHighlighted = isHighlighted
    }

    var body: some View {
        HStack {
            if message.role == .tutor || message.role == .assistant {
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
    }

    private var bubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .padding(8)
                .background(Circle().fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(message.role.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.54))

                    if message.isPinned {
                        Label("Pinned", systemImage: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }

                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isHighlighted
                        ? Color.white.opacity(0.16)
                        : (message.isQuiz ? Color.white.opacity(0.1) : Color.white.opacity(0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isHighlighted ? 0.22 : 0.1), lineWidth: 1)
        )
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }

    private var iconName: String {
        switch message.role {
        case .assistant:
            return "sparkles"
        case .tutor:
            return "questionmark.circle"
        case .student:
            return "person.fill"
        case .user:
            return "person.crop.circle"
        }
    }
}

private struct PromptConversationCard: View {
    let title: String
    let icon: String
    let messages: [PromptMessage]
    let highlightedMessageID: UUID?
    let errorState: PromptErrorState?
    let onRetry: (() -> Void)?
    let onDismissError: (() -> Void)?

    var body: some View {
        TimedCard(title: title, icon: icon) {
            PromptConversationList(
                messages: messages,
                highlightedMessageID: highlightedMessageID,
                errorState: errorState,
                onRetry: onRetry,
                onDismissError: onDismissError
            )
        }
    }
}

private struct PromptConversationList: View {
    let messages: [PromptMessage]
    let highlightedMessageID: UUID?
    let errorState: PromptErrorState?
    let onRetry: (() -> Void)?
    let onDismissError: (() -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            conversationContent(proxy: proxy)
        }
    }

    private func conversationContent(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorState, let onRetry, let onDismissError {
                PromptErrorBanner(error: errorState, onRetry: onRetry, onDismiss: onDismissError)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if messages.isEmpty {
                EmptyStateView(
                    systemImage: "message",
                    title: "No chat yet",
                    subtitle: "Ask Timed to plan, study, or quiz and the conversation will appear here."
                )
            }

            ForEach(messages) { message in
                PromptBubble(
                    message: message,
                    isHighlighted: highlightedMessageID == message.id
                )
                .id(message.id)
            }
        }
        .animation(.spring(response: 0.3), value: messages.map(\.id))
        .animation(.spring(response: 0.3), value: errorState?.id)
        .onChange(of: highlightedMessageID) { _, messageID in
            scrollToChatMessage(messageID, with: proxy)
        }
        .onAppear {
            scrollToChatMessage(highlightedMessageID, with: proxy)
        }
    }

    private func scrollToChatMessage(_ messageID: UUID?, with proxy: ScrollViewProxy) {
        guard let messageID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(messageID, anchor: .center)
            }
        }
    }
}

private struct CommandPaletteSheet: View {
    @Binding var query: String
    let onRun: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Command palette")
                .font(.system(size: 18, weight: .bold))

            TextField("quiz maths · import memory · sync vault · done task name", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let currentQuery = query
                    dismiss()
                    onRun(currentQuery)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text("Examples")
                    .font(.system(size: 13, weight: .semibold))
                Text("quiz maths")
                Text("plan 3h")
                Text("done economics test")
                Text("import seqta")
                Text("import memory")
                Text("add maths worksheet")
                Text("sync vault")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Run") {
                    let currentQuery = query
                    dismiss()
                    onRun(currentQuery)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

private struct AddTaskSheet: View {
    @Binding var draft: AddTaskDraft
    @Binding var errorMessage: String?
    let onSave: (AddTaskDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var subjectWasEditedManually = false
    @State private var importanceWasEditedManually = false
    @State private var dueDateWasEditedManually = false
    private let parser = NLTaskParser()

    var body: some View {
        NavigationStack {
            Form {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Task or natural language", text: $draft.title)

                    if !previewChips.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(previewChips, id: \.label) { chip in
                                    previewChip(icon: chip.icon, label: chip.label)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Picker("Subject", selection: subjectBinding) {
                    Text("Select subject").tag("")
                    ForEach(SubjectCatalog.supported, id: \.self) { subject in
                        Text(subject).tag(subject)
                    }
                }
                Stepper("Estimate \(draft.estimateMinutes) min", value: $draft.estimateMinutes, in: 5...300, step: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Importance \(Int(draft.importance.rounded()))")
                    Slider(value: importanceBinding, in: 1...10, step: 1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Confidence \(Int(draft.confidence.rounded()))")
                    Slider(value: $draft.confidence, in: 1...5, step: 1)
                }
                Toggle("Set due date", isOn: hasDueDateBinding)
                if draft.dueDate != nil {
                    DatePicker("Due date", selection: dueDateBinding, displayedComponents: [.date, .hourAndMinute])
                }
                Picker("Energy", selection: $draft.energy) {
                    ForEach(TaskEnergy.allCases) { energy in
                        Text(energy.rawValue).tag(energy)
                    }
                }
                Picker("Source", selection: $draft.source) {
                    ForEach(TaskSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 120)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(resolvedDraftForSave)
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
        .onAppear {
            applyNaturalLanguageAutofill(for: draft.title)
        }
        .onChange(of: draft.title) { _, newValue in
            applyNaturalLanguageAutofill(for: newValue)
        }
    }

    private var subjectBinding: Binding<String> {
        Binding(
            get: { draft.subject },
            set: { newValue in
                subjectWasEditedManually = true
                draft.subject = newValue
            }
        )
    }

    private var importanceBinding: Binding<Double> {
        Binding(
            get: { draft.importance },
            set: { newValue in
                importanceWasEditedManually = true
                draft.importance = newValue
            }
        )
    }

    private var hasDueDateBinding: Binding<Bool> {
        Binding(
            get: { draft.dueDate != nil },
            set: { enabled in
                dueDateWasEditedManually = true
                draft.dueDate = enabled ? (draft.dueDate ?? defaultDueDate()) : nil
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { draft.dueDate ?? defaultDueDate() },
            set: { newValue in
                dueDateWasEditedManually = true
                draft.dueDate = newValue
            }
        )
    }

    private var resolvedDraftForSave: AddTaskDraft {
        let parsed = parser.parse(draft.title)
        var resolved = draft
        let parsedTitle = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)

        resolved.title = parsedTitle.isEmpty ? draft.title.trimmingCharacters(in: .whitespacesAndNewlines) : parsedTitle

        if !subjectWasEditedManually, let parsedSubject = parsed.subject {
            resolved.subject = parsedSubject
        }

        if !importanceWasEditedManually, let parsedImportance = parsed.importance {
            resolved.importance = Double(parsedImportance)
        }

        if !dueDateWasEditedManually, let parsedDueDate = parsed.dueDate {
            resolved.dueDate = parsedDueDate
        }

        return resolved
    }

    private var previewChips: [(icon: String, label: String)] {
        let resolved = resolvedDraftForSave
        var chips: [(icon: String, label: String)] = [
            ("star.fill", "\(Int(resolved.importance.rounded()))")
        ]

        if let dueDate = resolved.dueDate {
            chips.append(("calendar", dueDateChipLabel(for: dueDate)))
        }

        if !resolved.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(("book.closed", resolved.subject))
        }

        return chips
    }

    private func applyNaturalLanguageAutofill(for input: String) {
        let parsed = parser.parse(input)

        if !subjectWasEditedManually, let parsedSubject = parsed.subject {
            draft.subject = parsedSubject
        } else if !subjectWasEditedManually, parsed.subject == nil {
            draft.subject = ""
        }

        if !importanceWasEditedManually, let parsedImportance = parsed.importance {
            draft.importance = Double(parsedImportance)
        } else if !importanceWasEditedManually, parsed.importance == nil {
            draft.importance = 5
        }

        if !dueDateWasEditedManually {
            draft.dueDate = parsed.dueDate
        }
    }

    private func previewChip(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func dueDateChipLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private func defaultDueDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(
            bySettingHour: 17,
            minute: 0,
            second: 0,
            of: tomorrow
        ) ?? tomorrow
    }
}

private struct StudyDebriefSheet: View {
    @Binding var confidence: Double
    @Binding var covered: String
    @Binding var blockers: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Study debrief")
                .font(.system(size: 18, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                Text("How confident are you now? \(Int(confidence.rounded()))/5")
                    .font(.system(size: 13, weight: .semibold))
                Slider(value: $confidence, in: 1...5, step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What did you cover?")
                    .font(.system(size: 13, weight: .semibold))
                TextEditor(text: $covered)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Any blockers?")
                    .font(.system(size: 13, weight: .semibold))
                TextEditor(text: $blockers)
                    .frame(minHeight: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()
                Button("Save debrief", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

private struct ImportReviewSheet: View {
    @Bindable var store: PlannerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Review imported tasks")
                    .font(.system(size: 15, weight: .semibold))

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let messages = store.pendingImportBatch?.messages, !messages.isEmpty {
                            ForEach(messages, id: \.self) { message in
                                Text(message)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        ForEach(taskDraftIndices, id: \.self) { index in
                            if let binding = bindingForDraft(at: index) {
                                ImportDraftEditor(draft: binding)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .navigationTitle("Import review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        store.discardPendingImport()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply import") {
                        store.applyPendingImport()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 640)
    }

    private func bindingForDraft(at index: Int) -> Binding<ImportTaskDraft>? {
        guard store.pendingImportBatch?.taskDrafts.indices.contains(index) == true else { return nil }
        return Binding(
            get: { store.pendingImportBatch!.taskDrafts[index] },
            set: { store.pendingImportBatch!.taskDrafts[index] = $0 }
        )
    }

    private var taskDraftIndices: [Int] {
        if let drafts = store.pendingImportBatch?.taskDrafts {
            return Array(drafts.indices)
        }
        return []
    }
}

private struct ImportDraftEditor: View {
    @Binding var draft: ImportTaskDraft

    var body: some View {
        TimedCard(title: draft.title, icon: "square.and.pencil") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $draft.title)
                Picker("Subject", selection: $draft.subject) {
                    ForEach(SubjectCatalog.supported, id: \.self) { subject in
                        Text(subject).tag(subject)
                    }
                }
                Stepper("Estimate \(draft.estimateMinutes) min", value: $draft.estimateMinutes, in: 5...240, step: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Importance \(draft.importance)")
                    Slider(
                        value: Binding(
                            get: { Double(draft.importance) },
                            set: { draft.importance = Int($0.rounded()) }
                        ),
                        in: 1...5,
                        step: 1
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Confidence \(draft.confidence)")
                    Slider(
                        value: Binding(
                            get: { Double(draft.confidence) },
                            set: { draft.confidence = Int($0.rounded()) }
                        ),
                        in: 1...5,
                        step: 1
                    )
                }
                DatePicker("Due date", selection: $draft.dueDate, displayedComponents: [.date, .hourAndMinute])
            }
        }
    }
}

private extension Calendar {
    func endOfDay(for targetDate: Date) -> Date {
        let start = startOfDay(for: targetDate)
        return self.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? targetDate
    }
}
