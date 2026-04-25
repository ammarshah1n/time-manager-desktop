import AVFoundation
import Foundation

enum DeepgramTranscriptEvent: Sendable, Equatable {
    case partial(String)
    case final(String, confidence: Double, speechFinal: Bool)
}

@MainActor
final class DeepgramSTTService {
    enum ServiceError: LocalizedError {
        case missingAPIKey
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: "Transcription API key is not configured."
            case .invalidURL: "Deepgram WebSocket URL is invalid."
            }
        }
    }

    private let audioEngine = AVAudioEngine()
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var lastPartialTranscript = ""

    func start() -> AsyncThrowingStream<DeepgramTranscriptEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    try await connect(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func connect(continuation: AsyncThrowingStream<DeepgramTranscriptEvent, Error>.Continuation) async throws {
        let apiKey = try KeychainStore.string(for: .deepgramAPIKey)
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }
        guard let url = URL(string: "wss://api.deepgram.com/v1/listen?model=nova-3&interim_results=true&endpointing=300&smart_format=true&language=en&encoding=linear16&sample_rate=16000&channels=1") else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(task: task, continuation: continuation)
        }

        try startMicrophone(task: task, continuation: continuation)
    }

    private func receiveLoop(
        task: URLSessionWebSocketTask,
        continuation: AsyncThrowingStream<DeepgramTranscriptEvent, Error>.Continuation
    ) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    if let event = parseEvent(text) {
                        switch event {
                        case .partial(let transcript):
                            lastPartialTranscript = transcript
                        case .final:
                            lastPartialTranscript = ""
                        }
                        continuation.yield(event)
                    }
                case .data:
                    break
                @unknown default:
                    break
                }
            }
        } catch {
            if !Task.isCancelled {
                continuation.finish(throwing: error)
            }
        }
    }

    private func startMicrophone(
        task: URLSessionWebSocketTask,
        continuation: AsyncThrowingStream<DeepgramTranscriptEvent, Error>.Continuation
    ) throws {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        var vad = VoiceActivityDetector()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            let endedByLocalVAD = vad.observe(level: VoiceActivityDetector.rmsLevel(from: buffer))
            if endedByLocalVAD {
                Task { @MainActor in
                    guard !self.lastPartialTranscript.isEmpty else { return }
                    continuation.yield(.final(self.lastPartialTranscript, confidence: 0, speechFinal: true))
                    self.lastPartialTranscript = ""
                }
            }

            guard let data = Self.linear16Data(from: buffer, inputSampleRate: inputFormat.sampleRate), !data.isEmpty else { return }

            Task {
                try? await task.send(.data(data))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private nonisolated static func linear16Data(from buffer: AVAudioPCMBuffer, inputSampleRate: Double) -> Data? {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        let frameLength = Int(buffer.frameLength)
        let ratio = inputSampleRate / 16_000
        let outputCount = max(1, Int(Double(frameLength) / ratio))
        var output = [Int16]()
        output.reserveCapacity(outputCount)

        for index in 0..<outputCount {
            let sourceIndex = min(frameLength - 1, Int(Double(index) * ratio))
            let sample = max(-1, min(1, samples[sourceIndex]))
            output.append(Int16(sample * Float(Int16.max)))
        }

        return output.withUnsafeBufferPointer { pointer in
            Data(buffer: pointer)
        }
    }

    private nonisolated func parseEvent(_ text: String) -> DeepgramTranscriptEvent? {
        guard let data = text.data(using: .utf8),
              let response = try? JSONDecoder().decode(DeepgramResponse.self, from: data),
              let alternative = response.channel.alternatives.first else {
            return nil
        }
        let transcript = alternative.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }
        if response.isFinal || response.speechFinal == true {
            return .final(transcript, confidence: alternative.confidence ?? 0, speechFinal: response.speechFinal ?? false)
        }
        return .partial(transcript)
    }
}

private struct DeepgramResponse: Decodable {
    let channel: Channel
    let isFinal: Bool
    let speechFinal: Bool?

    enum CodingKeys: String, CodingKey {
        case channel
        case isFinal = "is_final"
        case speechFinal = "speech_final"
    }

    struct Channel: Decodable {
        let alternatives: [Alternative]
    }

    struct Alternative: Decodable {
        let transcript: String
        let confidence: Double?
    }
}
