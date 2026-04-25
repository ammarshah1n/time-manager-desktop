// TasksPane.swift — Timed macOS
// Per-bucket task list. Shows time totals, review cadence, and quick-block action.

import SwiftUI

struct TasksPane: View {
    let bucket: TaskBucket
    @Binding var tasks: [TimedTask]
    @Binding var blocks: [CalendarBlock]
    @State private var selected: TimedTask.ID?
    @State private var showBlockSheet = false
    @State private var blockTarget: TimedTask?
    @State private var detailTask: TimedTask?
    @State private var isSelecting: Bool = false
    @State private var selectedIds: Set<UUID> = []

    var bucketTasks: [TimedTask] {
        tasks.filter { $0.bucket == bucket }
    }

    var totalMins: Int {
        bucketTasks.reduce(0) { $0 + $1.estimatedMinutes }
    }

    var body: some View {
        VStack(spacing: 0) {
            bucketHeader
            Divider()

            if bucketTasks.isEmpty {
                emptyState
            } else {
                List(selection: $selected) {
                    ForEach(bucketTasks) { task in
                        HStack(spacing: 8) {
                            if isSelecting {
                                Button {
                                    toggleSelection(task.id)
                                } label: {
                                    Image(systemName: selectedIds.contains(task.id)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(selectedIds.contains(task.id)
                                                         ? bucket.color
                                                         : .secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            TaskRow(
                                task: task,
                                onUpdateTime: { newMins in
                                    if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                                        tasks[idx].estimatedMinutes = newMins
                                    }
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
                    .onDelete { indexSet in
                        let ids = indexSet.map { bucketTasks[$0].id }
                        tasks.removeAll { ids.contains($0.id) }
                    }
                }
                .listStyle(.plain)
            }

            // Bulk action bar
            if isSelecting && !selectedIds.isEmpty {
                bulkActionBar
            }
        }
        .navigationTitle(bucket.rawValue)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if isSelecting {
                    Button("Select All") {
                        selectedIds = Set(bucketTasks.map(\.id))
                    }
                    Button("Deselect All") {
                        selectedIds.removeAll()
                    }
                }
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    if !isSelecting { selectedIds.removeAll() }
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
                        tasks.remove(at: idx)
                        detailTask = nil
                    },
                    onDismiss: {
                        detailTask = nil
                    }
                )
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

    // MARK: - Header

    private var bucketHeader: some View {
        HStack(spacing: 16) {
            // Bucket icon + label
            HStack(spacing: 8) {
                Image(systemName: bucket.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(bucket.color)
                Text(bucket.rawValue)
                    .font(.system(size: 14, weight: .semibold))
            }

            Spacer()

            // Stats
            HStack(spacing: 16) {
                stat("\(bucketTasks.count)", "tasks")
                if totalMins > 0 {
                    stat(formatMins(totalMins), "total")
                }
                stat(bucket.reviewCadence, "review")
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
        VStack(spacing: 12) {
            Image(systemName: bucket.icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(bucket.color.opacity(0.5))
            Text("No \(bucket.rawValue.lowercased()) tasks")
                .font(.system(size: 15, weight: .medium))
            Text("Triage emails to fill this bucket")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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

        Section("Move to") {
            ForEach(TaskBucket.allCases.filter { $0 != bucket && $0 != .ccFyi }, id: \.self) { b in
                Button {
                    if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                        let updated = tasks[idx]
                        tasks[idx] = TimedTask(
                            id: updated.id,
                            title: updated.title,
                            sender: updated.sender,
                            estimatedMinutes: updated.estimatedMinutes,
                            bucket: b,
                            emailCount: updated.emailCount,
                            receivedAt: updated.receivedAt,
                            replyMedium: updated.replyMedium,
                            dueToday: updated.dueToday,
                            isDoFirst: updated.isDoFirst,
                            isTransitSafe: updated.isTransitSafe,
                            waitingOn: updated.waitingOn,
                            askedDate: updated.askedDate,
                            expectedByDate: updated.expectedByDate,
                            isDone: updated.isDone
                        )
                    }
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
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx] = tasks[idx].withBucket(targetBucket)
            }
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
        tasks.removeAll { selectedIds.contains($0.id) }
        selectedIds.removeAll()
    }

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m/60)h" : "\(m/60)h\(m%60)m")
    }
}

// MARK: - TimedTask bucket helper

fileprivate extension TimedTask {
    func withBucket(_ newBucket: TaskBucket) -> TimedTask {
        TimedTask(
            id: id, title: title, sender: sender,
            estimatedMinutes: estimatedMinutes, bucket: newBucket,
            emailCount: emailCount, receivedAt: receivedAt,
            replyMedium: replyMedium, dueToday: dueToday,
            isDoFirst: isDoFirst, isTransitSafe: isTransitSafe,
            waitingOn: waitingOn, askedDate: askedDate,
            expectedByDate: expectedByDate, isDone: isDone
        )
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: TimedTask
    let onUpdateTime: (Int) -> Void
    let onBlock: () -> Void

    @State private var showTimePicker = false
    @State private var draftMinutes: Int = 0

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m/60)h" : "\(m/60)h \(m%60)m")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(task.bucket.color)
                .frame(width: 3, height: 36)

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
                            onUpdateTime(draftMinutes)
                            showTimePicker = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(16)
                    .frame(width: 200)
                }

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
