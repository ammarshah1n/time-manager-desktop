// MorningCheckInManager.swift — Timed macOS
//
// Thin abstraction around ElevenLabs Conversational AI 2.0. The SDK is the
// voice layer; Opus (via /functions/v1/voice-llm-proxy) is the brain. When the
// conversation ends, we call /functions/v1/extract-voice-learnings to persist
// perceived priorities, hidden context, and rule updates.
//
// Agent config (ops task):
//   ELEVENLABS_MORNING_AGENT_ID env var → the agent in the ElevenLabs dashboard
//   whose Custom LLM URL points at https://<supa>.supabase.co/functions/v1/voice-llm-proxy

import Foundation
import Combine
import SwiftUI
import ElevenLabs

// UserDefaults key — matches what `defaults write com.ammarshahin.timed
// elevenlabs_morning_agent_id <id>` writes, so Yasser can provision the
// agent ID without rebuilding the app.
private let kAgentIdDefaultsKey = "elevenlabs_morning_agent_id"

@MainActor
final class MorningCheckInManager: ObservableObject {

    enum Phase: Equatable {
        case idle
        case connecting
        case active
        case ending
        case ended
        case failed(String)
    }

    struct TranscriptMessage: Identifiable, Hashable {
        let id = UUID()
        let role: String      // "user" | "agent"
        let content: String
    }

    // MARK: - Published UI state

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isAgentSpeaking: Bool = false
    @Published private(set) var transcript: [TranscriptMessage] = []

    // MARK: - Private

    private var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()
    private var lastMessageCount = 0

    // Resolution order: UserDefaults (set via `defaults write`) → env var.
    // Finder-launched macOS apps don't inherit shell env, so UserDefaults wins.
    private var agentId: String {
        if let stored = UserDefaults.standard.string(forKey: kAgentIdDefaultsKey), !stored.isEmpty {
            return stored
        }
        return ProcessInfo.processInfo.environment["ELEVENLABS_MORNING_AGENT_ID"] ?? ""
    }

    // MARK: - Start / End

    func start() async {
        guard !agentId.isEmpty else {
            phase = .failed("ELEVENLABS_MORNING_AGENT_ID not configured. Set the env var to the Custom-LLM agent created in the ElevenLabs dashboard (URL → /functions/v1/voice-llm-proxy).")
            return
        }
        phase = .connecting
        do {
            let conv = try await ElevenLabs.startConversation(agentId: agentId)
            self.conversation = conv
            self.phase = .active
            observe(conv)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func end() async {
        phase = .ending
        if let conv = conversation {
            await conv.endConversation()
        }
        await extractAndPersistLearnings()
        phase = .ended
    }

    // MARK: - Observation

    private func observe(_ conv: Conversation) {
        // State → phase
        conv.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .connecting: self.phase = .connecting
                case .active:     self.phase = .active
                case .ended:      self.phase = .ended
                case .error(let e): self.phase = .failed(e.localizedDescription)
                default: break
                }
            }
            .store(in: &cancellables)

        // Messages → transcript. We infer "agent speaking" from message growth:
        // whenever a new `agent` message appears, treat it as an active utterance
        // for a short debounce window. The SDK's native speaking flag is not
        // publicly exposed in the README example; this is close enough for UI.
        conv.$messages
            .receive(on: RunLoop.main)
            .sink { [weak self] messages in
                guard let self else { return }
                self.transcript = messages.map { m in
                    TranscriptMessage(role: String(describing: m.role), content: m.content)
                }
                if messages.count > self.lastMessageCount {
                    let newestRoleString = messages.last.map { String(describing: $0.role) } ?? ""
                    let isAgent = newestRoleString.lowercased().contains("agent")
                    self.isAgentSpeaking = isAgent
                    if isAgent {
                        // Drop the flag after a short window so the orb settles.
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            self.isAgentSpeaking = false
                        }
                    }
                }
                self.lastMessageCount = messages.count
            }
            .store(in: &cancellables)
    }

    // MARK: - Learning extraction

    private func extractAndPersistLearnings() async {
        // Fire-and-forget — worst case we miss one session's learnings.
        // Never block the UI close on this.
        let transcriptText = transcript
            .map { "\($0.role): \($0.content)" }
            .joined(separator: "\n")
        guard !transcriptText.isEmpty else { return }

        Task.detached {
            let url = Self.supabaseFunctionURL("extract-voice-learnings")
            guard let u = url else { return }
            var req = URLRequest(url: u)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] {
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            let body: [String: Any] = [
                "session_date": ISO8601DateFormatter().string(from: Date()).prefix(10),
                "transcript":   transcriptText,
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    nonisolated private static func supabaseFunctionURL(_ name: String) -> URL? {
        let base = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
        return URL(string: "\(base)/functions/v1/\(name)")
    }
}
