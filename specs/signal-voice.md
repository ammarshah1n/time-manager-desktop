# Timed — Voice Input Signal Spec

**Status:** Implementation-ready
**Last updated:** 2026-04-02
**Layer:** L1 — Signal Ingestion
**Implements:** `VoiceCaptureService.swift`, `SpeechService.swift`, writes to signal queue via `DataStore.swift`
**Dependencies:** `AVAudioEngine`, `SFSpeechRecognizer` (Apple Speech), `TimedLogger.swift`

---

## 1. Overview

Voice is the richest signal source in Timed. It captures what no other signal can: the executive's own framing of their priorities, frustrations, corrections, and reflections — in their own words. The voice pipeline captures audio via `AVAudioEngine`, transcribes on-device via `SFSpeechRecognizer`, extracts metadata, and writes structured signals to the signal queue.

Raw audio is never stored. The pipeline is streaming: audio buffer → on-device transcription → transcript + metadata → signal queue → audio buffer released. After the signal is written, no audio data exists anywhere on disk or in memory.

---

## 2. Pipeline Architecture

```
┌──────────────┐    ┌──────────────────┐    ┌─────────────┐    ┌──────────────┐    ┌──────────────┐
│ AVAudioEngine │───→│ SFSpeechRecognizer│───→│  Transcript  │───→│   Metadata   │───→│ Signal Queue │
│  (capture)    │    │  (on-device)      │    │  Assembly    │    │  Extraction  │    │  (CoreData)  │
└──────────────┘    └──────────────────┘    └─────────────┘    └──────────────┘    └──────────────┘
     Audio              Recognition             Text              Structured            Persisted
     Buffer             Result                  + Timing          Signal
     (memory only)      (streaming)             (memory only)     (memory → disk)
```

### 2.1 AVAudioEngine Configuration

```swift
let audioEngine = AVAudioEngine()
let inputNode = audioEngine.inputNode
let recordingFormat = inputNode.outputFormat(forBus: 0)

// Verify format is compatible with SFSpeechRecognizer
// Expected: 16kHz or higher sample rate, mono or stereo, PCM float
// Apple Speech handles format conversion internally

inputNode.installTap(
    onBus: 0,
    bufferSize: 1024,        // ~64ms at 16kHz — low latency
    format: recordingFormat
) { [weak self] buffer, time in
    self?.recognitionRequest?.append(buffer)
}

audioEngine.prepare()
try audioEngine.start()
```

### 2.2 SFSpeechRecognizer Configuration

```swift
let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-AU"))!
// Falls back to "en" if "en-AU" model not available on-device

// CRITICAL: On-device only — never send audio to Apple servers
let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
recognitionRequest.requiresOnDeviceRecognition = true
recognitionRequest.shouldReportPartialResults = true
recognitionRequest.addsPunctuation = true  // macOS 13+

// Task-specific hints for executive vocabulary
recognitionRequest.contextualStrings = [
    "board", "quarterly", "P&L", "EBITDA", "revenue",
    "pipeline", "roadmap", "stakeholder", "deliverable",
    "one-on-one", "stand-up", "retrospective"
]
```

### 2.3 Recognition Task

```swift
let recognitionTask = recognizer.recognitionTask(
    with: recognitionRequest
) { [weak self] result, error in
    guard let self else { return }
    
    if let result {
        // Partial results → update live transcript display
        self.currentTranscript = result.bestTranscription
        self.partialResults.append(result)
        
        if result.isFinal {
            self.finaliseSession(transcript: result.bestTranscription)
        }
    }
    
    if let error {
        TimedLogger.voice.error("Recognition error: \(error.localizedDescription)")
        self.handleRecognitionError(error)
    }
}
```

---

## 3. Session Types

Each voice session has a type that determines how L2/L3 processes it.

### 3.1 Morning Interview

- **Trigger:** User initiates morning session (UI button or voice command "Hey Timed, good morning").
- **Duration:** Target 60-90 seconds. Soft cap at 120 seconds (gentle nudge in UI: "Got it — anything else before we start the day?").
- **Purpose:** Capture the executive's framing of the day ahead. What they're thinking about, worried about, excited about.
- **L3 usage:** Primary input for morning briefing. Compared against calendar and email signals to detect alignment or avoidance.
- **Structure:** Semi-structured. The morning Opus Director asks 1-2 targeted questions based on the previous night's reflection.

### 3.2 Ad-Hoc Capture

- **Trigger:** User activates capture any time (Cmd+Shift+Space global hotkey, or menu bar → "Quick capture").
- **Duration:** No minimum or maximum. Typical: 10-30 seconds.
- **Purpose:** Capture fleeting thoughts, observations, or decisions the executive wants to remember.
- **L3 usage:** Written as high-priority episodic memory. May trigger re-prioritisation if content indicates urgency.
- **Structure:** Unstructured. Free-form dictation.

### 3.3 Focus Debrief

- **Trigger:** Automatically prompted when a focus session (Pomodoro) ends. Optional — user can dismiss.
- **Duration:** Target 15-30 seconds.
- **Purpose:** Capture what the user actually did during focus time, whether they completed what they intended, and what's left.
- **L3 usage:** Feeds EMA time estimation (actual vs planned), focus quality assessment, and task completion records.
- **Structure:** Semi-structured. Prompted with "How did the focus session go? Did you finish [task name]?"

### 3.4 Correction

- **Trigger:** User says "That's wrong" or "Actually..." or "Correct this" during any session, or initiates a correction session from UI.
- **Duration:** No limit. Typical: 10-60 seconds.
- **Purpose:** Override or refine something Timed got wrong. These signals have the highest priority in the memory store.
- **L3 usage:** Written as `type: correction` with maximum importance. Nightly reflection must incorporate. Procedural rules may be updated immediately (not waiting for nightly cycle).
- **Structure:** Unstructured. The user states what was wrong and what's correct.

---

## 4. Captured Data

### 4.1 Signal Schema

```swift
struct VoiceSignal: Codable, Identifiable {
    let id: UUID
    let sessionType: VoiceSessionType   // .morningInterview, .adHoc, .focusDebrief, .correction
    let transcript: String              // Full transcript text
    let sessionStart: Date
    let sessionEnd: Date
    let duration: TimeInterval          // sessionEnd - sessionStart
    
    // Metadata (computed from transcript)
    let wordCount: Int
    let wordsPerMinute: Double          // pace
    let segmentTimings: [TranscriptSegment]  // Word-level timestamps
    let topics: [ExtractedTopic]        // Key topics/entities extracted
    let sentiment: SentimentScore       // Positive/negative/neutral
    
    // Context
    let relatedTaskId: UUID?            // Non-nil for focus debriefs
    let triggerSource: VoiceTriggerSource  // .ui, .globalHotkey, .autoPrompt
    
    // Metadata
    let capturedAt: Date
    let signalSource: SignalSource      // .voice
}

struct TranscriptSegment: Codable {
    let text: String
    let timestamp: TimeInterval         // Offset from session start
    let confidence: Float               // 0.0-1.0, from SFTranscription
    let duration: TimeInterval          // Segment duration
}

struct ExtractedTopic: Codable {
    let text: String                    // e.g., "board deck", "Q3 numbers"
    let salience: Double                // 0.0-1.0, how prominent in transcript
}

struct SentimentScore: Codable {
    let positive: Double                // 0.0-1.0
    let negative: Double                // 0.0-1.0
    let neutral: Double                 // 0.0-1.0
    let dominant: Sentiment             // .positive, .negative, .neutral
}
```

### 4.2 Captured

| Data | Source | Notes |
|------|--------|-------|
| Full transcript text | `SFTranscription.formattedString` | Complete text of everything spoken |
| Word-level timestamps | `SFTranscriptionSegment.timestamp` + `.duration` | Per-word timing from Apple Speech |
| Word count | Computed from transcript | Whitespace-split count |
| Speaking pace (WPM) | `wordCount / (duration / 60)` | Words per minute |
| Topics | Extracted from transcript | Using NLTagger (on-device NLP) for named entities + noun phrases |
| Sentiment | Computed from transcript | Using NLTagger sentiment analysis (on-device) |
| Session type | Set at session initiation | Determines L3 processing priority |
| Timestamps | System clock | Session start/end, per-segment offsets |

### 4.3 NOT Captured / NOT Stored

| Data | Status |
|------|--------|
| Raw audio | NEVER stored. Audio buffers exist in memory only during active capture. Released immediately after recognition task completes. |
| Audio files (.wav, .m4a, .caf) | NEVER written to disk. Not even temporarily. |
| Speaker identification | Not performed. Single-user assumption. |
| Background audio | Not captured. Only microphone input during active session. |
| Audio from other apps | Not captured. AVAudioEngine captures mic input only. |

---

## 5. Metadata Extraction Pipeline

After transcript is finalised, metadata is extracted before writing to signal queue.

### 5.1 Topic Extraction

```swift
import NaturalLanguage

func extractTopics(from transcript: String) -> [ExtractedTopic] {
    var topics: [ExtractedTopic] = []
    
    // Named Entity Recognition
    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = transcript
    
    tagger.enumerateTags(
        in: transcript.startIndex..<transcript.endIndex,
        unit: .word,
        scheme: .nameType
    ) { tag, range in
        if let tag, [.personalName, .organizationName, .placeName].contains(tag) {
            let text = String(transcript[range])
            topics.append(ExtractedTopic(text: text, salience: 0.8))
        }
        return true
    }
    
    // Noun phrase extraction for non-entity topics
    let nounTagger = NLTagger(tagSchemes: [.lexicalClass])
    nounTagger.string = transcript
    // Extract noun phrases (consecutive noun + adjective sequences)
    // Deduplicate against named entities
    // Assign salience based on frequency and position (earlier = more salient)
    
    return topics.sorted { $0.salience > $1.salience }
}
```

### 5.2 Sentiment Analysis

```swift
func analyseSentiment(of transcript: String) -> SentimentScore {
    let tagger = NLTagger(tagSchemes: [.sentimentScore])
    tagger.string = transcript
    
    // Sentence-level sentiment for granularity
    var sentenceScores: [Double] = []
    tagger.enumerateTags(
        in: transcript.startIndex..<transcript.endIndex,
        unit: .sentence,
        scheme: .sentimentScore
    ) { tag, range in
        if let tag, let score = Double(tag.rawValue) {
            sentenceScores.append(score)  // -1.0 to 1.0
        }
        return true
    }
    
    // Aggregate: average sentence sentiment
    let avgScore = sentenceScores.isEmpty ? 0 : sentenceScores.reduce(0, +) / Double(sentenceScores.count)
    
    // Map to three-axis score
    let positive = max(0, avgScore)
    let negative = max(0, -avgScore)
    let neutral = 1.0 - abs(avgScore)
    let dominant: Sentiment = avgScore > 0.1 ? .positive : (avgScore < -0.1 ? .negative : .neutral)
    
    return SentimentScore(
        positive: positive,
        negative: negative,
        neutral: neutral,
        dominant: dominant
    )
}
```

### 5.3 Processing Order

```
Transcript finalised (isFinal = true)
  → Stop audio engine
  → Release audio buffers (CRITICAL — no audio in memory after this point)
  → Extract word count, compute WPM
  → Extract segment timings from SFTranscription.segments
  → Run topic extraction (NLTagger — on-device, < 100ms for typical transcript)
  → Run sentiment analysis (NLTagger — on-device, < 50ms)
  → Assemble VoiceSignal
  → Write to CoreData (DataStore.saveVoiceSignal)
  → Log completion at .info level
```

---

## 6. Latency Targets

| Stage | Target | Measurement |
|-------|--------|-------------|
| Audio capture start (user presses button → mic active) | < 200ms | Time from UI action to `audioEngine.start()` completion |
| First partial result (mic active → first words appear) | < 500ms | Time from first spoken word to first `SFSpeechRecognitionResult` |
| Streaming transcript update | < 300ms | Time from word spoken to text appearing in UI |
| Final transcript (user stops → isFinal) | < 2 seconds | Time from last spoken word to `isFinal = true` |
| Metadata extraction (transcript → topics + sentiment) | < 200ms | NLTagger processing time for typical transcript (50-200 words) |
| Signal write (metadata → CoreData) | < 100ms | DataStore write time |
| Total pipeline (button press → signal queued) | < 3 seconds after speech ends | End-to-end, excluding user speaking time |

### 6.1 Latency Monitoring

```swift
struct VoicePipelineMetrics {
    let captureStartLatency: TimeInterval
    let firstPartialResultLatency: TimeInterval
    let finalTranscriptLatency: TimeInterval
    let metadataExtractionLatency: TimeInterval
    let signalWriteLatency: TimeInterval
    let totalPipelineLatency: TimeInterval
}
```

Logged at `.debug` level for every session. Aggregated weekly for performance regression detection.

---

## 7. macOS Permissions

### 7.1 Required: Microphone Access

| Permission | System Location | Required For |
|-----------|----------------|--------------|
| Microphone | System Preferences > Privacy > Microphone > Timed.app | All voice capture |

### 7.2 Required: Speech Recognition

| Permission | System Location | Required For |
|-----------|----------------|--------------|
| Speech Recognition | System Preferences > Privacy > Speech Recognition > Timed.app | SFSpeechRecognizer |

### 7.3 Permission Request Flow

1. **First voice session attempt:** Check `AVCaptureDevice.authorizationStatus(for: .audio)` and `SFSpeechRecognizer.authorizationStatus()`.
2. **If not determined:** Request both permissions sequentially (mic first, then speech). Show explanation before each: "Timed uses your microphone for voice capture during morning interviews and quick notes. Audio is processed on-device and never stored."
3. **If denied:** Show in-app explanation with "Open System Preferences" button. Voice features are disabled but all other features work.
4. **If restricted:** Same as denied (parental controls or MDM).

```swift
func requestVoicePermissions() async -> VoicePermissionState {
    // Step 1: Microphone
    let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    if micStatus == .notDetermined {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if !granted { return .microphoneDenied }
    } else if micStatus != .authorized {
        return .microphoneDenied
    }
    
    // Step 2: Speech Recognition
    let speechStatus = SFSpeechRecognizer.authorizationStatus()
    if speechStatus == .notDetermined {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized: continuation.resume(returning: .authorized)
                default: continuation.resume(returning: .speechRecognitionDenied)
                }
            }
        }
    } else if speechStatus != .authorized {
        return .speechRecognitionDenied
    }
    
    return .authorized
}

enum VoicePermissionState {
    case authorized
    case microphoneDenied
    case speechRecognitionDenied
    case restricted
}
```

### 7.4 On-Device Enforcement

```swift
// SFSpeechAudioBufferRecognitionRequest configuration
recognitionRequest.requiresOnDeviceRecognition = true
```

If the on-device model is not available (extremely rare on macOS 13+), the recognition request fails. Timed does NOT fall back to server-based recognition. The error is logged and the user is informed: "On-device speech recognition is not available. Please ensure macOS speech models are downloaded in System Preferences > Keyboard > Dictation."

---

## 8. Error Handling

### 8.1 Error Categories

```swift
enum VoiceCaptureError: Error {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case onDeviceModelUnavailable
    case audioEngineFailedToStart(underlying: Error)
    case recognitionTaskFailed(underlying: Error)
    case transcriptEmpty                    // User pressed record but said nothing
    case sessionTimedOut(duration: TimeInterval)  // Exceeded max session duration
}
```

### 8.2 Error Handling Matrix

| Error | User Impact | Action |
|-------|-------------|--------|
| `microphonePermissionDenied` | No voice capture | Show "Microphone access required" with Settings link. Disable voice UI. |
| `speechRecognitionPermissionDenied` | No voice capture | Show "Speech Recognition access required" with Settings link. Disable voice UI. |
| `onDeviceModelUnavailable` | No voice capture | Show "Download speech models" instructions. Do NOT fall back to server recognition. |
| `audioEngineFailedToStart` | Session fails | Log error. Retry once. If fails again, show "Microphone unavailable" error. |
| `recognitionTaskFailed` | Partial transcript | If partial results exist, use them. If no results, discard session. |
| `transcriptEmpty` | No signal | Discard session silently. Log at `.debug`. |
| `sessionTimedOut` | Session ends | Finalise with whatever transcript exists. Cap at 5 minutes for any session type. |

### 8.3 Audio Engine Recovery

```swift
/// If the audio engine stops unexpectedly (e.g., Bluetooth headset disconnects),
/// attempt recovery.
func handleAudioEngineInterruption() {
    // 1. Stop current recognition task
    recognitionTask?.cancel()
    
    // 2. Save any partial transcript
    if let partial = currentTranscript, !partial.formattedString.isEmpty {
        finaliseSession(transcript: partial, wasInterrupted: true)
    }
    
    // 3. Reset audio engine
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    
    // 4. Notify user
    // "Voice capture interrupted. Your words were saved."
}
```

---

## 9. Acceptance Criteria

### 9.1 Functional — Pipeline

- [ ] AVAudioEngine captures microphone input and feeds to SFSpeechRecognizer.
- [ ] `requiresOnDeviceRecognition = true` is set — no audio sent to Apple servers.
- [ ] Partial results stream to UI in real-time (< 300ms latency).
- [ ] Final transcript is produced when user stops speaking or ends session.
- [ ] Transcript includes word-level timestamps and confidence scores.
- [ ] Audio buffers are released immediately after recognition completes.
- [ ] No audio files (.wav, .m4a, .caf) exist on disk at any point.

### 9.2 Functional — Session Types

- [ ] Morning interview sessions are created with correct type and context.
- [ ] Ad-hoc captures are triggered by global hotkey and menu bar action.
- [ ] Focus debriefs are prompted at Pomodoro session end.
- [ ] Correction sessions are flagged with maximum priority.
- [ ] Each session type writes the correct `VoiceSessionType` to signal queue.

### 9.3 Functional — Metadata

- [ ] Word count is accurately computed from transcript.
- [ ] Words per minute (pace) is computed from word count and session duration.
- [ ] Topics are extracted using NLTagger (named entities + noun phrases).
- [ ] Sentiment is computed per-sentence and aggregated.
- [ ] All metadata fields are populated in VoiceSignal before write.

### 9.4 Latency

- [ ] Capture start < 200ms from user action.
- [ ] First partial result < 500ms from first spoken word.
- [ ] Final transcript < 2 seconds after last spoken word.
- [ ] Metadata extraction < 200ms.
- [ ] Total pipeline < 3 seconds after speech ends (excluding speaking time).

### 9.5 Privacy

- [ ] Raw audio is NEVER written to disk.
- [ ] Audio buffers are released from memory after recognition completes.
- [ ] `requiresOnDeviceRecognition = true` — no server fallback.
- [ ] No audio is captured outside of active voice sessions.
- [ ] Microphone tap is removed when session ends.

### 9.6 Permissions

- [ ] Microphone permission requested before first voice session.
- [ ] Speech Recognition permission requested before first voice session.
- [ ] Denied permissions disable voice features without affecting rest of app.
- [ ] Permission state is checked at session start (handles mid-session revocation).

### 9.7 Error Recovery

- [ ] Audio engine interruption saves partial transcript.
- [ ] Empty transcript (no speech detected) discards session silently.
- [ ] Session timeout (5 min) finalises with existing transcript.
- [ ] Recognition task failure uses partial results if available.
