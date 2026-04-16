// SpeechService.swift — Timed Core
// Text-to-speech via ElevenLabs REST API with AVSpeechSynthesizer fallback.
// British English voice, executive-appropriate tone and pacing.

import AVFoundation
import SwiftUI

@MainActor
final class SpeechService: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var isSpeaking: Bool = false
    @AppStorage("elevenlabs_api_key") private var apiKey: String = "sk_b1779a2f714a1022e0800a7d4aa097892cde5f440f8d44f2"
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
        guard !apiKey.isEmpty else { return false }

        let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)"
        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": [
                "stability": 0.6,
                "similarity_boost": 0.75,
                "style": 0.15,
                "use_speaker_boost": true
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = httpBody

        // Stream bytes for lower perceived latency
        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            if Task.isCancelled { return false }

            var audioData = Data()
            audioData.reserveCapacity(128_000)

            for try await byte in asyncBytes {
                if Task.isCancelled { return false }
                audioData.append(byte)
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
