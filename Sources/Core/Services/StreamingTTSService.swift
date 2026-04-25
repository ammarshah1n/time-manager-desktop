import AVFoundation
import Foundation

@MainActor
final class StreamingTTSService: NSObject, ObservableObject {
    enum ServiceError: LocalizedError {
        case missingAPIKey
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: "ElevenLabs API key is not configured."
            case .invalidURL: "ElevenLabs WebSocket URL is invalid."
            }
        }
    }

    @Published private(set) var isSpeaking = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var audioData = Data()
    private var audioPlayer: AVAudioPlayer?
    private let fallbackSpeech = SpeechService()

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "elevenlabs_api_key") ?? ""
    }

    private var voiceId: String {
        let stored = UserDefaults.standard.string(forKey: "elevenlabs_voice_id") ?? ""
        return stored.isEmpty ? "pFZP5JQG7iQjIQuC4Bku" : stored
    }

    func startSession() async throws {
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }
        guard let url = URL(string: "wss://api.elevenlabs.io/v1/text-to-speech/\(voiceId)/stream-input?model_id=eleven_turbo_v2_5&output_format=mp3_44100_128") else {
            throw ServiceError.invalidURL
        }

        stop()
        audioData = Data()
        isSpeaking = true

        let task = URLSession.shared.webSocketTask(with: URLRequest(url: url))
        webSocketTask = task
        task.resume()

        try await sendJSON([
            "xi_api_key": apiKey,
            "voice_settings": [
                "stability": 0.6,
                "similarity_boost": 0.75,
                "style": 0.15,
                "use_speaker_boost": true,
            ],
        ])

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(task: task)
        }
    }

    func send(sentence: String) async throws {
        try await sendJSON([
            "text": sentence + " ",
            "try_trigger_generation": true,
        ])
    }

    func finish() async {
        try? await sendJSON(["text": ""])
        try? await Task.sleep(for: .milliseconds(450))
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        if !audioData.isEmpty {
            await playAudioData(audioData)
        } else {
            isSpeaking = false
        }
    }

    func speakFallback(_ text: String) {
        isSpeaking = true
        fallbackSpeech.speak(text)
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        fallbackSpeech.stop()
        isSpeaking = false
        audioData.removeAll(keepingCapacity: true)
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    audioData.append(data)
                case .string(let text):
                    appendAudioFromJSON(text)
                @unknown default:
                    break
                }
            } catch {
                return
            }
        }
    }

    private func appendAudioFromJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64 = json["audio"] as? String,
              let audio = Data(base64Encoded: base64) else {
            return
        }
        audioData.append(audio)
    }

    private func sendJSON(_ payload: [String: Any]) async throws {
        guard let task = webSocketTask else { return }
        let data = try JSONSerialization.data(withJSONObject: payload)
        if let string = String(data: data, encoding: .utf8) {
            try await task.send(.string(string))
        }
    }

    private func playAudioData(_ data: Data) async {
        do {
            let player = try AVAudioPlayer(data: data)
            audioPlayer = player
            player.delegate = self
            player.prepareToPlay()
            player.play()
            while player.isPlaying {
                try? await Task.sleep(for: .milliseconds(50))
            }
            audioPlayer = nil
        } catch {
            audioPlayer = nil
        }
        isSpeaking = false
    }
}

extension StreamingTTSService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.audioPlayer = nil
            self.isSpeaking = false
        }
    }
}
