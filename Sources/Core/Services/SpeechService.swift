// SpeechService.swift — Timed Core
// Text-to-speech via AVSpeechSynthesizer.
// British English voice, executive-appropriate tone and pacing.

import AVFoundation
import SwiftUI

@MainActor
final class SpeechService: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var isSpeaking: Bool = false
    @AppStorage("prefs.voice.identifier") private var voiceIdentifier: String = ""

    // MARK: - Private

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Init

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    func speak(_ text: String, rate: Float = 0.50) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = resolveVoice()
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func previewVoice(_ identifier: String) {
        stop()
        let utterance = AVSpeechUtterance(string: "Here's your plan for today.")
        utterance.rate = 0.50
        utterance.voice = AVSpeechSynthesisVoice(identifier: identifier) ?? AVSpeechSynthesisVoice(language: "en-GB")
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    static func availablePremiumVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en") && ($0.quality == .premium || $0.quality == .enhanced)
        }
    }

    // MARK: - Private

    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        if !voiceIdentifier.isEmpty,
           let stored = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            return stored
        }
        if let premium = Self.availablePremiumVoices().first {
            return premium
        }
        return AVSpeechSynthesisVoice(language: "en-GB")
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
