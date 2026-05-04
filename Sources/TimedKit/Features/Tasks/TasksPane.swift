#if os(macOS)
// TasksPane.swift — Timed macOS
// Per-bucket task list. Shows time totals, review cadence, and quick-block action.

import SwiftUI

struct TasksPane: View {
    let bucket: TaskBucket
    var section: TaskSection? = nil
    @Binding var taskSections: [TaskSection]
    @Binding var tasks: [TimedTask]
    @Binding var blocks: [CalendarBlock]
    var onDeleteTasks: ([UUID]) -> Void = { _ in }
    @State private var selected: TimedTask.ID?
    @State private var showBlockSheet = false
    @State private var blockTarget: TimedTask?
    @State private var detailTask: TimedTask?
    @State private var isSelecting: Bool = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showAddTask = false
    @State private var showAddSubsection = false
    @State private var subtaskParent: TimedTask?
    @State private var newTaskTitle = ""
    @State private var newTaskMinutes = 15
    @State private var newTaskImportance: TaskManualImportance = .blue
    @State private var newSubsectionTitle = ""
    @State private var newSubsectionBucket: TaskBucket = .action
    @State private var showDoneTasks = false

    var bucketTasks: [TimedTask] {
        guard let section else {
            return tasks.filter { $0.bucket == bucket }
        }
        let sectionIds = Set(([section] + childSections(for: section)).map(\.id))
        return tasks.filter { task in
            if let sectionId = task.sectionId, sectionIds.contains(sectionId) { return true }
            return section.isSystem && task.sectionId == nil && task.bucket.dbValue == section.canonicalBucketType
        }
    }

    var totalMins: Int {
        activeRootTasks.reduce(0) { $0 + $1.estimatedMinutes }
    }

    private var activeBucket: TaskBucket { section?.bucket ?? bucket }
    private var title: String { section?.title ?? bucket.rawValue }
    private var activeRootTasks: [TimedTask] {
        bucketTasks
            .filter { !$0.isDone && $0.parentTaskId == nil }
            .sorted(by: taskSort)
    }
    private var doneTasks: [TimedTask] {
        bucketTasks
            .filter(\.isDone)
            .sorted(by: taskSort)
    }
    private var selectableTasks: [TimedTask] {
        activeRootTasks
    }

    var body: some View {
        VStack(spacing: 0) {
            bucketHeader
            Divider()

            if bucketTasks.isEmpty {
                emptyState
            } else {
                List(selection: $selected) {
                    ForEach(activeRootTasks) { task in
                        taskRow(task)
                        ForEach(subtasks(for: task).filter { !$0.isDone }) { subtask in
                            taskRow(subtask)
                                .padding(.leading, TimedLayout.Spacing.xl)
                        }
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { activeRootTasks[$0].id }
                        onDeleteTasks(ids)
                    }

                    if !doneTasks.isEmpty {
                        DisclosureGroup(isExpanded: $showDoneTasks) {
                            ForEach(doneTasks) { task in
                                taskRow(task)
                                    .opacity(0.55)
                            }
                        } label: {
                            Text("Done")
                                .font(TimedType.caption.weight(.semibold))
                                .foregroundStyle(Color.Timed.labelSecondary)
                        }
                    }
                }
                .listStyle(.plain)
            }

            // Bulk action bar
            if isSelecting && !selectedIds.isEmpty {
                bulkActionBar
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Add Task", systemImage: "plus") {
                    prepareNewTask()
                    showAddTask = true
                }
                if section != nil {
                    Button("Add Subsection", systemImage: "folder.badge.plus") {
                        newSubsectionTitle = ""
                        newSubsectionBucket = activeBucket
                        showAddSubsection = true
                    }
                }
                if isSelecting && !selectableTasks.isEmpty {
                    Button("Select All") {
                        selectedIds = Set(selectableTasks.map(\.id))
                    }
                    Button("Deselect All") {
                        selectedIds.removeAll()
                    }
                }
                if !selectableTasks.isEmpty {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selectedIds.removeAll() }
                    }
                }
            }
        }
        .sheet(isPresented: $showBlockSheet) {
            if let task = blockTarget {
                BlockTimeSheet(task: task, blocks: $blocks) {
                    showBlockSheet = false
                }
            }
        }
        .sheet(item: $detailTask) { selectedTask in
            if let idx = tasks.firstIndex(where: { $0.id == selectedTask.id }) {
                TaskDetailSheet(
                    task: $tasks[idx],
                    onDelete: {
                        onDeleteTasks([tasks[idx].id])
                        detailTask = nil
                    },
                    onDismiss: {
                        detailTask = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showAddTask) {
            AddTaskSheet(
                title: $newTaskTitle,
                minutes: $newTaskMinutes,
                importance: $newTaskImportance,
                heading: "New Task"
            ) {
                addTask(parent: nil)
                showAddTask = false
            } onCancel: {
                showAddTask = false
            }
        }
        .sheet(isPresented: $showAddSubsection) {
            AddSectionSheet(
                title: $newSubsectionTitle,
                bucket: $newSubsectionBucket,
                heading: "New Subsection"
            ) {
                addSubsection()
                showAddSubsection = false
            } onCancel: {
                showAddSubsection = false
            }
        }
        .sheet(item: $subtaskParent) { parent in
            AddTaskSheet(
                title: $newTaskTitle,
                minutes: $newTaskMinutes,
                importance: $newTaskImportance,
                heading: "New Subtask"
            ) {
                addTask(parent: parent)
                subtaskParent = nil
            } onCancel: {
                subtaskParent = nil
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    @ViewBuilder
    private func taskRow(_ task: TimedTask) -> some View {
        HStack(spacing: TimedLayout.Spacing.xs) {
            if isSelecting {
                Button {
                    toggleSelection(task.id)
                } label: {
                    Image(systemName: selectedIds.contains(task.id)
                          ? "checkmark.circle.fill"
                          : "circle")
                        .font(TimedType.body)
                        .foregroundStyle(selectedIds.contains(task.id)
                                         ? Color.Timed.labelPrimary
                                         : Color.Timed.labelSecondary)
                }
                .buttonStyle(.plain)
            }

            TaskRow(
                task: task,
                onUpdateTime: { newMins in
                    await updateEstimate(task.id, newMins)
                },
                onUpdateImportance: { importance in
                    updateImportance(task.id, importance)
                }
            ) {
                blockTarget = task
                showBlockSheet = true
            }
        }
        .tag(task.id)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggleSelection(task.id)
            } else {
                detailTask = task
            }
        }
        .contextMenu { taskContextMenu(task) }
    }

    private func updateEstimate(_ id: UUID, _ minutes: Int) async -> UUID? {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let oldMinutes = tasks[index].estimatedMinutes
        guard oldMinutes != minutes else { return nil }
        tasks[index].estimatedMinutes = minutes
        tasks[index].estimateSource = .manual
        tasks[index].estimateBasis = nil
        let updatedTask = tasks[index]
        return try? await DataBridge.shared.logEstimateOverride(
            task: updatedTask,
            oldMinutes: oldMinutes,
            newMinutes: minutes
        )
    }

    private func updateImportance(_ id: UUID, _ importance: TaskManualImportance) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let oldImportance = tasks[index].effectiveManualImportance
        guard oldImportance != importance else { return }
        tasks[index].manualImportance = importance
        let updatedTask = tasks[index]
        Task {
            try? await DataBridge.shared.logManualImportanceChanged(
                task: updatedTask,
                oldImportance: oldImportance,
                newImportance: importance
            )
        }
    }

    private func changeTaskBucket(_ id: UUID, to newBucket: TaskBucket) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let oldBucket = tasks[index].bucket
        guard oldBucket != newBucket else { return }
        tasks[index] = tasks[index].withBucket(newBucket, sectionId: nil)
        let updatedTask = tasks[index]
        Task {
            try? await DataBridge.shared.logTaskBucketChanged(task: updatedTask, oldBucket: oldBucket)
        }
    }

    private func childSections(for parent: TaskSection) -> [TaskSection] {
        let sections = taskSections.isEmpty ? TaskSection.defaultSystemSections : taskSections
        return sections
            .filter { !$0.isArchived && $0.parentSectionId == parent.id }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.title < rhs.title
            }
    }

    private func subtasks(for task: TimedTask) -> [TimedTask] {
        tasks.filter { $0.parentTaskId == task.id }.sorted(by: taskSort)
    }

    private func taskSort(_ lhs: TimedTask, _ rhs: TimedTask) -> Bool {
        if lhs.effectiveManualImportance != rhs.effectiveManualImportance {
            return lhs.effectiveManualImportance.rank > rhs.effectiveManualImportance.rank
        }
        if (lhs.sortOrder ?? Int.max) != (rhs.sortOrder ?? Int.max) {
            return (lhs.sortOrder ?? Int.max) < (rhs.sortOrder ?? Int.max)
        }
        return lhs.receivedAt > rhs.receivedAt
    }

    private func prepareNewTask() {
        newTaskTitle = ""
        newTaskMinutes = 15
        newTaskImportance = .blue
    }

    private func addTask(parent: TimedTask?) {
        let trimmedTitle = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let parentSectionId = parent?.sectionId
        let targetSectionId = parentSectionId ?? section?.id
        let targetBucket = parent?.bucket ?? activeBucket
        let task = TimedTask(
            id: UUID(),
            title: trimmedTitle,
            sender: "Manual",
            estimatedMinutes: newTaskMinutes,
            bucket: targetBucket,
            emailCount: 0,
            receivedAt: Date(),
            sectionId: targetSectionId,
            parentTaskId: parent?.id,
            sortOrder: nextSortOrder(parent: parent),
            manualImportance: newTaskImportance
        )
        tasks.append(task)
        if let parent {
            Task { try? await DataBridge.shared.logSubtaskCreated(parent: parent, child: task) }
        }
    }

    private func addSubsection() {
        guard let section else { return }
        let trimmedTitle = newSubsectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        var sections = taskSections.isEmpty ? TaskSection.defaultSystemSections : taskSections
        let parentId = section.parentSectionId == nil ? section.id : section.parentSectionId
        let siblings = sections.filter { $0.parentSectionId == parentId }
        let sortOrder = (siblings.map(\.sortOrder).max() ?? 0) + 1
        sections.append(TaskSection(
            id: UUID(),
            parentSectionId: parentId,
            title: trimmedTitle,
            canonicalBucketType: newSubsectionBucket.dbValue,
            sortOrder: sortOrder,
            colorKey: newSubsectionBucket.dbValue,
            isSystem: false,
            isArchived: false
        ))
        taskSections = sections
    }

    private func nextSortOrder(parent: TimedTask?) -> Int {
        let siblings = tasks.filter { task in
            if let parent { return task.parentTaskId == parent.id }
            return task.parentTaskId == nil && task.sectionId == section?.id && task.bucket == activeBucket
        }
        return (siblings.compactMap(\.sortOrder).max() ?? siblings.count) + 1
    }

    // MARK: - Header

    private var bucketHeader: some View {
        HStack(spacing: 16) {
            // Bucket icon + label
            HStack(spacing: 8) {
                Image(systemName: activeBucket.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(activeBucket.color)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }

            Spacer()

            // Stats — wider inter-column spacing so the labels (TASKS / TOTAL /
            // REVIEW) don't visually run into each other in the header.
            HStack(spacing: 28) {
                stat("\(bucketTasks.count)", "tasks")
                if totalMins > 0 {
                    stat(formatMins(totalMins), "total")
                }
                stat(activeBucket.reviewCadence, "review")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        // Option A — minimal empty state. Glyph + title + primary action only.
        // Add Subsection lives in the pane toolbar (above), no need to duplicate
        // it here. The "Add tasks here or triage emails…" caption is bloat:
        // the button next to it already says "Add Task". See docs/UI-RULES.md
        // rules 14–15 (no empty rows / no bloat) and CLAUDE.md design
        // principle 7 (cognitive load is the budget).
        VStack(spacing: 12) {
            Image(systemName: activeBucket.icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(activeBucket.color.opacity(0.5))
            Text(activeBucket.emptyStateTitle)
                .font(.system(size: 15, weight: .medium))
            Button("Add Task", systemImage: "plus") {
                prepareNewTask()
                showAddTask = true
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func taskContextMenu(_ task: TimedTask) -> some View {
        Button {
            blockTarget = task
            showBlockSheet = true
        } label: {
            Label("Block Time on Calendar", systemImage: "calendar.badge.plus")
        }

        Divider()

        if task.parentTaskId == nil {
            Button {
                prepareNewTask()
                subtaskParent = task
            } label: {
                Label("Add Subtask", systemImage: "plus")
            }
        }

        Divider()

        Section("Move to") {
            ForEach(TaskBucket.allCases.filter { $0 != task.bucket && $0 != .ccFyi }, id: \.self) { b in
                Button {
                    changeTaskBucket(task.id, to: b)
                } label: {
                    Label(b.rawValue, systemImage: b.icon)
                }
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            tasks.removeAll { $0.id == task.id }
        }
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        HStack(spacing: 16) {
            Text("\(selectedIds.count) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Menu("Move to\u{2026}") {
                ForEach(TaskBucket.allCases.filter { $0 != bucket }, id: \.self) { targetBucket in
                    Button {
                        moveToBucket(targetBucket)
                    } label: {
                        Label(targetBucket.rawValue, systemImage: targetBucket.icon)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button("Mark Done") {
                markSelectedDone()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Delete", role: .destructive) {
                deleteSelected()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(Color.Timed.destructive)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.controlBackgroundColor))
    }

    private func moveToBucket(_ targetBucket: TaskBucket) {
        for id in selectedIds {
            changeTaskBucket(id, to: targetBucket)
        }
        selectedIds.removeAll()
    }

    private func markSelectedDone() {
        for id in selectedIds {
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx].isDone = true
            }
        }
        selectedIds.removeAll()
    }

    private func deleteSelected() {
        onDeleteTasks(Array(selectedIds))
        selectedIds.removeAll()
    }

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m/60)h" : "\(m/60)h\(m%60)m")
    }
}

// MARK: - TimedTask bucket helper

fileprivate extension TimedTask {
    func withBucket(_ newBucket: TaskBucket, sectionId newSectionId: UUID?) -> TimedTask {
        TimedTask(
            id: id, title: title, sender: sender,
            estimatedMinutes: estimatedMinutes, bucket: newBucket,
            emailCount: emailCount, receivedAt: receivedAt,
            sectionId: newSectionId, parentTaskId: parentTaskId,
            sortOrder: sortOrder, manualImportance: manualImportance,
            notes: notes, isPlanningUnit: isPlanningUnit,
            replyMedium: replyMedium, dueToday: dueToday,
            isDoFirst: isDoFirst, isTransitSafe: isTransitSafe,
            waitingOn: waitingOn, askedDate: askedDate,
            expectedByDate: expectedByDate, isDone: isDone,
            source: source, estimateSource: estimateSource,
            estimateBasis: estimateBasis
        )
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: TimedTask
    let onUpdateTime: (Int) async -> UUID?
    let onUpdateImportance: (TaskManualImportance) -> Void
    let onBlock: () -> Void

    @State private var showTimePicker = false
    @State private var showReasonChips = false
    @State private var draftMinutes: Int = 0
    @State private var pendingOverrideEventId: UUID?

    private let reasonOptions = [
        "Took longer",
        "Took shorter",
        "Wrong category",
        "Hidden complexity"
    ]

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m/60)h" : "\(m/60)h \(m%60)m")
    }

    private var provenanceLabel: String {
        // Source overrides estimate source when it's more specific.
        switch task.source {
        case .voice: return "Voice"
        case .email: return "Email"
        case .whatsapp: return "WA"
        case .manual:
            switch task.estimateSource {
            case .ai: return "AI"
            case .manual: return "Manual"
            case .defaultBucket: return "Default"
            }
        }
    }

    private var provenanceColor: Color {
        task.estimateSource == .ai ? Color.accentColor : .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            BucketDot(color: task.bucket.dotColor)
            importanceMenu

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(task.sender)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let waiting = task.waitingOn {
                        Text("·")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                        Text("Waiting on \(waiting)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.Timed.labelSecondary)
                    }
                }
            }

            Spacer()

            // Right-side meta
            HStack(spacing: 10) {
                if task.isStale {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.Timed.labelSecondary)
                            .frame(width: 6, height: 6)
                        Text("\(task.daysInQueue)d")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.Timed.labelSecondary)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.Timed.backgroundSecondary, in: Capsule())
                }

                if task.emailCount > 1 {
                    Label("\(task.emailCount)", systemImage: "envelope.stack")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                // Time pill — clickable to edit
                Button {
                    draftMinutes = task.estimatedMinutes
                    showReasonChips = false
                    showTimePicker = true
                } label: {
                    Text(formatMins(task.estimatedMinutes))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(.controlBackgroundColor), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(.separatorColor), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTimePicker, arrowEdge: .bottom) {
                    if showReasonChips {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Why?")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                ForEach(reasonOptions, id: \.self) { reason in
                                    Button(reason) {
                                        Task {
                                            if let pendingOverrideEventId {
                                                try? await DataBridge.shared.attachReasonToOverride(
                                                    eventId: pendingOverrideEventId,
                                                    reason: reason
                                                )
                                            }
                                        }
                                        showReasonChips = false
                                        showTimePicker = false
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }
                        .padding(10)
                    } else {
                        VStack(spacing: 12) {
                            Text("Adjust time")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Stepper(
                                value: $draftMinutes,
                                in: 5...480,
                                step: 15
                            ) {
                                Text(formatMins(draftMinutes))
                                    .font(.system(size: 15, weight: .semibold))
                                    .monospacedDigit()
                                    .frame(minWidth: 60)
                            }
                            Button("Done") {
                                let didChange = draftMinutes != task.estimatedMinutes
                                if didChange {
                                    Task {
                                        let eventId = await onUpdateTime(draftMinutes)
                                        pendingOverrideEventId = eventId
                                        showReasonChips = eventId != nil
                                        showTimePicker = eventId != nil
                                    }
                                } else {
                                    showTimePicker = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(16)
                        .frame(width: 200)
                    }
                }

                Text(provenanceLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(provenanceColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            task.estimateSource == .ai
                                ? Color.accentColor.opacity(0.12)
                                : Color(.controlBackgroundColor)
                        )
                    )

                Button {
                    onBlock()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.Timed.labelSecondary)
                }
                .buttonStyle(.plain)
                .help("Block time on calendar")
            }
        }
        .padding(.vertical, 5)
    }

    private var importanceMenu: some View {
        Menu {
            ForEach(TaskManualImportance.allCases, id: \.self) { importance in
                Button {
                    onUpdateImportance(importance)
                } label: {
                    Label(importance.label, systemImage: "circle.fill")
                }
            }
        } label: {
            Circle()
                .fill(task.effectiveManualImportance.color)
                .frame(width: TimedLayout.Spacing.xs, height: TimedLayout.Spacing.xs)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Importance")
    }
}

struct AddTaskSheet: View {
    @Binding var title: String
    @Binding var minutes: Int
    @Binding var importance: TaskManualImportance
    let heading: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $title)
                Stepper("Estimated time: \(formatMins(minutes))", value: $minutes, in: 5...480, step: 5)
                Picker("Importance", selection: $importance) {
                    ForEach(TaskManualImportance.allCases, id: \.self) { importance in
                        Text(importance.label).tag(importance)
                    }
                }
                .pickerStyle(.segmented)
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
        .frame(minWidth: 380, minHeight: 260)
    }

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m/60)h" : "\(m/60)h \(m%60)m")
    }
}

fileprivate extension TaskManualImportance {
    var color: Color {
        switch self {
        case .blue: Color(.systemBlue)
        case .orange: Color(.systemOrange)
        case .red: Color(.systemRed)
        }
    }

    var label: String {
        switch self {
        case .blue: "Low"
        case .orange: "High"
        case .red: "Urgent"
        }
    }

    var rank: Int {
        switch self {
        case .blue: 0
        case .orange: 1
        case .red: 2
        }
    }
}

// MARK: - Block Time Sheet

struct BlockTimeSheet: View {
    let task: TimedTask
    @Binding var blocks: [CalendarBlock]
    let onDismiss: () -> Void

    @State private var duration: Double
    @State private var startHour: Double = 9

    init(task: TimedTask, blocks: Binding<[CalendarBlock]>, onDismiss: @escaping () -> Void) {
        self.task = task
        self._blocks = blocks
        self.onDismiss = onDismiss
        self._duration = State(initialValue: Double(max(task.estimatedMinutes, 30)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Block time for")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(task.title)
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(formatDur(duration)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.system(size: 13))
                    Slider(value: $duration, in: 15...240, step: 15)
                        .tint(task.bucket.color)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Start time")
                        Spacer()
                        Text(formatHour(startHour)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.system(size: 13))
                    Slider(value: $startHour, in: 6...20, step: 0.5)
                        .tint(task.bucket.color)
                }
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add to Calendar") {
                    addBlock()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(task.bucket.color)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private func addBlock() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let h = Int(startHour)
        let m = Int((startHour - Double(h)) * 60)
        let start = cal.date(bySettingHour: h, minute: m, second: 0, of: today)!
        let end = start.addingTimeInterval(duration * 60)
        let block = CalendarBlock(
            id: UUID(), title: task.title,
            startTime: start, endTime: end,
            sourceEmailId: nil,
            category: task.bucket == .action ? .focus : .admin
        )
        blocks.append(block)
    }

    private func formatDur(_ m: Double) -> String {
        let mins = Int(m)
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60; let r = mins % 60
        return r == 0 ? "\(h) hr" : "\(h)h \(r)m"
    }

    private func formatHour(_ h: Double) -> String {
        let hour = Int(h); let min = Int((h - Double(hour)) * 60)
        let sfx = hour >= 12 ? "pm" : "am"
        let disp = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return min == 0 ? "\(disp)\(sfx)" : "\(disp):\(String(format: "%02d", min))\(sfx)"
    }
}

#endif
