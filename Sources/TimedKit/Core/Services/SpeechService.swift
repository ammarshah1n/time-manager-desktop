// SpeechService.swift — Timed Core
// Text-to-speech via ElevenLabs REST API with AVSpeechSynthesizer fallback.
// British English voice, executive-appropriate tone and pacing.

import AVFoundation
import SwiftUI

@MainActor
final class SpeechService: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var isSpeaking: Bool = false
    @AppStorage("elevenlabs_voice_id") private var voiceId: String = "pFZP5JQG7iQjIQuC4Bku" // Lily — velvety, warm female

    // MARK: - Private

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var activeTask: Task<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    func speak(_ text: String, rate: Float = 0.50) {
        stop()
        isSpeaking = true

        activeTask = Task {
            let success = await elevenLabsSpeak(text)
            if !success, !Task.isCancelled {
                fallbackSpeak(text, rate: rate)
                return
            }
            if Task.isCancelled {
                isSpeaking = false
            }
        }
    }

    func stop() {
        activeTask?.cancel()
        activeTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - ElevenLabs TTS

    private func elevenLabsSpeak(_ text: String) async -> Bool {
        do {
            let stream = try await EdgeFunctions.shared.ttsBytes(text: text, voiceId: voiceId)
            var audioData = Data()
            audioData.reserveCapacity(128_000)
            for try await chunk in stream {
                if Task.isCancelled { return false }
                audioData.append(chunk)
            }

            if Task.isCancelled { return false }
            return await playAudioData(audioData)
        } catch {
            return false
        }
    }

    private func playAudioData(_ data: Data) async -> Bool {
        do {
            let player = try AVAudioPlayer(data: data)
            self.audioPlayer = player
            player.delegate = self
            player.prepareToPlay()
            player.play()

            // Wait for playback to finish
            while player.isPlaying {
                if Task.isCancelled {
                    player.stop()
                    self.audioPlayer = nil
                    return false
                }
                try? await Task.sleep(for: .milliseconds(100))
            }

            self.audioPlayer = nil
            self.isSpeaking = false
            return true
        } catch {
            return false
        }
    }

    // MARK: - AVSpeechSynthesizer Fallback

    private func fallbackSpeak(_ text: String, rate: Float) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = resolveVoice()
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: "en-GB")
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

// MARK: - AVAudioPlayerDelegate

extension SpeechService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            self.audioPlayer = nil
            self.isSpeaking = false
        }
    }
}
