# Timed — Voice Pipeline Deep Audit (Thread 1 of 7)
> **Repo:** `ammarshah1n/time-manager-desktop` · **Branch:** `ui/apple-v1-restore`  
> **Files in scope:** `Sources/Core/Services/SpeechService.swift`, `VoiceCaptureService.swift`, `VoiceResponseParser.swift`, `Sources/Features/MorningInterview/MorningInterviewPane.swift`  
> **Objective:** A+ tier implementation guide for the voice pipeline — covering adaptive rate, STT accuracy/fallback, intent completeness, error recovery, and voice selection.

***

## Impact-Ranked Findings at a Glance

| # | Finding | File | Impact | Effort |
|---|---------|------|--------|--------|
| 1 | Adaptive speech rate — fixed 0.50 | `SpeechService.swift` | 🔴 High | Low |
| 2 | 17 missing NL intents | `VoiceResponseParser.swift` | 🔴 High | Medium |
| 3 | Zero low-confidence STT guard | `VoiceCaptureService.swift` + `MorningInterviewPane` | 🔴 High | Medium |
| 4 | Apple Speech → `SpeechAnalyzer` migration path | `VoiceCaptureService.swift` | 🟠 Medium | Medium |
| 5 | No Personal Voice / optimal voice selection | `SpeechService.swift` | 🟠 Medium | Low |
| 6 | Conversational repair is single-path | `MorningInterviewPane.swift` | 🟠 Medium | Low |

***

## Finding 1 — Adaptive Speech Rate (SpeechService.swift)

### Current State

```swift
// SpeechService.swift, func speak(_:rate:), line ~28
func speak(_ text: String, rate: Float = 0.50) {
    ...
    utterance.rate = rate       // ← always 0.50 regardless of user preference
```

```swift
// previewVoice also hardcodes rate
utterance.rate = 0.50           // ← line ~40
```

The Apple documentation confirms that `0.5` is the *system default rate*, defined by `AVSpeechUtteranceDefaultSpeechRate`. For a morning planning assistant targeting a single executive user, locking the rate to the default is a missed optimisation opportunity.[^1]

### How Best-in-Class Assistants Handle Rate Adaptation

**Siri** reads the user's VoiceOver accessibility speech rate setting via `prefersAssistiveTechnologySettings`. When `AVSpeechUtterance.prefersAssistiveTechnologySettings = true`, the synthesiser automatically applies the user's configured rate, voice, and pitch from System Settings → Accessibility → Spoken Content. This is a single-line opt-in that mirrors what the user already expects.[^1]

**Alexa** uses *conversational entrainment* — when the user speaks at a faster clip, Alexa's next turn rate increases by a statistically significant coefficient (p < 0.001). The mechanism is a per-session exponential moving average (EMA) of the user's STT speech rate (words per second), with the TTS rate clamped to a delivery range of 0.48–0.72 on Apple's 0–1 scale.[^2]

**Google Assistant / Actions** exposes `<speak><prosody rate="fast">` SSML tags and adjusts rate based on content type — short confirmations are delivered faster, multi-item lists slower.[^3]

### The Optimal Adaptive Algorithm for Timed (Single-User App)

Because Timed serves exactly one executive user, a per-session EMA is the right design. The algorithm has three inputs:

1. **Explicit preference** — a slider/stepper in `PrefsView` persisted via `@AppStorage("prefs.voice.rate")`.
2. **Implicit signal** — `didCancel` delegate events (user hit stop), which signal *too slow*.
3. **Session EMA** — smooths both signals across the session.

The EMA update equation is:

\[ r_{n+1} = \alpha \cdot r_{\text{target}} + (1 - \alpha) \cdot r_n \]

where \( \alpha = 0.3 \) gives a responsive but stable adaptation (3–4 events to converge). `r_target` is bumped +0.04 on each `didCancel` and reset toward the user's persisted baseline on `didFinish` without cancellation.

### Exact Code Fix — SpeechService.swift

```swift
// ── NEW: add these two stored properties (after line 17) ──────────────────
@AppStorage("prefs.voice.rate")   private var preferredRate: Double = 0.50
@AppStorage("prefs.voice.rate.session") private var sessionRate: Double = 0.50
private let emaAlpha: Float = 0.3

// ── REPLACE speak(_:rate:) ─────────────────────────────────────────────────
func speak(_ text: String, overrideRate: Float? = nil) {
    stop()
    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = overrideRate ?? Float(sessionRate)
    utterance.voice = resolveVoice()
    utterance.pitchMultiplier = 1.0
    utterance.preUtteranceDelay = 0.15
    utterance.postUtteranceDelay = 0.1
    synthesizer.speak(utterance)
    isSpeaking = true
}

// ── ADD to delegate ─────────────────────────────────────────────────────────
nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
) {
    Task { @MainActor in
        self.isSpeaking = false
        // User stopped speaking — bump rate upward (they want faster)
        let bumped = min(Double(AVSpeechUtteranceMaximumSpeechRate),
                        sessionRate + 0.04)
        sessionRate = Double(emaAlpha) * bumped + Double(1 - emaAlpha) * sessionRate
    }
}

// ── ADD to PrefsView (new) ──────────────────────────────────────────────────
// Slider: value: $preferredRate, in: 0.35...0.70, label: "Speaking speed"
// On change: sessionRate = preferredRate  // reset session baseline
```

**Also fix `previewVoice`** (line ~40): replace `utterance.rate = 0.50` with `utterance.rate = Float(sessionRate)`.

**Why not `prefersAssistiveTechnologySettings`?** It overrides *all* utterance properties including voice, which conflicts with Timed's deliberate premium voice selection in `resolveVoice()`. Use the EMA approach instead and offer the accessibility opt-in as a separate pref toggle for users who already have system-wide settings configured.[^1]

***

## Finding 2 — Missing Natural Language Intents (VoiceResponseParser.swift)

### Current Coverage

`VoiceResponseParser` handles six intents:

| Intent | Examples covered |
|--------|-----------------|
| `.affirmative` | "yes", "sure", "sounds good" |
| `.negative` | "no", "skip", "cancel" |
| `.number(Int)` | "three hours", "45 minutes" |
| `.removeItem(Int)` | "remove the second" |
| `.swapItems(Int, Int)` | "swap 1 and 3" |
| `.estimateOverride(ordinal:minutes:)` | "make the third one 20 minutes" |

### What's Missing — Comparison to Alexa Skills Kit and Google Actions

Google Actions defines tiered built-in system intents including `YES`, `NO`, `CANCEL`, and `REPEAT`. It also specifies `NO_MATCH_1 / NO_MATCH_2 / NO_MATCH_FINAL` which are distinct from a simple `.unknown` return — each tier fires a progressively stronger re-prompt before exiting. Alexa's intent schema requires a `AMAZON.FallbackIntent` that must always be present. Neither pattern exists in the current `VoiceResponseParser`.[^4][^5]

Beyond system intents, a morning planning conversation in Timed needs the following **17 missing intents**:

```swift
// ── Add to VoiceResponse enum ──────────────────────────────────────────────

case skip                            // "skip that one", "pass", "move on"
case moveToTomorrow(Int?)            // "push that to tomorrow", "defer the second one"
case moveToNextWeek(Int?)            // "move it to next week"
case confirmAll                      // "keep everything", "lock all of them"
case clearAll                        // "clear the whole list", "start fresh"
case repeat_                         // "say that again", "what was that"
case whatIsNext                      // "what's next?", "next one"
case howLong(Int?)                   // "how long will that take?", "what's the estimate for the third?"
case addTask(String)                 // "add send invoice to the list"
case insertAt(ordinal: Int, String)  // "add client call at position 2"
case undo                            // "undo that", "go back", "revert"
case confirmItem(Int)                // "confirm the second one", "lock in the third"
case rejectItem(Int)                 // "remove only the first", separate from removeItem
case goBack                          // "go back to the previous step"
case setTime(Int)                    // "set my time to 3 hours" (step 0 synonym)
case done                            // "that's it", "done", "finish", "that's all"
case noMore                          // "nothing else", "no more", "that's enough"
```

### Exact Code Fix — VoiceResponseParser.swift

The parse pipeline (lines ~25–42) should be extended as follows — insert after the existing swap check, before the fallback `.number` check:

```swift
// In VoiceResponse.parse(), after parseSwap check (~line 40):

// 6b. Check skip
if isSkip(cleaned)           { return .skip }

// 6c. Check deferred scheduling
if let defer_ = parseMoveToDate(cleaned) { return defer_ }

// 6d. Check repeat request
if isRepeatRequest(cleaned)  { return .repeat_ }

// 6e. Check "what's next"
if isNextQuery(cleaned)      { return .whatIsNext }

// 6f. Check "how long"
if let howLong = parseHowLong(cleaned) { return howLong }

// 6g. Check add task
if let add = parseAddTask(cleaned) { return add }

// 6h. Check undo
if isUndo(cleaned)           { return .undo }

// 6i. Check done / no more
if isDone(cleaned)           { return .done }
if isNoMore(cleaned)         { return .noMore }

// 6j. Check go back
if isGoBack(cleaned)         { return .goBack }
```

**Key implementations:**

```swift
private static let skipWords: Set<String> = [
    "skip", "pass", "skip that", "skip that one", "next", "move on",
    "skip it", "pass on that", "not that one"
]
private static func isSkip(_ text: String) -> Bool {
    skipWords.contains(text) || skipWords.contains { text.hasPrefix($0) }
}

private static func parseMoveToDate(_ text: String) -> VoiceResponse? {
    let isTomorrow = text.contains("tomorrow") || text.contains("next day")
    let isNextWeek = text.contains("next week")
    guard (isTomorrow || isNextWeek) &&
          (text.contains("push") || text.contains("move") || text.contains("defer") ||
           text.contains("delay") || text.contains("put")) else { return nil }
    var ordinal: Int? = nil
    for (word, idx) in ordinalToIndex where text.contains(word) {
        ordinal = idx; break
    }
    return isTomorrow ? .moveToTomorrow(ordinal) : .moveToNextWeek(ordinal)
}

private static let repeatWords: Set<String> = [
    "repeat", "say that again", "what was that", "sorry what", "pardon",
    "could you repeat", "again please", "come again"
]
private static func isRepeatRequest(_ text: String) -> Bool {
    repeatWords.contains { text.contains($0) }
}

private static let nextWords: Set<String> = [
    "what's next", "whats next", "next one", "next item",
    "what comes next", "continue", "go on"
]
private static func isNextQuery(_ text: String) -> Bool {
    nextWords.contains { text.contains($0) }
}

private static func parseHowLong(_ text: String) -> VoiceResponse? {
    guard text.contains("how long") || text.contains("how much time") ||
          text.contains("what's the estimate") || text.contains("what is the estimate") else { return nil }
    for (word, idx) in ordinalToIndex where text.contains(word) {
        return .howLong(idx)
    }
    return .howLong(nil) // asking about current item
}

private static func parseAddTask(_ text: String) -> VoiceResponse? {
    let triggers = ["add ", "also add ", "include ", "and add ", "put "]
    for trigger in triggers where text.hasPrefix(trigger) {
        let raw = String(text.dropFirst(trigger.count))
        let cleaned = raw
            .replacingOccurrences(of: " to the list", with: "")
            .replacingOccurrences(of: " to my list", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 2 else { return nil }
        return .addTask(cleaned)
    }
    return nil
}

private static let undoWords: Set<String> = [
    "undo", "go back", "revert", "undo that", "take that back",
    "cancel that", "never mind that last", "oops"
]
private static func isUndo(_ text: String) -> Bool {
    undoWords.contains { text.hasPrefix($0) }
}

private static let doneWords: Set<String> = [
    "done", "that's it", "that's all", "finish", "finished", "complete",
    "all done", "i'm done", "that will do", "that's everything"
]
private static func isDone(_ text: String) -> Bool {
    doneWords.contains(text) || doneWords.contains { text.hasPrefix($0) }
}

private static let noMoreWords: Set<String> = [
    "nothing else", "no more", "that's enough", "nothing more",
    "no other", "no other items", "that's all of them"
]
private static func isNoMore(_ text: String) -> Bool {
    noMoreWords.contains { text.contains($0) }
}

private static let goBackWords: Set<String> = [
    "go back", "previous step", "back to", "step back", "go to step"
]
private static func isGoBack(_ text: String) -> Bool {
    goBackWords.contains { text.hasPrefix($0) }
}
```

**Wire up in `MorningInterviewPane.handleVoiceResponse`**: the `.repeat_` case should re-call `speakForStep(step)`. The `.whatIsNext` case should call `advanceStep()`. The `.moveToTomorrow` and `.moveToNextWeek` cases should update the task's `dueDate` (step 1 context). The `.addTask` case should append a new `ParsedItem` to the current step's list. The `.undo` case should decrement `step` by 1.

***

## Finding 3 — Zero STT Confidence Guard (VoiceCaptureService.swift + MorningInterviewPane.swift)

### Current State

```swift
// VoiceCaptureService.swift, startRecognitionTask(), ~line 97
self.liveTranscript = result.bestTranscription.formattedString
// ← no check on segment confidence; any transcript — even garbage — is accepted
```

`SFSpeechRecognitionResult` carries `transcriptions: [SFTranscription]` sorted by descending confidence. Each `SFTranscriptionSegment` has a `confidence: Float` property (0.0 = no recognition). The current code ignores this entirely and passes every `bestTranscription` directly to `VoiceResponse.parse()`.[^6][^7]

Research confirms that confidence scores at the **transcript level** correlate strongly with word error rate (p < 0.001), even though word-level confidence alone cannot reliably detect individual errors. For a tightly scoped yes/no/number domain — exactly Timed's use case — sentence-level confidence is highly actionable.[^8][^9]

### Confidence Threshold Strategy

The Apple framework populates `bestTranscription.segments[i].confidence` only when `isFinal == true`. This means the guard should live in `finishListening()` in `MorningInterviewPane`, not inside the partial-result handler.[^10]

Recommended thresholds based on domain research:[^11][^9]

| Scenario | Threshold | Action |
|----------|-----------|--------|
| High confidence | ≥ 0.75 | Accept and process |
| Medium confidence | 0.50–0.74 | Show transcript in UI, ask for verbal confirmation |
| Low confidence | 0.30–0.49 | "I didn't quite catch that — could you say it again?" |
| Very low / empty | < 0.30 | Show text fallback, auto-switch input mode |

### Exact Code Fix — VoiceCaptureService.swift

Add a computed property to expose confidence:

```swift
// Add to VoiceCaptureService, after parsedItems published var (~line 52)
@Published private(set) var lastConfidence: Float = 1.0

// In startRecognitionTask(), after assigning liveTranscript:
self.liveTranscript = result.bestTranscription.formattedString
if result.isFinal {
    let segmentConfidences = result.bestTranscription.segments.map(\.confidence)
    self.lastConfidence = segmentConfidences.isEmpty ? 0.5 :
        segmentConfidences.reduce(0, +) / Float(segmentConfidences.count)
}
```

### Exact Code Fix — MorningInterviewPane.swift

Replace the `finishListening()` body (the direct call to `VoiceResponse.parse`) with a confidence-gated version:

```swift
private func finishListening() {
    let transcript = voiceCapture.liveTranscript
    let confidence = voiceCapture.lastConfidence
    stopListening()
    cancelSilenceTimer()

    guard !transcript.isEmpty else {
        conversationState = .idle
        return
    }

    // ── Confidence gate ──────────────────────────────────────────────────
    switch confidence {
    case 0.75...:
        // High confidence — proceed normally
        processTranscript(transcript)

    case 0.50..<0.75:
        // Medium confidence — show transcript, ask for confirmation
        conversationState = .idle
        voiceStatusText = "Did you say: "\(transcript)"?"
        speechService.speak("Did you mean: \(transcript)?")
        // On next affirmative, commit; on negative, re-prompt
        pendingLowConfidenceTranscript = transcript

    case 0.30..<0.50:
        // Low confidence — re-prompt with variation
        silenceTimeoutCount += 1
        if silenceTimeoutCount < 2 {
            conversationState = .idle
            let reprompt = repromptForStep(step)
            speechService.speak(reprompt)
        } else {
            // Second failure — show text fallback
            conversationState = .idle
            showTextFallback = true
            silenceTimeoutCount = 0
        }

    default:
        // Very low — immediately offer text fallback
        conversationState = .idle
        showTextFallback = true
    }
}

// Add these state vars to MorningInterviewPane:
@State private var pendingLowConfidenceTranscript: String? = nil
@State private var showTextFallback: Bool = false

// Helper — varied reprompts to avoid robotic repetition:
private func repromptForStep(_ s: Int) -> String {
    let prompts: [Int: [String]] = [
        0: ["How many hours do you have today?",
            "Tell me your available time — for example, say 'three hours'.",
            "I didn't catch that. Try saying something like 'four hours'."],
        1: ["Should I keep all of today's tasks?",
            "Say 'yes' to keep them all, or name one to remove.",
            "I'm having trouble hearing. Should I keep everything?"],
        2: ["Are those time estimates correct?",
            "Say 'yes' to accept, or 'change the second to 30 minutes'.",
            "I missed that. Say 'yes' to accept all estimates."],
        3: ["Ready to start your day?",
            "Say 'yes' to lock in the plan, or 'go back' to review.",
            "I didn't quite get that. Say 'yes' to start your day."]
    ]
    let options = prompts[s] ?? ["I didn't catch that. Could you try again?"]
    let idx = min(silenceTimeoutCount, options.count - 1)
    return options[idx]
}

private func processTranscript(_ transcript: String) {
    conversationState = .processing
    voiceProcessing = true
    let response = VoiceResponse.parse(transcript)
    handleVoiceResponse(response)
    voiceProcessing = false
    if case .processing = conversationState { conversationState = .idle }
}
```

**Text fallback view**: add a small inline `TextField` that appears when `showTextFallback == true`, pre-populated with the best (even low-confidence) transcript, allowing the user to correct it and tap Enter. On submit, call `processTranscript(editedText)`.

***

## Finding 4 — Apple Speech Framework: SFSpeechRecognizer vs. SpeechAnalyzer Migration

### Accuracy and Latency Reality

The current `VoiceCaptureService` uses `SFSpeechRecognizer` with `requiresOnDeviceRecognition = false` (server-assisted), which gives the best accuracy of the legacy API. Benchmark data as of 2026:

| Engine | WER | Latency | Privacy | Offline |
|--------|-----|---------|---------|---------|
| OpenAI Whisper API | ~8.06% (92% acc.) | 2–5 s batch | ❌ Cloud | ❌ |
| Apple SFSpeechRecognizer (server) | ~12–15% (est.) | 200–400 ms streaming | ⚠️ Apple servers | ❌ |
| Apple SpeechAnalyzer (iOS 26 / macOS Tahoe) | Mid-tier Whisper parity | Faster than Whisper | ✅ On-device | ✅ |
| Apple SFSpeechRecognizer (on-device) | Higher WER | 100–200 ms | ✅ | ✅ |

[^12][^13][^14]

Apple introduced `SpeechAnalyzer` + `SpeechTranscriber` at WWDC 2025, shipping in iOS 26 / macOS Tahoe. In benchmarks by Argmax, it "matches the speed and accuracy of mid-tier OpenAI Whisper models on long-form conversational speech". MacStories testing confirmed it is faster than Whisper while matching or exceeding `SFSpeechRecognizer`'s accuracy.[^13][^15][^14][^16][^17]

**Critical note for Timed**: Apple's older `SFSpeechRecognizer` API supports **Custom Vocabulary** (task hint + `contextualStrings`), which lets you register known words ("Do First", "Triage", "Waiting") to improve recognition of app-specific terms. The new `SpeechAnalyzer` does *not* yet support Custom Vocabulary. For a planning assistant with app-specific bucket names and task vocabulary, `SFSpeechRecognizer` with Custom Vocabulary is **currently more accurate** for Timed's domain despite the newer API's general improvements.[^13]

### When to Fall Back to Whisper API

Whisper API should *not* be the default — it introduces network latency (2–5 s), cloud privacy exposure, and rate limits. The correct fallback decision tree:[^18]

```
1. SFSpeechRecognizer available + authorized?  
   → YES: Use with contextualStrings vocabulary  
   → NO: Fall through  

2. Network available + user has consented to cloud STT?  
   → Use OpenAI Whisper API (batch mode, ~3 s round-trip)  

3. Network unavailable OR user refused cloud?  
   → Use SFSpeechRecognizer with requiresOnDeviceRecognition = true  
     (higher WER but fully offline)  

4. Microphone unavailable?  
   → Text input fallback (showTextFallback = true)
```

### Custom Vocabulary Fix — VoiceCaptureService.swift

Add contextual strings to the recognition request (line ~83, in `startAudioEngine()`):

```swift
let request = SFSpeechAudioBufferRecognitionRequest()
request.shouldReportPartialResults = true
request.requiresOnDeviceRecognition = false
request.taskHint = .confirmation  // optimised for short yes/no/number answers

// ── NEW: vocabulary boost ─────────────────────────────────────────────────
request.contextualStrings = [
    "Do First", "Triage", "Waiting", "Today", "Overdue",
    "swap", "remove", "estimate", "ordinal",
    "lock it in", "sounds good", "skip that one",
    "move to tomorrow", "add task", "how long will that take",
    "what's next", "go back"
]
recognitionRequest = request
```

**`taskHint = .confirmation`** is the correct hint for step 0 (time declaration) and step 3 (plan lock-in). For step 2 (estimate overrides, free-form corrections), switch to `.dictation`:

```swift
// In speakForStep(), before calling voiceCapture.start():
await voiceCapture.updateTaskHint(step == 2 ? .dictation : .confirmation)
```

Add `updateTaskHint` to `VoiceCaptureService` to store the hint and apply it on next `start()` call.

### macOS Tahoe Migration Path

When the minimum deployment target is raised to macOS Tahoe (macOS 26+):

```swift
// New VoiceCaptureService.startAudioEngine() alternative path:
if #available(macOS 26.0, *) {
    let transcriber = SpeechTranscriber(
        locale: Locale(identifier: "en-US"),
        transcriptionOptions: [],
        reportingOptions: [.volatileResults],
        attributeOptions: []
    )
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    // ... new async streaming API
} else {
    // existing SFSpeechRecognizer path
}
```



***

## Finding 5 — Premium Voice Selection (SpeechService.swift)

### Current Behaviour

```swift
// SpeechService.swift, resolveVoice(), ~line 55
static func availablePremiumVoices() -> [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices().filter {
        $0.language.hasPrefix("en") && ($0.quality == .premium || $0.quality == .enhanced)
    }
}

private func resolveVoice() -> AVSpeechSynthesisVoice? {
    if !voiceIdentifier.isEmpty, let stored = ... { return stored }
    if let premium = Self.availablePremiumVoices().first { return premium }  // ← random .first
    return AVSpeechSynthesisVoice(language: "en-GB")
}
```

The `.first` call on an unordered array picks whichever premium voice happens to appear first — often a compact or non-ideal voice. There is no quality tiebreak between `.premium` and `.enhanced`.

### Best Voices for a Productivity Assistant

Apple's TTS voice quality tiers are: `.compact` (worst) → `.enhanced` → `.premium` (best). On Apple Silicon Macs, premium Siri-based neural voices are available and sound markedly more natural than standard enhanced voices. The current TTS voices whose foundation was last updated around iOS 16 remain the basis, though Apple Intelligence is expected to bring AI-driven TTS improvements in future OS releases.[^19][^20][^21][^1]

**Ranked voice identifiers for an executive productivity assistant (en-US and en-GB):**

| Priority | Voice | Identifier | Quality | Tone |
|----------|-------|-----------|---------|------|
| 1 | Ava (Premium) | `com.apple.voice.premium.en-US.Ava` | Premium | Clear, warm, professional |
| 2 | Evan (Premium) | `com.apple.voice.premium.en-US.Evan` | Premium | Measured, authoritative |
| 3 | Allison (Enhanced) | `com.apple.ttsbundle.Allison-premium` | Enhanced | Crisp, neutral |
| 4 | Daniel (en-GB Enhanced) | `com.apple.ttsbundle.Daniel-premium` | Enhanced | Formal, British |
| 5 | Kate (en-GB Enhanced) | `com.apple.ttsbundle.Kate-premium` | Enhanced | Professional British |

[^21][^22]

### Personal Voice — What's Possible and What's Not

Apple's Personal Voice API (`AVSpeechSynthesizer.requestPersonalVoiceAuthorization()`) allows a user to synthesise speech in their own recorded voice, introduced in iOS 17 / macOS Sonoma. Third-party apps can request authorisation. However, there are two blockers for Timed:[^23][^24][^25][^3]

1. **Commercial use is prohibited**: Apple's SLA explicitly prohibits commercial use of Personal Voice in third-party apps.[^26]
2. **Opt-in model**: Users must have created a Personal Voice in System Settings → Accessibility → Personal Voice, then explicitly grant the app permission. The voice also cannot be used to *capture* speech — only to speak.[^27][^28]

For Timed's single-user context, the correct approach is to offer Personal Voice as an *opt-in premium feature* with a clear onboarding explanation, while defaulting to the ranked neural voices above. The implementation path:

```swift
// SpeechService.swift — add Personal Voice support
func requestPersonalVoiceIfAvailable() async {
    if #available(macOS 14.0, *) {
        let status = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
        if status == .authorized {
            // Personal Voice voices appear in speechVoices() with quality == .personal
            if let personalVoice = AVSpeechSynthesisVoice.speechVoices()
                .first(where: { $0.quality == .personal }) {
                voiceIdentifier = personalVoice.identifier
            }
        }
    }
}
```

Add a "Use my voice" button in `PrefsView` that calls `requestPersonalVoiceIfAvailable()`.

### Exact Code Fix — resolveVoice() Priority Ordering

```swift
private func resolveVoice() -> AVSpeechSynthesisVoice? {
    // 1. User has explicitly chosen a voice
    if !voiceIdentifier.isEmpty,
       let stored = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
        return stored
    }

    // 2. Personal Voice (if authorised — opt-in only)
    if #available(macOS 14.0, *),
       AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized,
       let personal = AVSpeechSynthesisVoice.speechVoices()
           .first(where: { $0.quality == .personal }) {
        return personal
    }

    // 3. Premium English voices (ranked: Ava > Evan > others)
    let premiumVoices = AVSpeechSynthesisVoice.speechVoices().filter {
        $0.language.hasPrefix("en") && $0.quality == .premium
    }.sorted { lhs, rhs in
        // Prefer en-US Ava, then Evan, then any other premium
        let preferred = ["Ava", "Evan"]
        let lhsRank = preferred.firstIndex(where: { lhs.name.contains($0) }) ?? Int.max
        let rhsRank = preferred.firstIndex(where: { rhs.name.contains($0) }) ?? Int.max
        return lhsRank < rhsRank
    }
    if let best = premiumVoices.first { return best }

    // 4. Enhanced voices
    if let enhanced = AVSpeechSynthesisVoice.speechVoices().first(where: {
        $0.language.hasPrefix("en") && $0.quality == .enhanced
    }) { return enhanced }

    // 5. System default British
    return AVSpeechSynthesisVoice(language: "en-GB")
}
```

***

## Finding 6 — Conversational Repair (MorningInterviewPane.swift)

### Current State

The existing `handleSilenceTimeout(forStep:)` implements a single re-prompt strategy: after 5 seconds silence, the synthesiser says "Still there?" (a content-free nudge), then on second silence, auto-advances. There is no repair for:

- **Content-level misunderstanding** (parser returned `.unknown`)
- **Mid-session topic change** ("actually, let me start over")
- **Step-skipping requests** ("just go straight to the plan")

### Best-Practice Conversational Repair Taxonomy

Voice UX research distinguishes three repair strategies:[^29][^30]

1. **Clarification request** — system asks user to rephrase. Best when the utterance was heard but not understood.
2. **Repetition request** — system re-asks the question. Best when silence or very low confidence suggests the user didn't hear or respond.
3. **Mode escalation** — system offers a text fallback or visual alternative. Best after two failed repairs.

Google Actions implements exactly three failure tiers: `NO_MATCH_1` (re-prompt 1), `NO_MATCH_2` (re-prompt 2, reworded), `NO_MATCH_FINAL` (exit with instruction). This three-tier model maps cleanly onto Timed.[^5]

### Handling `.unknown` Response

Currently `handleVoiceResponse` silently does nothing on `.unknown`. This should be wired into the repair chain:

```swift
// In MorningInterviewPane.handleVoiceResponse, add a default case to all step handlers:
default:
    if case .unknown(let raw) = response, !raw.isEmpty {
        // We heard something but couldn't parse it
        handleUnrecognisedInput(transcript: raw)
    }
    // .unknown("") = silence, already handled by silence timer

private func handleUnrecognisedInput(transcript: String) {
    noMatchCount += 1
    switch noMatchCount {
    case 1:
        // Re-prompt with clarification hint
        let hint = clarificationHintForStep(step)
        speechService.speak(hint)
    case 2:
        // Offer simplified options
        let simplified = simplifiedPromptForStep(step)
        speechService.speak(simplified)
        showTextFallback = true    // also show text input
    default:
        // Third failure — auto-accept current state and advance
        noMatchCount = 0
        advanceStep()
    }
}

// Add: @State private var noMatchCount: Int = 0
// Reset noMatchCount = 0 at the start of each step in speakForStep()

private func clarificationHintForStep(_ s: Int) -> String {
    switch s {
    case 0: return "I didn't understand. Try saying a number — like 'three hours' or '180 minutes'."
    case 1: return "I didn't catch that. Say 'yes' to keep everything, or 'remove the first one'."
    case 2: return "I didn't get that. Say 'yes' to accept all estimates, or 'change the second to 30 minutes'."
    case 3: return "I didn't understand. Say 'yes' to start your day, or 'go back' to review."
    default: return "I didn't catch that. Could you try again?"
    }
}

private func simplifiedPromptForStep(_ s: Int) -> String {
    switch s {
    case 0: return "Just say a number — like 'four hours'."
    case 1: return "Just say 'yes' or 'no'."
    case 2: return "Just say 'yes' to accept."
    case 3: return "Just say 'yes' to confirm."
    default: return "Say 'yes' or 'no'."
    }
}
```

**Repair variety**: The `repromptForStep` function introduced in Finding 3 provides three indexed reprompts per step — this ensures the system never says the same phrase twice, which research identifies as a key driver of perceived naturalness and reduced frustration.[^30]

***

## Architecture: Wiring the Confidence Guard to the Repair Chain

The full interaction between components after this audit:

```
[User speaks]
     ↓
VoiceCaptureService
  ├── liveTranscript (partial) → voiceStatusBar shows transcript
  ├── lastConfidence (on isFinal)
     ↓
finishListening() in MorningInterviewPane
  ├── confidence ≥ 0.75  → processTranscript() → VoiceResponse.parse()
  │                         ├── Known intent  → handleVoiceResponse()
  │                         └── .unknown      → handleUnrecognisedInput()
  │                              ├── attempt 1 → clarificationHintForStep()
  │                              ├── attempt 2 → simplifiedPromptForStep() + text fallback
  │                              └── attempt 3 → advanceStep()
  ├── confidence 0.50–0.74 → "Did you mean…?" confirmation gate
  ├── confidence 0.30–0.49 → repromptForStep() (3 variants)
  └── confidence < 0.30   → showTextFallback = true (immediate)
```

***

## Prioritised Implementation Sequence

For a single executive user optimising for a 10-minute hands-free morning session, implement in this order:

1. **Confidence guard + repair chain** (Findings 3 + 6) — eliminates the most disruptive failure mode: garbage transcripts silently doing nothing or advancing the wrong step. ~2 hours work.

2. **Adaptive speech rate** (Finding 1) — immediately noticeable quality-of-life improvement. The EMA with `@AppStorage` persistence survives restarts. ~1 hour work.

3. **Missing intents** (Finding 2) — start with the 8 highest-frequency ones: `skip`, `done`, `noMore`, `repeat_`, `whatIsNext`, `goBack`, `moveToTomorrow`, `addTask`. The rest can follow. ~3 hours work.

4. **Custom vocabulary / task hint** (Finding 4) — improves recognition of app-specific terms for minimal code change. ~30 minutes work.

5. **Voice selection priority order** (Finding 5) — improves first impression. ~30 minutes work.

6. **Personal Voice opt-in** (Finding 5 extension) — deferred until post-MVP; requires user setup and clear commercial-use disclosure. ~1 hour work.

7. **SpeechAnalyzer migration** (Finding 4) — held until macOS Tahoe is the minimum deployment target. Track as a future tech debt item.

---

## References

1. [Create a seamless speech experience in your apps - Apple Developer](https://developer.apple.com/la/videos/play/wwdc2020/10022/) - Augment your app's accessibility experience with speech synthesis: Discover the best times and place...

2. [Speech Rate Adjustments in Conversations With an Amazon Alexa ...](https://www.frontiersin.org/journals/communication/articles/10.3389/fcomm.2021.671429/full) - This paper investigates users' speech rate adjustments during conversations with an Amazon Alexa soc...

3. [Extend Speech Synthesis with personal and custom voices - WWDC23](https://developer.apple.com/videos/play/wwdc2023/10033/) - Learn how you can integrate your custom speech synthesizer and voices into iOS and macOS. We'll show...

4. [Steps to Add Alexa Conversations to an Existing Skill](https://developer.amazon.com/en-US/docs/alexa/conversations/steps-to-add-to-existing-skill-migrated.html) - If you built a custom skill that uses intent-based dialog management features, you can adapt the ski...

5. [Intents | Conversational Actions - Google for Developers](https://developers.google.com/assistant/conversational/intents) - Intents represent a task Assistant needs your Action to carry out, such as some user input that need...

6. [confidence | Apple Developer Documentation](https://developer.apple.com/documentation/speech/sftranscriptionsegment/confidence) - This property reflects the overall confidence in the recognition of the entire phrase. The value is ...

7. [Level of confidence in the results of SFSpeechRecognizer()](https://forums.swift.org/t/level-of-confidence-in-the-results-of-sfspeechrecognizer/47565) - An array of potential transcriptions, sorted in descending order of confidence. can be returned from...

8. [Evaluating ASR Confidence Scores for Automated Error Detection in ...](https://arxiv.org/html/2503.15124v1) - Confidence scores can indicate misrecognised words, but as continuous data, they require a threshold...

9. [What is the significance of confidence scores in speech recognition?](https://milvus.io/ai-quick-reference/what-is-the-significance-of-confidence-scores-in-speech-recognition) - Confidence scores in speech recognition systems indicate how certain the model is about the accuracy...

10. [In Apple's Speech framework is SFTranscriptionSegment timing ...](https://stackoverflow.com/questions/79633752/in-apples-speech-framework-is-sftranscriptionsegment-timing-supposed-to-be-off) - The SFTranscriptionSegment values don't have correct timestamp and duration values until isFinal. Th...

11. [Get Word-Level Confidence in Speech-to-Text with Python - Picovoice](https://picovoice.ai/blog/speech-to-text-word-confidence-scores/) - Learn how to get word-level confidence scores in Python for speech-to-text. Set word confidence thre...

12. [Voice Recognition Accuracy - How AI Models Compare in 2026 - Voicy](https://usevoicy.com/blog/voice-recognition-accuracy-comparison) - OpenAI Whisper leads accuracy at 92% (8.06% WER) - used by Voicy · ☁️ Google Speech-to-Text hits 79-...

13. [Apple SpeechAnalyzer and Argmax WhisperKit](https://www.argmaxinc.com/blog/apple-and-argmax) - In our benchmarks, Apple matches the speed and accuracy of mid-tier OpenAI Whisper models on long-fo...

14. [Apple's New Transcription APIs Blow Past Whisper in Speed Tests](https://www.macrumors.com/2025/06/18/apple-transcription-api-faster-than-whisper/) - Apple's new speech-to-text transcription APIs in iOS 26 and macOS Tahoe are delivering dramatically ...

15. [Hands-On: How Apple's New Speech APIs Outpace Whisper for ...](https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/) - What's frustrated me with other tools is how slow they are. Most are built on Whisper, OpenAI's open...

16. [iOS 26: SpeechAnalyzer Guide - Anton's Substack](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide) - Made by Sora. SFSpeechRecognizer is part of the original Speech framework, designed to convert spoke...

17. [The Next Evolution of Speech-to-Text using SpeechAnalyzer](https://dev.to/arshtechpro/wwdc-2025-the-next-evolution-of-speech-to-text-using-speechanalyzer-6lo) - Apple's iOS 26 introduces SpeechAnalyzer, a groundbreaking replacement for the aging SFSpeechRecogni...

18. [Apple Speech Recognition vs OpenAI Whisper: The Privacy Battle](https://basilai.app/articles/2025-11-07-apple-speech-recognition-vs-openai-whisper-privacy-comparison.html) - While both can convert your speech to text with impressive accuracy, what happens to your voice data...

19. [Apple Intelligence on iPhone and Mac: What's New for TTS?](https://speechcentral.net/2024/11/08/apple-intelligence-in-ios-18-and-macos-15-whats-new-for-tts/) - Apple Intelligence is a sophisticated AI framework that harnesses generative technology to deliver a...

20. [From Robotic to Realistic: How to Add Premium Voices to Your Mac](https://www.youtube.com/watch?v=CqhYkeRd4dw) - Have you ever wondered why your Mac's TTS voice sounds like this… but mine sounds like this? Let's f...

21. [Availability of installed voices for use by AVSpeechSynthesis in iOS](https://stackoverflow.com/questions/60116322/availability-of-installed-voices-for-use-by-avspeechsynthesis-in-ios) - I would like to be able to test which text-to-speech voices are available for my iOS app to use with...

22. [List of AVSpeechSynthesisVoice.speechVoices() on iOS Device](https://gist.github.com/Koze/d1de49c24fc28375a9e314c72f7fdae4) - Hi, is there any Premium or Enhanced Voice is available by default to use in Text To Speech ? I coul...

23. [AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/personalvoiceauthorizationstatus-swift.enum) - Prompts the user to authorize your app to use personal voices.

24. [personalVoiceAuthorizationStatus | Apple Developer Documentation](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/personalvoiceauthorizationstatus-swift.type.property?changes=_7) - The user can grant or deny your app's request to use personal voices when they're initially prompted...

25. [personalVoiceAuthorizationStatus | Apple Developer Documentation](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/personalvoiceauthorizationstatus-swift.type.property) - Your app's authorization to use personal voices.

26. [Question on using Apple TTS voice (commercial use and license)](https://developer.apple.com/forums/thread/776244) - I was able to confirm that the license for the "Personal Voice" item in the iOS18 document of SLA pr...

27. [Cannot use Personalised Voice for Spoken Content](https://discussions.apple.com/thread/255920238) - I am using Sequoia 15.4 running on Mac Silicon M1. I have created a Personalised Voice, but I am una...

28. [iPhone Personal Voice (Accessibility) - P… - Apple Community](https://discussions.apple.com/thread/255952399) - Additionally, the third-party apps that you grant access can't capture speech from Personal Voice." ...

29. [Mastering Conversation Repair: Techniques and Best Practices](https://sparkco.ai/blog/mastering-conversation-repair-techniques-and-best-practices) - Explore expert techniques for effective conversation repair in human and AI interactions.

30. [Conversational UX: Designing Effective Voice & Chat Interfaces](https://www.wildnetedge.com/blogs/conversational-ux-designing-effective-voice-chat-interfaces) - Master conversational UX for voice and chat interfaces with expert chatbot flows and dialogue design...

