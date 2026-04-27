// SpeechService.swift — Timed Core
// Text-to-speech via the elevenlabs-tts-proxy Edge Function. The ElevenLabs
// API key lives server-side; the client never holds it. No Apple TTS fallback
// — if the proxy is unreachable, the failure surfaces visibly so we can fix
// the real cause instead of silently switching to AVSpeechSynthesizer.

import AVFoundation
import SwiftUI

@MainActor
final class SpeechService: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var isSpeaking: Bool = false
    @Published private(set) var lastError: String?
    @AppStorage("elevenlabs_voice_id") private var voiceId: String = "pFZP5JQG7iQjIQuC4Bku" // Lily — velvety, warm female

    // MARK: - Private

    private var audioPlayer: AVAudioPlayer?
    private var activeTask: Task<Void, Never>?

    // MARK: - Public API

    /// Speak `text` via the elevenlabs-tts-proxy Edge Function. The `rate`
    /// parameter is ignored (kept for source compatibility with prior callers
    /// that passed an AVSpeech rate value).
    func speak(_ text: String, rate: Float = 0.50) {
        _ = rate
        stop()
        isSpeaking = true
        lastError = nil

        activeTask = Task {
            let success = await proxiedSpeak(text)
            if !success, !Task.isCancelled {
                self.isSpeaking = false
                if self.lastError == nil {
                    self.lastError = "Voice playback unavailable. Check connection."
                }
            }
        }
    }

    func stop() {
        activeTask?.cancel()
        activeTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
    }

    // MARK: - Edge Function call

    private func proxiedSpeak(_ text: String) async -> Bool {
        guard let url = SupabaseEndpoints.functionURL("elevenlabs-tts-proxy") else {
            lastError = "Invalid TTS endpoint."
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseEndpoints.authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "voice_id": voiceId,
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = httpBody

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "TTS proxy: no HTTP response."
                return false
            }
            guard httpResponse.statusCode == 200 else {
                lastError = "TTS proxy HTTP \(httpResponse.statusCode)."
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
            lastError = "TTS error: \(error.localizedDescription)"
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
            lastError = "Audio playback failed: \(error.localizedDescription)"
            return false
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
