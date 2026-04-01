// TodayPane.swift — Timed macOS
// The day plan. Output of the morning interview. Running totals. Sections by type.
// Transcript D1-D9, Expanded PRD: due today vs total, reply sub-types, batch time totals.

import SwiftUI
import Dependencies

struct TodayPane: View {
    @Binding var tasks: [TimedTask]
    @Binding var blocks: [CalendarBlock]
    let triageCount: Int
    let morningDone: Bool
    var freeTimeSlots: [FreeTimeSlot] = []
    let onStartMorning: () -> Void
    let onDishMeUp: () -> Void

    @State private var completedIds: Set<UUID> = []
    @State private var expandedSections: Set<String> = ["doFirst", "replies", "action", "calls"]
    @State private var focusTask: TimedTask? = nil
    @State private var showFocus: Bool = false
    @State private var quickTitle = ""
    @State private var quickBucket: TaskBucket = .action
    @FocusState private var quickFieldFocused: Bool
    @State private var detailTask: TimedTask?
    @AppStorage("staleAlertSnoozedUntil") private var staleAlertSnoozedUntil: String = ""
    @State private var staleExpanded: Bool = false
    @State private var insights: [(bucket: TaskBucket, message: String)] = []
    @State private var bucketAccuracy: [TaskBucket: (avgEstimated: Double, avgActual: Double)] = [:]
    @AppStorage("insights.dismissedUntil") private var insightsDismissedUntil: String = ""
    @State private var insightsExpanded: Bool = false
    @State private var correctionToast: String? = nil

    // Stale items
    private var staleTasks: [TimedTask] {
        tasks.filter { $0.isStale && !completedIds.contains($0.id) }
    }
    private var isStaleSnoozed: Bool {
        guard !staleAlertSnoozedUntil.isEmpty else { return false }
        let f = ISO8601DateFormatter()
        guard let snoozedUntil = f.date(from: staleAlertSnoozedUntil) else { return false }
        return Date() < snoozedUntil
    }

    private var isInsightsDismissed: Bool {
        guard !insightsDismissedUntil.isEmpty else { return false }
        let f = ISO8601DateFormatter()
        guard let until = f.date(from: insightsDismissedUntil) else { return false }
        return Date() < until
    }

    // Section data
    private var doFirst:    [TimedTask] { tasks.filter { $0.isDoFirst && !completedIds.contains($0.id) } }
    private var replies:    [TimedTask] { tasks.filter { $0.bucket == .reply && !$0.isDoFirst && !completedIds.contains($0.id) } }
    private var actions:    [TimedTask] { tasks.filter { $0.bucket == .action && !$0.isDoFirst && !completedIds.contains($0.id) } }
    private var calls:      [TimedTask] { tasks.filter { $0.bucket == .calls && !completedIds.contains($0.id) } }
    private var transit:    [TimedTask] { tasks.filter { $0.bucket == .transit && !$0.isDoFirst && !completedIds.contains($0.id) } }
    private var readsToday: [TimedTask] { tasks.filter { $0.bucket == .readToday && !completedIds.contains($0.id) } }
    private var readsWeek:  [TimedTask] { tasks.filter { $0.bucket == .readThisWeek && !completedIds.contains($0.id) } }
    private var completed:  [TimedTask] { tasks.filter { completedIds.contains($0.id) } }

    private var plannedMins: Int {
        tasks.filter { !completedIds.contains($0.id) }.reduce(0) { $0 + $1.estimatedMinutes }
    }
    private var doneMins: Int {
        tasks.filter { completedIds.contains($0.id) }.reduce(0) { $0 + $1.estimatedMinutes }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning" }
        if h < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date())
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ──────────────────────────────────────────────
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(greeting)
                            .font(.system(size: 24, weight: .semibold))
                        Text(dateString)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Dish Me Up", action: onDishMeUp)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
                .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)

                // ── Morning interview banner ─────────────────────────────
                if !morningDone {
                    Button(action: onStartMorning) {
                        HStack(spacing: 10) {
                            Image(systemName: "sunrise.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Morning review not done yet")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("5 minutes to build your day plan.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Start →")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28).padding(.bottom, 14)
                }

                // ── Triage alert ─────────────────────────────────────────
                if triageCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 12)).foregroundStyle(.red)
                        Text("\(triageCount) emails unprocessed in Triage")
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .padding(.horizontal, 28).padding(.bottom, 14)
                }

                // ── Stale items banner ──────────────────────────────────
                if !staleTasks.isEmpty && !isStaleSnoozed {
                    staleItemsBanner
                        .padding(.horizontal, 28).padding(.bottom, 14)
                }

                // ── Free-time banner ────────────────────────────────────
                if let nextFree = freeTimeSlots.first(where: { $0.start > Date() }) {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
                        Text("You have \(nextFree.durationMinutes)min free at \(nextFree.start.formatted(date: .omitted, time: .shortened)) — want a plan?")
                            .font(.system(size: 12))
                        Spacer()
                        Button("Dish Me Up", action: onDishMeUp)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(.blue)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 28).padding(.bottom, 14)
                }

                // ── Insights banner ─────────────────────────────────────
                if !insights.isEmpty && !isInsightsDismissed {
                    insightsBanner
                        .padding(.horizontal, 28).padding(.bottom, 14)
                }

                // ── Quick add ────────────────────────────────────────────
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    TextField("Add a task…", text: $quickTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($quickFieldFocused)
                        .onSubmit { submitQuickTask() }

                    Menu {
                        ForEach([TaskBucket.action, .reply, .calls, .readToday, .readThisWeek, .transit], id: \.self) { b in
                            Button {
                                quickBucket = b
                            } label: {
                                Label(b.rawValue, systemImage: b.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: quickBucket.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(quickBucket.color)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    if !quickTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add") { submitQuickTask() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(quickBucket.color)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 12)
                .animation(.easeInOut(duration: 0.15), value: quickTitle.isEmpty)

                // ── Running totals ───────────────────────────────────────
                totalsStrip
                    .padding(.horizontal, 28).padding(.bottom, 20)

                // ── Sections ─────────────────────────────────────────────
                VStack(spacing: 6) {
                    if !doFirst.isEmpty {
                        TodaySection(
                            id: "doFirst",
                            icon: "star.fill",
                            title: "DO FIRST",
                            color: .indigo,
                            tasks: doFirst,
                            expanded: expandedSections.contains("doFirst"),
                            completedIds: $completedIds,
                            onToggle: { toggleSection("doFirst") },
                            onUpdateTime: { id, mins in
                                if let idx = tasks.firstIndex(where: { $0.id == id }) {
                                    tasks[idx].estimatedMinutes = mins
                                }
                            },
                            onTapDetail: { task in detailTask = task },
                            bucketAccuracy: bucketAccuracy
                        )
                    }

                    if !replies.isEmpty {
                        repliesSection
                    }

                    if !actions.isEmpty {
                        TodaySection(
                            id: "action",
                            icon: "bolt.fill",
                            title: "ACTION",
                            color: .orange,
                            tasks: actions,
                            expanded: expandedSections.contains("action"),
                            completedIds: $completedIds,
                            onToggle: { toggleSection("action") },
                            onUpdateTime: { id, mins in
                                if let idx = tasks.firstIndex(where: { $0.id == id }) {
                                    tasks[idx].estimatedMinutes = mins
                                }
                            },
                            onTapDetail: { task in detailTask = task },
                            bucketAccuracy: bucketAccuracy
                        )
                    }

                    if !calls.isEmpty {
                        TodaySection(
                            id: "calls",
                            icon: "phone.fill",
                            title: "CALLS",
                            color: .green,
                            tasks: calls,
                            expanded: expandedSections.contains("calls"),
                            completedIds: $completedIds,
                            onToggle: { toggleSection("calls") },
                            onUpdateTime: { id, mins in
                                if let idx = tasks.firstIndex(where: { $0.id == id }) {
                                    tasks[idx].estimatedMinutes = mins
                                }
                            },
                            onTapDetail: { task in detailTask = task },
                            bucketAccuracy: bucketAccuracy
                        )
                    }

                    if !transit.isEmpty {
                        TodaySection(
                            id: "transit",
                            icon: "car.fill",
                            title: "TRANSIT",
                            color: Color(red: 0.2, green: 0.6, blue: 0.45),
                            tasks: transit,
                            expanded: expandedSections.contains("transit"),
                            completedIds: $completedIds,
                            onToggle: { toggleSection("transit") },
                            onUpdateTime: { id, mins in
                                if let idx = tasks.firstIndex(where: { $0.id == id }) {
                                    tasks[idx].estimatedMinutes = mins
                                }
                            },
                            onTapDetail: { task in detailTask = task },
                            bucketAccuracy: bucketAccuracy
                        )
                    }

                    if !readsToday.isEmpty {
                        TodaySection(
                            id: "readToday",
                            icon: "doc.text.fill",
                            title: "READ TODAY",
                            color: .purple,
                            tasks: readsToday,
                            expanded: expandedSections.contains("readToday"),
                            completedIds: $completedIds,
                            onToggle: { toggleSection("readToday") },
                            onUpdateTime: { id, mins in
                                if let idx = tasks.firstIndex(where: { $0.id == id }) {
                                    tasks[idx].estimatedMinutes = mins
                                }
                            },
                            onTapDetail: { task in detailTask = task },
                            bucketAccuracy: bucketAccuracy
                        )
                    }

                    if !readsWeek.isEmpty {
                        TodaySection(
                            id: "readWeek",
                            icon: "doc.text",
                            title: "READ THIS WEEK",
                            color: Color(.systemGray),
                            tasks: readsWeek,
                            expanded: expandedSections.contains("readWeek"),
                            completedIds: $completedIds,
                            onToggle: { toggleSection("readWeek") },
                            onUpdateTime: { id, mins in
                                if let idx = tasks.firstIndex(where: { $0.id == id }) {
                                    tasks[idx].estimatedMinutes = mins
                                }
                            },
                            onTapDetail: { task in detailTask = task },
                            bucketAccuracy: bucketAccuracy
                        )
                    }

                    if !completed.isEmpty {
                        completedSection
                    }

                    if tasks.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 32)
            }
            .frame(maxWidth: 720, alignment: .leading)
        }
        .sheet(isPresented: $showFocus) {
            FocusPane(task: focusTask) {
                showFocus = false
                focusTask = nil
            }
            .frame(minWidth: 600, minHeight: 680)
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
        .onAppear {
            completedIds = Set(tasks.filter { $0.isDone }.map { $0.id })
        }
        .task {
            let records = (try? await DataStore.shared.loadCompletionRecords()) ?? []
            bucketAccuracy = InsightsEngine.accuracyByBucket(records)
            guard records.count >= 10 else { return }
            insights = InsightsEngine.suggestedAdjustments(records)
        }
        .onChange(of: completedIds) { (_: Set<UUID>, newIds: Set<UUID>) in
            for idx in tasks.indices {
                let done = newIds.contains(tasks[idx].id)
                if tasks[idx].isDone != done { tasks[idx].isDone = done }
            }
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("Today")
    }

    // MARK: - Stale items banner

    private var staleItemsBanner: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { staleExpanded.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(staleTasks.count) item\(staleTasks.count == 1 ? "" : "s") need\(staleTasks.count == 1 ? "s" : "") attention")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Sitting longer than expected in their buckets")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            let f = ISO8601DateFormatter()
                            staleAlertSnoozedUntil = f.string(from: Date().addingTimeInterval(86_400))
                        } label: {
                            Text("Snooze")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.orange)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(staleExpanded ? 90 : 0))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if staleExpanded {
                Divider().padding(.leading, 38)
                ForEach(staleTasks) { task in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(task.bucket.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(task.bucket.color)
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text("sitting \(task.daysInQueue) day\(task.daysInQueue == 1 ? "" : "s")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                        }

                        Spacer()

                        Text("Review")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { detailTask = task }
                }
            }
        }
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.18), value: staleExpanded)
    }

    // MARK: - Insights banner

    private var insightsBanner: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { insightsExpanded.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.yellow)
                    Text("Insights")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(insightsExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if insightsExpanded {
                Divider().padding(.leading, 38)
                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    HStack(spacing: 10) {
                        Image(systemName: insight.bucket.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(insight.bucket.color)
                            .frame(width: 14)
                        Text(insight.message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let acc = bucketAccuracy[insight.bucket],
                           acc.avgEstimated > 0,
                           abs(acc.avgActual - acc.avgEstimated) / acc.avgEstimated > 0.15 {
                            Button {
                                let correctedMinutes = Int(acc.avgActual)
                                var updatedCount = 0
                                for idx in tasks.indices where tasks[idx].bucket == insight.bucket && !completedIds.contains(tasks[idx].id) {
                                    tasks[idx].estimatedMinutes = correctedMinutes
                                    updatedCount += 1
                                }
                                correctionToast = "Updated \(updatedCount) \(insight.bucket.rawValue) tasks to \(correctedMinutes)m"
                                Task {
                                    try? await Task.sleep(for: .seconds(3))
                                    correctionToast = nil
                                }
                            } label: {
                                Text("Update all \(insight.bucket.rawValue) \u{2192}")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(insight.bucket.color)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }

                if let toast = correctionToast {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(.green)
                        Text(toast).font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .transition(.opacity)
                }

                Divider().padding(.leading, 38)
                Button {
                    let f = ISO8601DateFormatter()
                    insightsDismissedUntil = f.string(from: Date().addingTimeInterval(7 * 86_400))
                } label: {
                    Text("Dismiss for 7 days")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.yellow)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.18), value: insightsExpanded)
    }

    // MARK: - Totals strip

    private var totalsStrip: some View {
        HStack(spacing: 0) {
            totalCell("Planned", formatMins(plannedMins + doneMins), .primary)
            Divider().frame(height: 32)
            totalCell("Done", formatMins(doneMins), .green)
            Divider().frame(height: 32)
            totalCell("Remaining", formatMins(plannedMins), .orange)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func totalCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Replies section (grouped by medium)

    private var repliesSection: some View {
        VStack(spacing: 0) {
            // Section header
            Button { toggleSection("replies") } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 14)

                    Text("REPLIES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.blue)
                        .tracking(0.8)

                    Text("·  \(replies.count) item\(replies.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(formatMins(replies.reduce(0) { $0 + $1.estimatedMinutes }))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                        .monospacedDigit()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expandedSections.contains("replies") ? 90 : 0))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedSections.contains("replies") {
                Divider().padding(.leading, 38)

                // Group by medium
                ForEach(ReplyMedium.allCases, id: \.self) { medium in
                    let mediumReplies = replies.filter { $0.replyMedium == medium }
                    if !mediumReplies.isEmpty {
                        ForEach(mediumReplies) { task in
                            TodayTaskRow(
                            task: task,
                            completedIds: $completedIds,
                            showMediumBadge: true,
                            bucketAccuracy: bucketAccuracy[task.bucket],
                                onUpdateTime: { mins in
                                    if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                                        tasks[idx].estimatedMinutes = mins
                                    }
                                },
                                onTapDetail: { detailTask = task }
                            )
                            if task.id != mediumReplies.last?.id {
                                Divider().padding(.leading, 46)
                            }
                        }
                        if medium != ReplyMedium.allCases.last {
                            Divider().padding(.leading, 38)
                        }
                    }
                }

                let noMediumReplies = replies.filter { $0.replyMedium == nil }
                if !noMediumReplies.isEmpty {
                    if replies.filter({ $0.replyMedium != nil }).count > 0 {
                        Divider().padding(.leading, 38)
                    }
                    ForEach(noMediumReplies) { task in
                        TodayTaskRow(
                            task: task,
                            completedIds: $completedIds,
                            showMediumBadge: false,
                            bucketAccuracy: bucketAccuracy[task.bucket],
                            onUpdateTime: { mins in
                                if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                                    tasks[idx].estimatedMinutes = mins
                                }
                            },
                            onTapDetail: { detailTask = task }
                        )
                        if task.id != noMediumReplies.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
        }
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.18), value: expandedSections.contains("replies"))
    }

    // MARK: - Completed section

    private var completedSection: some View {
        VStack(spacing: 0) {
            Button { toggleSection("completed") } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .frame(width: 14)
                    Text("COMPLETED")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                        .tracking(0.8)
                    Text("·  \(completed.count)")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text(formatMins(doneMins))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green).monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expandedSections.contains("completed") ? 90 : 0))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedSections.contains("completed") {
                Divider().padding(.leading, 38)
                ForEach(completed) { task in
                    HStack(spacing: 12) {
                        Button {
                            completedIds.remove(task.id)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        Text(task.title)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .strikethrough(true, color: .secondary)
                        Spacer()
                        Text(task.timeLabel)
                            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                }
            }
        }
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.18), value: expandedSections.contains("completed"))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("No tasks yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Button("Run Morning Review") { onStartMorning() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func submitQuickTask() {
        let trimmed = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let newTask = TimedTask(
            id: UUID(),
            title: trimmed,
            sender: "",
            estimatedMinutes: 15,
            bucket: quickBucket,
            emailCount: 0,
            receivedAt: Date()
        )
        tasks.append(newTask)
        quickTitle = ""
    }

    private func toggleSection(_ id: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedSections.contains(id) {
                expandedSections.remove(id)
            } else {
                expandedSections.insert(id)
            }
        }
    }

    private func formatMins(_ m: Int) -> String {
        if m == 0 { return "0m" }
        return m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m")
    }
}

// MARK: - Today Section (generic)

struct TodaySection: View {
    let id: String
    let icon: String
    let title: String
    let color: Color
    let tasks: [TimedTask]
    let expanded: Bool
    @Binding var completedIds: Set<UUID>
    let onToggle: () -> Void
    var onUpdateTime: ((UUID, Int) -> Void)? = nil
    var onTapDetail: ((TimedTask) -> Void)? = nil
    var bucketAccuracy: [TaskBucket: (avgEstimated: Double, avgActual: Double)] = [:]

    private var totalMins: Int { tasks.reduce(0) { $0 + $1.estimatedMinutes } }

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m")
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(color)
                        .frame(width: 14)

                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                        .tracking(0.8)

                    Text("·  \(tasks.count) item\(tasks.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(formatMins(totalMins))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                        .monospacedDigit()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().padding(.leading, 38)
                ForEach(Array(tasks.enumerated()), id: \.element.id) { idx, task in
                    TodayTaskRow(
                        task: task,
                        completedIds: $completedIds,
                        showMediumBadge: false,
                        bucketAccuracy: bucketAccuracy[task.bucket],
                        onUpdateTime: onUpdateTime.map { cb in { mins in cb(task.id, mins) } },
                        onTapDetail: onTapDetail.map { cb in { cb(task) } }
                    )
                    if idx < tasks.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }
}

// MARK: - Today task row

struct TodayTaskRow: View {
    let task: TimedTask
    @Binding var completedIds: Set<UUID>
    let showMediumBadge: Bool
    var bucketAccuracy: (avgEstimated: Double, avgActual: Double)? = nil
    var onUpdateTime: ((Int) -> Void)? = nil
    var onTapDetail: (() -> Void)? = nil

    @State private var showTimePicker = false
    @State private var draftMinutes: Int = 0
    @State private var showActualTime = false
    @State private var actualMinutes: Int = 0

    private var isCompleted: Bool { completedIds.contains(task.id) }

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m/60)h" : "\(m/60)h \(m%60)m")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if completedIds.contains(task.id) {
                        completedIds.remove(task.id)
                    } else {
                        completedIds.insert(task.id)
                        actualMinutes = task.estimatedMinutes
                        showActualTime = true
                    }
                }
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isCompleted ? .green : Color(.separatorColor))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showActualTime, arrowEdge: .trailing) {
                VStack(spacing: 10) {
                    Text("How long did it take?")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Stepper(value: $actualMinutes, in: 1...480, step: 5) {
                        Text(formatMins(actualMinutes))
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .frame(minWidth: 50)
                    }
                    Button("Save") {
                        let record = CompletionRecord(
                            id: UUID(),
                            taskId: task.id,
                            bucket: task.bucket,
                            estimatedMinutes: task.estimatedMinutes,
                            actualMinutes: actualMinutes,
                            completedAt: Date(),
                            wasDeferred: task.daysInQueue > task.bucket.staleAfterDays,
                            deferredCount: min(task.daysInQueue / 7, 10)
                        )
                        Task {
                            let store = DataStore.shared
                            var records = (try? await store.loadCompletionRecords()) ?? []
                            records.append(record)
                            try? await store.saveCompletionRecords(records)

                            // EMA posterior update
                            var estimates = (try? await store.loadBucketEstimates()) ?? [:]
                            var est = estimates[task.bucket.rawValue] ?? BucketEstimate(
                                meanMinutes: Double(task.estimatedMinutes), sampleCount: 0, lastUpdatedAt: Date()
                            )
                            let alpha = est.sampleCount < 20 ? 1.0 / Double(est.sampleCount + 1) : 0.15
                            est.meanMinutes = (1 - alpha) * est.meanMinutes + alpha * Double(actualMinutes)
                            est.sampleCount += 1
                            est.lastUpdatedAt = Date()
                            estimates[task.bucket.rawValue] = est
                            try? await store.saveBucketEstimates(estimates)

                            // Log behaviour event + sync EMA to Supabase
                            if let wsId = AuthService.shared.workspaceId,
                               let profileId = AuthService.shared.profileId {
                                @Dependency(\.supabaseClient) var supa
                                let event = BehaviourEventInsert(
                                    workspaceId: wsId, profileId: profileId,
                                    eventType: "task_completed", taskId: task.id,
                                    bucketType: task.bucket.rawValue,
                                    hourOfDay: Calendar.current.component(.hour, from: Date()),
                                    dayOfWeek: Calendar.current.component(.weekday, from: Date()),
                                    oldValue: nil, newValue: "\(actualMinutes)"
                                )
                                try? await supa.insertBehaviourEvent(event)
                                try? await supa.upsertBucketEstimate(wsId, profileId, task.bucket.rawValue, est.meanMinutes, est.sampleCount)

                                // Update tasks.actual_minutes — DB trigger auto-inserts to estimation_history
                                try? await supa.updateTaskActualMinutes(task.id, actualMinutes)
                            }
                        }
                        showActualTime = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(14)
                .frame(width: 200)
            }

            // Medium badge (for replies)
            if showMediumBadge, let medium = task.replyMedium {
                Text(medium.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted, color: .secondary)
                    .lineLimit(1)
                if !task.sender.isEmpty && task.sender != "System" && task.sender != "" {
                    Text(task.sender)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTapDetail?() }

            Spacer()

            if task.dueToday && !task.isDoFirst {
                Text("Due")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
            }

            if task.emailCount > 1 {
                Label("\(task.emailCount)", systemImage: "envelope.stack")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Confidence warning
            if let acc = bucketAccuracy,
               acc.avgEstimated > 0,
               abs(acc.avgActual - acc.avgEstimated) / acc.avgEstimated > 0.15 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                    .help("Usually takes \(Int(acc.avgActual))m")
            }

            // Time pill — clickable to edit
            Button {
                draftMinutes = task.estimatedMinutes
                showTimePicker = true
            } label: {
                Text(formatMins(task.estimatedMinutes))
                    .font(.system(size: 12, weight: .medium))
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
                        onUpdateTime?(draftMinutes)
                        showTimePicker = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(16)
                .frame(width: 200)
            }

        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .opacity(isCompleted ? 0.5 : 1)
    }
}
