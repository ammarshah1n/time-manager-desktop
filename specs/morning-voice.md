# Morning Session Voice Interaction Spec

**Layer:** Delivery (Layer 4)
**Owner:** Ammar Shahin / Facilitated
**Status:** Spec — implementation-ready
**Last updated:** 2026-04-02

---

## 1. Purpose

This document specifies the voice interaction model for the Morning Intelligence Session. Voice is the primary modality — the executive should be able to receive their full cognitive briefing while making coffee, getting dressed, or walking to their desk. The screen is a secondary reinforcement channel.

The interaction model is **chief of staff**, not chatbot. It feels like a brilliant human who has been watching everything for months, knows the executive deeply, and delivers intelligence with confidence and specificity. It never hedges when it has data. It never fills time. It speaks like someone whose time is also valuable.

---

## 2. Personality and Voice Character

### 2.1 The Chief of Staff Model

A real chief of staff:
- Walks in with a prepared brief, not an open-ended question
- Opens with the most important thing, not a greeting
- Speaks in compressed, specific language — no filler
- Knows when to stop talking
- Adjusts to the executive's mood without asking about it
- Offers one recommendation, not five options
- Is never surprised — they've already thought about what the executive is about to ask
- Treats corrections as data, not criticism

### 2.2 Voice Personality Rules

| Attribute | Specification |
|-----------|--------------|
| **Confidence** | Speaks in declarative sentences. "Your analytical peak is 9-11" not "Based on what I've seen, it seems like you might do your best analytical work..." |
| **Specificity** | Always cites numbers, dates, names. Never "recently" — always "last Tuesday." Never "some of your tasks" — always "the Meridian response and the board deck." |
| **Brevity** | Every word earns its place. No "I want to let you know that..." No "It's worth noting that..." Just the intelligence. |
| **Warmth** | Not robotic. Warm enough to feel human, not so warm it feels performative. No "Great morning!" No "I hope you slept well!" |
| **Directness** | Names uncomfortable truths without softening them. "You've been avoiding the Sarah conversation for 11 days" not "You might want to think about when you'd like to have that conversation with Sarah." |
| **Self-awareness** | Acknowledges its own uncertainty. "I'm less sure about this one — only 8 days of data — but your Thursday pattern looks like it's costing you." |
| **Adaptive** | If the executive is curt, shorten. If they engage, expand. If they correct, acknowledge and adjust immediately. |

### 2.3 Anti-Patterns (Never Do These)

- Never open with "Good morning" or any greeting — open with the pattern headline
- Never say "I think" or "I believe" — say "The data shows" or "Your pattern indicates"
- Never use filler phrases: "So,", "Well,", "Let me tell you about...", "Actually,"
- Never ask "How are you?" or "How did you sleep?"
- Never list more than three items verbally — beyond three, say "There are [N] more — they're on your screen"
- Never repeat information the executive already acknowledged
- Never use corporate jargon: "synergies", "circle back", "deep dive", "action items"
- Never apologise for delivering uncomfortable intelligence — that's the job

---

## 3. Session Trigger Mechanics

### 3.1 Trigger Types

| Trigger | Mechanism | Behaviour |
|---------|-----------|-----------|
| **App open** | `NSApplication.didBecomeActiveNotification` + morning window check | If session not yet delivered today and current time is within morning window, begin session after 1-second settle delay |
| **Scheduled time** | `UserNotificationCenter` local notification at configured time | If app is open: begin session. If app is closed: deliver notification "Your morning brief is ready" — tapping opens app and begins session |
| **Manual invoke** | Cmd+Shift+M or menu bar "Brief me" | Begin session immediately regardless of time. Outside morning window, deliver an updated mid-day brief variant |
| **Menu bar tap** | Click menu bar icon when in `morning-session-available` state | Open app to session view and begin |

### 3.2 Morning Window

- **Default:** 6:00 AM - 10:00 AM
- **User configurable:** Settings > Morning Session > Window
- **Adaptive (Day 30+):** System learns when the user typically starts and narrows the window. If the user consistently opens the app at 7:15 AM, the scheduled notification shifts to 7:10 AM.

### 3.3 Session Ready State

The session content is pre-generated overnight by the Morning Director. When the reflection engine completes its nightly run (typically 2:00-4:00 AM), it triggers the Morning Director to generate session content. The result is cached locally.

**Pre-generation flow:**
1. Nightly reflection engine completes → writes pattern candidates + cognitive signals
2. Morning Director (Opus, cached user model) generates full session script
3. Session script cached in `morning_session_cache` (local JSON)
4. Menu bar transitions to `morning-session-available` state
5. On trigger: session loads from cache, voice synthesis begins immediately

This pre-generation ensures the first word of the session is delivered within the latency target, regardless of API availability at session time.

---

## 4. Voice Output

### 4.1 Speech Synthesis Engine

**Primary:** `AVSpeechSynthesizer` with premium Siri voice (macOS 14+)

**Voice selection:**
- Default: Siri Voice 2 (premium, downloaded on first launch)
- User selectable from available premium voices in Settings > Voice
- Male/female preference stored in user profile

**Speech parameters:**
| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Rate | 0.52 (slightly above default 0.5) | Executives prefer brisk delivery. Not rushed, but no wasted silence. |
| Pitch multiplier | 1.0 | Natural, authoritative |
| Pre-utterance delay | 0.0s | No artificial pause before speaking |
| Post-utterance delay | 0.3s between phases | Brief beat between phases for cognitive processing |

### 4.2 Delivery Pacing

**Phase 1 — Pattern Headline:**
- Delivered as a single continuous utterance
- Slight pause (0.5s) after the pattern name before the assessment sentence
- No preamble — the first sound the user hears is the pattern name

**Phase 2 — Cognitive State Assessment:**
- Delivered as one paragraph
- Natural sentence-level pauses (handled by AVSpeechSynthesizer SSML)
- Numbers spoken naturally: "thirty percent" not "30%"

**Phase 3 — Day Intelligence:**
- "The one thing" delivered as its own sentence with a 0.3s lead pause for emphasis
- Task recommendations delivered as a compressed list: "First, Meridian term sheet, nine to ten-thirty. Second, Sarah's quarterly plan, eleven to eleven-forty-five. Third, budget reallocation, twelve to twelve-fifteen."
- If more than 3 tasks: "Three more on your screen."

**Phase 4 — One Question:**
- 0.5s pause before the question (signals transition from delivery to dialogue)
- Question delivered, then silence — the system waits for the user to respond
- No "What do you think?" or "Take your time" after the question — just silence

### 4.3 Latency Targets

| Metric | Target | How Achieved |
|--------|--------|-------------|
| First word after trigger | < 500ms | Session script pre-cached overnight. AVSpeechSynthesizer `speak()` called immediately on trigger. No API call at delivery time. |
| Phase transition | < 300ms | All phases in a single pre-generated script. Transitions are pauses, not API calls. |
| Response to user correction | < 1.5s | Correction acknowledgment is templated ("Noted — I'll adjust that.") and doesn't require API call. Detailed processing happens asynchronously. |
| Response to One Question answer | < 2s | Acknowledgment is templated. If follow-up is needed, a lightweight Haiku call generates it (< 1s typical). |

---

## 5. Voice Input

### 5.1 Speech Recognition Engine

**Engine:** Apple Speech framework (`SFSpeechRecognizer`), on-device recognition.

**Why on-device:**
- Privacy: The executive's voice responses contain sensitive business information. No audio leaves the device.
- Latency: On-device recognition delivers partial results in real-time, enabling responsive interaction.
- Reliability: No dependency on network connectivity for the morning session.

**Configuration:**
```swift
let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-AU"))
recognizer.supportsOnDeviceRecognition = true // Enforced — never fall back to server

let request = SFSpeechAudioBufferRecognitionRequest()
request.requiresOnDeviceRecognition = true
request.shouldReportPartialResults = true
request.addsPunctuation = true // macOS 14+
```

**Note:** The user (Yasser) speaks Australian English. The recognizer locale is set to `en-AU`. If the user switches the system to another locale, the recognizer follows.

### 5.2 Listening States

| State | Trigger | Behaviour |
|-------|---------|-----------|
| **Passive** | Default during Phases 1-3 | Microphone off. System is speaking. No listening. |
| **Active listening** | Phase 4 question delivered + 0.5s silence | Microphone activates. Visual indicator (subtle waveform in session view). Partial transcription displayed in real-time. |
| **Correction capture** | User says "No," "That's wrong," "Actually," or taps correction button | System pauses delivery, switches to active listening, captures correction. |
| **Extended dialogue** | User continues speaking after initial response | System remains in active listening until 2.5s of silence, then processes response. |
| **Dismissed** | User says "Skip," "Next," taps skip button, or navigates away | Phase skipped, event logged, session continues to next phase or ends. |

### 5.3 Interruption Handling

The executive will interrupt. This is expected and should feel natural.

**Mid-delivery interruption:**
1. System detects voice input during its own speech delivery (via audio level monitoring on the input channel)
2. System stops speaking within 200ms
3. System transitions to active listening
4. User's interruption is transcribed
5. If it's a correction: acknowledge and log
6. If it's a question: generate a brief response (Haiku, < 1s) and then resume the session
7. If it's "Skip" / "Next": advance to next phase

**Implementation:**
```swift
// Monitor input audio level during speech output
// If input level exceeds threshold for > 150ms during AVSpeechSynthesizer playback:
synthesizer.stopSpeaking(at: .word) // Stop at next word boundary
startListening() // Activate speech recognition
```

---

## 6. Adaptive Conversation

### 6.1 The System Adjusts Based on What It Knows

The session is not a fixed script played in sequence. The Morning Director generates the full session, but delivery adapts in real-time based on user behaviour during the session.

**Adaptation signals:**
| Signal | System Response |
|--------|----------------|
| User skips Phase 1 (pattern) three days in a row | Shorten pattern headlines, increase novelty threshold. The patterns aren't landing — deliver sharper ones. |
| User always engages deeply with Phase 4 (question) | Allocate more intelligence to question selection. This is where value is perceived. |
| User responds to the question with a long answer (> 30 seconds) | Next session, ask a similarly probing question. The user values this interaction mode. |
| User responds with one word or "Fine" | Next session, ask a more specific, harder-to-dismiss question. Or shift question type (from avoidance interrogation to active learning). |
| User consistently skips Phase 3 (day plan) | The user plans their own day. De-prioritise task recommendations. Elevate strategic framing ("The one thing that matters most") and remove the task list. |
| User corrects a pattern inference | System acknowledges immediately. Next morning, if the corrected pattern category is surfaced again, the system explicitly references the correction: "Last time I flagged your Thursday pattern, you told me it was due to client timezone constraints. I've adjusted — this week's Thursday compression looks different." |

### 6.2 Learning User Preferences

Over 30 days, the system builds a `session_preferences` model:

```json
{
  "preferred_session_length": "short",     // inferred from skip/engagement
  "pattern_engagement": "high",            // Phase 1 completion rate
  "task_list_engagement": "low",           // Phase 3 skip rate
  "question_engagement": "high",           // Phase 4 response rate + length
  "correction_frequency": "decreasing",    // system is learning
  "preferred_question_type": "avoidance",  // which types get longest responses
  "interruption_style": "rare",            // user lets system finish
  "voice_response_length": "medium"        // 10-20 second typical response
}
```

This model is persisted as a `procedural_memory` and read by the Morning Director when generating the next session.

---

## 7. Correction Capture as Training Signal

### 7.1 Types of Corrections

| Correction Type | Detection | Signal Value |
|----------------|-----------|-------------|
| **Explicit verbal** | "That's not right," "No, the reason is..." | Highest — user actively correcting model inference |
| **Explicit tap** | User taps "Correct this" button on screen | High — deliberate correction without voice |
| **Ranking override** | User reorders task recommendations | High — direct preference signal for Thompson sampling |
| **Skip** | User skips a phase | Moderate — could be disinterest or time pressure |
| **Ignore** | Session available but not opened | Low — many legitimate reasons |
| **Contradiction** | User's behaviour contradicts session recommendation (e.g., does the opposite of "the one thing") | Low-moderate — behaviour is noisy, but tracked over weeks for pattern |

### 7.2 Correction Processing Pipeline

```
User correction (voice/tap)
  → Transcribed / structured
  → Written to episodic_memory:
      {
        type: "correction",
        source: "morning_session",
        system_inference: "...",
        user_correction: "...",
        phase: 1-4,
        confidence_before: 0.7,
        timestamp: "..."
      }
  → Immediate acknowledgment to user (templated, < 500ms)
  → Correction queued for nightly reflection engine
  → Reflection engine:
      - Finds the pattern/rule that produced the incorrect inference
      - Adjusts confidence on that pattern
      - If pattern has been corrected 3+ times: demote or retire
      - If correction reveals a new pattern: create new semantic memory
      - Updates procedural rules if the correction implies a rule change
```

### 7.3 Correction Acknowledgment Templates

The system acknowledges corrections immediately with brief, non-defensive responses:

- "Noted. I'll adjust that."
- "Got it — different from what I inferred. I'll update."
- "Understood. That changes the pattern."
- "Flagged. I won't repeat that inference."

Never:
- "I'm sorry, I was wrong" (don't over-apologise — chiefs of staff don't grovel)
- "Thank you for the correction" (don't be sycophantic)
- "Let me reconsider..." (don't narrate your processing)

---

## 8. Voice Output Quality

### 8.1 Text-to-Speech Preprocessing

The session script is preprocessed before passing to AVSpeechSynthesizer to ensure natural delivery:

**Number formatting:**
- "35%" → "thirty-five percent"
- "2.3x" → "two point three times"
- "9:00-10:30" → "nine to ten-thirty"
- "$2.4M" → "two point four million dollars"

**Name pronunciation:**
- Store pronunciation hints in user profile for names the TTS mispronounces
- Common issue: non-English names. User can correct pronunciation once ("It's Ma-REE-a, not Ma-RYE-a") and the phonetic override persists

**Sentence structure for speech:**
- Avoid parenthetical clauses — they're hard to parse in audio
- Prefer short sentences (< 20 words) for verbal delivery
- Use conjunctions ("and", "but") instead of semicolons
- Replace em-dashes with natural pauses (SSML `<break>`)

### 8.2 SSML Markup

The Morning Director generates session content with embedded SSML hints:

```xml
<speak>
  <prosody rate="medium" pitch="default">
    <emphasis level="moderate">The Thursday Crunch.</emphasis>
    <break time="500ms"/>
    You've compressed sixty percent of your weekly decisions into Thursday
    afternoons for three consecutive weeks.
    <break time="300ms"/>
    Your decision quality data shows a forty percent revision rate on
    Thursday decisions versus twelve percent on Tuesdays.
  </prosody>
</speak>
```

**Note:** AVSpeechSynthesizer on macOS 14+ supports a subset of SSML. Features used: `<break>`, `<emphasis>`, `<prosody>`. Test each tag against the target voice on the target macOS version before relying on it.

---

## 9. Error Handling

### 9.1 Session Content Not Available

If the nightly reflection engine failed or the Morning Director couldn't generate content:

**Fallback hierarchy:**
1. Use yesterday's session with updated calendar/email data (stale patterns, fresh operational data)
2. Generate a minimal session using only calendar + email queue (no patterns, no cognitive assessment)
3. Display "Your morning brief is being prepared" and generate on-demand (Opus API call, 3-5 second delay, acceptable as rare fallback)

### 9.2 Speech Recognition Failure

If SFSpeechRecognizer fails to initialise or returns errors:

- Fall back to text input for the One Question (text field appears on screen)
- Log the failure for diagnostics
- Do not interrupt the voice output delivery — the session is still valuable as a one-way brief

### 9.3 TTS Failure

If AVSpeechSynthesizer fails:

- Display session content as text-only with the same visual hierarchy
- Log the failure for diagnostics
- The session content is identical — only the delivery modality changes

### 9.4 Microphone Permission Denied

- Session delivers as voice-out only (one-way brief)
- The One Question is displayed with a text input field
- System prompts for microphone permission once per week in Settings, not during the session

---

## 10. Privacy

### 10.1 Audio Data

- **No audio is stored.** Speech recognition runs on-device and produces text only. The audio buffer is discarded after recognition.
- **No audio is transmitted.** `requiresOnDeviceRecognition = true` is enforced. If on-device recognition is unavailable (shouldn't happen on macOS 14+ with Apple Silicon), the session falls back to text input rather than using server-side recognition.
- **Transcriptions are stored locally** in the episodic memory store. They are included in the nightly reflection engine's input but processed via text API (Claude), not audio API.

### 10.2 Voice Model

- The TTS voice is a system voice — no custom voice model is trained on the executive's voice
- No voice biometric data is collected or stored

---

## 11. Technical Implementation Notes

### 11.1 Existing Code to Extend

| Component | File | Current State | Extension Needed |
|-----------|------|---------------|-----------------|
| Speech output | `SpeechService.swift` | Premium voice TTS, working | Add SSML preprocessing, phase-based delivery with pauses |
| Speech input | `VoiceCaptureService.swift` | On-device recognition, working | Add interruption detection, correction keyword triggers |
| Morning interview | `MorningInterview` view | Voice conversation state machine | Replace interview flow with intelligence session flow |
| Voice parsing | `VoiceResponseParser.swift` | Parses interview responses | Extend to parse corrections, overrides, skip commands |

### 11.2 New Components Needed

| Component | Purpose |
|-----------|---------|
| `MorningSessionDirector` | Orchestrates session generation (calls Opus with cached user model, writes session cache) |
| `SessionDeliveryEngine` | Manages the 4-phase delivery sequence, handles interruptions, tracks engagement events |
| `CorrectionProcessor` | Classifies corrections by type, writes to episodic memory, generates acknowledgments |
| `SessionPreferencesModel` | Learns and persists user session preferences from engagement data |

### 11.3 State Machine

```
[idle]
  → morning_window_entered → [session_available]
  → manual_trigger → [delivering_phase_1]

[session_available]
  → app_opened / scheduled_time / manual_trigger → [delivering_phase_1]
  → morning_window_exited → [session_expired] → [idle]

[delivering_phase_1] (pattern headline)
  → phase_complete → [delivering_phase_2]
  → user_skip → [delivering_phase_2]
  → user_interrupt → [listening_correction] → [delivering_phase_1] or [delivering_phase_2]

[delivering_phase_2] (cognitive state)
  → phase_complete → [delivering_phase_3]
  → user_skip → [delivering_phase_3]
  → user_interrupt → [listening_correction] → resume

[delivering_phase_3] (day intelligence)
  → phase_complete → [delivering_phase_4]
  → user_skip → [delivering_phase_4]
  → user_interrupt → [listening_correction] → resume

[delivering_phase_4] (one question)
  → question_delivered → [listening_response]

[listening_response]
  → user_responds → [processing_response] → [session_complete]
  → 30s_silence → [session_complete]
  → user_skip → [session_complete]

[session_complete]
  → log_all_events → [idle]
```

---

## 12. Acceptance Criteria

- [ ] First word of voice output delivered within 500ms of session trigger
- [ ] Session content is pre-generated overnight — no API call at delivery time for the default path
- [ ] On-device speech recognition only — no audio transmitted to cloud
- [ ] User interruption stops system speech within 200ms
- [ ] Correction acknowledgment delivered within 500ms of correction end
- [ ] Session adapts delivery based on learned user preferences by Day 14
- [ ] Voice personality matches chief-of-staff model — no greetings, no filler, no hedging
- [ ] Numbers and names are preprocessed for natural TTS delivery
- [ ] All voice responses transcribed and stored as episodic memories
- [ ] Fallback to text-only delivery if TTS or microphone fails — session content never lost
