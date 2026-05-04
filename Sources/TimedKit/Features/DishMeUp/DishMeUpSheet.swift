#if os(macOS)
// DishMeUpSheet.swift — Timed macOS
// "I have X minutes — give me the most efficient thing I can do right now."
// Transcript D1: "I'm prepared to do an hour right now, and it dishes me up the right work in the right order."
// Expanded PRD: mood-aware filtering ("kill the avoidance list", "easy wins", "deep focus")

import SwiftUI
import Dependencies

enum DishMeUpContext: String, CaseIterable {
    case desk    = "At Desk"
    case transit = "In Transit"
    case flight  = "On a Flight"
    case noCalls = "No Calls"

    var icon: String {
        switch self {
        case .desk:    "desktopcomputer"
        case .transit: "car.fill"
        case .flight:  "airplane"
        case .noCalls: "phone.slash.fill"
        }
    }

    var allowedBuckets: [TaskBucket] {
        switch self {
        case .desk:    [.reply, .action, .calls, .readToday]
        case .transit: [.transit, .readToday, .readThisWeek, .reply]
        case .flight:  [.transit, .action, .readToday, .readThisWeek]
        case .noCalls: [.reply, .action, .readToday, .readThisWeek, .transit]
        }
    }
}

enum DishMeUpMood: String, CaseIterable {
    case none        = "No preference"
    case easyWins    = "Easy wins"
    case avoidance   = "Kill my avoidance list"
    case deepFocus   = "Deep focus only"

    var icon: String {
        switch self {
        case .none:      "equal.circle"
        case .easyWins:  "bolt.fill"
        case .avoidance: "flame.fill"
        case .deepFocus: "brain.head.profile"
        }
    }

    var color: Color {
        switch self {
        case .none:      Color(.systemGray)
        case .easyWins:  .green
        case .avoidance: .orange
        case .deepFocus: .primary
        }
    }
}

struct DishMeUpSheet: View {
    @Binding var tasks: [TimedTask]
    var blocks: [CalendarBlock] = []
    let onDismiss: () -> Void
    let onAccept: (TimedTask?) -> Void

    @State private var minutes     = 60
    @State private var context     = DishMeUpContext.desk
    @State private var mood        = DishMeUpMood.none
    @State private var stack: [TimedTask] = []
    @State private var taskReasons: [UUID: String] = [:]
    @State private var generated   = false
    @State private var behaviourRules: [BehaviourRule] = []
    @State private var bucketStats: [BucketCompletionStat] = []
    @State private var bucketEstimates: [String: Double] = [:]
    // Allocation metadata
    @State private var totalFreeMinutes: Int = 0
    @State private var freeTimeGapCount: Int = 0
    @State private var utilizationPercent: Double = 0
    @State private var warningMessage: String? = nil
    @State private var deferredCount: Int = 0

    private let presets: [(label: String, mins: Int)] = [("30m", 30), ("1h", 60), ("2h", 120), ("3h", 180)]

    private var stackTotal: Int {
        stack.reduce(0) { total, task in
            let corrected = bucketEstimates[task.bucket.rawValue].map { Int($0) } ?? task.estimatedMinutes
            return total + corrected
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    timePicker
                    contextPicker
                    moodPicker
                    if generated { outputStack }
                }
                .padding(.horizontal, 28).padding(.vertical, 22)
            }

            sheetFooter
        }
        .frame(width: 560)
        .task {
            guard let profileId = AuthService.shared.profileId else { return }
            @Dependency(\.supabaseClient) var supa
            if let rows = try? await supa.fetchBehaviourRules(profileId) {
                behaviourRules = rows.map {
                    BehaviourRule(ruleKey: $0.ruleKey, ruleType: $0.ruleType,
                                 ruleValueJson: $0.ruleValueJson, confidence: $0.confidence)
                }
            }
            // Fetch bucket completion stats for Thompson sampling
            if let wsId = AuthService.shared.activeOrPrimaryWorkspaceId {
                if let stats = try? await supa.fetchBucketStats(wsId, profileId) {
                    bucketStats = stats
                }
            }
            let bucketEst = (try? await DataStore.shared.loadBucketEstimates()) ?? [:]
            bucketEstimates = bucketEst.mapValues { $0.meanMinutes }
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dish Me Up")
                    .font(.system(size: 18, weight: .semibold))
                Text("Tell me how much time you have.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.Timed.labelTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
    }

    // MARK: - Time picker

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW MUCH TIME?")
                .sectionLabel()

            HStack(spacing: 8) {
                ForEach(presets, id: \.mins) { preset in
                    Button {
                        minutes = preset.mins
                        if generated { generate() }
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 13, weight: .medium))
                            .frame(minWidth: 48)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(
                                minutes == preset.mins ? Color.primary : Color(.controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(minutes == preset.mins ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: 4) {
                    Button { minutes = max(15, minutes - 15) } label: {
                        Image(systemName: "minus").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    Text("\(minutes)m")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 44)
                    Button { minutes += 15 } label: {
                        Image(systemName: "plus").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Context picker

    private var contextPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONTEXT")
                .sectionLabel()
            HStack(spacing: 8) {
                ForEach(DishMeUpContext.allCases, id: \.self) { c in
                    Button {
                        context = c
                        if generated { generate() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: c.icon).font(.system(size: 11))
                            Text(c.rawValue).font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(
                            context == c ? Color.primary : Color(.controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(context == c ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Mood picker

    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MOOD (OPTIONAL)")
                .sectionLabel()
            HStack(spacing: 8) {
                ForEach(DishMeUpMood.allCases, id: \.self) { m in
                    Button {
                        mood = m
                        if generated { generate() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: m.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(mood == m ? Color.Timed.accent : Color.Timed.labelSecondary)
                            Text(m.rawValue).font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            mood == m ? Color.Timed.accent.opacity(0.10) : Color(.controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(mood == m ? Color.Timed.accent : Color.Timed.labelPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Output stack

    private var outputStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR STACK")
                        .sectionLabel()
                    Text("\(stack.count) tasks · \(formatMins(stackTotal)) · finish by \(endTimeLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    generate()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11))
                        Text("Regenerate")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 2) {
                ForEach(Array(stack.enumerated()), id: \.element.id) { idx, task in
                    HStack(spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.Timed.labelTertiary)
                            .frame(width: 16, alignment: .trailing)

                        BucketDot(color: task.bucket.dotColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Text(taskReasons[task.id] ?? whySelected(task))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.Timed.labelSecondary)
                        }

                        Spacer()

                        Text(task.timeLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.Timed.labelSecondary)

                        Button {
                            // Training signal: user skipped a task the algorithm ranked highly
                            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                                tasks[idx].skipCount += 1
                            }
                            stack.removeAll { $0.id == task.id }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9))
                                .foregroundStyle(Color(.tertiaryLabelColor))
                        }
                        .buttonStyle(.plain)
                        .help("Remove from plan (trains the algorithm)")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                }
            }

            // Flight offline note
            if context == .flight {
                HStack(spacing: 6) {
                    Image(systemName: "airplane").font(.system(size: 10)).foregroundStyle(.primary)
                    Text("Plan saved for offline use")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            // Allocation stats
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(Color.Timed.labelSecondary)
                    Text("\(formatMins(totalFreeMinutes)) free across \(freeTimeGapCount) block\(freeTimeGapCount == 1 ? "" : "s")")
                        .font(.system(size: 11)).foregroundStyle(Color.Timed.labelSecondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar").font(.system(size: 10))
                        .foregroundStyle(Color.Timed.labelSecondary)
                    Text("\(Int(utilizationPercent))% utilised")
                        .font(.system(size: 11, weight: utilizationPercent > 90 ? .semibold : .regular))
                        .foregroundStyle(Color.Timed.labelSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 2)

            // Warning
            if let warning = warningMessage {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(Color.Timed.labelSecondary)
                    Text(warning)
                        .font(.system(size: 11)).foregroundStyle(Color.Timed.labelSecondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.Timed.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
            }

            // Deferred / overflow
            if deferredCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.forward").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("\(deferredCount) task\(deferredCount == 1 ? "" : "s") deferred to tomorrow")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack {
            if !generated {
                Button("Dish Me Up \(formatMins(minutes)) of work") {
                    generate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.return, modifiers: [])
            } else {
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Accept & Start") {
                    onAccept(stack.first)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    // MARK: - Generation logic

    private func generate() {
        var filtered = tasks.filter { !$0.isDone && context.allowedBuckets.contains($0.bucket) }

        // Mood-based pre-filtering
        switch mood {
        case .easyWins:
            let quick = filtered.filter { $0.estimatedMinutes <= 15 }
            if !quick.isEmpty { filtered = quick }
        case .avoidance:
            let stale = filtered.sorted { $0.daysInQueue >= $0.bucket.staleAfterDays && !($1.daysInQueue >= $1.bucket.staleAfterDays) }
            filtered = stale
        case .deepFocus:
            let deep = filtered.filter { $0.bucket == .action && $0.estimatedMinutes >= 30 }
            if !deep.isEmpty { filtered = deep }
        case .none:
            break
        }

        // Hard filter: energy mismatch — remove high-energy tasks when user is tired
        let sod = MorningInterviewState.shared.latestStateOfDay
        if sod.energyLevel <= 4 {
            filtered = filtered.filter { $0.energyRequired != "high" }
        }

        // Hard filter: context mismatch — only show tasks matching current context
        let contextFilter: String
        switch context {
        case .desk:    contextFilter = "desk"
        case .transit, .flight: contextFilter = "transit"
        case .noCalls: contextFilter = "anywhere"
        }
        if contextFilter != "anywhere" {
            filtered = filtered.filter { $0.context == contextFilter || $0.context == "anywhere" }
        }

        let planTasks = filtered.map { toPlanTask($0) }
        // Translate bucket estimate keys from TaskBucket.rawValue to PlanTask.bucketType format
        var planEstimates: [String: Double] = [:]
        for bucket in TaskBucket.allCases {
            if let val = bucketEstimates[bucket.rawValue] {
                planEstimates[bucketTypeStr(bucket)] = val
            }
        }
        let request = PlanRequest(
            workspaceId: AuthService.shared.activeOrPrimaryWorkspaceId ?? UUID(),
            profileId: AuthService.shared.profileId ?? UUID(),
            availableMinutes: minutes,
            moodContext: toMoodContext(mood),
            behaviouralRules: behaviourRules,
            tasks: planTasks,
            bucketStats: bucketStats,
            bucketEstimates: planEstimates,
            calendarBlocks: blocks,
            workStartHour: OnboardingUserPrefs.workStartHour,
            workEndHour: OnboardingUserPrefs.workEndHour,
            stateOfDay: sod
        )
        let result = PlanningEngine.generatePlan(request)

        // Capture allocation metadata
        totalFreeMinutes = result.totalFreeMinutes
        freeTimeGapCount = result.freeTimeGapCount
        utilizationPercent = result.utilizationPercent
        warningMessage = result.warningMessage
        deferredCount = result.deferredTaskIds.count

        let taskById = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var reasons: [UUID: String] = [:]
        stack = result.items.compactMap { item in
            guard let t = taskById[item.task.id] else { return nil }
            reasons[t.id] = item.rankReason ?? whySelected(t)
            return t
        }
        taskReasons = reasons
        generated = true
    }

    private func whySelected(_ task: TimedTask) -> String {
        if task.isDoFirst   { return "Do First — always runs first" }
        if task.dueToday    { return "Due today" }
        if task.daysInQueue > 14 { return "\(task.daysInQueue) days in queue" }
        return task.bucket.rawValue
    }

    private var endTimeLabel: String {
        let end = Date().addingTimeInterval(TimeInterval(stackTotal * 60))
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: end)
    }

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m")
    }

    private func toPlanTask(_ task: TimedTask) -> PlanTask {
        PlanTask(
            id: task.id,
            title: task.title,
            bucketType: bucketTypeStr(task.bucket),
            estimatedMinutes: task.estimatedMinutes,
            priority: task.isDoFirst ? 10 :
                      task.dueToday ? 8 :
                      task.daysInQueue > 21 ? 6 :
                      task.daysInQueue > 14 ? 5 :
                      task.daysInQueue > 7  ? 4 :
                      task.daysInQueue > 3  ? 3 : 1,
            dueAt: task.dueToday ? Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) : nil,
            isOverdue: task.dueToday && task.daysInQueue > 1,
            isDoFirst: task.isDoFirst,
            isDailyUpdate: task.title.lowercased().hasPrefix("daily update"),
            isFamilyEmail: task.bucket == .reply && !task.sender.isEmpty && task.isDoFirst,
            deferredCount: min(task.daysInQueue / 7, 10),
            isTransitSafe: task.isTransitSafe,
            urgency: task.urgency,
            importance: task.importance,
            energyRequired: task.energyRequired,
            context: task.context,
            skipCount: task.skipCount,
            createdAt: task.receivedAt
        )
    }

    private func bucketTypeStr(_ b: TaskBucket) -> String {
        switch b {
        case .action:                   return "action"
        case .reply:                    return "reply"
        case .calls:                    return "calls"
        case .readToday, .readThisWeek: return "read"
        case .transit:                  return "transit"
        case .waiting:                  return "waiting"
        case .ccFyi:                    return "other"
        }
    }

    private func toMoodContext(_ mood: DishMeUpMood) -> MoodContext? {
        switch mood {
        case .none:      return nil
        case .easyWins:  return .easyWins
        case .avoidance: return .avoidance
        case .deepFocus: return .deepFocus
        }
    }
}

// MARK: - Label style helper

extension Text {
    func sectionLabel() -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(1.2)
    }
}

#endif
