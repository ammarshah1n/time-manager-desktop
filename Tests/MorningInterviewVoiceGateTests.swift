import Foundation
import Testing

@Suite("Morning Interview Voice Gate")
struct MorningInterviewVoiceGateTests {
    @Test func onAppearDoesNotStartVoiceSpeech() throws {
        let contents = try read("Sources/TimedKit/Features/MorningInterview/MorningInterviewPane.swift")
        let onAppear = try slice(contents, from: ".onAppear {", to: "\n        }\n        .onDisappear")

        #expect(!onAppear.contains("speakForStep("),
                "Morning interview must not speak from onAppear. Voice starts only after explicit user action.")
    }

    @Test func stepSpeechIsGatedByStartedVoiceSession() throws {
        let contents = try read("Sources/TimedKit/Features/MorningInterview/MorningInterviewPane.swift")
        let speakForStep = try slice(contents, from: "private func speakForStep", to: "private func hardcodedTextForStep")

        #expect(contents.contains("@State private var voiceSessionStarted"),
                "Morning interview needs local session state before using TTS.")
        #expect(contents.contains("private var canUseVoice"),
                "Morning interview needs a single voice gate.")
        #expect(speakForStep.contains("guard canUseVoice else { return }"),
                "speakForStep must refuse TTS unless the voice session has been explicitly started.")
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func slice(_ contents: String, from start: String, to end: String) throws -> String {
        guard let startRange = contents.range(of: start),
              let endRange = contents[startRange.upperBound...].range(of: end) else {
            Issue.record("Could not find expected source section from \(start) to \(end)")
            return ""
        }
        return String(contents[startRange.upperBound..<endRange.lowerBound])
    }

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
