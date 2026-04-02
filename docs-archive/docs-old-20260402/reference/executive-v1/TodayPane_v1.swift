// TodayPane.swift — Timed macOS
// The day plan. Output of the morning interview. Running totals. Sections by type.
// Transcript D1-D9, Expanded PRD: due today vs total, reply sub-types, batch time totals.

import SwiftUI

struct TodayPane: View {
    @Binding var tasks: [TimedTask]
    @Binding var blocks: [CalendarBlock]
    let triageCount: Int
    let morningDone: Bool
    let onStartMorning: () -> Void
    let onDishMeUp: () -> Void

    @State private var completedIds: Set<UUID> = []
    @State private var expandedSections: Set<String> = ["doFirst", "replies", "action", "calls"]
    @State private var focusTask: TimedTask? = nil
    @State private var showFocus: Bool = false

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
                    Button {
                        onDishMeUp()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 12))
                            Text("Dish Me Up")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.indigo, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
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
                        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.2), lineWidth: 1))
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
                    .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.red.opacity(0.15), lineWidth: 1))
                    .padding(.horizontal, 28).padding(.bottom, 14)
                }

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
                            onStartFocus: { task in
                                focusTask = task
                                showFocus = true
                            }
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
                            onStartFocus: { task in
                                focusTask = task
                                showFocus = true
                            }
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
                            }
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
                            }
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
                            }
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
                            }
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
        .frame(maxWidth: .infinity)
        .navigationTitle("Today")
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
                                onUpdateTime: { mins in
                                    if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                                        tasks[idx].estimatedMinutes = mins
                                    }
                                }
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
                            onUpdateTime: { mins in
                                if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                                    tasks[idx].estimatedMinutes = mins
                                }
                            }
                        )
                        if task.id != noMediumReplies.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
        }
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.blue.opacity(0.12), lineWidth: 1))
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
    var onStartFocus: ((TimedTask) -> Void)? = nil

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
                        onUpdateTime: onUpdateTime.map { cb in { mins in cb(task.id, mins) } },
                        onStartFocus: onStartFocus.map { cb in { cb(task) } }
                    )
                    if idx < tasks.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(0.12), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }
}

// MARK: - Today task row

struct TodayTaskRow: View {
    let task: TimedTask
    @Binding var completedIds: Set<UUID>
    let showMediumBadge: Bool
    var onUpdateTime: ((Int) -> Void)? = nil
    var onStartFocus: (() -> Void)? = nil

    @State private var showTimePicker = false
    @State private var draftMinutes: Int = 0

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
                    }
                }
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isCompleted ? .green : Color(.separatorColor))
            }
            .buttonStyle(.plain)

            // Medium badge (for replies)
            if showMediumBadge, let medium = task.replyMedium {
                HStack(spacing: 3) {
                    Image(systemName: medium.icon)
                        .font(.system(size: 9))
                    Text(medium.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(medium.color)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(medium.color.opacity(0.1), in: Capsule())
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

            Spacer()

            if task.dueToday && !task.isDoFirst {
                Text("DUE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.red, in: Capsule())
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

            if let onStartFocus, !isCompleted {
                Button {
                    onStartFocus()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.indigo.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Start Focus on this task")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .opacity(isCompleted ? 0.5 : 1)
    }
}
