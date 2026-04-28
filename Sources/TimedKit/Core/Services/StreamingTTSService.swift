import AVFoundation
import Foundation

@MainActor
final class StreamingTTSService: ObservableObject {
    enum ServiceError: LocalizedError {
        case audioEngineFailure(String)
        case proxyFailed(String)

        var errorDescription: String? {
            switch self {
            case .audioEngineFailure(let m): m
            case .proxyFailed(let m): m
            }
        }
    }

    @Published private(set) var isSpeaking = false

    private let fallbackSpeech = SpeechService()
    private var fallbackTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var pendingText = ""
    private var sessionActive = false

    func startSession() async throws {
        stop()
        sessionActive = true
        pendingText = ""
    }

    func send(sentence: String) async throws {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingText += pendingText.isEmpty ? trimmed : " " + trimmed
    }

    func finish() async {
        let textToSpeak = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = ""
        sessionActive = false
        guard !textToSpeak.isEmpty else {
            isSpeaking = false
            return
        }
        await playProxiedAudio(text: textToSpeak)
    }

    func speakFallback(_ text: String) {
        fallbackTask?.cancel()
        isSpeaking = true
        fallbackSpeech.speak(text)
        fallbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(150))
            while self.fallbackSpeech.isSpeaking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
            }
            if !Task.isCancelled { self.isSpeaking = false }
        }
    }

    func stop() {
        sessionActive = false
        playbackTask?.cancel()
        playbackTask = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        if let audioPlayer, audioPlayer.isPlaying { audioPlayer.stop() }
        audioPlayer = nil
        fallbackSpeech.stop()
        isSpeaking = false
        pendingText = ""
    }

    private func playProxiedAudio(text: String) async {
        isSpeaking = true
        do {
            let stream = try await EdgeFunctions.shared.ttsBytes(text: text)
            var mp3 = Data()
            for try await chunk in stream {
                mp3.append(chunk)
            }
            guard !mp3.isEmpty else {
                isSpeaking = false
                return
            }
            try playMP3(mp3)
            await waitForPlayback()
        } catch {
            // Falls back to elevenlabs-tts-proxy one-shot via SpeechService.
            // No Apple TTS — if the network's gone, the user hears nothing and
            // we surface the failure visibly rather than silently downgrade.
            TimedLogger.voice.warning("orb-tts unreachable; falling back to elevenlabs-tts-proxy one-shot: \(error.localizedDescription, privacy: .private)")
            speakFallback(text)
        }
    }

    private func playMP3(_ data: Data) throws {
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        player.play()
        audioPlayer = player
    }

    private func waitForPlayback() async {
        while let player = audioPlayer, player.isPlaying, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(80))
        }
        audioPlayer = nil
        isSpeaking = false
    }
}
