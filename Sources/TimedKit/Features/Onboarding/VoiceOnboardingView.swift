// VoiceOnboardingView.swift — Timed macOS
//
// Replaces the 10-step click-through OnboardingFlow with a fully
// voice-conversational setup driven by the ElevenLabs Morning Agent.
// The same agent is used — voice-llm-proxy branches on
// executives.onboarded_at to pick onboarding vs morning-check-in prompts.
//
// When the agent emits the literal tag [[ONBOARDING_COMPLETE]], this view:
//   1. Ends the ElevenLabs conversation
//   2. POSTs the transcript to /functions/v1/extract-onboarding-profile
//      (Haiku parses → writes to executives + sets onboarded_at)
//   3. Calls onComplete() so the app drops into Dish Me Up
//
// Visual pass: Apple Calendar / System Settings aesthetic. No gradients, no
// decorative chrome, no oversized display type. The orb is the one feature
// element on the screen.

import SwiftUI

struct VoiceOnboardingView: View {
    let onComplete: () -> Void

    @StateObject private var manager = MorningCheckInManager()
    @State private var sawCompletionTag = false
    @State private var isFinalising = false
    @State private var transcriptCollapsed = true  // Default hidden — open on tap

    var body: some View {
        ZStack {
            // Plain system-app surface. No gradient, no radial tint.
            Color.Timed.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: TimedLayout.Spacing.xl) {
                Spacer(minLength: TimedLayout.Spacing.hero)

                OrbView(isActive: manager.isAgentSpeaking, phase: manager.phase)
                    .frame(width: orbSize, height: orbSize)

                // Mic activity bar — pulses only while the user is speaking
                // (agent is NOT speaking and the conversation is active).
                MicActivityBar(isListening: isUserSpeaking)
                    .frame(width: micBarWidth)

                phaseLabel
                    .frame(height: phaseLabelHeight)

                transcriptSection
                    .frame(maxWidth: transcriptMaxWidth)

                Spacer()

                if isFinalising {
                    Text("Saving your setup…")
                        .font(TimedType.body)
                        .foregroundStyle(Color.Timed.labelSecondary)
                        .padding(.bottom, TimedLayout.Spacing.xxl)
                } else {
                    skipControl
                        .padding(.bottom, TimedLayout.Spacing.xxl)
                }
            }
        }
        .task {
            await manager.start()
        }
        .onChange(of: manager.transcript.count) { _, _ in
            checkForCompletionTag()
        }
    }

    // MARK: - Layout constants (named here because OrbView/MicActivityBar are
    // feature components, not general tokens — kept local and semantic.)

    private var orbSize: CGFloat { 220 }
    private var micBarWidth: CGFloat { 80 }
    private var phaseLabelHeight: CGFloat { 22 }
    private var transcriptMaxWidth: CGFloat { 640 }
    private var transcriptMaxHeight: CGFloat { 240 }

    // MARK: - Phase label

    @ViewBuilder
    private var phaseLabel: some View {
        switch manager.phase {
        case .idle:
            Text("Ready")
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.labelSecondary)
        case .connecting:
            Text("Connecting…")
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.labelSecondary)
        case .active:
            // The only element on this screen allowed to use the accent.
            Text(manager.isAgentSpeaking ? "Timed is speaking" : "Listening")
                .font(TimedType.body)
                .foregroundStyle(Color.Timed.accent)
                .contentTransition(.opacity)
        case .ending:
            Text("Saving…")
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
                .padding(.horizontal, TimedLayout.Spacing.hero)
        }
    }

    // MARK: - Listening state

    /// True when Yasser is talking — the agent is not speaking and we're actively connected.
    private var isUserSpeaking: Bool {
        guard case .active = manager.phase else { return false }
        return !manager.isAgentSpeaking
    }

    // MARK: - Transcript (collapsible — default hidden so the orb is the focus)

    private var transcriptSection: some View {
        VStack(spacing: TimedLayout.Spacing.xs) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { transcriptCollapsed.toggle() }
            } label: {
                HStack(spacing: TimedLayout.Spacing.xxs) {
                    Image(systemName: transcriptCollapsed ? "chevron.down" : "chevron.up")
                        .font(TimedType.caption2)
                    Text(transcriptCollapsed ? "Show transcript" : "Hide transcript")
                        .font(TimedType.caption)
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
                LazyVStack(alignment: .leading, spacing: TimedLayout.Spacing.sm) {
                    ForEach(manager.transcript) { msg in
                        HStack(alignment: .top, spacing: TimedLayout.Spacing.sm) {
                            Text(msg.role.lowercased().contains("user") ? "You" : "Timed")
                                .font(TimedType.caption2)
                                .foregroundStyle(Color.Timed.labelTertiary)
                                .frame(width: 44, alignment: .leading)
                            Text(cleanForDisplay(msg.content))
                                .font(TimedType.body)
                                .foregroundStyle(Color.Timed.labelPrimary)
                        }
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, TimedLayout.Spacing.xl)
                .padding(.vertical, TimedLayout.Spacing.sm)
            }
            .frame(maxHeight: transcriptMaxHeight)
            .onChange(of: manager.transcript.count) { _, _ in
                if let last = manager.transcript.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // The completion tag is for the app, not for display.
    private func cleanForDisplay(_ s: String) -> String {
        s.replacingOccurrences(of: "[[ONBOARDING_COMPLETE]]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Skip control (escape hatch for dev; native-styled, quiet)

    private var skipControl: some View {
        Button("Skip setup") {
            Task { await finalise(extractProfile: false) }
        }
        .buttonStyle(.plain)
        .font(TimedType.body)
        .foregroundStyle(Color.Timed.labelTertiary)
    }

    // MARK: - Completion detection

    private func checkForCompletionTag() {
        guard !sawCompletionTag else { return }
        let joined = manager.transcript
            .filter { $0.role.lowercased().contains("agent") }
            .map { $0.content }
            .joined(separator: " ")
        if joined.contains("[[ONBOARDING_COMPLETE]]") {
            sawCompletionTag = true
            Task { await finalise(extractProfile: true) }
        }
    }

    // MARK: - Finalise

    private func finalise(extractProfile: Bool) async {
        isFinalising = true
        await manager.end()
        if extractProfile {
            await postTranscriptToExtractor()
        } else {
            // User skipped — mark onboarded so we don't re-run every launch.
            await markOnboardedDirect()
        }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }

    private func postTranscriptToExtractor() async {
        let transcriptText = manager.transcript
            .map { "\($0.role): \(cleanForDisplay($0.content))" }
            .joined(separator: "\n")
        guard !transcriptText.isEmpty else { return }
        await fireFunction("extract-onboarding-profile",
                           body: ["transcript": transcriptText])
    }

    private func markOnboardedDirect() async {
        // Hit the extractor with an empty transcript so Haiku applies defaults
        // and onboarded_at gets set server-side. Cheap enough.
        await fireFunction("extract-onboarding-profile",
                           body: ["transcript": "user accepted defaults"])
    }

    private func fireFunction(_ name: String, body: [String: Any]) async {
        let baseURL = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
        guard let url = URL(string: "\(baseURL)/functions/v1/\(name)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let anon = UserDefaults.standard.string(forKey: "supabase_anon_key")
            ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZwbWp1dWZlZmh0bHdiZmlueGx4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5MTMxMDEsImV4cCI6MjA5MDQ4OTEwMX0.VUtjezhFMpwrcVMXltyYmU2n0Xazi9lvhuwAQlKOTO4"
        req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
}
