// DishMeUpHomeView.swift — Timed macOS
//
// "What should I do next, given the time I have?"
// Calls the generate-dish-me-up Edge Function. No local planning. Opus orders.
//
// Visual recipe (per .claude/skills/timed-design):
// - Apple Calendar / Reminders / Settings aesthetic
// - Background: `Color.Timed.backgroundPrimary`. No mesh, no animation.
// - Idle: native segmented `Picker` for minutes, plain `.borderedProminent` button
// - Loading: native `ProgressView()` with secondary caption
// - Result: native `List(.plain)` rows matching `TasksPane` recipe — `BucketDot`,
//   13pt title, 12pt secondary reason, monospaced-digit time
// - Failure: native `ContentUnavailableView` style — icon + heading + retry

import SwiftUI
import Dependencies

// MARK: - Models (match the Edge Function response)

struct DishMeUpPlanItem: Codable, Identifiable, Hashable {
    var id: String { taskId }
    let taskId: String
    let title: String
    let estimatedMinutes: Int
    let reason: String
    let avoidanceFlag: String?
    /// Bucket key from the Edge Function (e.g. "Action", "Reply"). Optional —
    /// older responses don't include it; the row falls back to a neutral dot.
    let bucket: String?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case title
        case estimatedMinutes = "estimated_minutes"
        case reason
        case avoidanceFlag = "avoidance_flag"
        case bucket
    }

    /// Map the JSON bucket string to a TaskBucket. Tolerant of casing/spacing.
    var resolvedBucket: TaskBucket? {
        guard let raw = bucket?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let exact = TaskBucket(rawValue: raw) { return exact }
        let normalised = raw.lowercased()
        return TaskBucket.allCases.first { $0.rawValue.lowercased() == normalised }
    }
}

struct DishMeUpPlan: Codable, Equatable {
    let sessionFraming: String
    let plan: [DishMeUpPlanItem]
    let overflow: [DishMeUpPlanItem]

    enum CodingKeys: String, CodingKey {
        case sessionFraming = "session_framing"
        case plan
        case overflow
    }
}

struct DishMeUpRequest: Codable {
    let availableMinutes: Int
    let currentTime: String

    enum CodingKeys: String, CodingKey {
        case availableMinutes = "available_minutes"
        case currentTime = "current_time"
    }
}

// MARK: - View

struct DishMeUpHomeView: View {
    @Dependency(\.supabaseClient) private var supa

    enum Phase: Equatable {
        case idle
        case loading
        case result(DishMeUpPlan)
        case failure(String)
    }

    @State private var phase: Phase = .idle
    @State private var minutes: Int = 45
    @State private var showVoiceCheckIn: Bool = false

    private let presets: [Int] = [15, 30, 45, 60, 90, 120]

    var body: some View {
        ZStack {
            Color.Timed.backgroundPrimary.ignoresSafeArea()

            switch phase {
            case .idle:              idleContent
            case .loading:           loadingContent
            case .result(let plan):  planContent(plan)
            case .failure(let msg):  failureContent(msg)
            }
        }
        .navigationTitle("Dish Me Up")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Voice check-in") { showVoiceCheckIn = true }
                    .help("Voice check-in — talk through your day. Your assistant listens, learns how you think, and surfaces what matters tomorrow.")
            }
        }
        .animation(TimedMotion.smooth, value: phaseKey)
        .sheet(isPresented: $showVoiceCheckIn) {
            MorningCheckInView()
                .frame(minWidth: 720, minHeight: 640)
        }
    }

    /// Coarse key for SwiftUI animation diffing (Phase isn't Hashable due to DishMeUpPlan).
    private var phaseKey: String {
        switch phase {
        case .idle: "idle"
        case .loading: "loading"
        case .result: "result"
        case .failure: "failure"
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: TimedLayout.Spacing.xl) {
            VStack(spacing: TimedLayout.Spacing.xs) {
                Text("How much time do you have?")
                    .font(TimedType.title2)
                    .foregroundStyle(Color.Timed.labelPrimary)
                Text("Pick a window. Dish me up the right work in the right order.")
                    .font(TimedType.body)
                    .foregroundStyle(Color.Timed.labelSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TimedLayout.Spacing.xxxl)

            minuteSelector

            Button("Dish Me Up") { start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])

            Text("\(minutes) min")
                .font(TimedType.footnote)
                .foregroundStyle(Color.Timed.labelTertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var minuteSelector: some View {
        HStack(spacing: TimedLayout.Spacing.xs) {
            ForEach(presets, id: \.self) { n in
                let selected = minutes == n
                Button {
                    minutes = n
                } label: {
                    Text(label(for: n))
                        .font(TimedType.subheadline)
                        .foregroundStyle(selected ? Color.white : Color.Timed.labelPrimary)
                        .padding(.horizontal, TimedLayout.Spacing.sm)
                        .padding(.vertical, TimedLayout.Spacing.xs)
                        .background(
                            Capsule().fill(selected ? Color.Timed.labelPrimary : Color.Timed.backgroundSecondary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(for minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(minutes % 60)m")
    }

    // MARK: - Loading

    private var loadingContent: some View {
        VStack(spacing: TimedLayout.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("Reading your day…")
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.labelSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result

    private func planContent(_ plan: DishMeUpPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TimedLayout.Spacing.xl) {
                Text(plan.sessionFraming)
                    .font(TimedType.title3.weight(.semibold))
                    .foregroundStyle(Color.Timed.labelPrimary)
                    .padding(.top, TimedLayout.Spacing.xl)
                    .padding(.horizontal, TimedLayout.Spacing.lg)

                VStack(spacing: TimedLayout.Spacing.xxs) {
                    ForEach(Array(plan.plan.enumerated()), id: \.element.id) { idx, item in
                        PlanRow(index: idx + 1, item: item, isOverflow: false)
                    }
                }
                .padding(.horizontal, TimedLayout.Spacing.lg)

                if !plan.overflow.isEmpty {
                    Text("OVERFLOW")
                        .font(TimedType.caption2)
                        .tracking(1.2)
                        .foregroundStyle(Color.Timed.labelTertiary)
                        .padding(.horizontal, TimedLayout.Spacing.lg)
                        .padding(.top, TimedLayout.Spacing.xs)

                    VStack(spacing: TimedLayout.Spacing.xxs) {
                        ForEach(plan.overflow) { item in
                            PlanRow(index: nil, item: item, isOverflow: true)
                        }
                    }
                    .padding(.horizontal, TimedLayout.Spacing.lg)
                }

                HStack(spacing: TimedLayout.Spacing.sm) {
                    Button("New plan") { phase = .idle }
                        .keyboardShortcut(.cancelAction)
                    Button("Refresh") { start() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("r", modifiers: [.command])
                }
                .padding(.horizontal, TimedLayout.Spacing.lg)
                .padding(.bottom, TimedLayout.Spacing.xxl)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Failure

    private func failureContent(_ message: String) -> some View {
        VStack(spacing: TimedLayout.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.Timed.labelTertiary)
            Text("Couldn't dish up a plan")
                .font(TimedType.title3)
                .foregroundStyle(Color.Timed.labelPrimary)
            Text(message)
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TimedLayout.Spacing.xxxl)
            Button("Try again") { start() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func start() {
        phase = .loading
        let m = minutes
        Task { @MainActor in
            do {
                let plan = try await supa.generateDishMeUp(m)
                DishMeUpStore.shared.update(plan: plan, minutes: m)
                phase = .result(plan)
            } catch {
                phase = .failure(error.localizedDescription)
            }
        }
    }
}

// MARK: - Plan row (Apple-Reminders-style)

private struct PlanRow: View {
    let index: Int?
    let item: DishMeUpPlanItem
    let isOverflow: Bool

    var body: some View {
        HStack(alignment: .top, spacing: TimedLayout.Spacing.sm) {
            if let index {
                Text("\(index)")
                    .font(TimedType.subheadline)
                    .foregroundStyle(Color.Timed.labelTertiary)
                    .monospacedDigit()
                    .frame(width: 18, alignment: .trailing)
            } else {
                Image(systemName: "pause")
                    .font(TimedType.caption)
                    .foregroundStyle(Color.Timed.labelTertiary)
                    .frame(width: 18)
            }

            // Bucket-coloured dot when the Edge Function surfaces it; neutral grey
            // as fallback for older responses or unrecognised bucket strings.
            BucketDot(color: item.resolvedBucket?.dotColor ?? Color.Timed.labelSecondary)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: TimedLayout.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(TimedType.subheadline)
                        .foregroundStyle(isOverflow ? Color.Timed.labelTertiary : Color.Timed.labelPrimary)
                    Spacer()
                    Text("\(item.estimatedMinutes)m")
                        .font(TimedType.caption)
                        .foregroundStyle(Color.Timed.labelSecondary)
                        .monospacedDigit()
                }
                Text(item.reason)
                    .font(TimedType.caption)
                    .foregroundStyle(Color.Timed.labelSecondary)
                if let flag = item.avoidanceFlag, !flag.isEmpty {
                    HStack(spacing: TimedLayout.Spacing.xxs) {
                        Image(systemName: "flag")
                            .font(.system(size: 10))
                        Text(flag).font(TimedType.caption)
                    }
                    .foregroundStyle(Color.Timed.labelSecondary)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, TimedLayout.Spacing.sm)
        .padding(.vertical, TimedLayout.Spacing.sm)
        .background(Color.Timed.backgroundSecondary, in: RoundedRectangle(cornerRadius: TimedLayout.Radius.input))
    }
}
