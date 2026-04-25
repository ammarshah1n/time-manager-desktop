import AVFoundation
import Foundation

@MainActor
final class StreamingTTSService: ObservableObject {
    enum ServiceError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case audioEngineFailure(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: "ElevenLabs API key is not configured."
            case .invalidURL: "ElevenLabs WebSocket URL is invalid."
            case .audioEngineFailure(let message): message
            }
        }
    }

    @Published private(set) var isSpeaking = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!
    private let fallbackSpeech = SpeechService()
    private var pendingFrames = 0
    private var sessionClosed = true
    private var fallbackTask: Task<Void, Never>?

    private var apiKey: String { KeychainStore.string(for: .elevenlabsAPIKey) }
    private var voiceId: String {
        let stored = UserDefaults.standard.string(forKey: "elevenlabs_voice_id") ?? ""
        return stored.isEmpty ? "pFZP5JQG7iQjIQuC4Bku" : stored
    }

    func startSession() async throws {
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }
        guard let url = URL(string: "wss://api.elevenlabs.io/v1/text-to-speech/\(voiceId)/stream-input?model_id=eleven_turbo_v2_5&output_format=pcm_24000") else {
            throw ServiceError.invalidURL
        }

        stop()
        try setupAudioEngine()
        sessionClosed = false
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
        try await sendJSON(["text": sentence + " ", "try_trigger_generation": true])
    }

    func finish() async {
        try? await sendJSON(["text": ""])
        sessionClosed = true

        for _ in 0..<200 {
            if pendingFrames == 0 && !player.isPlaying { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        isSpeaking = false
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
        sessionClosed = true
        fallbackTask?.cancel()
        fallbackTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
        fallbackSpeech.stop()
        isSpeaking = false
        pendingFrames = 0
    }

    private func setupAudioEngine() throws {
        if !engine.attachedNodes.contains(player) {
            engine.attach(player)
        }
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw ServiceError.audioEngineFailure(error.localizedDescription)
        }
        if !player.isPlaying { player.play() }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    schedulePCM(data)
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let base64 = json["audio"] as? String, let audio = Data(base64Encoded: base64) {
            schedulePCM(audio)
        }
    }

    private func schedulePCM(_ data: Data) {
        guard !data.isEmpty else { return }
        let frameCount = data.count / 2
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        data.withUnsafeBytes { rawPointer in
            guard let baseAddress = rawPointer.baseAddress,
                  let floatChannel = buffer.floatChannelData?[0] else { return }
            let int16Pointer = baseAddress.assumingMemoryBound(to: Int16.self)
            let scale = Float(1) / Float(Int16.max)
            for index in 0..<frameCount {
                floatChannel[index] = Float(int16Pointer[index]) * scale
            }
        }

        pendingFrames += frameCount
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pendingFrames -= frameCount
                if self.pendingFrames <= 0 && self.sessionClosed {
                    self.isSpeaking = false
                }
            }
        }
    }

    private func sendJSON(_ payload: [String: Any]) async throws {
        guard let task = webSocketTask else { return }
        let data = try JSONSerialization.data(withJSONObject: payload)
        if let string = String(data: data, encoding: .utf8) {
            try await task.send(.string(string))
        }
    }
}
