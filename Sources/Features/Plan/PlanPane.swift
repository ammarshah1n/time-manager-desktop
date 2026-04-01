// PlanPane.swift — Timed macOS
// "Dish me up" — declare available time, get a sequenced work plan.
// Sequences tasks by bucket priority: Reply → Action → Read Today → Read This Week → Waiting

import SwiftUI

struct PlanPane: View {
    @Binding var tasks: [TimedTask]
    @Binding var blocks: [CalendarBlock]

    @State private var availableMinutes: Int = 60
    @State private var customMinutes: String = "60"
    @State private var useCustom = false
    @State private var generatedPlan: [PlannedItem] = []
    @State private var planGenerated = false

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
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 13, weight: .medium))
                            .frame(minWidth: 64)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(
                                !useCustom && availableMinutes == preset.mins
                                    ? Color.indigo : Color(.controlBackgroundColor),
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
                        .onTapGesture { useCustom = true; planGenerated = false }
                    Text("min")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    useCustom ? Color.indigo : Color(.controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(useCustom ? .white : .primary)
                .onTapGesture { useCustom = true }
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
                .background(.indigo, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    // MARK: - Plan prompt (pre-generation)

    private var planPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.indigo.opacity(0.6))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to plan")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Hit \"Dish me up\" and Timed will sequence your tasks by urgency and time fit.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Task inventory
            let total = tasks.count
            let totalMins = tasks.reduce(0) { $0 + $1.estimatedMinutes }
            if total > 0 {
                HStack(spacing: 16) {
                    planStat("\(total)", "tasks queued")
                    planStat(formatMins(totalMins), "total backlog")
                }
                .padding(.top, 8)
            }
        }
        .padding(18)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
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
                    .tint(.indigo)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            // Task sequence
            VStack(spacing: 2) {
                ForEach(Array(generatedPlan.enumerated()), id: \.element.id) { idx, item in
                    PlanItemRow(index: idx + 1, item: item)
                }
            }
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            // Overflow notice
            let overflow = tasks.filter { t in
                !generatedPlan.contains(where: { $0.task.id == t.id })
            }
            if !overflow.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("\(overflow.count) tasks don't fit in \(formatMins(totalAvailable)) — left in queue.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Generation logic

    private func generate() {
        let planTasks = tasks.filter { !$0.isDone }.map { toPlanTask($0) }
        let request = PlanRequest(
            workspaceId: UUID(),   // placeholder until Supabase is wired
            profileId: UUID(),
            availableMinutes: totalAvailable,
            moodContext: nil,
            behaviouralRules: [],
            tasks: planTasks
        )
        let result = PlanningEngine.generatePlan(request)

        // Map PlanItems back to PlannedItems using original TimedTask
        let taskById = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        generatedPlan = result.items.compactMap { item in
            guard let original = taskById[item.task.id] else { return nil }
            return PlannedItem(task: original)
        }
        planGenerated = true
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
            isTransitSafe: task.isTransitSafe
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
}

// MARK: - Plan item row

struct PlanItemRow: View {
    let index: Int
    let item: PlannedItem

    var body: some View {
        HStack(spacing: 12) {
            // Sequence number
            Text("\(index)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 20, alignment: .trailing)

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
