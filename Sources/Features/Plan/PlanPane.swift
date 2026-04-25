// PlanPane.swift — Timed macOS
// "Dish me up" — declare available time, get a sequenced work plan.
// Sequences tasks by bucket priority: Reply → Action → Read Today → Read This Week → Waiting

import SwiftUI
import Dependencies

struct PlanPane: View {
    @Binding var tasks: [TimedTask]
    @Binding var blocks: [CalendarBlock]

    @State private var availableMinutes: Int = 60
    @State private var customMinutes: String = "60"
    @State private var useCustom = false
    @State private var generatedPlan: [PlannedItem] = []
    @State private var planGenerated = false
    @State private var planRevealed = false
    @State private var behaviourRules: [BehaviourRule] = []
    @State private var bucketStats: [BucketCompletionStat] = []
    @State private var bucketEstimates: [String: Double] = [:]
    @State private var mood: DishMeUpMood = .none
    // Allocation metadata
    @State private var totalFreeMinutes: Int = 0
    @State private var freeTimeGapCount: Int = 0
    @State private var utilizationPercent: Double = 0
    @State private var warningMessage: String? = nil
    @State private var deferredCount: Int = 0

    private let presets: [(label: String, mins: Int)] = [
        ("30 min", 30), ("1 hr", 60), ("2 hr", 120), ("3 hr", 180)
    ]

    private var totalAvailable: Int {
        useCustom ? (Int(customMinutes) ?? 60) : availableMinutes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                timeSelector
                if planGenerated {
                    planOutput
                } else {
                    planPrompt
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("Plan")
        .task {
            guard let profileId = AuthService.shared.profileId else { return }
            @Dependency(\.supabaseClient) var supa
            if let rows = try? await supa.fetchBehaviourRules(profileId) {
                behaviourRules = rows.map {
                    BehaviourRule(ruleKey: $0.ruleKey, ruleType: $0.ruleType,
                                 ruleValueJson: $0.ruleValueJson, confidence: $0.confidence)
                }
            }
            if let wsId = AuthService.shared.workspaceId {
                if let stats = try? await supa.fetchBucketStats(wsId, profileId) {
                    bucketStats = stats
                }
            }
            let bucketEst = (try? await DataStore.shared.loadBucketEstimates()) ?? [:]
            bucketEstimates = bucketEst.mapValues { $0.meanMinutes }
        }
    }

    // MARK: - Time selector

    private var timeSelector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HOW MUCH TIME DO YOU HAVE?")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            HStack(spacing: 8) {
                ForEach(presets, id: \.mins) { preset in
                    Button {
                        availableMinutes = preset.mins
                        useCustom = false
                        planGenerated = false
                        planRevealed = false
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 13, weight: .medium))
                            .frame(minWidth: 64)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(
                                !useCustom && availableMinutes == preset.mins
                                    ? Color.Timed.accent : Color(.controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(
                                !useCustom && availableMinutes == preset.mins ? .white : .primary
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Custom
                HStack(spacing: 4) {
                    TextField("mins", text: $customMinutes)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 44)
                        .multilineTextAlignment(.center)
                        .onTapGesture { useCustom = true; planGenerated = false; planRevealed = false }
                    Text("min")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    useCustom ? Color.Timed.accent : Color(.controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(useCustom ? .white : .primary)
                .onTapGesture { useCustom = true }
            }

            // Mood picker
            Text("MOOD (OPTIONAL)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
                .padding(.top, 6)

            HStack(spacing: 8) {
                ForEach(DishMeUpMood.allCases, id: \.self) { m in
                    let selected = mood == m
                    Button {
                        mood = m
                        if planGenerated { generate() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: m.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(selected ? Color.Timed.accent : Color.Timed.labelSecondary)
                            Text(m.rawValue).font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            selected ? Color.Timed.accent.opacity(0.12) : Color(.controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selected ? Color.Timed.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                        .foregroundStyle(selected ? Color.Timed.accent : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                generate()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Dish me up \(formatMins(totalAvailable)) of work")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(Color.Timed.accent, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    // MARK: - Plan prompt (pre-generation)

    private var planPrompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Preview card — shows what a generated plan looks like
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.Timed.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your plan will appear here")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.Timed.primaryText)
                        Text("Tasks sequenced by urgency, time fit, and your mood")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.Timed.secondaryText)
                    }
                    Spacer()
                }
                .padding(14)

                // Mock skeleton rows
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 10) {
                        Text("\(i + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.Timed.tertiaryText)
                            .frame(width: 18, alignment: .trailing)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.Timed.tertiaryText.opacity(0.18))
                            .frame(height: 10)
                            .frame(maxWidth: [160, 120, 140][i])
                        Spacer()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.Timed.tertiaryText.opacity(0.12))
                            .frame(width: 36, height: 10)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    if i < 2 {
                        Divider().padding(.leading, 42)
                    }
                }
            }
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.Timed.hairline, lineWidth: 1)
            )

            // Task inventory
            let total = tasks.filter({ !$0.isDone }).count
            let totalMins = tasks.filter({ !$0.isDone }).reduce(0) { $0 + $1.estimatedMinutes }

            if total > 0 {
                HStack(spacing: 16) {
                    planStat("\(total)", "tasks queued")
                    planStat(formatMins(totalMins), "total backlog")
                    Spacer()
                }
                .padding(.top, 2)
            } else {
                // No tasks at all
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.Timed.tertiaryText)
                    Text("No tasks to plan")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.Timed.secondaryText)
                    Text("Add tasks in the Today view or import from your calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.Timed.tertiaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Generated plan

    private var planOutput: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR PLAN — \(formatMins(totalAvailable))")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text("\(generatedPlan.count) tasks · \(formatMins(generatedPlan.reduce(0) { $0 + $1.task.estimatedMinutes })) scheduled")
                        .font(.system(size: 13))
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        generate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Regenerate")

                    Button {
                        sendToCalendar()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar.badge.plus")
                            Text("Send to Calendar")
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.Timed.accent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            // Allocation stats
            allocationInfoBar

            // Task sequence — staggered auto-weave reveal
            VStack(spacing: 2) {
                ForEach(Array(generatedPlan.enumerated()), id: \.element.id) { idx, item in
                    PlanItemRow(index: idx + 1, item: item, isRevealed: planRevealed)
                        .opacity(planRevealed ? 1 : 0)
                        .offset(y: planRevealed ? 0 : 20)
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.85)
                            .delay(Double(idx) * 0.025),
                            value: planRevealed
                        )
                }
            }
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            // Warning message
            if let warning = warningMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.Timed.labelSecondary)
                    Text(warning)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.Timed.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
            }

            // Deferred tasks notice
            if deferredCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(deferredCount) task\(deferredCount == 1 ? "" : "s") deferred to tomorrow")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Allocation info bar

    private var allocationInfoBar: some View {
        HStack(spacing: 16) {
            // Free time
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.Timed.labelSecondary)
                Text("\(formatMins(totalFreeMinutes)) free across \(freeTimeGapCount) block\(freeTimeGapCount == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Utilization
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.Timed.labelSecondary)
                Text("Plan is \(Int(utilizationPercent))% of free time")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Generation logic

    private func toMoodContext(_ mood: DishMeUpMood) -> MoodContext? {
        switch mood {
        case .none:      return nil
        case .easyWins:  return .easyWins
        case .avoidance: return .avoidance
        case .deepFocus: return .deepFocus
        }
    }

    private func generate() {
        let planTasks = tasks.filter { !$0.isDone }.map { toPlanTask($0) }
        // Translate bucket estimate keys from TaskBucket.rawValue to PlanTask.bucketType format
        var planEstimates: [String: Double] = [:]
        for bucket in TaskBucket.allCases {
            if let val = bucketEstimates[bucket.rawValue] {
                planEstimates[bucketTypeStr(bucket)] = val
            }
        }
        let request = PlanRequest(
            workspaceId: AuthService.shared.workspaceId ?? UUID(),
            profileId: AuthService.shared.profileId ?? UUID(),
            availableMinutes: totalAvailable,
            moodContext: toMoodContext(mood),
            behaviouralRules: behaviourRules,
            tasks: planTasks,
            bucketStats: bucketStats,
            bucketEstimates: planEstimates,
            calendarBlocks: blocks,
            workStartHour: OnboardingUserPrefs.workStartHour,
            workEndHour: OnboardingUserPrefs.workEndHour,
            stateOfDay: MorningInterviewState.shared.latestStateOfDay
        )
        let result = PlanningEngine.generatePlan(request)

        // Capture allocation metadata
        totalFreeMinutes = result.totalFreeMinutes
        freeTimeGapCount = result.freeTimeGapCount
        utilizationPercent = result.utilizationPercent
        warningMessage = result.warningMessage
        deferredCount = result.deferredTaskIds.count

        // Map PlanItems back to PlannedItems using original TimedTask
        // Use scheduledStartTime from allocator slots where available
        let taskById = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // Build a lookup of slotStart by taskId from the PlanItems' positions
        // The PlanningEngine already sets items ordered by slotStart from the allocator
        let cal = Calendar.current
        var fallbackCursor = Date()
        let mins = cal.component(.minute, from: fallbackCursor)
        let roundedMins = mins < 30 ? 30 : 60
        fallbackCursor = cal.date(byAdding: .minute, value: roundedMins - mins, to: fallbackCursor) ?? fallbackCursor

        planRevealed = false
        generatedPlan = result.items.compactMap { item in
            guard let original = taskById[item.task.id] else { return nil }
            // Use the allocator's slot start time; fall back to sequential cursor
            let startTime = item.scheduledSlotStart ?? fallbackCursor
            let planned = PlannedItem(task: original, scheduledStartTime: startTime)
            fallbackCursor = startTime.addingTimeInterval(TimeInterval(original.estimatedMinutes * 60 + 5 * 60))
            return planned
        }
        planGenerated = true

        // Trigger staggered reveal after layout settles
        let itemCount = generatedPlan.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            planRevealed = true
        }

        // Play completion tone after last item finishes revealing
        // Total duration: 0.05s layout delay + (itemCount * 0.025s stagger) + 0.4s spring
        let totalRevealDuration = 0.05 + Double(itemCount) * 0.025 + 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + totalRevealDuration) {
            TimedSound.planGenerated.play()
        }
    }

    private func sendToCalendar() {
        let cal = Calendar.current
        var cursor = Date()
        // Round up to next half hour
        let mins = cal.component(.minute, from: cursor)
        let roundedMins = mins < 30 ? 30 : 60
        cursor = cal.date(byAdding: .minute, value: roundedMins - mins, to: cursor)!

        for item in generatedPlan {
            let duration = TimeInterval(item.task.estimatedMinutes * 60)
            let block = CalendarBlock(
                id: UUID(),
                title: item.task.title,
                startTime: cursor,
                endTime: cursor.addingTimeInterval(duration),
                sourceEmailId: nil,
                category: item.task.bucket == .action ? .focus : .admin
            )
            blocks.append(block)
            cursor = cursor.addingTimeInterval(duration + 5 * 60) // 5 min buffer
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func planStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 15, weight: .semibold))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func formatMins(_ m: Int) -> String {
        m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m/60)h" : "\(m/60)h \(m%60)m")
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
}

// MARK: - Plan item model

struct PlannedItem: Identifiable {
    let id = UUID()
    let task: TimedTask
    let scheduledStartTime: Date?
}

// MARK: - Counting time text animation

struct CountingTimeText: View {
    let targetTime: Date
    @State private var progress: Double = 0

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var interpolatedTime: String {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: targetTime)
        let targetInterval = targetTime.timeIntervalSince(midnight)
        let currentInterval = targetInterval * progress
        let display = midnight.addingTimeInterval(currentInterval)
        return Self.formatter.string(from: display)
    }

    var body: some View {
        Text(interpolatedTime)
            .monospacedDigit()
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.Timed.accent.opacity(0.8))
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    progress = 1.0
                }
            }
    }
}

// MARK: - Plan item row

struct PlanItemRow: View {
    let index: Int
    let item: PlannedItem
    var isRevealed: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            // Sequence number
            Text("\(index)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 20, alignment: .trailing)

            // Scheduled time slot
            if let startTime = item.scheduledStartTime, isRevealed {
                CountingTimeText(targetTime: startTime)
                    .frame(width: 56, alignment: .leading)
            } else {
                Text("0:00 AM")
                    .monospacedDigit()
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.Timed.accent.opacity(0.3))
                    .frame(width: 56, alignment: .leading)
            }

            // Bucket indicator
            Image(systemName: item.task.bucket.icon)
                .font(.system(size: 11))
                .foregroundStyle(item.task.bucket.color)
                .frame(width: 16)

            // Title + sender
            VStack(alignment: .leading, spacing: 2) {
                Text(item.task.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(item.task.sender)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Bucket label
            Text(item.task.bucket.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(item.task.bucket.color)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(item.task.bucket.color.opacity(0.1), in: Capsule())

            // Duration
            Text(item.task.timeLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 48)
        }
    }
}
