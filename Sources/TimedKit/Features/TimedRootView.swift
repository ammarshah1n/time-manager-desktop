#if os(macOS)
// TimedRootView.swift — Timed macOS V2
// Sidebar: Today → Triage → WORK (buckets + Waiting) → TOOLS (Capture, Calendar) → Settings
// Morning Interview auto-shows on open. Dish Me Up via sheet.

import SwiftUI
import Dependencies

struct TimedRootView: View {
    @AppStorage("hasCompletedOnboarding")       private var hasCompletedOnboarding: Bool = false
    @AppStorage("lastMorningInterviewDate")     private var lastMorningInterviewDate: String = ""

    @State private var selection: NavSection? = .dishMeUp
    @State private var triageItems: [TriageItem] = []
    @State private var tasks: [TimedTask] = []
    @State private var taskSections: [TaskSection] = []
    @State private var blocks: [CalendarBlock] = []
    @State private var wooItems: [WOOItem] = []
    @State private var captureItems: [CaptureItem] = []
    @State private var freeTimeSlots: [FreeTimeSlot] = []

    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var auth = AuthService.shared
    @StateObject private var alerts = AlertsPresenter.shared
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @State private var showMorningInterview = false
    @State private var morningDone          = false
    @State private var showDishMeUp         = false
    @State private var focusTask: TimedTask? = nil
    @State private var showFocus: Bool = false
    @State private var showCommandPalette = false

    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        rootSplitView
    }

    private func saveTasks(_ v: [TimedTask]) {
        let workspaceId = auth.activeOrPrimaryWorkspaceId
        Task { @MainActor in
            guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }
            try? await DataBridge.shared.saveTasks(v, workspaceId: workspaceId)
        }
    }
    private func saveTaskSections(_ v: [TaskSection]) {
        let workspaceId = auth.activeOrPrimaryWorkspaceId
        Task { @MainActor in
            guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }
            try? await DataBridge.shared.saveTaskSections(v, workspaceId: workspaceId)
        }
    }
    private func saveTriage(_ v: [TriageItem])    { Task { try? await DataBridge.shared.saveTriageItems(v) } }
    private func saveWOO(_ v: [WOOItem])          { Task { try? await DataBridge.shared.saveWOOItems(v) } }
    private func saveBlocks(_ v: [CalendarBlock])   { Task { try? await DataBridge.shared.saveBlocks(v) } }
    private func saveCaptures(_ v: [CaptureItem])   { Task { try? await DataBridge.shared.saveCaptureItems(v) } }
    private func deleteTasks(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let workspaceId = auth.activeOrPrimaryWorkspaceId
        Task { @MainActor in
            var latest = tasks
            for id in ids {
                if let updated = try? await DataBridge.shared.delete(id: id) {
                    latest = updated
                }
            }
            guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }
            tasks = latest
            syncMenuBar()
        }
    }

    private var rootSplitView: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .background(persistenceObserver)
        .onAppear { loadData(); checkMorningInterview(); network.start(); wireMenuBar() }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                if !network.isConnected {
                    Text("Offline")
                        .font(TimedType.caption2)
                        .foregroundStyle(Color.Timed.labelSecondary)
                }

                if let alert = alerts.currentAlert {
                    AlertDeliveryView(
                        alert: alert,
                        onAcknowledge: { alerts.acknowledge() },
                        onDismiss: { alerts.dismiss() },
                        onActionable: { alerts.recordActionable($0) }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
            .animation(TimedMotion.springy, value: alerts.currentAlert?.id)
        }
        .onChange(of: auth.graphAccessToken) { _, newToken in
            if newToken != nil {
                startEmailSyncIfReady()
                startCalendarSyncIfReady()
            }
        }
        .onChange(of: auth.googleAccessToken) { _, newToken in
            if newToken != nil {
                startGmailSyncIfReady()
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn {
                Task { await fetchFromSupabaseIfConnected() }
            }
        }
        .onChange(of: auth.activeWorkspaceId) { _, _ in
            let workspaceId = auth.activeOrPrimaryWorkspaceId
            resetWorkspaceScopedState()
            Task { await fetchFromSupabaseIfConnected(expectedWorkspaceId: workspaceId) }
        }
        .sheet(isPresented: onboardingBinding) { onboardingSheet }
        .sheet(isPresented: $showMorningInterview) { morningInterviewSheet }
        .sheet(isPresented: $showDishMeUp) { dishMeUpSheet }
        .sheet(isPresented: $showFocus) {
            FocusPane(task: focusTask, onComplete: { showFocus = false; focusTask = nil }, onSessionComplete: { taskId, actualMinutes in
                if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
                    tasks[idx].isDone = true
                }
            })
                .frame(minWidth: 600, minHeight: 680)
        }
        .onKeyPress(keys: [.init("k")], phases: .down) { keyPress in
            guard keyPress.modifiers == .command else { return .ignored }
            showCommandPalette.toggle()
            return .handled
        }
        .overlay {
            if showCommandPalette {
                CommandPaletteView(
                    isPresented: $showCommandPalette,
                    actions: paletteActions
                )
            }
        }
    }

    private var paletteActions: [PaletteAction] {
        ActionRegistry.actions(
            navigate: { section in selection = section },
            showMorningInterview: { showMorningInterview = true },
            showFocus: { task in focusTask = task; showFocus = true },
            addTask: {
                // Navigate to Action bucket where new task can be created
                selection = .tasks(.action)
            }
        )
    }

    @ViewBuilder private var persistenceObserver: some View {
        Color.clear
            .onChange(of: tasks)       { (_: [TimedTask],     v: [TimedTask])     in saveTasks(v); syncMenuBar() }
            .onChange(of: taskSections) { (_: [TaskSection],   v: [TaskSection])   in saveTaskSections(v) }
            .onChange(of: triageItems) { (_: [TriageItem],    v: [TriageItem])    in saveTriage(v) }
            .onChange(of: wooItems)    { (_: [WOOItem],       v: [WOOItem])       in saveWOO(v) }
            .onChange(of: blocks)        { (_: [CalendarBlock], v: [CalendarBlock]) in saveBlocks(v); syncMenuBar() }
            .onChange(of: captureItems)  { (_: [CaptureItem],   v: [CaptureItem])   in saveCaptures(v) }
    }

    // MARK: - Helpers broken out to avoid type-checker timeout

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !hasCompletedOnboarding }, set: { _ in })
    }

    @ViewBuilder private var onboardingSheet: some View {
        // Voice-led setup. The orb speaks, Yasser speaks, no typing, no clicking.
        // voice-llm-proxy branches on executives.onboarded_at — null routes to
        // the onboarding system prompt; the same ElevenLabs agent is reused.
        VoiceOnboardingView {
            hasCompletedOnboarding = true
            lastMorningInterviewDate = Self.ymd.string(from: Date())
            // Skip the old morning interview sheet on fresh setup — drop straight
            // into Dish Me Up. Voice check-in is on the hero for manual trigger.
            showMorningInterview = false
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var morningInterviewSheet: some View {
        MorningInterviewPane(tasks: $tasks, blocks: $blocks, isPresented: $showMorningInterview)
            .onDisappear {
                morningDone = true
                lastMorningInterviewDate = Self.ymd.string(from: Date())
            }
    }

    @ViewBuilder private var dishMeUpSheet: some View {
        DishMeUpSheet(tasks: $tasks, blocks: blocks) {
            showDishMeUp = false
        } onAccept: { firstTask in
            showDishMeUp = false
            focusTask = firstTask
            showFocus = true
        }
    }

    private func loadData() {
        Task {
            let localStore = DataStore.shared
            let bridge = DataBridge.shared
            let workspaceId = auth.activeOrPrimaryWorkspaceId

            // Load from local DataStore first (offline-first)
            if let v = try? await localStore.loadTasks(), !v.isEmpty {
                guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }
                tasks = v
            }
            if let v = try? await localStore.loadTaskSections(), !v.isEmpty {
                guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }
                taskSections = v
            }
            if let v = try? await bridge.loadTriageItems(),      !v.isEmpty { triageItems = v }
            if let v = try? await bridge.loadWOOItems(),         !v.isEmpty { wooItems    = v }
            if let v = try? await bridge.loadBlocks(),           !v.isEmpty { blocks      = v }
            if let v = try? await bridge.loadCaptureItems(),     !v.isEmpty { captureItems = v }

            // Start email sync if Graph token is available
            startEmailSyncIfReady()

            // Start calendar sync if Graph token is available
            startCalendarSyncIfReady()

            // Start Gmail + Google Calendar sync if a Google session was restored.
            startGmailSyncIfReady()

            // Fetch from Supabase if signed in (overlay on local data)
            guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }
            await fetchFromSupabaseIfConnected(expectedWorkspaceId: workspaceId)
        }
    }

    private func resetWorkspaceScopedState() {
        tasks = []
        taskSections = []
        focusTask = nil
        syncMenuBar()
    }

    private func fetchFromSupabaseIfConnected(expectedWorkspaceId: UUID? = nil) async {
        guard auth.isSignedIn,
              let profileId = auth.profileId else { return }
        let taskWorkspaceId = expectedWorkspaceId ?? auth.activeOrPrimaryWorkspaceId
        @Dependency(\.supabaseClient) var supa
        do {
            if let taskWorkspaceId {
                let dbTasks = try await supa.fetchTasks(taskWorkspaceId, profileId, ["pending", "in_progress"])
                guard auth.activeOrPrimaryWorkspaceId == taskWorkspaceId else { return }
                tasks = dbTasks.map(TimedTask.init(from:))
            }
            if let taskWorkspaceId {
                do {
                    let sectionRows = try await supa.fetchTaskSections(taskWorkspaceId)
                    guard auth.activeOrPrimaryWorkspaceId == taskWorkspaceId else { return }
                    taskSections = sectionRows.map(TaskSection.init(from:))
                } catch {
                    guard auth.activeOrPrimaryWorkspaceId == taskWorkspaceId else { return }
                    TimedLogger.supabase.error("Supabase section fetch failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            if let primaryWorkspaceId = auth.workspaceId {
                let dbEmails = try await supa.fetchEmailMessages(primaryWorkspaceId, "inbox", 100)
                if !dbEmails.isEmpty { triageItems = dbEmails.map(TriageItem.init(from:)) }
            }
        } catch {
            TimedLogger.supabase.error("Supabase fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startEmailSyncIfReady() {
        guard auth.graphAccessToken != nil,
              let wsId = auth.workspaceId,
              let eaId = auth.emailAccountId else { return }
        let tokenProvider = auth.makeTokenProvider()
        Task {
            await EmailSyncService.shared.start(
                tokenProvider: tokenProvider, workspaceId: wsId, emailAccountId: eaId,
                profileId: auth.profileId
            )
        }
    }

    private func startCalendarSyncIfReady() {
        guard auth.graphAccessToken != nil else { return }
        let tokenProvider = auth.makeTokenProvider()
        Task {
            do {
                let result = try await CalendarSyncService.shared.autoSync(tokenProvider: tokenProvider)
                blocks = result.blocks
                freeTimeSlots = result.freeSlots
            } catch {
                TimedLogger.calendar.error("Calendar auto-sync failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func startGmailSyncIfReady() {
        guard auth.googleAccessToken != nil,
              let executiveId = auth.executiveId else { return }
        Task {
            await auth.connectGmailIfPossible(executiveId: executiveId)
        }
    }

    private func checkMorningInterview() {
        let today = Self.ymd.string(from: Date())
        guard hasCompletedOnboarding && lastMorningInterviewDate != today else { return }

        // Skip morning interview during quiet hours
        let quietEnabled = UserDefaults.standard.bool(forKey: "prefs.quietHours.enabled")
        let quietEnd = UserDefaults.standard.integer(forKey: "prefs.quietHours.end")
        let currentHour = Calendar.current.component(.hour, from: Date())
        if quietEnabled && currentHour < quietEnd { return }

        showMorningInterview = true
    }

    // MARK: - Sidebar

    /// Default false — all screens visible. Toggle via Preferences (or debug).
    @AppStorage("v1BetaMode") private var v1BetaMode: Bool = false
    @State private var showAddSection = false
    @State private var newSectionTitle = ""
    @State private var newSectionBucket: TaskBucket = .action
    @State private var newSectionMode: WorkItemCreationMode = .planningBucket
    @State private var newSectionParentId: UUID?
    @State private var collapsedTaskSectionIds: Set<UUID> = []

    private var visibleTaskSections: [TaskSection] {
        let sections = taskSections.isEmpty ? TaskSection.defaultSystemSections : taskSections
        return sections.filter { section in
            !section.isArchived
                && !(section.isSystem && section.parentSectionId == nil && section.canonicalBucketType == TaskBucket.waiting.dbValue)
        }.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.title < rhs.title
        }
    }

    private var topLevelTaskSections: [TaskSection] {
        visibleTaskSections.filter { $0.parentSectionId == nil }
    }

    private func childSections(for parent: TaskSection) -> [TaskSection] {
        visibleTaskSections.filter { $0.parentSectionId == parent.id }
    }

    private func tasksForSection(_ section: TaskSection) -> [TimedTask] {
        let childIds = Set(childSections(for: section).map(\.id))
        return tasks.filter { task in
            if task.sectionId == section.id { return true }
            if let sectionId = task.sectionId, childIds.contains(sectionId) { return true }
            return section.isSystem && task.sectionId == nil && task.bucket.dbValue == section.canonicalBucketType
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selection) {
            Section { WorkspaceSwitcher() }

            SidebarRow(label: "Dish Me Up", icon: "play.circle",
                       isSelected: selection == .dishMeUp)
                .tag(NavSection.dishMeUp)

            SidebarRow(label: "Today", icon: "calendar",
                       isSelected: selection == .today)
                .tag(NavSection.today)

            SidebarRow(label: "Briefing", icon: "sparkles",
                       isSelected: selection == .briefing)
                .tag(NavSection.briefing)

            if !v1BetaMode {
                SidebarRow(label: "Triage", icon: "tray.and.arrow.down",
                           badge: triageItems.count,
                           isSelected: selection == .triage)
                    .tag(NavSection.triage)
            }

            Section {
                ForEach(topLevelTaskSections) { section in
                    let children = childSections(for: section)
                    sectionSidebarRow(
                        section,
                        indent: 0,
                        isCollapsible: !children.isEmpty,
                        isExpanded: isSectionExpanded(section)
                    )
                    if isSectionExpanded(section) {
                        ForEach(children) { child in
                            sectionSidebarRow(child, indent: 18)
                        }
                    }
                }

                if !v1BetaMode {
                    SidebarRow(label: "Waiting", icon: "clock.badge.questionmark",
                               badge: overdueWOOCount,
                               isSelected: selection == .waiting)
                        .tag(NavSection.waiting)
                }

                Button {
                    newSectionTitle = ""
                    newSectionBucket = .action
                    newSectionMode = .planningBucket
                    newSectionParentId = topLevelTaskSections.first?.id
                    showAddSection = true
                } label: {
                    SidebarRow(label: "Add Section", icon: "plus")
                }
                .buttonStyle(.plain)
            } header: {
                sidebarHeader("WORK")
            }

            Section {
                SidebarRow(label: "Capture", icon: "mic",
                           isSelected: selection == .capture)
                    .tag(NavSection.capture)

                SidebarRow(label: "Calendar", icon: "calendar",
                           isSelected: selection == .calendar)
                    .tag(NavSection.calendar)
            } header: {
                sidebarHeader("TOOLS")
            }

            Section {
                SidebarRow(label: "Settings", icon: "gearshape",
                           isSelected: selection == .prefs)
                    .tag(NavSection.prefs)
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showAddSection) {
            AddWorkItemSheet(
                title: $newSectionTitle,
                bucket: $newSectionBucket,
                mode: $newSectionMode,
                parentSectionId: $newSectionParentId,
                parentSections: topLevelTaskSections
            ) {
                addWorkItem()
                showAddSection = false
            } onCancel: {
                showAddSection = false
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .dishMeUp {
        case .dishMeUp:
            DishMeUpHomeView()
        case .today:
            TodayPane(
                tasks: $tasks,
                blocks: $blocks,
                triageCount: triageItems.count,
                morningDone: morningDone,
                freeTimeSlots: freeTimeSlots,
                onStartMorning: { showMorningInterview = true },
                onDishMeUp: { showDishMeUp = true }
            )
        case .triage:
            TriagePane(items: $triageItems, tasks: $tasks) {
                selection = .prefs
            }
        case .tasks(let bucket):
            TasksPane(bucket: bucket, section: nil, taskSections: $taskSections, tasks: $tasks, blocks: $blocks, onDeleteTasks: deleteTasks)
        case .taskSection(let sectionId):
            let section = visibleTaskSections.first { $0.id == sectionId }
            TasksPane(
                bucket: section?.bucket ?? .action,
                section: section,
                taskSections: $taskSections,
                tasks: $tasks,
                blocks: $blocks,
                onDeleteTasks: deleteTasks
            )
        case .waiting:
            WaitingPane(items: $wooItems, tasks: $tasks)
        case .capture:
            CapturePane(tasks: $tasks, items: $captureItems)
        case .calendar:
            CalendarPane(blocks: $blocks)
        case .briefing:
            MorningBriefingPane()
        case .prefs:
            PrefsPane()
        }
    }

    // MARK: - Helpers

    private var overdueWOOCount: Int {
        wooItems.filter { item in
            guard let expected = item.expectedByDate else { return false }
            return expected < Date()
        }.count
    }

    private func timeHint(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : (minutes % 60 == 0 ? "\(minutes/60)h" : "\(minutes/60)h\(minutes%60)m")
    }

    @ViewBuilder
    private func sectionSidebarRow(
        _ section: TaskSection,
        indent: CGFloat,
        isCollapsible: Bool = false,
        isExpanded: Bool = true
    ) -> some View {
        let sectionTasks = tasksForSection(section).filter { !$0.isDone }
        let totalMins = sectionTasks.reduce(0) { $0 + $1.estimatedMinutes }
        let bucket = section.bucket

        SidebarRow(
            label: section.title,
            icon: bucket?.icon ?? "folder",
            disclosureState: isCollapsible ? isExpanded : nil,
            dotColor: bucket?.dotColor,
            badge: sectionTasks.count,
            timeHint: totalMins > 0 ? timeHint(totalMins) : nil,
            isSelected: selection == .taskSection(section.id),
            indent: indent,
            onToggleDisclosure: isCollapsible ? { toggleSectionExpansion(section) } : nil
        )
        .tag(NavSection.taskSection(section.id))
    }

    private func isSectionExpanded(_ section: TaskSection) -> Bool {
        !collapsedTaskSectionIds.contains(section.id)
    }

    private func toggleSectionExpansion(_ section: TaskSection) {
        if collapsedTaskSectionIds.contains(section.id) {
            collapsedTaskSectionIds.remove(section.id)
        } else {
            collapsedTaskSectionIds.insert(section.id)
        }
    }

    private func addWorkItem() {
        let trimmedTitle = newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        var sections = taskSections.isEmpty ? TaskSection.defaultSystemSections : taskSections
        let parentId: UUID?
        let canonicalBucketType: String
        let sortOrder: Int

        switch newSectionMode {
        case .planningBucket:
            parentId = nil
            canonicalBucketType = newSectionBucket.dbValue
            sortOrder = (sections.filter { $0.parentSectionId == nil }.map(\.sortOrder).max() ?? 0) + 1
        case .section:
            guard let selectedParentId = newSectionParentId ?? topLevelTaskSections.first?.id,
                  let parent = sections.first(where: { $0.id == selectedParentId }) else { return }
            parentId = parent.id
            canonicalBucketType = parent.canonicalBucketType
            sortOrder = (sections.filter { $0.parentSectionId == parent.id }.map(\.sortOrder).max() ?? 0) + 1
        }

        sections.append(TaskSection(
            id: UUID(),
            parentSectionId: parentId,
            title: trimmedTitle,
            canonicalBucketType: canonicalBucketType,
            sortOrder: sortOrder,
            colorKey: canonicalBucketType,
            isSystem: false,
            isArchived: false
        ))
        taskSections = sections
    }

    @ViewBuilder
    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(TimedType.caption2)
            .foregroundStyle(Color.Timed.labelTertiary)
            .tracking(1.2)
    }

    // MARK: - Menu Bar Integration

    private func wireMenuBar() {
        menuBarManager.onStartFocus = { task in
            focusTask = task
            showFocus = true
            NSApp.activate(ignoringOtherApps: true)
        }

        menuBarManager.onMarkComplete = { taskId in
            if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[idx].isDone = true
            }
        }

        menuBarManager.onQuickCapture = { text in
            let parsed = TranscriptParser.parse(text)
            let newItems: [CaptureItem]
            if parsed.isEmpty {
                newItems = [CaptureItem(
                    id: UUID(), inputType: .text,
                    rawText: text, parsedTitle: text,
                    suggestedBucket: .action, suggestedMinutes: 15,
                    capturedAt: Date()
                )]
            } else {
                newItems = parsed.map { p in
                    CaptureItem(
                        id: p.id, inputType: .text,
                        rawText: text, parsedTitle: p.title,
                        suggestedBucket: bucketFromParser(p.bucketType),
                        suggestedMinutes: p.estimatedMinutes ?? 15,
                        capturedAt: Date()
                    )
                }
            }
            captureItems.insert(contentsOf: newItems, at: 0)
        }

        syncMenuBar()
    }

    private func syncMenuBar() {
        let focusName = focusTask?.title
        let undone = tasks.filter { !$0.isDone }

        // Next calendar event
        let now = Date()
        let upcoming = blocks
            .filter { $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
        let nextBlock = upcoming.first
        let nextName = nextBlock?.title
        let nextIn = nextBlock.map { $0.startTime.timeIntervalSince(now) }

        menuBarManager.updateStatus(
            currentTask: focusName,
            elapsed: 0,
            nextEvent: nextName,
            nextEventIn: nextIn,
            remainingCount: undone.count,
            allTasks: tasks
        )
    }

    private func bucketFromParser(_ type: String) -> TaskBucket {
        switch type {
        case "calls":       return .calls
        case "reply_email": return .reply
        case "read_today":  return .readToday
        case "action":      return .action
        default:            return .action
        }
    }
}

// MARK: - Nav section enum

enum NavSection: Hashable {
    case dishMeUp
    case today
    case triage
    case tasks(TaskBucket)
    case taskSection(UUID)
    case waiting
    case capture
    case calendar
    case briefing
    case prefs
}

// MARK: - Sidebar row

private enum WorkItemCreationMode: String, CaseIterable, Identifiable {
    case planningBucket = "Planning Bucket"
    case section = "Section"

    var id: Self { self }
}

private struct AddWorkItemSheet: View {
    @Binding var title: String
    @Binding var bucket: TaskBucket
    @Binding var mode: WorkItemCreationMode
    @Binding var parentSectionId: UUID?
    let parentSections: [TaskSection]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $mode) {
                    ForEach(WorkItemCreationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Name", text: $title)

                if mode == .planningBucket {
                    Picker("Default behaviour", selection: $bucket) {
                        ForEach(TaskBucket.allCases.filter { $0 != .ccFyi }, id: \.self) { bucket in
                            Label(bucket.rawValue, systemImage: bucket.icon).tag(bucket)
                        }
                    }
                } else {
                    Picker("Planning bucket", selection: parentBinding) {
                        ForEach(parentSections) { section in
                            Label(section.title, systemImage: section.bucket?.icon ?? "folder")
                                .tag(Optional(section.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode == .planningBucket ? "New Planning Bucket" : "New Section")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: onSave)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if parentSectionId == nil {
                    parentSectionId = parentSections.first?.id
                }
            }
        }
        .frame(minWidth: 380, minHeight: 260)
    }

    private var parentBinding: Binding<UUID?> {
        Binding(
            get: { parentSectionId ?? parentSections.first?.id },
            set: { parentSectionId = $0 }
        )
    }
}

struct AddSectionSheet: View {
    @Binding var title: String
    @Binding var bucket: TaskBucket
    let heading: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $title)
                Picker("Planning bucket", selection: $bucket) {
                    ForEach(TaskBucket.allCases.filter { $0 != .ccFyi }, id: \.self) { bucket in
                        Label(bucket.rawValue, systemImage: bucket.icon).tag(bucket)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(heading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: onSave)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 220)
    }
}

struct SidebarRow: View {
    let label: String
    let icon: String
    var disclosureState: Bool? = nil
    var dotColor: Color? = nil
    var badge: Int = 0
    var timeHint: String? = nil
    var isSelected: Bool = false
    var indent: CGFloat = 0
    var onToggleDisclosure: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: TimedLayout.Spacing.xs) {
            if let disclosureState {
                Button {
                    onToggleDisclosure?()
                } label: {
                    Image(systemName: disclosureState ? "chevron.down" : "chevron.right")
                        .font(TimedType.caption2)
                        .foregroundStyle(Color.Timed.labelTertiary)
                        .frame(width: TimedLayout.Spacing.sm)
                }
                .buttonStyle(.plain)
            }

            Image(systemName: icon)
                .font(TimedType.subheadline)
                .foregroundStyle(isSelected ? Color.Timed.labelPrimary : Color.Timed.labelSecondary)
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))

            if let dotColor {
                BucketDot(color: dotColor)
            }

            Text(label)
                .font(TimedType.subheadline)
                .foregroundStyle(Color.Timed.labelPrimary)
                .fontWeight(isSelected ? .semibold : .regular)

            Spacer()

            if let hint = timeHint {
                Text(hint)
                    .font(TimedType.caption2)
                    .foregroundStyle(Color.Timed.labelTertiary)
            }

            if badge > 0 {
                Text("\(badge)")
                    .font(TimedType.caption)
                    .foregroundStyle(Color.Timed.labelTertiary)
            }
        }
        .padding(.leading, indent)
        .animation(TimedMotion.smooth, value: isSelected)
    }
}

#endif
