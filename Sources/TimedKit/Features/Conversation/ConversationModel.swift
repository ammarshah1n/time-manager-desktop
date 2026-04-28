import Foundation
import SwiftUI

@MainActor
final class ConversationModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case connecting
        case listening
        case thinking
        case speaking
        case ending
        case ended
        case failed(String)
    }

    struct TranscriptMessage: Identifiable, Hashable {
        let id = UUID()
        let role: String
        let content: String
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveTranscript = ""
    @Published private(set) var transcript: [TranscriptMessage] = []

    private let tasks: Binding<[TimedTask]>
    private let blocks: Binding<[CalendarBlock]>
    private let freeTimeSlots: [FreeTimeSlot]
    private let stt = DeepgramSTTService()
    private let tts = StreamingTTSService()
    private let aiClient: ConversationAIClient

    private var listenTask: Task<Void, Never>?
    private var turnTask: Task<Void, Never>?
    private var pendingFinalSegments: [String] = []

    init(tasks: Binding<[TimedTask]>, blocks: Binding<[CalendarBlock]>, freeTimeSlots: [FreeTimeSlot]) {
        self.tasks = tasks
        self.blocks = blocks
        self.freeTimeSlots = freeTimeSlots
        let taskBinding = tasks
        let tools = ConversationTools { updatedTasks in
            taskBinding.wrappedValue = updatedTasks
        }
        self.aiClient = ConversationAIClient(tools: tools)
    }

    var phaseTitle: String {
        switch phase {
        case .idle: "Ready"
        case .connecting: "Connecting"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .ending: "Ending"
        case .ended: "Done"
        case .failed: "Failed"
        }
    }

    var phaseDetail: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    var isListening: Bool {
        if case .listening = phase { return true }
        return false
    }

    var isSpeaking: Bool {
        if case .speaking = phase { return true }
        return false
    }

    var isThinking: Bool {
        if case .thinking = phase { return true }
        return false
    }

    func start() async {
        guard listenTask == nil else { return }
        phase = .connecting

        // Pre-warm the Edge Function isolates the first orb turn will hit so
        // the user's first utterance lands on a warm container. OPTIONS is the
        // cheapest call that materialises a Deno isolate (200-400ms cold start
        // → ~5ms warm round-trip). Fire-and-forget — failures are not fatal.
        Task.detached {
            await EdgeFunctions.shared.preWarm(["orb-conversation", "orb-tts", "deepgram-token"])
        }

        phase = .listening

        listenTask = Task { @MainActor in
            do {
                for try await event in stt.start() {
                    try Task.checkCancellation()
                    switch event {
                    case .partial(let text):
                        let combined = combinedTranscript(with: text)
                        liveTranscript = combined
                        // Don't barge-in on partials — they trip on background
                        // noise / coughs. Only `final` interrupts.
                    case .final(let text, let confidence, let speechFinal):
                        if (isSpeaking || isThinking),
                           confidence >= 0.4,
                           text.split(separator: " ").count >= 2 {
                            interruptCurrentTurn()
                        }
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            pendingFinalSegments.append(trimmed)
                        }
                        liveTranscript = pendingFinalSegments.joined(separator: " ")
                        if speechFinal {
                            let combined = pendingFinalSegments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                            pendingFinalSegments.removeAll()
                            liveTranscript = ""
                            guard !combined.isEmpty else { continue }
                            turnTask?.cancel()
                            turnTask = Task { @MainActor in
                                await handleFinalTranscript(combined)
                            }
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func end() async {
        phase = .ending
        listenTask?.cancel()
        listenTask = nil
        turnTask?.cancel()
        turnTask = nil
        stt.stop()
        tts.stop()
        aiClient.cancelCurrentTurn()
        pendingFinalSegments.removeAll()
        phase = .ended
    }

    private func interruptCurrentTurn() {
        turnTask?.cancel()
        tts.stop()
        aiClient.cancelCurrentTurn()
        phase = .listening
    }

    private func combinedTranscript(with partial: String) -> String {
        let confirmed = pendingFinalSegments.joined(separator: " ")
        let trimmedPartial = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if confirmed.isEmpty { return trimmedPartial }
        if trimmedPartial.isEmpty { return confirmed }
        return confirmed + " " + trimmedPartial
    }

    private func handleFinalTranscript(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        transcript.append(TranscriptMessage(role: "You", content: trimmed))
        liveTranscript = ""
        phase = .thinking

        var chunker = SentenceChunker()
        var responseText = ""
        var ttsStreaming = false
        do {
            try await tts.startSession()
            ttsStreaming = true
        } catch {
            ttsStreaming = false
        }

        var firstDelta = true

        let snapshot = clientSnapshot()
        do {
            for try await event in aiClient.streamTurn(userText: trimmed, clientState: snapshot) {
                try Task.checkCancellation()
                switch event {
                case .textDelta(let delta):
                    responseText += delta
                    if firstDelta {
                        phase = .speaking
                        firstDelta = false
                    }
                    let chunks = chunker.append(delta)
                    for chunk in chunks where ttsStreaming {
                        try? await tts.send(sentence: chunk)
                    }
                case .toolResult:
                    break
                case .completed:
                    break
                case .endConversation:
                    await end()
                    return
                }
            }

            if let remaining = chunker.flush() {
                if ttsStreaming {
                    try? await tts.send(sentence: remaining)
                }
            }

            let spoken = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty {
                transcript.append(TranscriptMessage(role: "Timed", content: spoken))
                if ttsStreaming {
                    await tts.finish()
                } else {
                    phase = .speaking
                    tts.speakFallback(spoken)
                    while tts.isSpeaking, !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                }
            }
            if phase != .ended { phase = .listening }
        } catch {
            if !Task.isCancelled {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func clientSnapshot() -> [String: Any] {
        let activeTasks = tasks.wrappedValue.filter { !$0.isDone }
        let taskRows: [[String: Any]] = activeTasks.map { t in
            [
                "id": t.id.uuidString,
                "title": t.title,
                "bucket": t.bucket.rawValue,
                "estimatedMinutes": t.estimatedMinutes,
                "isDoFirst": t.isDoFirst,
                "isStale": t.isStale,
                "urgency": t.urgency,
                "importance": t.importance,
                "planScore": t.planScore as Any,
            ]
        }
        let blockRows: [[String: Any]] = blocks.wrappedValue.map { b in
            [
                "title": b.title,
                "category": b.category.rawValue,
                "startTime": ISO8601DateFormatter().string(from: b.startTime),
                "endTime": ISO8601DateFormatter().string(from: b.endTime),
            ]
        }
        let slotRows: [[String: Any]] = freeTimeSlots.map { s in
            [
                "start": ISO8601DateFormatter().string(from: s.start),
                "end": ISO8601DateFormatter().string(from: s.end),
                "durationMinutes": s.durationMinutes,
            ]
        }
        return [
            "tasks": taskRows,
            "blocks": blockRows,
            "freeTimeSlots": slotRows,
        ]
    }
}
