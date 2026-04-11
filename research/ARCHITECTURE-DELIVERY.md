# ARCHITECTURE-DELIVERY.md — Delivery, Experience & Strategy Layer

Definitive specification for how Timed delivers intelligence, earns trust, handles privacy, implements on macOS, and goes to market. Synthesised from extracts 05, 06, 09, 11, 12, 13, 14.

Where sources conflict, a resolution is stated with rationale.

---

## 1. Morning Briefing Design

### 7-Section Structure

The morning briefing follows CIA PDB design principles: lead with the lead, compress ruthlessly, and never bury the conclusion. Every section is a single cognitive chunk (Cowan's 3-5 limit for complex information, not Miller's 7).

| Section | Content | Rationale |
|---------|---------|-----------|
| 1. Lead Insight (BLUF) | Single highest-salience, highest-confidence item. The one thing the executive must know before anything else. | Primacy effect: first-position items receive disproportionate encoding and retention. CIA PDB always opens with the lead item. |
| 2. Calendar Intelligence | What today's schedule reveals: meeting load, back-to-back risk, decision density, deep-work availability. | Immediately actionable. The executive can restructure their day within minutes of reading this. |
| 3. Email Pattern Analysis | Overnight shifts, unanswered threads reaching critical age, relationship signals, response latency anomalies. | Surfaces invisible dynamics. "Your CFO emails take 3x longer to reply to than average" is the kind of observation that earns trust. |
| 4. Decision Quality Observations | Patterns from yesterday's decisions worth noticing. Optional — omit if nothing notable. | Connects today's awareness to yesterday's behaviour. Feedforward framing (Goldsmith): focus on what to do differently, not what went wrong. |
| 5. Cognitive Load Forecast | Predicted energy curve for today based on schedule + recent keystroke/behaviour signals + chronotype model. | Enables preventive action. "Your highest-quality work output happens between 6-8am. You've scheduled your most important meeting at 3pm." |
| 6. Emerging Patterns | Multi-day or multi-week trends: relationship dynamics, avoidance patterns, recurring friction. 0-2 items. | This is where compounding intelligence lives. Month-6 briefings will have patterns month-1 briefings cannot. |
| 7. Recency Anchor | One forward-looking observation or question to carry into the day. | Recency effect ensures this persists in working memory. A question is more powerful than a statement here — it travels with the executive. |

### Information Density Limits

- **Total word count:** ~610 words. Hard cap 800.
- **Distinct insights:** 5-7, each compressed to 1-2 sentences + one supporting data point.
- **Cognitive chunks:** 3-5 per briefing (Cowan's limit).
- **Novelty ratio:** ~60-70% novel information, 30-40% contextualising (connecting to known patterns). Above 70% novel = overwhelming. Below 50% novel = stale.
- **Confidence language:** ICD 203 standard — numeric probability with verbal anchor ("likely, ~70%") produces 66% comprehension vs 32% for verbal-only.

### Routing Matrix (What Goes Where)

| Criticality | Reliability | Destination |
|-------------|-------------|-------------|
| High | High | Morning brief lead (Section 1) |
| High | Moderate | Morning brief body with explicit confidence language |
| Low | High | Weekly synthesis or on-demand drill-down |
| Low | Moderate | Suppress entirely until pattern strengthens |

Items that are important-but-not-urgent route to the weekly synthesis. Granular supporting data is available on drill-down, never in the brief itself.

### Coaching Integration in Briefing

Sections 4 and 6 are the coaching touchpoints. They follow extract-06's five framing principles:

1. **Data-first, interpretation-second.** Present the observable pattern before offering meaning.
2. **Feedforward, not feedback.** Frame observations as opportunities, not diagnoses.
3. **Curiosity framing.** "I notice X — does that match your experience?" not "You do X."
4. **One challenging insight per briefing.** Never stack multiple uncomfortable observations.
5. **Anchor to stated goals.** Every observation connects to something the executive said they care about.

### Data Structure

```swift
struct MorningBriefing {
    let date: Date
    let generatedAt: Date

    // Section 1 — BLUF (primacy position)
    let leadInsight: BriefingItem

    // Sections 2-6 — Body
    let calendarIntelligence: BriefingItem
    let emailPatterns: BriefingItem
    let decisionObservations: BriefingItem?      // Optional — omit if nothing notable
    let cognitiveLoadForecast: BriefingItem
    let emergingPatterns: [BriefingItem]          // 0-2 items

    // Section 7 — Recency anchor
    let forwardLookingObservation: BriefingItem

    let totalWordCount: Int                       // Target ~610, hard cap 800
    let confidenceProfile: BriefingConfidence
}

struct BriefingItem {
    let insight: String                           // 1-2 sentences, BLUF format
    let supportingData: String?                   // One data point max
    let confidence: ConfidenceLevel               // .high or .moderate only
    let category: InsightCategory
    let sourceSignals: [SignalReference]
}

enum ConfidenceLevel: String, Codable {
    case high       // No hedging needed
    case moderate   // Include probability language ("likely, ~70%")
    case low        // NEVER in morning brief — hold for strengthening
}

struct BriefingConfidence {
    let overallConfidence: Double                 // Weighted average across items
    let noveltyRatio: Double                      // Target 0.60-0.70
}
```

### Generation Pipeline

Morning brief generation runs via Sonnet at ~5-10s latency. Context assembly:
1. Last 7 daily syntheses (recency)
2. Current cognitive model state
3. Today's calendar + overnight email metadata
4. Any active/pending insights from the insights table
5. Top-5 semantically similar past briefings (for pattern continuity)

Generated by Supabase Edge Function triggered at executive's configured wake time (default 6:30 AM local). Cached locally for instant display when the executive opens the morning session.

---

## 2. Real-Time Alert System

### Alert Threshold Logic (5-Dimension Scoring)

Every candidate alert is scored on five dimensions, each 0.0-1.0:

| Dimension | Definition |
|-----------|------------|
| **Salience** | How important is this to the executive's goals? |
| **Confidence** | How certain is the system about this observation? |
| **Time-sensitivity** | How much value is lost per hour of delay? |
| **Actionability** | Can the executive do something about this right now? |
| **Cognitive state permit** | Is the executive in a state to receive this? (inferred from app usage, keystroke dynamics, calendar context) |

**Scoring is multiplicative, not additive.** Any zero dimension kills the alert. This prevents high-salience but unactionable items from interrupting.

```swift
struct AlertCandidate {
    let insight: String
    let category: InsightCategory

    let salience: Double
    let confidence: Double
    let timeSensitivity: Double
    let actionability: Double
    let cognitiveStatePermit: Double

    var compositeScore: Double {
        salience * confidence * timeSensitivity * actionability * cognitiveStatePermit
    }

    static let interruptThreshold: Double = 0.5
    static let holdThreshold: Double = 0.2
    // Between hold and interrupt → queue for next scheduled delivery
}
```

### Frequency Management

- **Hard cap:** 3 real-time alerts per day. Target 0-1 on most days.
- **Minimum inter-alert gap:** 60 minutes.
- **Actionability rate target:** >80% across a rolling 20-alert window. If actionability drops below 60%, the system dynamically raises the interrupt threshold by 30%.
- **Recovery cost:** Every interruption costs ~23 minutes 15 seconds of productive capacity (Gloria Mark, UC Irvine). Only interrupt when insight value exceeds this cost.

```swift
struct AlertFrequencyState {
    let alertsToday: Int                    // Hard cap: 3
    let lastAlertTime: Date?
    let minimumInterAlertGap: TimeInterval  // 60 minutes

    var canAlert: Bool {
        alertsToday < 3 &&
        (lastAlertTime == nil || Date().timeIntervalSince(lastAlertTime!) > minimumInterAlertGap)
    }
}
```

### Decision Algorithm

```swift
func shouldDeliverAlert(
    _ candidate: AlertCandidate,
    state: AlertFrequencyState,
    history: [AlertOutcome]
) -> AlertDecision {
    // Gate 1: Hard frequency cap
    guard state.canAlert else { return .queueForBriefing }

    // Gate 2: Composite score threshold
    guard candidate.compositeScore > AlertCandidate.interruptThreshold else {
        return candidate.compositeScore > AlertCandidate.holdThreshold
            ? .queueForBriefing
            : .discard
    }

    // Gate 3: Historical actionability rate
    let recentActionabilityRate = history.suffix(20).actionabilityRate
    if recentActionabilityRate < 0.6 {
        let adjustedThreshold = AlertCandidate.interruptThreshold * 1.3
        guard candidate.compositeScore > adjustedThreshold else {
            return .queueForBriefing
        }
    }

    // Gate 4: Cognitive state window
    guard candidate.cognitiveStatePermit > 0.6 else { return .deferUntilWindow }

    return .deliverNow
}
```

### Interrupt Window Detection

```swift
struct InterruptWindowDetector {
    // Low-cost signals (window open)
    let taskTransitionDetected: Bool        // App switch, document close
    let postMeetingGap: Bool                // 2-3 min after calendar event ends
    let applicationIdle: TimeInterval       // No input for >60s
    let betweenDeepWorkBlocks: Bool

    // High-cost signals (window closed)
    let inDeepWork: Bool                    // Sustained single-app focus >15 min
    let inMeeting: Bool                     // Calendar event active
    let backToBackMeetings: Bool
    let recentInterrupt: Bool               // Alert delivered <60 min ago

    var windowOpen: Bool {
        let hasOpen = taskTransitionDetected || postMeetingGap
            || applicationIdle > 60 || betweenDeepWorkBlocks
        let hasBlock = inDeepWork || inMeeting || backToBackMeetings || recentInterrupt
        return hasOpen && !hasBlock
    }
}
```

### Alert Content Constraints

- Single insight, 1-2 sentences max.
- One actionable observation.
- Zero context that is not immediately necessary.
- Format: text notification in menu bar. Voice delivery only for alerts scored above 0.8 composite AND the executive has explicitly opted into voice alerts.

---

## 3. Voice Interaction Design

### Three Delivery Modes

**Conflict resolution:** Extract-05 defines voice modes broadly; extract-09 provides precise parameters. Extract-09's parameterised specification takes precedence for implementation. Extract-05's Motivational Interviewing architecture governs framing and emotional scaffolding.

| Dimension | Routine Briefing | Uncomfortable Insight | Real-Time Alert |
|-----------|-----------------|----------------------|-----------------|
| **Pace** | 140-150 wpm, natural rhythm | 110-120 wpm, deliberate slowing | 160+ wpm (urgent) / 140 (important-not-urgent) |
| **Pitch** | Mid-range, moderate variation | Lower pitch, narrow range (gravitas) | Slightly elevated to signal salience |
| **Terminal intonation** | Falling (statements of fact) | Rising on interpretive claims; falling on data-backed | Falling (directive clarity) |
| **Confidence calibration** | High for data-backed; hedged for interpretive | Always hedged: "The data suggests..." | High confidence, no hedging |
| **Framing** | Direct: "Your calendar shows..." | Questions first: "Have you noticed..." | Declarative: "Your 2pm was just cancelled." |
| **Permission** | Not needed | Always ask before self-concept-threatening content | Not needed for time-sensitive |
| **Pauses** | 500ms between topics | 1-2s after key points — let it land | Minimal. Deliver and stop. |
| **Channel** | Voice (optimal) | Voice for moderate; TEXT for very negative | Voice for urgent; text for non-urgent |
| **Length** | 2-5 min for morning session | Single insight only. Never stack negatives. | 1-2 sentences max |

### TTS System Selection

**Primary (online):** OpenAI TTS or ElevenLabs for professional-grade output. Lower pitch range, measured pace (~140-150 wpm), minimal vocal fry, no uptalk. Formal-conversational hybrid.

**Fallback / offline / alerts:** Apple AVSpeechSynthesizer. Zero latency, no network dependency, privacy-preserving.

**Conflict resolution:** Extract-05 recommends AVSpeechSynthesizer as the primary TTS. Extract-09 recommends OpenAI TTS / ElevenLabs as primary with AVSpeechSynthesizer as fallback. **Decision: extract-09 takes precedence.** Rationale: AVSpeechSynthesizer has limited prosody control (per-utterance, not per-word, no SSML) and sits at the edge of the uncanny valley for sustained 2-5 minute briefings. For the morning session (the highest-stakes delivery moment), cloud TTS quality justifies the network dependency. AVSpeechSynthesizer serves as the offline fallback and is primary for short alerts where latency matters more than naturalness.

### Trust-Building Prosody (AVSpeechSynthesizer Offline Parameters)

When delivering via AVSpeechSynthesizer (offline mode, alerts, fallback):

| Parameter | Standard Delivery | Uncomfortable Insight |
|-----------|------------------|----------------------|
| `AVSpeechUtterance.rate` | 0.50 (default) | 0.42-0.45 |
| `AVSpeechUtterance.pitchMultiplier` | 1.0 | 0.95-0.98 |
| `AVSpeechUtterance.preUtteranceDelay` | 0s | 0.3-0.5s before key observations |
| `AVSpeechUtterance.postUtteranceDelay` | 0.3s | 1.0-2.0s after uncomfortable observations |
| Voice quality | `.premium` (Siri neural voices) | `.premium` |

Break complex deliveries into multiple `AVSpeechUtterance` instances with varying parameters per segment. SSML is not supported natively.

### Uncomfortable Insight Delivery (Motivational Interviewing Protocol)

Five-stage disclosure architecture, derived from Miller & Rollnick's Motivational Interviewing:

1. **Establish context.** Reference something the executive already knows. "You mentioned your board prep feels rushed."
2. **Affirm competence.** Acknowledge what they are doing well in the relevant domain. "You shifted your Monday scheduling last month — that took one conversation with your EA."
3. **Present observation as data, not judgment.** "I notice your prep time has decreased 40% this quarter" — not "You're not preparing enough."
4. **Invite interpretation.** "What do you make of that?" — provide the scaffolding, not the verdict.
5. **Let them reach the conclusion.** Executives who reach their own conclusions show higher behaviour change than those who are told what to do.

**Three-mode conversational repair** when delivery triggers defensiveness:

1. **Acknowledge mode:** Validate the pushback without retracting. "That's a fair read."
2. **Reframe mode:** Present the same data from a different angle.
3. **Defer mode:** "I'll hold this and bring it back when there's more data." Preserves trust, avoids entrenchment.

### Text vs Voice Selection Logic

**Decision (extract-09):** For very negative, self-concept-threatening insights, text outperforms voice. The absence of social presence cues reduces defensive reactions.

```
if insight.threatLevel == .selfConceptThreatening {
    deliver via text (never voice)
} else if insight.threatLevel == .moderatelyDiscomforting {
    deliver via voice with uncomfortable-insight prosody
} else {
    deliver via standard voice
}
```

Always ask permission before delivering self-concept-threatening observations regardless of channel.

### Voice Language Rules

| USE | NEVER USE (too human) | NEVER USE (too clinical) |
|-----|----------------------|--------------------------|
| "I notice..." | "I feel..." | "The algorithm detected..." |
| "I observe..." | "I'm worried..." | "The data indicates..." |
| "I've been tracking..." | "I care..." | "Analysis shows..." |
| "The pattern suggests..." | "I believe..." | "Statistical evidence..." |

Timed speaks in first person. It claims perception and pattern recognition. It never claims emotions. It never distances behind clinical framing.

---

## 4. Coaching Intelligence Layer

### Automation Feasibility Matrix

| Coaching Function | Feasibility | Signal Source | Confidence Timeline |
|---|---|---|---|
| Communication pattern tracking | **Full** | Email metadata (timestamps, recipients, lengths, frequency), keystroke dynamics | 30-60 days |
| Calendar/priority alignment | **Full** | Calendar events + categories, voice-stated priorities | 60 days |
| Energy/engagement mapping | **Full** | App usage, keystroke velocity/error rates, time-of-day productivity | 45-60 days |
| Temporal pattern detection | **Full** | All timestamped metadata | 30 days |
| Avoidance pattern detection | **Partial** | Email non-response patterns, calendar rescheduling, document dwell time | 90+ days |
| Decision pattern analysis | **Partial** | Email chain analysis, calendar sequences, delegation patterns | 90-120 days |
| Relationship dynamics | **Partial** | Email metadata + calendar co-attendance over time | 120+ days |
| Self-awareness gap detection | **Partial** | Voice self-reports cross-referenced against observed patterns | 90+ days |
| 360-degree feedback | **Impossible** | Requires human interviews | N/A |
| Embodied co-presence | **Impossible** | Requires physical co-presence | N/A |
| Vulnerability facilitation | **Impossible** | Requires human witness | N/A |
| Accountability with social weight | **Impossible** | Requires genuine human relationship | N/A |

### Trust Calibration Stages

Based on Bordin's working alliance model + Prochaska's Transtheoretical Model:

**Stage 1: Establishment (Days 1-30)**
- Deliver only positive/neutral observations: energy patterns, temporal rhythms, productivity insights.
- Insight intensity: 2/10. No challenging observations.
- Goal: demonstrate accuracy. Every observation must be verifiably true when the executive checks.
- Advance signal: executive voluntarily engages with an insight (asks follow-up, references it later).
- Maps to Insight Sequencing Level 0 (Accuracy Foundation): 10+ verifiably accurate observations, 5+ confirmed by executive, zero false positives in last 7 days.

**Stage 2: Calibration (Days 30-90)**
- Introduce mild discrepancy observations: stated vs actual priority allocation, communication frequency patterns.
- Insight intensity: 4/10. Surprises but does not threaten self-concept.
- Frame everything as curiosity: "I notice X — is that intentional?"
- Advance signal: executive acknowledges a pattern they had not noticed, without defensiveness.
- Maps to Insight Sequencing Levels 1-2 (Pattern Recognition, Mild Discrepancy).

**Stage 3: Working Alliance (Days 90-180)**
- Surface avoidance patterns, relationship asymmetries, decision rigidity.
- Insight intensity: 6/10. Challenges self-perception.
- Always connect to executive's stated goals.
- Advance signal: executive modifies behaviour in response to an observation.
- Maps to Insight Sequencing Level 3 (Self-Concept Challenge).

**Stage 4: Deep Observation (Days 180+)**
- Full pattern surfacing: defence mechanism signatures, blind spots, energy-decision quality correlations.
- Insight intensity: 8/10. Can surface uncomfortable truths.
- Never reach 10/10 — always leave room for the executive to dismiss without feeling the system is insistent.
- Maps to Insight Sequencing Level 4 (Deep Pattern): 180+ day relationship, validated cognitive model with <15% false positive rate.

**Rupture Protocol:** If the executive dismisses 3+ consecutive observations or explicitly expresses frustration, drop back one stage immediately. Acknowledge: "I may be reading this pattern wrong. I'll keep watching and come back to it only if the data becomes clearer."

### Insight Sequencing (Pre-Requisite Chain)

Each level requires the previous level to be established. NEVER skip a level.

```
Level 0: ACCURACY FOUNDATION
  - 10+ verifiably accurate observations delivered
  - 5+ confirmed by executive
  - Zero false positives in last 7 days

Level 1: PATTERN RECOGNITION
  - 3+ temporal/energy patterns confirmed
  - Executive referenced a Timed observation unprompted
  → Unlocks: "you didn't know this about yourself" observations

Level 2: MILD DISCREPANCY
  - 2+ stated-vs-actual misalignments surfaced
  - Constructive engagement (questions, not defensiveness)
  → Unlocks: avoidance patterns, relationship asymmetries

Level 3: SELF-CONCEPT CHALLENGE
  - 1+ avoidance pattern acknowledged
  - Behaviour modified in response to at least 1 observation
  → Unlocks: defence mechanism observations, deep blind spots

Level 4: DEEP PATTERN (Stage 4 only, 180+ days)
  - Validated cognitive model with <15% false positive rate
  → Unlocks: decision rigidity, unconscious bias patterns, leadership blind spots
```

### Observation Priority Framework

Ranked by detection feasibility x transformative value x confidence achievability:

1. **Communication asymmetries** — "Your median response time to your CFO is 47 minutes. To your VP Engineering it's 14 hours." Pure metadata. Highest feasibility. Frequently produces "I had no idea" moments. Confidence at 30-60 days.
2. **Calendar-revealed priority misalignment** — "You say product strategy is your top priority. 11% of your calendar hours go to it." Confidence at 60 days.
3. **Temporal energy patterns** — "Your highest-quality work output happens 6-8am. You schedule your most important meetings at 3pm." Confidence at 45-60 days.
4. **Avoidance signatures** — "You have not responded to any email from [board member] in 23 days." Confidence at 90+ days.
5. **Decision pattern rigidity** — "You make hiring decisions in 2 days. The office relocation proposal has been on your desk for 7 weeks." Confidence at 90-120 days.
6. **Relationship network drift** — Gradual engagement changes, emerging isolation patterns, alliance shifts. Confidence at 120+ days.

### Avoidance Detection Algorithm

```
Input: Rolling 30-day window of email metadata, calendar events, app usage

For each {sender, topic_cluster, meeting_type, decision_thread}:
  1. Compute baseline metrics (days 1-60)
  2. Compute current_window metrics (rolling 30 days)
  3. Compute deviation scores: (current - baseline) / baseline_stddev
  4. Flag if ANY:
     - response_deviation < -2.0 (significant drop in response rate)
     - latency_deviation > 2.0 (significant increase in response time)
     - reschedule_deviation > 2.0
     - AND pattern persists across 3+ instances
  5. Cluster flagged entities by department/theme/type
  6. Confidence: Low (2.0-2.5 stddev, <5 instances) | Medium (2.5-3.0, 5-10) | High (>3.0, >10)
```

### Positioning Statement

Four-part framework for how Timed describes its own role:

1. **What I am:** "A continuous observation system that sees patterns in your behaviour you cannot see yourself — because you're inside them."
2. **What I am not:** "I am not a coach, therapist, or advisor. I do not have opinions about what you should do. I surface what is, and you decide what it means."
3. **My limitation:** "A human coach sees your face, feels the room, and carries the weight of a real relationship. I cannot do any of that. What I can do is watch continuously — every email, every calendar choice, every pattern — which no human coach can."
4. **My value:** "I am the objective mirror. I make your coach better. I make your self-awareness faster."

### Escalation Triggers (Surface Data + Suggest Human Support)

When behavioural signals suggest a psychological state requiring professional support, Timed surfaces only the behavioural data and suggests the executive "may want to discuss these patterns with someone they trust." Never name a condition, never diagnose.

- Sustained productivity decline >40% over 3+ weeks
- Near-complete avoidance of a major responsibility area
- Voice patterns showing significantly elevated stress markers over 2+ weeks
- Calendar showing systematic elimination of all non-essential human contact

---

## 5. Privacy & Trust Architecture

### Local/Cloud Processing Boundary

| Data Type | Captured By | Processed Where | What Leaves Device | What Never Leaves Device |
|---|---|---|---|---|
| Keystroke dynamics | CGEventTap (XPC) | On-device only | 5-min aggregates: WPM, pause_mean, pause_variance, backspace_rate, hesitation_before_send, burst_length | Raw keystrokes, key values, characters typed |
| Voice audio | AVAudioEngine + Whisper.cpp (XPC) | On-device only | Acoustic features: speech_rate, pause_duration_mean, pitch_variance, energy_contour, silence_ratio. LLM-summarised transcript (never raw). | Raw audio, raw transcripts |
| Application usage | NSWorkspace + AXUIElement (XPC) | On-device only | Session summaries: app_category, duration, switch_count, focus_block_bool. SHA-256 hashed window titles. | Raw window titles, URLs, document names, screen content |
| Email metadata | Microsoft Graph delta | Supabase (already in Microsoft cloud) | Sender, recipient, timestamp, subject hash, thread structure, response latency. Never email body. | Email body content |
| Calendar data | Microsoft Graph delta | Supabase | Event times, attendee count, organiser, response status, cancellation/reschedule flags. | N/A (lowest sensitivity tier) |
| Cognitive model | Claude API (stateless) | Supabase (encrypted) | Encrypted model state. Claude processes feature vectors + metadata, returns reflections, retains nothing. | Decryption keys (KEK in Secure Enclave) |

**Critical invariant:** Feature extraction is lossy by design. You cannot reconstruct raw signals from feature vectors. Typing cadence vectors cannot reveal what was typed. Acoustic features cannot reconstruct speech. This is the architectural guarantee that makes the cloud boundary defensible.

**Screen content is NEVER captured. Not even on-device.**

### Encryption Architecture

```
Executive Password
       |
       v  PBKDF2 (100K+ iterations, random salt)
   +-------+
   |  KEK  | <-- stored in Secure Enclave, biometric-gated (Touch ID)
   +---+---+
       | wraps/unwraps
       v
   +-------+  +-------+  +-------+  +-------+
   |DEK-cal|  |DEK-eml|  |DEK-ftr|  |DEK-cog|
   +-------+  +-------+  +-------+  +-------+
   Calendar    Email      Feature    Cognitive
   data        metadata   vectors    model
```

**At rest (on-device):** FileVault for full-disk encryption. App-level encryption via Keychain-stored keys. Biometric-gated Keychain access for cognitive data.

**At rest (Supabase):** AES-256-GCM client-side encryption before data leaves the device. Per-data-type DEKs wrapped by KEK. Supabase never holds plaintext — zero-knowledge model.

**In transit:** TLS 1.3 mandatory. Certificate pinning for Supabase and Claude API endpoints. No TLS fallback.

**Zero-knowledge guarantee:** Timed (the company) CANNOT access user data. This is architecturally enforced via client-side encryption with hardware-bound keys, not policy-based. A Supabase breach yields only AES-256-GCM ciphertext that is computationally useless without both the user's password AND their specific hardware Secure Enclave.

### Trust-Earning Sequence (Week-by-Week Permission Expansion)

This sequence merges extract-11's privacy permission expansion with extract-12's cold-start value delivery. Each permission request is gated on demonstrated value AND engagement thresholds.

| Week | Permission Requested | Value Demonstrated Before Ask | Creepiness Level | Success Signal |
|------|---------------------|------------------------------|------------------|----------------|
| 1 | Calendar read (Graph API) | None — first ask, lowest threat. Frame: "schedule intelligence." | Lowest | Executive opens morning session 3+ of 5 days |
| 2 | Email metadata read (Graph API) | Calendar intelligence delivered: "You had 14 meetings last week, 6 with no clear agenda. Tuesday 2-5pm was your only deep-work window." | Low-medium | Executive reads email pattern report, doesn't revoke |
| 3 | Accessibility API (app usage) | Email + calendar insights: "Your CFO emails take 3x longer to reply to than average." Frame: "focus analytics." | Medium | Executive checks focus analytics daily |
| 4 | Microphone + keystroke dynamics | Focus/fragmentation analysis delivered. Frame: "decision rhythm analysis" and "meeting energy patterns." | Highest | Executive grants both; morning session is habit |

**Expansion gating logic:**

```swift
func shouldRequestNextPermission(
    currentState: ConsentState,
    metrics: EngagementMetrics
) -> PermissionRequest? {
    guard metrics.daysInCurrentState >= 7 else { return nil }
    guard metrics.morningSessionOpenRate(last: 5) >= 0.6 else { return nil }
    guard metrics.insightsEngaged(last: 7) >= 1 else { return nil }
    guard metrics.daysSinceLastRevocation >= 14 else { return nil }

    switch currentState {
    case .calendarOnly:
        return .emailMetadata(valueEvidence: metrics.topCalendarInsight)
    case .calendarEmail:
        return .appUsage(valueEvidence: metrics.topCommunicationInsight)
    case .calendarEmailApps:
        return .voiceAndKeystroke(valueEvidence: metrics.topFocusInsight)
    case .fullObservation:
        return nil
    }
}
```

**Decline handling:** Accept gracefully. Do not re-ask for 14 days. Never nag.

**Approval handling:** Enable immediately. Show first insight from new data source within 24 hours (fast reward loop).

### Consent UX Design

- **Layered consent:** Plain-language summary at top, drill-down detail available but not forced. Never a wall-of-text EULA.
- **Just-in-time consent:** Each permission requested at the moment it becomes relevant (Week 1-4 sequence), accompanied by evidence of value already delivered.
- **Dynamic consent:** Revoke any individual data stream without losing the rest. Revocation is instant and visible. Re-granting is easy, never nagged.
- **Privacy nutrition labels** (Kelley & Cranor model): For each data type, show what is collected, where processed, how long retained, who can access. Always visible in settings.

**Language rules:**
- Say "calendar patterns" not "calendar surveillance"
- Say "typing rhythm" not "keystroke logging"
- Say "meeting energy" not "voice analysis"
- Say "focus time" not "screen monitoring"
- Never use "track" — use "observe" or "notice"

### Consent State Machine

```
States: DORMANT -> CALENDAR_ONLY -> CAL_EMAIL -> CAL_EMAIL_APPS -> FULL_OBSERVATION
                                                                        |
        <---- PARTIAL_REVOKE (any individual stream) <------------------+
        |
        v
    PAUSED (all observation stopped, model frozen, data retained encrypted)
        |
        v
    DELETED (KEK destroyed, all cloud data permanently unrecoverable)

Transitions:
- Any state -> PARTIAL_REVOKE: instant toggle off individual stream
- PARTIAL_REVOKE -> previous state: toggle on (no re-consent wall)
- Any state -> PAUSED: one tap in menu bar
- PAUSED -> previous state: one tap
- Any state -> DELETED: confirmation dialog, then cryptographic KEK destruction
- DELETED is terminal — no recovery possible
```

### Data Ownership & Portability

- Executive owns all data unconditionally. Timed is data processor; executive is data controller.
- Cognitive model belongs to the individual, not employer, not Timed.
- **Full export:** One-click export (JSON, CSV). Includes raw stored data + cognitive model + reflection history.
- **Full deletion:** One-click cryptographic deletion (KEK destruction). Supabase ciphertext becomes permanently unrecoverable.
- **Legal isolation from employer:** Personal account, not corporate SSO. Even if company owns the device, cognitive model is encrypted with personal keys. MDM detection: warn executive if device is managed.

### Adversarial Threat Model

| Scenario | Impact with Current Architecture | Mitigation |
|---|---|---|
| Supabase breach | None — AES-256-GCM ciphertext without KEK | Zero-knowledge encryption. KEK in Secure Enclave, never on server. |
| Divorce subpoena | Cryptographic deletion capability. Executive destroys KEK, data unrecoverable. | Structure cognitive model as personal health data (analogous to therapy notes). |
| Corporate litigation discovery | NOVEL RISK — no precedent for cognitive model discoverability. | Architectural separation (personal account, not corporate SSO). Pre-launch: get outside counsel opinion. Define cognitive model as personal health data in DPA. |
| Device stolen (locked) | None — FileVault encryption | Standard macOS security. |
| Device stolen (unlocked + biometric) | FULL EXPOSURE — residual risk. | Remote KEK destruction via authenticated API call from another device. |
| Insider threat (Timed employee) | None — zero-knowledge architecture | Employees see only ciphertext. No admin backdoor. No master key. |
| Government subpoena | "We can provide ciphertext but cannot decrypt it." | Data residency in user's jurisdiction. CLOUD Act mitigation: incorporate in privacy-friendly jurisdiction. |

### EU AI Act Compliance (In Force Since 2 February 2025)

- Article 5(1)(f) prohibits emotion inference from biometric data in workplaces.
- Voice and keystroke analysis must demonstrably infer cognitive states (focus, fragmentation, decision rhythm) — never emotional states.
- Feature extraction pipeline must architecturally exclude emotion classification labels. This is not a labelling choice; the underlying model must not be trained on or capable of emotion classification.
- Validate with adversarial testing before launch.
- Timed likely classifies as high-risk AI (Article 6, Annex III point 4: AI in employment/workforce management). Requires risk management system, data governance, technical documentation, transparency, human oversight, accuracy/robustness.

---

## 6. Cold Start Pipeline

### 48-Hour Thin-Slice Inference

Research basis: Ambady & Rosenthal (1992) showed accurate personality judgments from 30-second behavioural clips. 48 hours of email/calendar data is orders of magnitude more information. Kosinski (2015): 10 Facebook Likes outperform a coworker's accuracy; 150 outperform a family member.

**Reliably inferable in 48 hours (high confidence):**
- Extraversion, network centrality, communication energy
- Email response time distribution (reactive vs batched)
- Calendar density/fragmentation, meeting-to-deep-work ratio
- Top contact clusters

**NOT inferable in 48 hours (requires 2-4+ weeks):**
- Conscientiousness, decision-making style, agreeableness
- Delegation patterns, stress response shifts

**Algorithms:**
1. Email metadata clustering: group contacts by response time into strategic/operational/low-priority tiers. Requires email volume >= 20/day.
2. Calendar fragmentation scoring: uninterrupted blocks >= 90 min, scored against Porter/Nohria baseline (CEOs average 28% alone time).
3. Communication energy classification: median response < 15 min = reactive; 15-60 min = moderate; > 60 min = deliberate/batched.
4. Network centrality extraction: weighted contact graph from email frequency + calendar co-attendance. Top 5 hub contacts identifiable within 48h.

### Onboarding Sequence (12-Minute Ceiling)

**SOKA model (Vazire):** Ask ONLY about what the executive uniquely knows (internal states). NEVER ask about externalised behaviours (the data reveals them more accurately).

```
Day 0 (Setup, ~12 min max):
  1. Grant Microsoft Graph permissions (email + calendar read-only)
  2. 4-5 SOKA-informed questions:
     a. "What keeps you up at night about your role right now?" (internal state)
     b. "When you need to make a high-stakes decision, what does your process
         look like?" (cognitive style — self-report, will verify against observed)
     c. "What does a good week look like for you vs a bad week?" (personal benchmark)
     d. "Who are the 3-5 people whose input matters most to your decisions?"
         (network seed)
     e. Optional: "What should I know about you that wouldn't be visible from
         your calendar and email?" (unknown unknowns)
  3. System begins background ingestion of last 90 days email metadata + calendar
```

**5-minute option** captures 3 high-value questions. Sufficient if email/calendar history is available.

**15+ minutes:** Actively harmful. Signals disrespect for executive time. Coach intake sessions are 45-60 min but coaches have reciprocal human rapport — an AI onboarding does not.

### Default Intelligence Library (20-30 Base-Rate Insights)

Available from hour 1, requiring no personalisation:

**Calendar-derived:**
- Deep work availability score (uninterrupted blocks >= 90 min)
- Meeting load vs Porter/Nohria baseline (72% in meetings, 28% alone)
- Context-switch count (meeting-to-different-topic transitions per day)
- Recovery gap analysis (meetings with <15 min buffer)
- Evening/weekend calendar bleed index

**Email-derived:**
- Response time distribution (median, p90, p99) — reactive vs batched classification
- Email volume by hour heatmap (cognitive load temporal profile)
- Contact network tier map (top 10 by frequency, top 10 by response speed)
- Sent:received ratio (information producer vs consumer)
- After-hours email percentage

**Research-backed universal insights (no data required):**
- Gloria Mark: 23 min recovery per context switch
- Kahneman System 1/2: decision fatigue applied to meeting sequencing
- Klein RPD: pattern recognition degrades after 4+ hours without breaks
- Eisenhardt: simultaneous alternatives outperform sequential

Every insight must reference a specific number from the executive's data. Zero generic insights, ever.

### Value Trajectory (Day 1 to Month 3)

This merges extract-12's intelligence progression with extract-11's trust-earning sequence:

| Milestone | Intelligence Type | Confidence | Permission State | Trust Stage |
|-----------|------------------|------------|-----------------|-------------|
| **Hour 1** | Calendar structure analysis | High | CALENDAR_ONLY | Establishment |
| **Hour 1** | Email volume/timing (if granted) | High | CALENDAR_ONLY | Establishment |
| **Day 1** | Base-rate benchmarking vs research | High | CALENDAR_ONLY | Establishment |
| **Day 3** | Thin-slice personality hypotheses | Moderate | CAL_EMAIL | Establishment |
| **Day 3** | Network centrality map | Moderate | CAL_EMAIL | Establishment |
| **Week 1** | Recurring scheduling inefficiencies | Moderate+ | CAL_EMAIL | Establishment |
| **Week 1** | Self-report vs observed comparison | Low-Moderate | CAL_EMAIL | Establishment |
| **Week 2** | Cross-signal correlations | Moderate | CAL_EMAIL_APPS | Establishment |
| **Week 4** | Predictive insights (overload anticipation) | Moderate+ | FULL_OBSERVATION | Calibration |
| **Week 4** | Decision-style inference | Moderate | FULL_OBSERVATION | Calibration |
| **Month 3** | Deep cognitive model outputs | High | FULL_OBSERVATION | Working Alliance |

**Conflict resolution:** Extract-14's trust-building algorithm calls for "Week 1 silent observation, Week 2 first insight." Extract-12's value trajectory delivers insights from Hour 1. **Decision: extract-12 wins.** Rationale: extract-14's silent first week is designed for a concierge GTM where a human relationship manager buffers the experience. At the product level, the executive expects value from the first morning session. The GTM layer can modulate timing, but the product must be capable of day-1 intelligence.

### Engagement Monitoring During Learning Period

- Track morning session engagement: did the executive read it? How long? Did they interact?
- If engagement drops 2 consecutive days: escalate insight specificity (shift from base-rate to thin-slice even at lower confidence — the risk of boring them exceeds the risk of a wrong hypothesis).
- If engagement drops 5 consecutive days: trigger recalibration prompt — "Based on my first [N] days of observation, here are the 3 most important things I've learned about how you work. Are any of these wrong?"
- Never let more than 48 hours pass without delivering at least one novel insight. Repetition = death.

### Expectation Gap Management

- **Frame the cold start as a feature:** "I can already see your calendar structure. I cannot yet comment on how your communication style shifts under board pressure — that requires 3-4 weeks of observation."
- **Endowed progress effect (Nunes & Dreze):** Pre-populate the cognitive model with dimensions already measured (communication style: filled; network map: filled). Explicitly leave others empty with reasons. This produces 34% vs 19% completion/retention.
- **Qualitative calibration, not quantified progress:** "I can now distinguish your strategic contacts from your operational contacts" beats "I'm 15% through learning your patterns." Never show progress bars or percentages.
- **Rapid rapport building:** Mirror the executive's detected communication style in the first output. If their emails are terse, the morning session is terse.

### Cold-Start Prompt Templates

**Day 1 system prompt:**
```
You are the intelligence layer of Timed. You have:
1. Raw calendar data for the past [N] days
2. Email metadata (timestamps, contact frequency, response times) for [N] days
3. Research baselines: Porter & Nohria CEO time study (27 CEOs, 60,000 hours),
   Gloria Mark attention research, Klein RPD model
4. Executive's onboarding answers: [injected]

Generate 3-5 insights that are genuinely valuable to a C-suite executive. Each must:
- Reference a specific pattern in THEIR data
- Calibrate against research baselines
- Be actionable without prescribing action
- Include confidence level and what additional observation would increase confidence

Do NOT generate generic productivity advice.
```

**Day 3 thin-slice prompt:**
```
Given 48 hours of email metadata and calendar data, generate hypotheses about:
1. Communication energy (rapid responder vs deliberate batched processor)
2. Network structure (hub-and-spoke vs distributed vs hierarchical)
3. Time sovereignty (controls own calendar vs calendar-controlled)
4. Cognitive load trajectory (building through week vs front-loaded vs chaotic)

For each: state the hypothesis, specific data points, confidence level, and what
data over the next 2 weeks would confirm or disconfirm.

Frame as: "Based on 48 hours, here is what I'm beginning to see."
```

---

## 7. Swift/macOS Implementation Architecture

### Distribution

**Developer ID, non-sandboxed, notarised.** This is mandatory, not a preference.

AXUIElement (accessibility observation), CGEventTap (keystroke dynamics), and continuous microphone access are architecturally incompatible with App Store sandboxing. ScreenTime API is App Store-only and unavailable to Developer ID apps, but is unnecessary — NSWorkspace + AXUIElement provide equivalent app usage data.

Implications:
- No TestFlight (use Sparkle beta channel)
- No App Store review process (faster iteration)
- No App Store payment processing (use Stripe or direct licensing)
- Manual TCC permission grants during onboarding (mapped to Week 1-4 trust sequence)

### Background Processing: Multi-Process XPC Mesh

Five XPC services aligned to permission boundaries and crash domains:

| XPC Service | Captures | Permission | Crash Domain |
|---|---|---|---|
| `KeystrokeXPC` | CGEventTap: timestamps + virtual keycodes only | Input Monitoring | Isolated — keystroke loss does not affect voice/calendar/email |
| `VoiceXPC` | AVAudioEngine + Whisper.cpp (Core ML) | Microphone | Isolated — Whisper inference crash does not affect other modalities |
| `AccessibilityXPC` | AXUIElement: window titles (hashed), active document classification | Accessibility | Isolated |
| `AppUsageXPC` | NSWorkspace: app switches, launch/terminate notifications | None | Isolated |
| Main app process | Graph API polling, Supabase sync, Claude API calls, UI | Network | Coordinator — receives features from all XPC services |

**Crash recovery:** XPC services register as LaunchAgents via SMAppService (macOS 13+). launchd restarts them automatically (KeepAlive = true). If VoiceXPC crashes during Whisper inference, keystroke and calendar observation continue uninterrupted.

**Login persistence:** SMAppService for login item registration. NOT LaunchDaemon (those run as root — wrong privilege level for per-user observation).

**App Nap prevention:** XPC services registered as LaunchAgents are not subject to App Nap (separate processes managed by launchd). For the main app: `NSProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Continuous executive observation")`.

### Local Feature Extraction Pipeline

```
AsyncSequence (sensor events from XPC)
  -> .debounce / .throttle (rate limiting per signal type)
  -> FeatureExtractor actor (per-modality)
     -> Computes aggregate metrics in 5-min windows
     -> Privacy filter: strips raw content, hashes identifiers
  -> LocalBuffer actor (SwiftData/SQLite)
     -> Batches observations (max 50 rows or 5 minutes, whichever first)
  -> SyncActor
     -> Writes batch to Supabase via PostgREST
     -> Marks local rows as synced
     -> Retries with exponential backoff (1s, 2s, 4s, 8s, max 5min)
```

**Observation cadence:**

| Signal | Method | Frequency |
|---|---|---|
| Keystroke dynamics | CGEventTap callback (event-driven) | Continuous; aggregated to 5-min windows |
| App usage | NSWorkspace notifications (event-driven) | On every app switch |
| Email metadata | Graph delta query (polling) | Every 5 min (business hours), 30 min (off-hours) |
| Calendar | Graph delta query (polling) | Every 15 min |
| Voice | AVAudioEngine tap (continuous stream) | 30-second segments; on-demand during meetings/sessions, continuous only when plugged in |

**Low battery mode (<20%):** Reduce observation frequency — keystroke aggregation 5min to 15min, email poll 5min to 30min, voice analysis pauses. Resume normal on charge detection (IOPowerSources notification).

### Supabase Schema

Core tables with BRIN indexes for time-series data and HNSW indexes for semantic retrieval:

**Observation tables** (partitioned by month for fastest-growing tables):
- `email_observations` — sender, recipient_count, subject_hash (SHA-256), response_latency, thread_depth, categories. BRIN on (executive_id, observed_at).
- `calendar_observations` — event times, attendee_count, organiser_is_self, response_status, was_cancelled, was_rescheduled, original_start. BRIN on (executive_id, observed_at).
- `keystroke_aggregates` — 5-min windows: mean_inter_key_interval, typing_speed_wpm, pause_frequency, error_rate, cognitive_load_score. BRIN on (executive_id, window_start).
- `voice_observations` — speech_rate, pause_frequency, mean_pitch, vocal_energy, confidence, transcript_summary (LLM-summarised, never raw). BRIN on (executive_id, observed_at).
- `app_usage_events` — bundle_id, window_title_hash (SHA-256), focus_duration, app_category. BRIN on (executive_id, observed_at).

**Intelligence tables:**
- `daily_syntheses` — Sonnet output. energy_curve (JSONB), focus_quality_score, key_observations, synthesis_text, embedding (VECTOR(1024)). HNSW on embedding.
- `weekly_syntheses` — Opus output. pattern_detections, trend_analyses, cognitive_model_updates, thinking_text, embedding. HNSW on embedding.
- `cognitive_model` — versioned. semantic_facts, procedural_rules, personality_profile, communication_graph, energy_model, decision_model, model_confidence.
- `insights` — proactive alerts. insight_type, severity, title, body, evidence (JSONB), was_delivered, was_helpful, embedding. HNSW on embedding.

**RLS:** Every table locked to the authenticated executive via `auth.uid()`. Helper function `get_executive_id()` for policy evaluation.

### Claude API Integration

**Three-tier model routing:**

| Task | Model | Latency | Cadence |
|---|---|---|---|
| Email classification, app category classification, anomaly detection | Haiku 3.5 | <1-2s | Real-time |
| Daily synthesis, morning brief generation, burnout risk, pattern detection | Sonnet | 5-30s | Nightly / morning |
| Weekly deep analysis, monthly cognitive model evolution, procedural rule generation, relationship graph | Opus 4.6 + extended thinking | 2-15 min | Weekly / monthly |

**Context window management (Opus 200K):**
- System prompt + cognitive model: ~10K tokens
- Current week's daily syntheses (7): ~15K tokens
- Semantically retrieved historical context: ~40K tokens (top-30 via pgvector HNSW)
- Raw observation samples: ~10K tokens
- Reserved for extended thinking: ~125K tokens

**Prompt caching:** Cache system prompt + cognitive model as a stable prefix (unchanged within a day). Only new observation data varies per call.

**Nightly consolidation Edge Function (cron: 0 2 * * *):**
1. Acquire advisory lock per executive_id
2. Fetch all observations for today across 5 tables
3. Aggregate daily summary statistics per signal type
4. Retrieve current cognitive_model
5. Call Sonnet with aggregated stats + model + last 3 daily syntheses
6. Embed synthesis_text via Jina v3 (1024-dim)
7. Write to daily_syntheses
8. Check if any patterns cross threshold → insert into insights
9. Release lock. Idempotency: skip if row exists for (executive_id, today).

**Weekly analysis (Sunday 3:00 AM):** Opus 4.6 + extended thinking analyses 7 daily syntheses + observation patterns. Generates weekly_syntheses, updates cognitive_model version.

**Monthly evolution (1st of month, 4:00 AM):** Opus 4.6 + maximum thinking budget. Full cognitive model review and rewrite. This is where compounding intelligence lives.

### Graceful Degradation

| Failure | Behaviour | Recovery |
|---|---|---|
| Offline (no network) | XPC services continue. Local buffer accumulates. No Claude API calls. | On reconnect: SyncActor flushes in chronological order. Edge Functions catch up. |
| Claude API down | Last daily/weekly synthesis displayed. Observations continue collecting. | Queue drains on recovery. Delayed, not lost. |
| Supabase unreachable | Local SwiftData buffer absorbs (7-day capacity, ~50MB typical). | Batch sync with conflict resolution (server timestamp wins for syntheses, client for observations). |
| XPC service crash | launchd auto-restarts (KeepAlive). Other XPC services unaffected. Menu bar shows degraded indicator. | Restarted XPC resumes from current moment. Gap noted in next consolidation. |
| Main app crash | XPC services continue independently. Observations accumulate in their buffers. | Main app restart picks up XPC connections, flushes buffers. |
| macOS reboot | SMAppService re-launches all login items on next login. | Full pipeline restarts. First consolidation notes the gap. |
| Low battery (<20%) | Reduced observation frequency across all modalities. | Resume normal on charge. |

### Deployment & Updates (Sparkle)

- Sparkle 2.x for auto-updates. Delta updates via BinaryDelta to minimise download size.
- EdDSA signing for update verification. Appcast.xml hosted on CDN.
- **Critical:** Update installation must not interrupt observation. XPC services continue running during main app update.
- Schema migrations via Supabase CLI: **additive only** (new columns, new tables, new indexes). NEVER DROP COLUMN, DROP TABLE, or ALTER COLUMN TYPE on production. Data continuity is non-negotiable.

### Battery/CPU Budget

| Modality | CPU | Power | Memory |
|---|---|---|---|
| Keystroke (CGEventTap) | <0.1% | ~5-15mW | <5MB |
| App usage (NSWorkspace) | <0.1% | ~5mW | <3MB |
| Email (Graph polling, 5min) | ~0.5% spike | ~50mW avg | <20MB |
| Calendar (Graph polling, 15min) | ~0.3% spike | ~20mW avg | <10MB |
| Voice Whisper-small (on-demand) | ~8-12% during speech | ~200mW avg | ~500MB |
| Accessibility (AXUIElement) | <0.2% | ~10mW | <5MB |
| Supabase sync | ~0.3% per batch | ~30mW | <15MB |
| **Total (voice on-demand)** | **~1.5% avg** | **~350mW** | **~560MB** |

~2% battery/hour on battery. 10-hour workday feasible. Voice continuous mode (~1.3W, ~6% battery/hour) only when plugged in.

### Whisper Model Selection

**Whisper-small** is the production model. 244MB, 8x real-time on M1, ~4.5% WER, ~500MB memory. A 30-second segment processes in ~4 seconds. Sufficient accuracy for executive speech patterns.

---

## 8. Go-to-Market & Positioning

### Category Creation Strategy

Timed is not a product in an existing category. It is a new category: **Executive Cognitive Intelligence.**

**Core principles:**
1. **Anti-category framing.** Never position as "AI productivity tool" or "executive assistant." The enemy is the status quo (scattered attention, reactive calendars, "I already have people for that"), not a competitor.
2. **Name the category first.** The company that names the category wins 76% of total market cap (Lochhead/Category Pirates). "Executive Cognitive Intelligence" is Timed's category, defined on Timed's terms.
3. **Three-devices framing (iPhone model).** Position as three things with independent value — observation engine + compounding cognitive model + intelligence delivery — then reveal they are one system. Bypasses "I already have something for that."
4. **One-sentence explanation:** "It watches how you work and tells you what you're not seeing."

**Point of View (the worldview, not the marketing message):** "Every executive operates with a cognitive blind spot that grows with seniority. The higher you rise, the less honest feedback you get about how you actually operate. Timed is the first system that shows you what no one else will tell you."

**Blue Ocean strategy:**
- **Eliminate:** Dashboards, metrics, productivity scores, task management.
- **Reduce:** UI surface area, setup complexity, notification frequency.
- **Raise:** Intelligence depth, personalisation, privacy.
- **Create:** Cognitive self-awareness as a product category. Compounding intelligence. The "it knows me" experience.

### Pricing Architecture

| Tier | Price | Buyer | Expense Type | Rationale |
|------|-------|-------|-------------|-----------|
| Individual Executive | $24,000-$36,000/year | The executive personally | Personal professional development | Below exec coaching annual spend ($24K-$48K); personal purchase = no procurement friction |
| Board Cohort | $48,000-$72,000/year per seat | Company/board | Governance / cognitive risk | Boards buying cognitive intelligence for entire C-suite |
| Founding Member | $18,000/year (first 100 only) | Hand-selected executives | Personal | Lower BUT framed as exclusive early access, not discount; locked rate for life |

**Pricing rules:**
- No free tier. No trial. No money-back guarantee. Each signals low confidence.
- Annual commitment only. Monthly billing signals optionality = disposable.
- Application-only. No public pricing page. No self-serve signup.
- Reference prices are executive coaching ($500-1000/hr) and management consulting ($5,000-10,000/day), not software.
- Veblen goods psychology: below $20K/year = "another SaaS tool." Above $20K = "serious professional investment."
- Bloomberg Terminal proof point: $24K/year/seat, 325,000+ terminals, never offered a free tier.

### First 100 Users Strategy

**Selection criteria (in order of priority):**
1. Multi-board directors (3+ boards) — maximum diffusion surface
2. Connectors in C-suite networks (Gladwell's framework)
3. Executives who already invest in executive coaching (proven willingness)
4. YPO/Vistage peer group leaders (built-in amplification)
5. Cognitively curious — executives who read, reflect, journal

**Language: "Founding Member," never "beta tester."** IKEA effect: people who feel like co-creators value the product 63% more and advocate 5x harder. "Beta tester" transfers risk. "Founding member" transfers ownership.

**Rollout timeline:**

| Week | Activity | Goal |
|------|----------|------|
| Pre-launch | Hand-identify 300 candidates across YPO, board networks, PE portfolios. Personal outreach from founder. | 300 qualified candidates |
| Week 1-2 | Accept first 25. 1:1 onboarding call (60 min). Install + configure passive observation. | 25 active, system observing |
| Week 3-4 | First insights delivered. Personal follow-up: "Was this accurate? What surprised you?" | Identify which impressive moments land |
| Week 5-8 | Accept next 25 (total 50). Iterate delivery. Introduce founding members to each other. | 50 active, peer connections forming |
| Week 9-12 | Accept next 50 (total 100). First founding member dinner (12-15 people, no sales pitch). | 100 active, community forming |
| Month 4-6 | Weekly check-ins -> monthly. Founding member advisory board. First organic referrals. | Self-sustaining advocacy |

**Concierge-to-scale transition:**
- Users 1-100: Full concierge. Dedicated relationship manager per 10-15 executives. Weekly check-ins. Every insight human-reviewed before delivery.
- Users 100-500: Semi-concierge. RM per 25-30. Bi-weekly check-ins. Automated delivery with human QA on flagged items.
- Users 500-2000: Scaled. RM per 50-75. Monthly check-ins. Human escalation only.
- Users 2000+: Product-led with premium support. Self-serve onboarding refined from 2000 manual onboardings.
- **Never remove the human layer entirely.** Bloomberg retains dedicated support at $24K/seat even at 325,000+ terminals.

### "Impressive Moment" Blueprint

The first-week aha moment is the single most important retention mechanism. Target: >70% probability of triggering it in week 1.

| Rank | Moment | Engineering Approach | Psychological Basis |
|------|--------|---------------------|---------------------|
| **#1** | The Pattern They Couldn't Name — a recurring behavioural pattern the executive never consciously identified | Minimum 5 days observation + Opus reflection at max effort. Must be non-obvious AND immediately recognisable once stated. | Kounios & Beeman: aha requires true + surprising + personally relevant simultaneously |
| **#2** | The Prediction That Proved Right — predict behaviour/outcome before it happens | 2+ weeks data. Only surface high-confidence predictions. | Confirmation of system intelligence: "it knows me" |
| **#3** | The Hidden Connection — link two areas they hadn't connected | Cross-domain pattern matching across email + calendar + behaviour. Opus synthesis. | Novelty + relevance = maximum shareability (Berger's Social Currency) |
| **#4** | The Morning Brief That Feels Telepathic — so precisely relevant it feels mind-reading | Aggressive context loading. Prioritise by predicted attention, not urgency. | "This is what my chief of staff should be doing" |
| **#5** | The Relationship You'd Forgotten — surface a neglected relationship that matters strategically | Email frequency + calendar gap detection for key contacts. | Practical value + emotional resonance |

**Engineering serendipity for week 1:**
1. Over-collect in week 1 — all passive signals at maximum sensitivity.
2. Run Opus reflection at maximum effort on day 5.
3. Pre-compute 5 candidate insights, surface only the strongest (ranked by non-obviousness x relevance x recognisability).
4. Deliver at 7:15 AM on day 6, before the executive enters reactive mode. Present in morning session, not pushed as notification.
5. Fallback: if no non-obvious pattern found, deliver a precise observation. "You spent 47% of last week in meetings with your direct reports but 0% with their direct reports" — concrete enough to demonstrate attention.

### Word-of-Mouth Channels

| Channel | Leverage | Strategy |
|---------|----------|----------|
| **YPO** (35,000+ members, forums of 8-12) | 1 placement = 8-12 high-trust impressions | Target forum chairs first. 50 YPO members in first 100 users. |
| **Board director networks** | 1 director on 4 boards = 4 enterprise deployment surfaces | Multi-board directors as founding members. Average Fortune 500 board member: 2.1 boards. |
| **PE/VC portfolio CEO networks** | 1 PE partner = 15-50 CEO introductions | Average mid-market PE firm: 15-25 portfolio companies. |
| **Executive coach network** | Coaches as distribution partners, not threatened competitors | Position Timed as "the data layer that makes coaching 3-5x more effective." Coach sees continuous observation data vs their 2 hours/month. |

**The dinner conversation test (Berger's STEPPS):**
- **Social Currency:** Using Timed signals cognitive sophistication.
- **Practical Value:** The insight was genuinely useful.
- **Stories:** "My cognitive intelligence system told me I avoid strategic planning after board meetings — and it was right." Complete, shareable story.

**Channels that DESTROY credibility at this buyer level:**
- Ads, SEO, content marketing, social media campaigns — all signal "another SaaS product."
- PR/media coverage before the first 100 users are advocates.
- The channel IS the message. Bloomberg has never run a consumer ad. McKinsey does not do SEO for client acquisition.

### Executive Adoption Psychology

**Drivers:**
1. Competitive edge signalling — "I operate at a higher level"
2. Identity integration (Belk's extended self) — the cognitive model becomes part of how the executive sees themselves
3. Cognitive offloading — genuine reduction in decision fatigue
4. Peer validation — "other executives I respect use this"
5. Exclusivity — invitation-only signals selection, not marketing

**Resistance and pre-emption:**

| Resistance | Pre-emption |
|------------|-------------|
| "I already have people for that" | Timed sees patterns your people cannot — it observes YOU, not your org |
| "I don't have time to learn new tools" | Zero learning curve, fully passive, no interface to learn |
| "AI can't understand my context" | It doesn't try on day 1. It compounds over months. Month 6 is the proof. |
| "Privacy — I don't want software watching me" | On-device only, never leaves your machine, you own the model |
| "I've seen AI hype before" | Don't demo features. Demo an actual insight about THEM during onboarding. |
| "This is too expensive" | If this objection comes, wrong buyer. |

### Retention Mechanics

- **Chamath's Facebook metric adapted:** 1 non-obvious true insight in 7 days = permanent commitment. Target: 70%+ week-1 aha rate.
- **Habit formation:** If executive opens morning session as part of daily routine by Day 21, probability of long-term retention exceeds 85% (Lally et al.: median 66 days for full automaticity, 21 days for initial routine).
- **Point of no return (Week 6-8):** The cognitive model contains enough compounded intelligence that turning it off feels like "losing a capability" rather than "stopping a tool."
- **The deepest switching cost:** The cognitive model IS the executive's extended self (Belk). Leaving Timed means leaving behind a model of yourself. Language reinforces this: "your model," "your patterns," "your cognitive signature." Never "our analysis."

### Feedback Without Feature Creep

1. Separate insight feedback from feature requests. Ask: "Was this insight accurate? Was it useful?" Never: "What features do you want?"
2. Three buckets: (a) Insight quality (tune reflection engine), (b) Delivery timing/format (tune surface), (c) Feature request (log but ignore unless 30%+ independently surface same need).
3. Monthly synthesis, not reactive sprints.
4. Vision filter: "Does this make the cognitive model smarter, or does this add a feature?" Only the former ships.

---

## Appendix: Cross-Cutting Anti-Patterns

These are the failure modes that appear across multiple extractions, aggregated here for reference:

1. **Data dump briefings.** Present everything instead of 5-7 earned items. Executives stop reading entirely.
2. **Crying wolf.** A single false alarm damages trust more than ten accurate predictions build it. Maintain >80% actionability.
3. **Generic advice.** "Consider delegating more" is useless. "You've handled 14 of 22 escalations personally; your direct reports resolved the other 8 with 94% satisfaction" shows what they cannot see.
4. **Premature confrontation.** No self-concept-challenging observations before Day 90. No deep patterns before Day 180. There is no shortcut.
5. **Anthropomorphising.** "I feel," "I'm concerned," "I care" — the executive finds it cringe and disengages, or forms parasocial attachment. Narrow band between too human and too mechanical.
6. **Overstepping into therapy.** Observe behaviour, not psychological states. "Your error rate increased 200% over 3 weeks" is observation. "You seem burned out" is diagnosis.
7. **Requesting all permissions upfront.** Reduces grant rates by 50-70%. Week 1-4 graduated expansion exists specifically to avoid this.
8. **Storing raw signals.** Raw keystroke content = keylogger. Raw audio = surveillance. Feature extraction is lossy by design — this is a legal requirement, not an optimisation.
9. **Quantifying learning progress.** "I'm 15% through learning your patterns" is actively harmful. Use qualitative calibration.
10. **Free tiers, "beta testing" language, traditional marketing.** All destroy credibility at the C-suite buyer level. The channel is the message.
