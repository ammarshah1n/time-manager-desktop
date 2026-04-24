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

import SwiftUI

struct VoiceOnboardingView: View {
    let onComplete: () -> Void

    @StateObject private var manager = MorningCheckInManager()
    @State private var sawCompletionTag = false
    @State private var isFinalising = false
    @State private var transcriptCollapsed = true  // Default hidden — open on tap

    var body: some View {
        ZStack {
            // Same hero treatment as IntroView so the handoff feels continuous.
            background.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 56)

                OrbView(isActive: manager.isAgentSpeaking, phase: manager.phase)
                    .frame(width: 220, height: 220)

                // Mic activity bar — pulses only while the user is speaking
                // (agent is NOT speaking and the conversation is active).
                MicActivityBar(isListening: isUserSpeaking)
                    .frame(width: 80)

                phaseLabel
                    .frame(height: 22)

                transcriptSection
                    .frame(maxWidth: 640)

                Spacer()

                if isFinalising {
                    Text("Saving your setup…")
                        .font(BrandType.body)
                        .foregroundStyle(BrandColor.ink.opacity(0.55))
                        .padding(.bottom, 36)
                } else {
                    skipControl
                        .padding(.bottom, 36)
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

    // MARK: - Background (matches IntroView ambience)

    @ViewBuilder
    private var background: some View {
        ZStack {
            BrandColor.surface
            RadialGradient(
                colors: [BrandColor.primary.opacity(0.28), .clear],
                center: .center, startRadius: 40, endRadius: 620
            )
        }
    }

    // MARK: - Phase label

    @ViewBuilder
    private var phaseLabel: some View {
        switch manager.phase {
        case .idle:
            Text("Ready")
                .font(BrandType.body)
                .foregroundStyle(BrandColor.ink.opacity(0.55))
        case .connecting:
            Text("Connecting…")
                .font(BrandType.body)
                .foregroundStyle(BrandColor.ink.opacity(0.55))
        case .active:
            Text(manager.isAgentSpeaking ? "Timed is speaking" : "Listening")
                .font(BrandType.body)
                .foregroundStyle(BrandColor.primary)
                .contentTransition(.opacity)
        case .ending:
            Text("Saving…")
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
                .padding(.horizontal, 48)
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
                        HStack(alignment: .top, spacing: 10) {
                            Text(msg.role.lowercased().contains("user") ? "You" : "Timed")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.0)
                                .foregroundStyle(
                                    msg.role.lowercased().contains("user")
                                    ? BrandColor.ink.opacity(0.45)
                                    : BrandColor.primary
                                )
                                .frame(width: 44, alignment: .leading)
                            Text(cleanForDisplay(msg.content))
                                .font(BrandType.body)
                                .foregroundStyle(BrandColor.ink.opacity(0.88))
                        }
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 240)
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

    // MARK: - Skip control (escape hatch for dev; fades once the orb settles in)

    private var skipControl: some View {
        Button("Skip setup") {
            Task { await finalise(extractProfile: false) }
        }
        .buttonStyle(.plain)
        .font(BrandType.body)
        .foregroundStyle(BrandColor.ink.opacity(0.4))
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
