# Extract 02 — Digital Signal Extraction

Source: `research/perplexity-outputs/v2/v2-02-digital-signal-extraction.md`
Extracted: 2026-04-03

---

## DECISIONS

- **We will use intra-subject (personal baseline) models exclusively, never population-level models, because** the CMU 116-subject study is unambiguous: universal keystroke stress models fail cross-subject, while intra-subject models work reliably. The same pattern holds across voice biomarkers, email latency, and every other modality. Intelligence quality is architecturally a function of observation duration on *this specific human*, not model sophistication on day one.

- **We will use email metadata (never body content) as the primary Tier 1 signal because** hierarchy detection from metadata alone achieves 87.58% accuracy for dominance pair classification. Out-of-hours email frequency is the single best behavioural predictor of burnout (52,190-email, five-month study). Response latency deviation from established norms is a validated predictor of relationship deterioration and employee turnover. Metadata-only is both high-signal and privacy-preserving.

- **We will use Microsoft Graph API as the sole email/calendar data source because** it exposes sender, recipients (to/cc/bcc), timestamps (sent/received/read), subject lines, thread IDs, folder actions, flags, categories, and read receipts — the complete metadata surface needed for all email-derived signals.

- **We will use openSMILE (C++ toolkit) on CoreAudio input for voice feature extraction because** it is explicitly macOS-compatible, runs real-time, extracts the full prosodic and voice quality feature set (F0 mean/variance/contour, jitter, shimmer, HNR, spectral tilt), and is the standard toolkit used in the clinical studies that validate these signals (including Sonde Health / Mass General).

- **We will use late-fusion with cross-modal attention (Multimodal Bottleneck Transformer architecture) for multi-signal fusion because** Google's NeurIPS 2021 paper demonstrated that late-layer cross-modal attention with bottleneck tokens outperforms both early fusion and full cross-attention. This maps directly to Timed's five signal branches — each modality has its own encoder, fused through a small set of learned bottleneck tokens.

- **We will extract acoustic features only (no speech-to-text) from voice because** this is privacy-preserving, avoids transcription costs and errors, and the validated biomarkers (jitter, shimmer, F0, HNR) are all acoustic-level features. Longitudinal voice tracking from the Framingham Heart Study confirms jitter alone tracks episodic memory and cognitive decline over 10 years.

- **We will implement keystroke capture via the Accessibility API (not IOKit) because** Accessibility API provides inter-key intervals, dwell time, and flight time at the application level with user-granted permission, while IOKit requires kernel-level access that is increasingly restricted. Keystroke dynamics are the fastest signal to show cognitive load changes (sub-second resolution).

- **We will build four composite intelligence indices (CCLI, BEWI, RDS, DQEI) as the primary intelligence outputs because** no single signal has sufficient accuracy alone, but validated multi-modal composites cross the actionable threshold:
  - CCLI (Composite Cognitive Load Index): email response latency + keystroke speed + voice stress
  - BEWI (Burnout Early Warning Index): calendar fragmentation + late-night email + typing error rate
  - RDS (Relationship Deterioration Score): meeting cancellation + email avoidance of specific contacts + voice tension with those contacts
  - DQEI (Decision Quality Estimation Index): decision speed (email) + confidence markers (keystroke) + voice certainty

- **We will implement signals in three tiers, prioritised by intelligence-per-engineering-effort:**
  - Tier 1 (implement first): Email metadata (Graph API), calendar structure (Graph API), app usage (NSWorkspace)
  - Tier 2 (implement second): Keystroke dynamics (Accessibility API), basic voice features (CoreAudio + openSMILE)
  - Tier 3 (implement third): Advanced voice longitudinal tracking, full multi-modal fusion indices

---

## DATA STRUCTURES

### Signal Taxonomy Table

| Signal | Raw Source | What It Encodes | Validated Accuracy |
|--------|-----------|----------------|--------------------|
| Response latency distribution (by sender, time-of-day, thread depth) | Graph API: sent/received/read timestamps | Relationship priority, cognitive load, avoidance, decision confidence | Response latency deviation predicts turnover/relationship deterioration |
| Thread topology (depth, branching, CC additions) | Graph API: thread IDs, recipients per message | Decision-making style, escalation patterns, organisational dynamics | — |
| Communication reciprocity (initiation vs response ratio) | Graph API: sender/recipient fields | Power dynamics, influence, isolation risk | 87.58% accuracy for dominance pair classification from metadata alone |
| Send-time distribution (after-hours, weekends, circadian pattern) | Graph API: sent timestamps | Chronotype, cognitive peak times, work-life boundary erosion, burnout risk | Out-of-hours email = single best burnout predictor (52,190-email study) |
| Email volume trends (daily/weekly) | Graph API: message count + timestamps | Executive overwhelm, coping strategy (batch vs continuous) | — |
| Subject line metadata (length, question frequency, urgency markers) | Graph API: subject field | Communication urgency, decisiveness | — |
| Keystroke inter-key interval (IKI) | Accessibility API | Cognitive load (longer IKI = higher load), fatigue | Intra-subject models reliable; cross-subject models fail (CMU, n=116) |
| Keystroke dwell time + flight time | Accessibility API | Hesitation (pre-commit), motor fatigue | — |
| Backspace/error rate | Accessibility API | Decision uncertainty, cognitive interference | — |
| Typing speed (WPM rolling average) | Accessibility API | Flow state vs distraction, fatigue onset | — |
| Pause patterns (>2s gaps in typing) | Accessibility API | Deep thought vs distraction (disambiguated by app context) | — |
| F0 (pitch) mean, variance, contour | CoreAudio + openSMILE | Emotional valence, stress, confidence, engagement | ~70% population-level; higher with personal baseline |
| Jitter (F0 cycle-to-cycle variation) | CoreAudio + openSMILE | Cognitive decline, chronic stress, fatigue | Framingham Heart Study: tracks episodic memory over 10 years |
| Shimmer (amplitude variation) | CoreAudio + openSMILE | Stress, emotional regulation, vocal fatigue | — |
| Harmonics-to-noise ratio (HNR) | CoreAudio + openSMILE | Voice quality degradation under stress/fatigue | — |
| Speaking time ratio + turn-taking | CoreAudio (VAD segmentation) | Power dynamics, rapport, meeting effectiveness | — |
| Meeting density + fragmentation | Graph API: calendar events | Maker vs manager time, context-switching cost, deep work availability | 23 min average recovery from context switch (Mark et al.) |
| Cancellation + modification rate | Graph API: event modifications | Overcommitment, prioritisation failure, avoidance | — |
| Meeting composition (size, internal vs external, 1:1 vs group) | Graph API: attendees list | Leadership style, delegation, isolation risk | — |
| Calendar compression (density trend over weeks) | Graph API: event density time series | Burnout early warning, strategic drift | — |
| App usage (active app, duration, switch frequency) | NSWorkspace notifications | Attention allocation, distraction patterns, tool reliance | — |

### Feature Schema: Email Metadata

```
EmailSignalRecord {
  message_id: String           // Graph API message ID
  thread_id: String            // conversation ID
  timestamp_sent: DateTime
  timestamp_received: DateTime
  timestamp_read: DateTime?    // null if unread
  sender: ContactHash          // hashed identifier
  recipients_to: [ContactHash]
  recipients_cc: [ContactHash]
  recipients_bcc: [ContactHash]
  subject_length: Int
  subject_has_question: Bool
  subject_urgency_markers: [String]  // RE:, URGENT, FYI, etc.
  thread_depth: Int            // position in thread
  thread_participants_added: Int  // CC escalation count
  is_after_hours: Bool         // based on learned schedule
  response_latency_seconds: Int?  // null if outbound-initiated
  folder_action: String?       // moved to archive, flagged, etc.
}
```

### Feature Schema: Keystroke Dynamics

```
KeystrokeWindow {
  window_start: DateTime
  window_end: DateTime
  window_duration_ms: Int      // typically 60-second windows
  active_app: String           // which app was frontmost
  total_keystrokes: Int
  mean_iki_ms: Float           // inter-key interval
  std_iki_ms: Float
  median_iki_ms: Float
  mean_dwell_ms: Float         // key hold time
  mean_flight_ms: Float        // time between key release and next key press
  error_rate: Float            // backspace_count / total_keystrokes
  pause_count: Int             // pauses > 2000ms
  pause_total_ms: Int
  wpm: Float                   // words per minute estimate
  bigraph_latencies: [String: Float]  // top-20 bigraph mean latencies for personal calibration
}
```

### Feature Schema: Voice / Acoustic

```
VoiceSegment {
  segment_start: DateTime
  segment_end: DateTime
  duration_seconds: Float
  is_user_speaking: Bool       // VAD classification
  f0_mean_hz: Float
  f0_std_hz: Float
  f0_contour: [Float]         // sampled at 10Hz
  jitter_percent: Float        // cycle-to-cycle F0 variation
  shimmer_percent: Float       // amplitude variation
  hnr_db: Float               // harmonics-to-noise ratio
  spectral_tilt_db: Float
  speaking_rate_syllables_per_sec: Float?  // estimated from energy envelope
  energy_mean_db: Float
  energy_std_db: Float
}

ConversationDynamics {
  call_id: String
  total_duration_seconds: Float
  user_speaking_ratio: Float   // 0.0 - 1.0
  turn_count: Int
  user_interruption_count: Int
  other_interruption_count: Int
  mean_silence_gap_ms: Float
  longest_silence_gap_ms: Float
}
```

### Feature Schema: Calendar

```
CalendarDayProfile {
  date: Date
  total_events: Int
  total_meeting_minutes: Int
  longest_uninterrupted_block_minutes: Int  // "maker time"
  context_switches: Int        // transitions between meeting types
  meetings_1on1: Int
  meetings_group: Int
  meetings_external: Int
  meetings_internal: Int
  cancellations_by_user: Int
  cancellations_by_others: Int
  last_minute_changes: Int     // modified < 2hr before start
  after_hours_events: Int
  back_to_back_sequences: Int  // meetings with < 5min gap
}
```

### Feature Schema: App Usage

```
AppUsageWindow {
  window_start: DateTime
  window_end: DateTime
  active_app_bundle_id: String
  active_app_name: String
  duration_seconds: Float
  category: AppCategory        // enum: communication, productivity, browser, creative, admin, other
  switches_in_window: Int      // how many times user left and returned
}
```

### Multi-Signal Fusion Architecture

```
                    +-----------+
                    | Raw Signals|
                    +-----------+
                         |
         +-------+-------+-------+-------+
         |       |       |       |       |
     [Email] [Keystroke] [Voice] [Calendar] [App]
         |       |       |       |       |
     Encoder  Encoder  Encoder  Encoder  Encoder
     (per-modality feature extraction + personal baseline z-scoring)
         |       |       |       |       |
         +---+---+---+---+---+---+---+---+
             |               |
       [Bottleneck Tokens]   |
       (learned cross-modal  |
        attention, 4-8 tokens)|
             |               |
         +---+---+           |
         | Fusion |<----------+
         | Layer  |
         +---+---+
             |
    +--------+--------+--------+
    |        |        |        |
  [CCLI]  [BEWI]   [RDS]   [DQEI]
  Cognitive Burnout  Relationship  Decision
  Load     Warning  Deterioration Quality
```

Each encoder normalises features against the personal rolling baseline (z-score relative to 30-day mean). The fusion layer applies late cross-modal attention via bottleneck tokens. Composite indices are weighted sums of fused representations, with weights learned from the executive's own behavioural history.

---

## ALGORITHMS

### Email Signal Extraction Pipeline

1. **Ingest** — Poll Graph API `/me/messages` delta endpoint every 5 minutes. Store raw `EmailSignalRecord`.
2. **Response latency computation** — Match reply to parent via `conversationId`. Latency = `timestamp_sent(reply) - timestamp_received(parent)`. Store per-sender rolling distribution (mean, P50, P90).
3. **Norm violation detection** — For each response, compute z-score against that sender's historical latency distribution. Flag if |z| > 2.0. Track direction: positive z = delayed (avoidance/overload), negative z = unusually fast (urgency/anxiety).
4. **Network topology** — Build ego-network graph monthly. Nodes = contacts, edges = email count. Compute: degree centrality, clustering coefficient, reciprocity ratio per contact. Track month-over-month changes.
5. **Temporal pattern extraction** — Bin send-times into hourly buckets. Fit circadian model. Flag after-hours deviation from baseline. Compute weekly after-hours ratio.
6. **Thread escalation detection** — Track CC additions within threads. Flag threads where participant count increases by >2 (escalation signal).

### Keystroke Dynamics Pipeline

1. **Capture** — Register global event tap via Accessibility API (`CGEvent.tapCreate`). Capture keyDown/keyUp timestamps. Do NOT capture key values (privacy). Compute IKI, dwell, flight per keystroke.
2. **Windowing** — Aggregate into 60-second non-overlapping windows. Compute statistical moments: mean, std, median, skewness of IKI and dwell distributions per window.
3. **Baseline calibration** — First 14 days = calibration period. Compute personal baseline distributions for each feature. After calibration, all features expressed as z-scores against personal baseline.
4. **Cognitive load signal** — Mean IKI z-score + error rate z-score + pause frequency z-score. Higher = more cognitive load. Weight: IKI (0.4), error rate (0.35), pause (0.25).
5. **Bigraph calibration** — Track latencies for top-20 most frequent character bigraphs (th, he, in, er, etc.). These are the most stable personal fingerprint and the most sensitive to cognitive state changes.

### Voice Feature Extraction Pipeline

1. **Audio capture** — CoreAudio `AVAudioEngine` with input node tap. Buffer at 16kHz mono.
2. **VAD (Voice Activity Detection)** — Apple's `SFSpeechRecognizer` for segmentation only, or energy-threshold VAD. Segment audio into user-speaking vs other-speaking vs silence.
3. **Feature extraction** — Feed user-speaking segments to openSMILE (compiled as C++ library, bridged via Swift C interop). Extract eGeMAPS feature set (88 features): F0 statistics, jitter, shimmer, HNR, spectral features, energy, MFCC 1-4.
4. **Per-segment z-scoring** — Normalise all features against rolling 30-day personal baseline.
5. **Conversational dynamics** — From VAD segments: compute speaking ratio, turn count, interruptions (overlap > 200ms), silence gaps.

### Multi-Modal Fusion (Late Fusion with Bottleneck Attention)

1. **Per-modality encoding** — Each modality's z-scored features for a time window (1 hour) are passed through a small feedforward encoder (2 layers, 64-dim hidden) producing a 32-dim modality embedding.
2. **Bottleneck fusion** — 4-8 learned bottleneck tokens attend to all 5 modality embeddings via cross-attention. This forces information compression and prevents modality dominance.
3. **Composite index heads** — Four linear heads on the fused representation:
   - CCLI = weighted(email_latency_z, keystroke_iki_z, voice_f0_variance_z)
   - BEWI = weighted(calendar_fragmentation_z, after_hours_email_z, keystroke_error_rate_z)
   - RDS = weighted(contact_specific_avoidance_z, meeting_cancellation_rate_z, voice_tension_with_contact_z)
   - DQEI = weighted(decision_speed_z, keystroke_confidence_z, voice_certainty_z)
4. **Training signal** — Self-supervised from longitudinal consistency. The system never asks the executive to label their state. Instead, it uses convergent validity: if 3+ signals agree on a state change, reinforce the composite weights.

### Composite Index Computation

```
// CCLI — Composite Cognitive Load Index
ccli = 0.35 * email_response_latency_z
     + 0.30 * keystroke_iki_mean_z
     + 0.20 * voice_f0_variance_z
     + 0.15 * app_switch_frequency_z

// BEWI — Burnout Early Warning Index
bewi = 0.30 * calendar_fragmentation_z
     + 0.25 * after_hours_email_ratio_z
     + 0.20 * keystroke_error_rate_z
     + 0.15 * voice_hnr_decline_z
     + 0.10 * weekend_activity_z

// RDS — Relationship Deterioration Score (per-contact)
rds(contact) = 0.35 * response_latency_deviation_z(contact)
             + 0.25 * meeting_cancellation_rate_z(contact)
             + 0.25 * voice_tension_z(contact)
             + 0.15 * cc_escalation_frequency_z(contact)

// DQEI — Decision Quality Estimation Index
dqei = 0.30 * email_decision_speed_z
     + 0.25 * keystroke_hesitation_z  // inverse of pre-send pause duration
     + 0.25 * voice_certainty_z       // low F0 variance + high HNR
     + 0.20 * thread_resolution_speed_z
```

All z-scores are computed against the executive's own 30-day rolling baseline. Positive values indicate deviation *above* baseline (more load, more burnout risk, more deterioration, lower decision quality respectively). Alert thresholds: z > 1.5 = "notable", z > 2.0 = "significant", z > 2.5 = "critical".

---

## APIS & FRAMEWORKS

### Email + Calendar (Microsoft Graph API)

| Endpoint | Fields Used | Permission Scope |
|----------|------------|-----------------|
| `GET /me/messages` (delta) | id, conversationId, sender, toRecipients, ccRecipients, bccRecipients, subject, receivedDateTime, sentDateTime, isRead, flag, categories | `Mail.Read` |
| `GET /me/messages/{id}` | Read receipt: isReadReceiptRequested, readDateTime via extended properties | `Mail.Read` |
| `GET /me/calendarView` | subject, start, end, attendees, isOrganizer, isCancelled, type (single/recurring), importance, sensitivity | `Calendars.Read` |
| `GET /me/events` (delta) | Same + recurrence pattern, modifications | `Calendars.Read` |

- Auth: MSAL (Microsoft Authentication Library) for macOS — `@azure/msal-browser` equivalent in Swift via `MSAL.framework`
- Token refresh: MSAL handles silently. Store refresh token in Keychain.
- Rate limits: 10,000 requests per 10 minutes per app. Delta queries reduce this dramatically.

### Keystroke Capture (macOS Accessibility API)

| API | Usage | Entitlement |
|-----|-------|-------------|
| `CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)` | Global event tap for keyDown/keyUp timestamps | Accessibility permission (TCC `kTCCServiceAccessibility`) |
| `AXIsProcessTrusted()` | Check if Accessibility permission granted | None |
| `NSWorkspace.shared.frontmostApplication` | Correlate keystrokes with active app | None |

- **Permission flow:** App must be added to System Preferences > Privacy > Accessibility. Prompt user on first launch. Cannot be silently granted.
- **No App Sandbox:** Accessibility event taps are incompatible with App Sandbox. Timed must be distributed outside the Mac App Store (direct download + notarisation).
- **Privacy constraint:** Capture timestamps and inter-key intervals only. Never capture the actual key character. This is enforced in code, not just policy.

### Voice / Audio (CoreAudio + openSMILE)

| API/Library | Usage | Entitlement |
|-------------|-------|-------------|
| `AVAudioEngine` (AVFoundation) | Microphone input tap, 16kHz mono buffer | `NSMicrophoneUsageDescription` (Info.plist) + TCC `kTCCServiceMicrophone` |
| `AVAudioSession` | Configure audio routing | None |
| openSMILE 3.x (C++ library) | Extract eGeMAPS feature set (88 acoustic features) | None (linked as static library) |
| `SFSpeechRecognizer` (Speech framework) | VAD segmentation only (no transcription stored) | `NSSpeechRecognitionUsageDescription` (Info.plist) + TCC `kTCCServiceSpeechRecognition` |

- **openSMILE integration:** Compile openSMILE as static C++ library. Bridge to Swift via C interop (`-import-c-header`). Feed PCM buffers from AVAudioEngine tap. Extract features per segment.
- **macOS Sequoia (15+):** Screen recording permission now prompts monthly for reconfirmation. Microphone permission is one-time but Sequoia added a persistent menu bar indicator when mic is active. Plan UX around this.
- **No audio storage:** Extract features in real-time, discard raw audio buffers immediately. Only `VoiceSegment` feature records are persisted.

### App Usage (NSWorkspace)

| API | Usage | Entitlement |
|-----|-------|-------------|
| `NSWorkspace.shared.notificationCenter` with `didActivateApplicationNotification` | Detect app switches | None |
| `NSWorkspace.shared.frontmostApplication` | Get current active app | None |
| `NSRunningApplication.bundleIdentifier` | Categorise apps | None |

- **No special permissions required.** NSWorkspace app activation notifications are available to all macOS apps without sandboxing restrictions.
- **ScreenTime API** (`DeviceActivityReport`): Not useful — designed for parental controls, not passive observation. Requires Family Sharing context. Avoid.

### Calendar (EventKit — Local Fallback)

| API | Usage | Entitlement |
|-----|-------|-------------|
| `EKEventStore` | Read local calendar events if Graph API unavailable | `NSCalendarsUsageDescription` + TCC `kTCCServiceCalendar` |

- Primary source is Graph API. EventKit is fallback only for non-Outlook calendars.

---

## NUMBERS

### Email Metadata Signals

- **Hierarchy detection from metadata alone:** 87.58% accuracy for dominance pair classification (no body content needed)
- **After-hours email as burnout predictor:** Single best behavioural predictor in a 52,190-email, 5-month study
- **Response latency norm violation:** Validated predictor of relationship deterioration and employee turnover (effect size not reported numerically, but statistically significant in longitudinal studies)
- **Context switch recovery time:** 23 minutes average to regain full focus after interruption (Mark et al., UC Irvine)

### Keystroke Dynamics

- **Intra-subject stress detection:** Reliable with personal calibration (CMU study, n=116). Cross-subject models fail completely — accuracy drops to near-chance.
- **Minimum calibration period:** 14 days of normal typing to establish personal baseline distributions
- **Cognitive load detection:** IKI increases 15-40% under high cognitive load (effect varies by individual, hence personal baseline requirement)
- **Observation window for reliable inference:** 60-second windows minimum for stable IKI statistics; 5-minute windows for error rate

### Voice / Acoustic Features

- **Population-level cognitive impairment classification:** ~70% accuracy (Sonde Health / Mass General clinical platform)
- **Personal baseline longitudinal tracking:** Substantially higher ceiling than 70% — deviation from personal baseline is more sensitive than population norms
- **Jitter as cognitive biomarker:** Tracks episodic memory and cognitive decline over 10 years (Framingham Heart Study)
- **Minimum segment for reliable F0 extraction:** 3-5 seconds of continuous speech
- **Minimum data for personal voice baseline:** 10-15 call recordings spanning 2-3 weeks
- **eGeMAPS feature set:** 88 features extracted per segment by openSMILE

### Calendar Structure

- **Meeting fragmentation cost:** Each context switch costs ~23 minutes of recovery time
- **Calendar density threshold for burnout risk:** No validated absolute threshold — must be computed relative to personal baseline. Track week-over-week compression ratio.

### Multi-Modal Fusion

- **Late fusion (Multimodal Bottleneck Transformer) vs early fusion:** Late fusion consistently outperforms early fusion for temporal behavioural data (NeurIPS 2021)
- **Bottleneck token count:** 4-8 tokens optimal for 5-modality fusion (beyond 8 shows diminishing returns)
- **Convergent validity threshold:** Require 3+ modalities agreeing on state change before alerting (reduces false positive rate to acceptable levels for executive-facing product)

### Personal Baseline Windows

- **Email patterns:** 30-day rolling window for stable per-sender response latency distributions
- **Keystroke baseline:** 14-day calibration, then 30-day rolling
- **Voice baseline:** 2-3 weeks (10-15 recordings) for initial calibration, then 30-day rolling
- **Calendar baseline:** 4-week rolling window to account for weekly cycle variation
- **Composite indices:** All z-scores against 30-day rolling baseline; trend detection against 90-day window

---

## ANTI-PATTERNS

### Signals That Sound Useful But Lack Validation

- **Sentiment from subject lines alone:** Subject line text is too short and too formulaic for reliable sentiment analysis. The research validates subject line *metadata* (length, question marks, urgency markers) but not sentiment classification from subject text.
- **Typing rhythm as emotion classifier (population-level):** Multiple studies claim high accuracy for emotion detection from keystrokes, but these are population-level lab studies with constrained tasks. Real-world single-user cognitive load detection is validated; fine-grained emotion classification (happy/sad/angry) from keystrokes is not.
- **Meeting duration as productivity signal:** Longer meetings are not reliably worse. Duration without context (attendee count, topic type, follow-up actions) is noise.
- **App usage time as "productivity score":** Time-in-app is not a reliable proxy for productive work. A 3-hour Excel session could be deep analysis or procrastination. Use app *switching frequency* as a distraction signal instead.
- **Email volume alone as overwhelm indicator:** Volume without response latency context is ambiguous. High volume + fast responses = high capacity. High volume + increasing latency = overwhelm. Always pair with latency.

### macOS API Limitations and Sandboxing Constraints

- **App Sandbox is incompatible with keystroke capture.** `CGEvent` taps require Accessibility permission which is unavailable to sandboxed apps. Timed MUST be distributed outside the Mac App Store (developer ID + notarisation). This is a hard architectural constraint, not a workaround.
- **ScreenTime API (`DeviceActivityReport`) is useless for Timed.** It requires Family Sharing context and is designed for parental controls. It does not expose per-app duration for the current user in a format suitable for passive observation.
- **IOKit for input device monitoring is deprecated/restricted.** Don't use `IOHIDManager` for keystroke capture on modern macOS. Accessibility API is the supported path.
- **macOS Sequoia (15+) screen recording permission changes:** Screen recording permission now re-prompts monthly. This does not directly affect Timed (we don't screen-record), but be aware that if any future feature touches screen content, the UX cost is a monthly permission prompt.
- **CoreAudio microphone indicator:** macOS shows a persistent orange dot in the menu bar when the microphone is active. This is not suppressible. Design UX expectations around this — the executive will see the indicator during all calls. Frame it as "Timed is listening to how you sound, not what you say."
- **Speech recognition permission is separate from microphone permission.** If using `SFSpeechRecognizer` for VAD, both `kTCCServiceMicrophone` AND `kTCCServiceSpeechRecognition` must be granted. Consider implementing energy-threshold VAD instead to avoid the second permission.

### Privacy and Permission Gotchas

- **Accessibility permission cannot be requested programmatically.** The app can only check `AXIsProcessTrusted()` and direct the user to System Preferences. There is no system dialog — the user must manually navigate to Privacy > Accessibility and toggle the app on.
- **TCC database is read-only at runtime.** You cannot pre-populate permissions. Each permission must be explicitly granted by the user through the system UI.
- **Microphone access on first use triggers a blocking system dialog.** Plan the onboarding flow so this dialog appears in a context where the user expects it (e.g., "Let's set up voice analysis" step), not randomly during first call.
- **Keychain is the only acceptable storage for MSAL tokens.** Never store OAuth tokens in UserDefaults, plist files, or plain files. `SecKeychain` / `KeychainAccess` library only.
- **Never capture actual key characters.** Even though the Accessibility API provides them, Timed must architecturally prevent key value capture. The `CGEvent` callback should extract timestamps only and discard the `keyCode` / `characters` fields. This is a trust boundary — if the executive discovers key logging, the product is dead.
- **Email body content must never be fetched.** Even though Graph API provides it via `body` field, Timed must never request or store email bodies. Use `$select` parameter on all Graph queries to explicitly exclude body fields. This is a trust boundary, not just a preference.
