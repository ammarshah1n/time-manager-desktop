// DishMeUpHomeView.swift — Timed macOS
//
// The opening screen. One question: what should Yasser do next?
// Hero hero + minutes selector + Dish Me Up button → loading → plan list.
// Calls the generate-dish-me-up Edge Function. No local planning. Opus orders.

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

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case title
        case estimatedMinutes = "estimated_minutes"
        case reason
        case avoidanceFlag = "avoidance_flag"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Dependency(\.supabaseClient) private var supa

    enum Phase: Equatable {
        case idle
        case loading
        case result(DishMeUpPlan)
        case failure(String)
    }

    @State private var phase: Phase = .idle
    @State private var minutes: Int = 45
    @State private var meshT: Double = 0
    @State private var showVoiceCheckIn: Bool = false

    private let presets: [Int] = [15, 30, 45, 60, 90, 120]

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            switch phase {
            case .idle:      idleContent
            case .loading:   loadingContent
            case .result(let plan):   planContent(plan)
            case .failure(let msg):   failureContent(msg)
            }
        }
        .animation(BrandMotion.easeStandard, value: phaseKey)
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

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if reduceMotion {
            BrandColor.surface
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let drift = (sin(t * 0.18) + 1) * 0.5
                meshGradient(drift: drift)
            }
        }
    }

    /// Lifted from IntroView — same 3×3 MeshGradient, reduced amplitude so it
    /// reads as ambient rather than a cinematic takeover.
    private func meshGradient(drift: Double) -> some View {
        let surface = BrandColor.surface
        let primary = BrandColor.primary
        let accent  = BrandColor.accent
        let mist    = BrandColor.mist

        let d = drift
        let points: [SIMD2<Float>] = [
            .init(0, 0), .init(0.5, 0), .init(1, 0),
            .init(0, 0.5), .init(0.5 + Float(d - 0.5) * 0.04, 0.5), .init(1, 0.5),
            .init(0, 1), .init(0.5, 1), .init(1, 1),
        ]
        let colors: [Color] = [
            surface, mist, accent.opacity(0.5),
            mist, primary.opacity(0.18 + d * 0.08), mist,
            accent.opacity(0.35), mist, surface,
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors, smoothsColors: true)
    }

    // MARK: - States

    private var idleContent: some View {
        VStack(spacing: 36) {
            Spacer()

            // Small label + question. Matches the 28pt headline / body scale
            // the rest of the app uses. The IntroView is the place for 72pt
            // display type — this pane lives in the sidebar every session, so
            // calm beats loud.
            VStack(spacing: 10) {
                Text("DISH ME UP")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(BrandColor.primary.opacity(0.75))
                Text("What should you do next?")
                    .font(BrandType.headline)
                    .foregroundStyle(BrandColor.ink)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)

            minuteSelector

            Button(action: start) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text("Dish Me Up")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(minWidth: 240, minHeight: 48)
                .background(
                    LinearGradient(
                        colors: [BrandColor.primary, BrandColor.accent],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: BrandColor.primary.opacity(0.28), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])

            Spacer()

            HStack(spacing: 14) {
                Button {
                    showVoiceCheckIn = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 11))
                        Text("Voice check-in")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(BrandColor.ink.opacity(0.65))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(BrandColor.mist.opacity(0.7)))
                }
                .buttonStyle(.plain)

                Text("\(minutes) min")
                    .font(.system(size: 12))
                    .foregroundStyle(BrandColor.ink.opacity(0.45))
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var minuteSelector: some View {
        HStack(spacing: 10) {
            ForEach(presets, id: \.self) { n in
                let selected = minutes == n
                Button {
                    minutes = n
                } label: {
                    Text(label(for: n))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selected ? .white : BrandColor.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            Capsule().fill(selected ? BrandColor.primary : BrandColor.mist)
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                selected ? BrandColor.primary : BrandColor.ink.opacity(0.06),
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(for minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(minutes % 60)m")
    }

    private var loadingContent: some View {
        VStack(spacing: 28) {
            PulsingOrb()
                .frame(width: 120, height: 120)
            Text("Reading your day…")
                .font(BrandType.tagline)
                .foregroundStyle(BrandColor.ink.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func planContent(_ plan: DishMeUpPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(plan.sessionFraming)
                    .font(BrandType.headline)
                    .foregroundStyle(BrandColor.ink)
                    .padding(.top, 48)
                    .padding(.horizontal, 40)

                VStack(spacing: 14) {
                    ForEach(Array(plan.plan.enumerated()), id: \.element.id) { idx, item in
                        PlanCard(index: idx + 1, item: item, isOverflow: false)
                    }
                }
                .padding(.horizontal, 32)

                if !plan.overflow.isEmpty {
                    Text("OVERFLOW")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(BrandColor.ink.opacity(0.45))
                        .padding(.horizontal, 40)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(plan.overflow) { item in
                            PlanCard(index: nil, item: item, isOverflow: true)
                        }
                    }
                    .padding(.horizontal, 32)
                }

                HStack(spacing: 14) {
                    Button("New plan") { phase = .idle }
                        .keyboardShortcut(.cancelAction)
                    Button("Redish") { start() }
                        .keyboardShortcut("r", modifiers: [.command])
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func failureContent(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(BrandColor.ink.opacity(0.6))
            Text("Couldn't dish up a plan")
                .font(BrandType.headline)
                .foregroundStyle(BrandColor.ink)
            Text(message)
                .font(BrandType.body)
                .foregroundStyle(BrandColor.ink.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Try again") { start() }
                .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: 520)
    }

    // MARK: - Actions

    private func start() {
        phase = .loading
        let m = minutes
        Task { @MainActor in
            do {
                let plan = try await supa.generateDishMeUp(m)
                phase = .result(plan)
            } catch {
                phase = .failure(error.localizedDescription)
            }
        }
    }
}

// MARK: - Plan card

private struct PlanCard: View {
    let index: Int?
    let item: DishMeUpPlanItem
    let isOverflow: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isOverflow ? BrandColor.mist : BrandColor.primary.opacity(0.12))
                    .frame(width: 34, height: 34)
                if let index {
                    Text("\(index)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isOverflow ? BrandColor.ink.opacity(0.5) : BrandColor.primary)
                } else {
                    Image(systemName: "pause")
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColor.ink.opacity(0.45))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BrandColor.ink.opacity(isOverflow ? 0.55 : 1))
                    Spacer()
                    Text("\(item.estimatedMinutes)m")
                        .font(BrandType.mono)
                        .foregroundStyle(BrandColor.ink.opacity(0.55))
                }
                Text(item.reason)
                    .font(BrandType.body)
                    .foregroundStyle(BrandColor.ink.opacity(isOverflow ? 0.5 : 0.75))
                if let flag = item.avoidanceFlag, !flag.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill").font(.system(size: 10))
                        Text(flag).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.Timed.labelSecondary)
                    .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BrandColor.surface.opacity(isOverflow ? 0.6 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(BrandColor.ink.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Loading orb

private struct PulsingOrb: View {
    @State private var scale: CGFloat = 0.85

    var body: some View {
        ZStack {
            Circle()
                .fill(BrandColor.primary.opacity(0.12))
                .blur(radius: 24)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [BrandColor.accent, BrandColor.primary],
                        center: .center, startRadius: 2, endRadius: 60
                    )
                )
                .scaleEffect(scale)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                scale = 1.05
            }
        }
        .accessibilityLabel("Loading plan")
    }
}

