// MorningCheckInManager.swift — Timed macOS
//
// Thin abstraction around ElevenLabs Conversational AI 2.0. The SDK is the
// voice layer; Opus (via /functions/v1/voice-llm-proxy) is the brain. When the
// conversation ends, we call /functions/v1/extract-voice-learnings to persist
// perceived priorities, hidden context, and rule updates.
//
// Agent config:
//   The agent ID is baked into the binary as `kBakedInAgentID` so a fresh
//   install just works — no env vars, no `defaults write`, no Settings field.
//   The agent in the ElevenLabs dashboard has its Custom-LLM URL pointed at
//   https://fpmjuufefhtlwbfinxlx.supabase.co/functions/v1/voice-llm-proxy
//   and Deepgram set as its ASR provider. Public ID — not a secret.
//
//   Override order (for testing/dev): UserDefaults > env var > baked-in constant.

import Foundation
import Combine
import SwiftUI
import ElevenLabs

// Baked-in default. Override locally with:
//   defaults write com.ammarshahin.timed elevenlabs_morning_agent_id <id>
private let kBakedInAgentID = "agent_3501kpyz0cnrfj8tgbb2bmg5arfk"
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

    // Resolution order: UserDefaults override → env var → baked-in constant.
    // Finder-launched macOS apps don't inherit shell env, so the baked-in
    // constant is what fresh installs actually hit.
    private var agentId: String {
        if let stored = UserDefaults.standard.string(forKey: kAgentIdDefaultsKey), !stored.isEmpty {
            return stored
        }
        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_MORNING_AGENT_ID"], !env.isEmpty {
            return env
        }
        return kBakedInAgentID
    }

    // MARK: - Start / End

    func start() async {
        guard !agentId.isEmpty else {
            phase = .failed("ElevenLabs Agent ID not set. Open Settings → Voice and paste the Agent ID from your ElevenLabs dashboard (the agent whose Custom-LLM URL points at /functions/v1/voice-llm-proxy).")
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
            guard let url = SupabaseEndpoints.functionURL("extract-voice-learnings") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(SupabaseEndpoints.authHeader, forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "session_date": ISO8601DateFormatter().string(from: Date()).prefix(10),
                "transcript":   transcriptText,
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}
