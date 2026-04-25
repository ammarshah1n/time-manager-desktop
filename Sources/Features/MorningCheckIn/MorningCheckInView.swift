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
        Color.Timed.backgroundPrimary
    }

    @ViewBuilder
    private var phaseLabel: some View {
        switch manager.phase {
        case .idle:
            Text("Ready when you are")
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.labelSecondary)
        case .connecting:
            Text("Connecting…")
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.labelSecondary)
        case .active:
            Text(manager.isAgentSpeaking ? "Speaking" : "Listening")
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.labelPrimary)
                .contentTransition(.opacity)
        case .ending:
            Text("Saving your session…")
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.labelSecondary)
        case .ended:
            Text("Done")
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.labelSecondary)
        case .failed(let msg):
            Text(msg)
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.destructive)
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
                .foregroundStyle(Color.Timed.labelTertiary)
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
                                .foregroundStyle(Color.Timed.labelTertiary)
                                .frame(width: 42, alignment: .leading)
                            Text(msg.content)
                                .font(TimedType.body)
                                .foregroundStyle(Color.Timed.labelPrimary)
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

// MARK: - Voice indicator
//
// Static, state-aware system icon. No gradients, no decorative pulse — every
// animation here is bound to a real signal (the phase changes, or
// `.symbolEffect(.variableColor.iterative)` while the agent speaks).
// Apple's Voice Memos / Siri use the same idiom.

struct OrbView: View {
    let isActive: Bool
    let phase: MorningCheckInManager.Phase

    var body: some View {
        ZStack {
            switch phase {
            case .idle, .ended:
                Image(systemName: "mic")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.Timed.labelTertiary)

            case .connecting, .ending:
                ProgressView()
                    .controlSize(.large)

            case .active:
                if isActive {
                    Image(systemName: "waveform")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color.Timed.labelPrimary)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color.Timed.destructive)
                        .contentTransition(.symbolEffect(.replace))
                }

            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.Timed.destructive)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle, .ended:    return "Microphone idle"
        case .connecting:      return "Connecting"
        case .ending:          return "Saving session"
        case .active:          return isActive ? "Speaking" : "Listening"
        case .failed:          return "Error"
        }
    }
}
