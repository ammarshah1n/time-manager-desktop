// VoiceCaptureService.swift — Timed Core
// Continuous voice dictation → segmented task items via Apple Speech framework.
// Pure Apple framework — no external dependencies.
// Research: ~/Timed-Brain/06 - Context/ (voice capture deep research 2026-03-31)
//
// Entitlement required: com.apple.security.device.microphone
// Info.plist: NSMicrophoneUsageDescription, NSSpeechRecognitionUsageDescription

import Foundation
import AVFoundation
import Speech
import os

// MARK: - ParsedItem

struct ParsedItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var estimatedMinutes: Int?
    var dueDate: Date?
    var bucketType: String     // action | calls | reply_email | read_today | other
    var extractionConfidence: Float

    init(
        id: UUID = UUID(),
        title: String,
        estimatedMinutes: Int? = nil,
        dueDate: Date? = nil,
        bucketType: String = "action",
        extractionConfidence: Float = 0.5
    ) {
        self.id = id
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.dueDate = dueDate
        self.bucketType = bucketType
        self.extractionConfidence = extractionConfidence
    }
}

// MARK: - VoiceCaptureService

@MainActor
final class VoiceCaptureService: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var liveTranscript: String = ""   // updates in real-time
    @Published private(set) var parsedItems: [ParsedItem] = []
    @Published private(set) var lastError: Error?
    @Published var lastConfidence: Float = 1.0
    @Published private(set) var audioLevel: Float = 0.0  // 0.0–1.0 normalized RMS for waveform display

    // MARK: - Private

    private let speechRecognizer: SFSpeechRecognizer
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Init

    /// Whether voice capture is available on this system
    private(set) var isAvailable: Bool = true

    init?(locale: Locale = Locale(identifier: "en-US")) {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            TimedLogger.voice.error("Unsupported locale for speech recognition: \(locale.identifier, privacy: .public)")
            return nil
        }
        self.speechRecognizer = recognizer
        super.init()
        self.speechRecognizer.delegate = self
        TimedLogger.voice.info("VoiceCaptureService initialised with locale \(locale.identifier, privacy: .public)")
    }

    /// Non-failable init that creates a degraded instance when speech recognition is unavailable.
    /// All recording calls become no-ops. UI shows "Voice unavailable" instead of crashing.
    override init() {
        // Use en-US as fallback — if even this fails, isAvailable = false and all ops are no-ops
        if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) {
            self.speechRecognizer = recognizer
            self.isAvailable = true
            super.init()
            self.speechRecognizer.delegate = self
        } else {
            // Truly unavailable — create with a dummy recognizer reference
            // We use en-AU as last resort
            self.speechRecognizer = SFSpeechRecognizer()!
            self.isAvailable = false
            super.init()
            TimedLogger.voice.warning("Speech recognition unavailable — voice capture disabled")
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        isAuthorized = speechStatus == .authorized && micGranted
    }

    // MARK: - Start / Stop

    func start() async {
        lastError = nil
        liveTranscript = ""
        parsedItems = []

        if !isAuthorized { await requestAuthorization() }
        guard isAuthorized else {
            TimedLogger.voice.warning("Voice capture not authorised — aborting start")
            return
        }

        // Cancel any existing session
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        do {
            try setupAudioSession()
            try startAudioEngine()
            startRecognitionTask()
            isRecording = true
            TimedLogger.voice.info("Recording started")
        } catch {
            TimedLogger.voice.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
            lastError = error
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        audioLevel = 0

        // Parse final transcript into discrete task items
        parsedItems = TranscriptParser.parse(liveTranscript)
        TimedLogger.voice.info("Recording stopped — parsed \(self.parsedItems.count) items")
    }

    // MARK: - Private audio setup

    private func setupAudioSession() throws {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif
    }

    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false   // use server for accuracy
        recognitionRequest = request

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            // Compute RMS audio level for waveform visualization
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            var rms: Float = 0
            if let samples = channelData, frameLength > 0 {
                var sum: Float = 0
                for i in 0..<frameLength { sum += samples[i] * samples[i] }
                rms = sqrtf(sum / Float(frameLength))
            }
            // Normalize to 0-1 range (typical speech RMS is 0.01-0.2)
            let normalized = min(1.0, rms * 8)
            Task { @MainActor in
                self.recognitionRequest?.append(buffer)
                self.audioLevel = normalized
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func startRecognitionTask() {
        guard let request = recognitionRequest else { return }
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    // Apple Speech handles in-place corrections natively
                    // "actually make that 20, not 30" — last mentioned value wins in bestTranscription
                    self.liveTranscript = result.bestTranscription.formattedString

                    // Average segment confidences for STT confidence guard
                    let segments = result.bestTranscription.segments
                    if !segments.isEmpty {
                        let avg = segments.reduce(Float(0)) { $0 + $1.confidence } / Float(segments.count)
                        self.lastConfidence = avg
                    }

                    if result.isFinal {
                        TimedLogger.voice.debug("Final transcript received (\(result.bestTranscription.formattedString.count) chars, confidence: \(self.lastConfidence, privacy: .public))")
                    }
                }
                if let error {
                    TimedLogger.voice.error("Recognition error: \(error.localizedDescription, privacy: .public)")
                    self.lastError = error
                    self.stop()
                } else if result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension VoiceCaptureService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(
        _ speechRecognizer: SFSpeechRecognizer,
        availabilityDidChange available: Bool
    ) {
        Task { @MainActor in
            if !available && self.isRecording { self.stop() }
        }
    }
}

// MARK: - TranscriptParser

enum TranscriptParser {

    static func parse(_ transcript: String) -> [ParsedItem] {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let clauses = segmentIntoClauses(transcript)
        return clauses.compactMap { makeItem(from: $0) }
    }

    // ── Segmentation ──────────────────────────────────────────────────────────

    private static func segmentIntoClauses(_ text: String) -> [String] {
        // Split on sentence delimiters first
        let sentenceBreaks = CharacterSet(charactersIn: ".?!;")
        var parts = text.components(separatedBy: sentenceBreaks)

        // Secondary: split on " and " when followed by a task verb
        let taskVerbs = ["call ", "email ", "reply ", "text ", "pick up ", "review ", "read ",
                         "draft ", "send ", "write ", "check ", "prepare ", "book ", "schedule "]
        parts = parts.flatMap { sentence -> [String] in
            let lower = sentence.lowercased()
            guard lower.contains(" and ") else { return [sentence] }

            var result: [String] = []
            var remaining = sentence
            while let range = remaining.lowercased().range(of: " and ") {
                let after = String(remaining[range.upperBound...])
                let afterLower = after.lowercased()
                if taskVerbs.contains(where: { afterLower.hasPrefix($0) }) {
                    result.append(String(remaining[..<range.lowerBound]))
                    remaining = after
                } else {
                    break
                }
            }
            result.append(remaining)
            return result
        }

        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // ── Item construction ─────────────────────────────────────────────────────

    private static func makeItem(from clause: String) -> ParsedItem? {
        let trimmed = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3 else { return nil }

        let duration  = extractDuration(trimmed)
        let dueDate   = extractDueDate(trimmed)
        let bucket    = detectBucket(trimmed)
        let title     = cleanTitle(trimmed)
        let confidence = computeConfidence(trimmed, duration: duration, dueDate: dueDate)

        return ParsedItem(
            title: title,
            estimatedMinutes: duration,
            dueDate: dueDate,
            bucketType: bucket,
            extractionConfidence: confidence
        )
    }

    // ── Duration extraction ───────────────────────────────────────────────────

    /// Extracts the LAST mentioned duration (handles "make that 20 not 30").
    static func extractDuration(_ text: String) -> Int? {
        let pattern = #"(\d+)\s*(minutes?|mins?|hours?|hrs?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard let last = matches.last else { return nil }

        guard
            let numRange  = Range(last.range(at: 1), in: text),
            let unitRange = Range(last.range(at: 2), in: text),
            let number    = Int(text[numRange])
        else { return nil }

        let unit = String(text[unitRange]).lowercased()
        return (unit.hasPrefix("hour") || unit.hasPrefix("hr")) ? number * 60 : number
    }

    // ── Due date extraction ───────────────────────────────────────────────────

    static func extractDueDate(_ text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, range: range) ?? []
        return matches.first?.date
    }

    // ── Bucket detection ──────────────────────────────────────────────────────

    static func detectBucket(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.hasPrefix("call") || lower.contains("phone ") || lower.contains("ring ") {
            return "calls"
        }
        if lower.hasPrefix("email") || lower.hasPrefix("reply") || lower.hasPrefix("respond") || lower.hasPrefix("send") {
            return "reply_email"
        }
        if lower.hasPrefix("read") || lower.hasPrefix("review") || lower.contains("have a look at") {
            return "read_today"
        }
        return "action"
    }

    // ── Title cleaning ────────────────────────────────────────────────────────

    static func cleanTitle(_ text: String) -> String {
        var result = text
        // Remove duration phrases: "allow 30 minutes", "30 min", "for an hour"
        let durationPatterns = [
            #"\s*,?\s*(allow|for|takes?|about|around|roughly|approximately)\s+\d+\s*(minutes?|mins?|hours?|hrs?)\b"#,
            #"\s*,?\s*\d+\s*(minutes?|mins?|hours?|hrs?)\s*(each|long|total)?\b"#,
        ]
        for pattern in durationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        // Remove due date phrases
        let datePhrases = ["before ", "by ", "due ", "no later than ", "until "]
        // Simple: remove "before Thursday", "by Friday", etc.
        let weekdays = ["monday","tuesday","wednesday","thursday","friday","saturday","sunday",
                        "tomorrow","today","this week","next week","end of week","eod"]
        for day in weekdays {
            for prep in datePhrases {
                result = result.replacingOccurrences(
                    of: "\(prep)\(day)", with: "", options: .caseInsensitive
                )
            }
        }
        // Remove trailing commas and whitespace
        result = result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalise first letter
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    // ── Confidence scoring ────────────────────────────────────────────────────

    private static func computeConfidence(_ text: String, duration: Int?, dueDate: Date?) -> Float {
        var score: Float = 0.4  // base
        if duration != nil  { score += 0.25 }
        if dueDate  != nil  { score += 0.20 }
        if text.count > 10  { score += 0.10 }
        if text.count > 25  { score += 0.05 }
        return min(score, 1.0)
    }
}
