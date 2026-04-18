// IntroView.swift — Timed macOS
//
// Cinematic first-launch cover.
//
// Animation technique chosen: **circular mask reveal** for the logo, paired
// with a slow MeshGradient hue drift behind it. Justification — executive
// mood is "calm-but-sharp": a mask reveal reads as cognitive focus
// materialising into clarity. A stroke-draw would feel playful; a primitive
// morph would feel abstract. One technique, executed well.
//
// All animations are transform/opacity only — no layout-affecting modifiers
// inside animation blocks. ProMotion-friendly (no overdraw, no heavy blurs).

import ComposableArchitecture
import SwiftUI

struct IntroView: View {

    // MARK: - Store

    @Bindable var store: StoreOf<IntroFeature>

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - View-local animation state

    @State private var revealDiameter: CGFloat = 0     // 0 → logoSize * 1.6
    @State private var logoOpacity: Double = 0          // 0 → 1
    @State private var logoScale: CGFloat = 1.0         // 1 → 0.35 on exit
    @State private var meshPhase: Double = 0            // drives hue drift via TimelineView
    @State private var wordsVisible: Int = 0            // tagline reveal counter
    @State private var exitBackgroundMorph: Double = 0  // 0 → 1 on exit
    @State private var didStart: Bool = false

    // MARK: - Constants

    private let logoSize: CGFloat = 180
    private let tagline: [String] = ["The", "operating", "system", "that", "thinks", "with", "you."]

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundLayer
                .ignoresSafeArea()

            VStack(spacing: 36) {
                logoLayer
                taglineLayer
                    .frame(height: 32)
            }
            .scaleEffect(logoScale)

            VStack {
                HStack {
                    Spacer()
                    skipButton
                        .padding(.top, 24)
                        .padding(.trailing, 28)
                }
                Spacer()
            }
        }
        .opacity(store.phase == .finished ? 0 : 1)
        .animation(.easeOut(duration: BrandMotion.durBase), value: store.phase == .finished)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            store.send(.onAppear(reduceMotion: reduceMotion))
            if reduceMotion {
                runReducedSequence()
            } else {
                runFullSequence()
            }
        }
        .onChange(of: store.phase) { _, newPhase in
            if newPhase == .exiting {
                runExitAnimation()
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if reduceMotion {
            BrandColor.surface
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let drift = (sin(t * 0.25) + 1) * 0.5         // 0..1, 24s-ish loop
                meshBackground(drift: drift, exitMorph: exitBackgroundMorph)
            }
        }
    }

    /// 3×3 MeshGradient drifting through BrandPrimary / accent / surface.
    /// On exit, colours morph toward a flat BrandColor.surface so the handoff
    /// into the resting app surface feels continuous rather than a hard cut.
    private func meshBackground(drift: Double, exitMorph: Double) -> some View {
        let surface = BrandColor.surface
        let primary = BrandColor.primary
        let accent  = BrandColor.accent
        let mist    = BrandColor.mist

        func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
            // Morph via SwiftUI's built-in opacity stack — simple + correct.
            // At t=0 returns `a`; at t=1 returns `b`.
            let clamped = max(0, min(1, t))
            return clamped < 0.5 ? a.opacity(1 - clamped) : b.opacity(clamped)
        }

        let m = exitMorph
        let d = drift

        let points: [SIMD2<Float>] = [
            .init(0, 0), .init(0.5, 0), .init(1, 0),
            .init(0, 0.5), .init(0.5 + Float(d - 0.5) * 0.08, 0.5), .init(1, 0.5),
            .init(0, 1), .init(0.5, 1), .init(1, 1),
        ]

        let colors: [Color] = [
            blend(primary, surface, m),
            blend(mist, surface, m),
            blend(accent, surface, m),

            blend(accent.opacity(0.75 + d * 0.25), surface, m),
            blend(primary.opacity(0.9), surface, m),
            blend(mist, surface, m),

            blend(mist, surface, m),
            blend(accent, surface, m),
            blend(primary, surface, m),
        ]

        return MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: colors,
            smoothsColors: true
        )
    }

    // MARK: - Logo

    private var logoLayer: some View {
        BrandAsset.logoImage()
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: logoSize, height: logoSize)
            .opacity(logoOpacity)
            .mask(
                Circle()
                    .frame(width: revealDiameter, height: revealDiameter)
            )
            .shadow(color: BrandColor.primary.opacity(0.35), radius: 40, x: 0, y: 12)
    }

    // MARK: - Tagline

    private var taglineLayer: some View {
        HStack(spacing: 6) {
            ForEach(Array(tagline.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(BrandType.tagline)
                    .foregroundStyle(BrandColor.ink)
                    .opacity(index < wordsVisible ? 1 : 0)
                    .offset(y: index < wordsVisible ? 0 : 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tagline.joined(separator: " "))
    }

    // MARK: - Skip

    private var skipButton: some View {
        Button {
            store.send(.skipTapped)
        } label: {
            Text("Skip")
                .font(BrandType.body)
                .foregroundStyle(BrandColor.ink.opacity(0.65))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(BrandColor.ink.opacity(0.08))
                )
                .overlay(
                    Capsule().strokeBorder(BrandColor.ink.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(store.skipAvailable ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: store.skipAvailable)
    }

    // MARK: - Sequences

    private func runFullSequence() {
        // Phase 1: reveal (mask expands + fade in) — 0.9s
        withAnimation(BrandMotion.easeExpressive) {
            revealDiameter = logoSize * 1.6
            logoOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            store.send(.revealCompleted)
            revealTagline()
        }
    }

    private func revealTagline() {
        // Phase 2: word-by-word typing via staggered opacity/offset.
        for index in 0..<tagline.count {
            let delay = Double(index) * BrandMotion.wordStagger
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: BrandMotion.durBase)) {
                    wordsVisible = index + 1
                }
            }
        }
        let total = Double(tagline.count) * BrandMotion.wordStagger + BrandMotion.durBase
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            store.send(.taglineCompleted)
        }
    }

    /// Triggered when store.phase becomes .exiting — drives the visual exit.
    private func runExitAnimation() {
        withAnimation(.easeInOut(duration: 0.55)) {
            logoScale = 0.35
            logoOpacity = 0
            exitBackgroundMorph = 1.0
        }
    }

    private func runReducedSequence() {
        // Show final composed frame statically, then fade out on completion.
        revealDiameter = logoSize * 1.6
        logoOpacity = 1.0
        wordsVisible = tagline.count
    }
}

