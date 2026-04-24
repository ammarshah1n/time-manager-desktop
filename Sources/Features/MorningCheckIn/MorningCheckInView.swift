// MorningCheckInView.swift — Timed macOS
//
// The ElevenLabs-driven morning check-in. Orb animates while Opus speaks
// (via ElevenLabs TTS). Live transcript scrolls beneath.

import SwiftUI

struct MorningCheckInView: View {
    @StateObject private var manager = MorningCheckInManager()
    @Environment(\.dismiss) private var dismiss
    @State private var transcriptCollapsed = true

    /// User is speaking when the agent isn't and the conversation is active.
    private var isUserSpeaking: Bool {
        guard case .active = manager.phase else { return false }
        return !manager.isAgentSpeaking
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 32)

                OrbView(isActive: manager.isAgentSpeaking, phase: manager.phase)
                    .frame(width: 180, height: 180)

                MicActivityBar(isListening: isUserSpeaking)
                    .frame(width: 70)

                phaseLabel
                    .frame(height: 20)

                transcriptSection
                    .frame(maxWidth: 620)

                Spacer()

                controlRow
                    .padding(.bottom, 36)
            }
        }
        .task {
            await manager.start()
        }
    }

    @ViewBuilder
    private var background: some View {
        ZStack {
            BrandColor.surface
            RadialGradient(
                colors: [BrandColor.primary.opacity(0.22), .clear],
                center: .center, startRadius: 40, endRadius: 520
            )
        }
    }

    @ViewBuilder
    private var phaseLabel: some View {
        switch manager.phase {
        case .idle:
            Text("Ready when you are")
                .font(BrandType.body)
                .foregroundStyle(BrandColor.ink.opacity(0.55))
        case .connecting:
            Text("Connecting…")
                .font(BrandType.body)
                .foregroundStyle(BrandColor.ink.opacity(0.55))
        case .active:
            Text(manager.isAgentSpeaking ? "Speaking" : "Listening")
                .font(BrandType.body)
                .foregroundStyle(BrandColor.primary)
                .contentTransition(.opacity)
        case .ending:
            Text("Saving your session…")
                .font(BrandType.body)
                .foregroundStyle(BrandColor.ink.opacity(0.55))
        case .ended:
            Text("Done")
                .font(BrandType.body)
                .foregroundStyle(BrandColor.ink.opacity(0.55))
        case .failed(let msg):
            Text(msg)
                .font(BrandType.body)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var transcriptSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { transcriptCollapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: transcriptCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                    Text(transcriptCollapsed ? "Show transcript" : "Hide transcript")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(BrandColor.ink.opacity(0.5))
            }
            .buttonStyle(.plain)

            if !transcriptCollapsed {
                transcriptScroll
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(manager.transcript) { msg in
                        HStack(alignment: .top, spacing: 8) {
                            Text(msg.role.lowercased().contains("user") ? "You" : "Timed")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.0)
                                .foregroundStyle(
                                    msg.role.lowercased().contains("user")
                                    ? BrandColor.ink.opacity(0.45)
                                    : BrandColor.primary
                                )
                                .frame(width: 42, alignment: .leading)
                            Text(msg.content)
                                .font(BrandType.body)
                                .foregroundStyle(BrandColor.ink.opacity(0.85))
                        }
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 230)
            .onChange(of: manager.transcript.count) { _, _ in
                if let last = manager.transcript.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 14) {
            switch manager.phase {
            case .active:
                Button("End check-in") {
                    Task { await manager.end() }
                }
                .keyboardShortcut(.escape)
            case .ended:
                Button("Close") { dismiss() }
                    .keyboardShortcut(.return)
            case .failed:
                Button("Skip") { dismiss() }
                    .keyboardShortcut(.return)
            default:
                Button("Cancel") {
                    Task {
                        await manager.end()
                        dismiss()
                    }
                }
                .keyboardShortcut(.escape)
            }
        }
    }
}

// MARK: - Orb

struct OrbView: View {
    let isActive: Bool
    let phase: MorningCheckInManager.Phase

    @State private var pulse: CGFloat = 1.0
    @State private var hue: Double = 0.0

    var body: some View {
        ZStack {
            // Glow halo — amplitude reacts to isActive.
            Circle()
                .fill(BrandColor.primary.opacity(isActive ? 0.35 : 0.18))
                .blur(radius: isActive ? 48 : 28)
                .scaleEffect(isActive ? 1.2 : 1.0)

            // Main orb — radial gradient + slow rotation.
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            BrandColor.primary,
                            BrandColor.accent,
                            BrandColor.primary.opacity(0.75),
                            BrandColor.primary,
                        ],
                        center: .center,
                        angle: .degrees(hue)
                    )
                )
                .scaleEffect(pulse)

            // Specular highlight — a cheap illusion of depth.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.55), .clear],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 2,
                        endRadius: 70
                    )
                )
                .blendMode(.plusLighter)
        }
        .onAppear { startAnimations() }
        .onChange(of: isActive) { _, _ in restartPulse() }
    }

    private func startAnimations() {
        // Slow rotation always running; hue communicates "alive".
        withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
            hue = 360
        }
        restartPulse()
    }

    private func restartPulse() {
        withAnimation(.easeInOut(duration: isActive ? 0.5 : 1.2).repeatForever(autoreverses: true)) {
            pulse = isActive ? 1.08 : 1.02
        }
    }
}
