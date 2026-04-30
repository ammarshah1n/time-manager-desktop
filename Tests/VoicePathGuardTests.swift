// VoicePathGuardTests.swift — Timed
// Build-failing regression guard. Voice path is locked to ElevenLabs + Deepgram +
// Anthropic Opus. Apple TTS (AVSpeechSynthesizer / NSSpeechSynthesizer) and Apple
// STT (SFSpeechRecognizer) must NEVER appear in the orb call graph — if a
// well-meaning future change reintroduces one, this test fails the build.
//
// VoiceCaptureService is exempt — it's the dictation-to-task feature (Apple
// Speech is the only on-device option), not the orb conversation path.

import Foundation
import Testing

@Suite("Voice Path Guard")
struct VoicePathGuardTests {
    /// Files in the orb conversation call graph. None of these may reference
    /// Apple TTS/STT symbols.
    private let orbFiles: [String] = [
        "Sources/TimedKit/Core/Services/StreamingTTSService.swift",
        "Sources/TimedKit/Core/Services/SpeechService.swift",
        "Sources/TimedKit/Core/Services/DeepgramSTTService.swift",
        "Sources/TimedKit/Features/Conversation/ConversationModel.swift",
        "Sources/TimedKit/Features/Conversation/ConversationView.swift",
        "Sources/TimedKit/Core/Clients/ConversationAIClient.swift",
    ]

    private let bannedSymbols: [String] = [
        "AVSpeechSynthesizer",
        "NSSpeechSynthesizer",
        "SFSpeechRecognizer",
        "SFSpeechAudioBufferRecognitionRequest",
    ]

    @Test func noAppleTTSorSTTInOrbCallGraph() throws {
        let repoRoot = repoRoot()
        for relativePath in orbFiles {
            let fullPath = repoRoot.appendingPathComponent(relativePath)
            // If a file in the list is renamed or removed, fail loudly so the
            // guard list stays in sync with reality.
            #expect(FileManager.default.fileExists(atPath: fullPath.path),
                    "Orb-graph file missing — update VoicePathGuardTests when refactoring: \(relativePath)")
            guard let contents = try? String(contentsOf: fullPath, encoding: .utf8) else { continue }
            for symbol in bannedSymbols {
                #expect(!contents.contains(symbol),
                        "Banned symbol \"\(symbol)\" found in \(relativePath). The orb is locked to ElevenLabs + Deepgram + Opus — Apple TTS/STT must not appear in this call graph.")
            }
        }
    }

    /// Walk up from this source file to the repo root — works regardless of
    /// where `swift test` is invoked from.
    private func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
