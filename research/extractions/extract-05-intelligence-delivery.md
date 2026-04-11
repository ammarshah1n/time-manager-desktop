# Extract 05 — Intelligence Delivery Design

Source: `research/perplexity-outputs/v2/v2-05-intelligence-delivery.md`
177 cited sources. Covers CIA PDB design, military intelligence briefing methodology, interruption science, voice interaction, adaptive delivery, cognitive load.

---

## DECISIONS

### Morning briefing structure
- **BLUF first.** Lead with the single highest-salience insight — the one thing the executive must know before anything else. CIA PDB uses "lead item" structure; primacy effect research confirms first-position items receive disproportionate encoding and retention.
- **Section order (7 sections, ~610 words total):**
  1. Lead insight (BLUF) — highest-salience, highest-confidence item
  2. Calendar intelligence — what today's schedule reveals (meeting load, back-to-back risk, decision density)
  3. Email pattern analysis — overnight shifts, unanswered threads reaching critical age, relationship signals
  4. Decision quality observations — patterns from yesterday's decisions worth noticing
  5. Cognitive load assessment — predicted energy curve for today based on schedule + recent sleep/behaviour signals
  6. Emerging patterns — multi-day or multi-week trends the model has detected (relationship dynamics, avoidance patterns, recurring friction)
  7. Recency anchor — one forward-looking observation or question to carry into the day (recency effect ensures this persists)
- **Exclude from morning brief, route to other channels:** items that are important-but-not-urgent (route to weekly synthesis), items with moderate confidence below threshold (hold until confidence rises or pattern strengthens), granular data that supports conclusions (available on drill-down, not in the brief itself).
- **2x2 criticality/reliability routing matrix:**
  - High criticality + high reliability → morning brief lead
  - High criticality + moderate reliability → morning brief with explicit confidence language
  - Low criticality + high reliability → weekly synthesis or on-demand
  - Low criticality + moderate reliability → suppress entirely until pattern strengthens

### Real-time alert threshold logic
- **Five dimensions scored for every candidate alert:** salience, confidence, time-sensitivity, actionability, current cognitive state of the executive.
- **Interrupt only when:** the alert scores high on ALL of salience + time-sensitivity + actionability AND confidence is above threshold AND cognitive state permits interruption. Missing any one dimension = hold for next scheduled delivery.
- **Hard frequency ceiling:** maximum 3 real-time alerts per day. Target 0-1 on most days. Every alert above 1/day degrades the signal value of all alerts.
- **Timing logic:** detect low-cost interrupt windows — task transitions, post-meeting 2-3 minute gaps, application switches, natural break points. Never interrupt during deep work blocks or back-to-back meetings.

### Voice interaction design for uncomfortable insights
- **Five-stage disclosure architecture** (derived from Motivational Interviewing):
  1. Establish rapport/context — reference something the executive already knows
  2. Affirm competence — acknowledge what they're doing well in the relevant domain
  3. Present the observation as data, not judgment — "The pattern shows X" not "You're doing X wrong"
  4. Invite the executive's interpretation — "What do you make of that?"
  5. Let them reach the conclusion — provide the scaffolding, not the verdict
- **Three-mode conversational repair protocol** for when delivery triggers defensiveness:
  1. Acknowledge mode — validate the pushback without retracting the observation
  2. Reframe mode — present the same data from a different angle
  3. Defer mode — "I'll hold this and bring it back when there's more data" (preserves trust, avoids entrenchment)

### Adaptive delivery learning approach
- **Phased timeline:** calibration (days 1-30) -> structured delivery (days 31-90) -> format adaptation (days 91-180) -> content personalisation (days 181-365) -> compounding model (365+)
- **3:1 implicit-to-explicit preference weighting.** What the executive does (time spent, follow-up queries, behaviour change, re-access) matters 3x more than what they say they prefer.
- **Convergence checkpoints:** 90 days (basic format preferences stable), 180 days (content depth preferences stable), 365 days (full cognitive model producing qualitatively different delivery than month 1).

### Information density limits per interaction type
- **Morning briefing:** ~610 words, 5-7 distinct insights, each compressed to 1-2 sentences + one supporting data point. Approximately 3-5 cognitive chunks (Cowan's limit, not Miller's 7).
- **Real-time alert:** single insight, 1-2 sentences max. One actionable observation. Zero context that isn't immediately necessary.
- **Voice interaction:** 3 chunks maximum per conversational turn. Pause after each chunk for processing. Never stack more than one uncomfortable observation per session.

---

## DATA STRUCTURES

### Briefing template (annotated)

```
struct MorningBriefing {
    let date: Date
    let generatedAt: Date
    
    // Section 1 — BLUF (primacy position: highest encoding + retention)
    let leadInsight: BriefingItem           // Single highest-salience item
    
    // Sections 2-6 — Body (protected by structural position between primacy/recency anchors)
    let calendarIntelligence: BriefingItem   // Today's schedule analysis
    let emailPatterns: BriefingItem          // Overnight email dynamics
    let decisionObservations: BriefingItem?  // Yesterday's decision patterns (optional — omit if nothing notable)
    let cognitiveLoadForecast: BriefingItem  // Predicted energy curve
    let emergingPatterns: [BriefingItem]     // Multi-day/week trends (0-2 items)
    
    // Section 7 — Recency anchor (last-position: persists in working memory)
    let forwardLookingObservation: BriefingItem
    
    let totalWordCount: Int                  // Target ~610, hard cap 800
    let confidenceProfile: BriefingConfidence
}

struct BriefingItem {
    let insight: String                      // 1-2 sentences, BLUF format
    let supportingData: String?              // One data point max
    let confidence: ConfidenceLevel          // .high, .moderate (no .low items in brief)
    let category: InsightCategory
    let sourceSignals: [SignalReference]     // What data produced this
}

enum ConfidenceLevel: String, Codable {
    case high       // Include in brief, no hedging needed
    case moderate   // Include with explicit probability language (ICD 203 style)
    case low        // NEVER include in morning brief — hold for pattern strengthening
}

struct BriefingConfidence {
    let overallConfidence: Double            // Weighted average across items
    let noveltyRatio: Double                 // % of items that are new vs recurring (optimal ~60-70% novel)
}
```

### Alert decision matrix

```
struct AlertCandidate {
    let insight: String
    let category: InsightCategory
    
    // Five scoring dimensions (each 0.0-1.0)
    let salience: Double          // How important is this to the executive's goals?
    let confidence: Double        // How certain is the system about this observation?
    let timeSensitivity: Double   // How much value is lost per hour of delay?
    let actionability: Double     // Can the executive do something about this right now?
    let cognitiveStatePermit: Double  // Is the executive in a state to receive this? (inferred from behaviour signals)
    
    var compositeScore: Double {
        // Multiplicative, not additive — any zero dimension kills the alert
        salience * confidence * timeSensitivity * actionability * cognitiveStatePermit
    }
    
    // Thresholds
    static let interruptThreshold: Double = 0.5   // Composite must exceed this to interrupt
    static let holdThreshold: Double = 0.2        // Below this, discard entirely
    // Between hold and interrupt: queue for next scheduled delivery
}

struct AlertFrequencyState {
    let alertsToday: Int                    // Hard cap: 3
    let targetDaily: Int                    // 0-1
    let lastAlertTime: Date?
    let minimumInterAlertGap: TimeInterval  // 60 minutes minimum between alerts
    
    var canAlert: Bool {
        alertsToday < 3 &&
        (lastAlertTime == nil || Date().timeIntervalSince(lastAlertTime!) > minimumInterAlertGap)
    }
}
```

### Feedback signal schema

```
struct DeliveryFeedback {
    let briefingId: UUID
    let deliveredAt: Date
    
    // Implicit signals (weighted 3x over explicit)
    let timeSpentReading: TimeInterval      // Dwell time on each section
    let sectionsExpanded: [String]          // Which sections got drill-down
    let followUpQueries: [String]           // Questions asked after briefing
    let behaviourChangeObserved: Bool       // Did subsequent actions reflect the insight?
    let reAccessCount: Int                  // How many times they came back to this briefing
    let reAccessSections: [String]          // Which sections on re-access
    
    // Explicit signals (weighted 1x)
    let explicitRating: ExplicitFeedback?   // Optional thumbs/dismiss
    let dismissedSections: [String]         // Sections swiped away
    let requestedMoreDetail: [String]       // "Tell me more about..."
    
    // Derived engagement score
    var genuineEngagement: Double {
        // High dwell time + follow-up queries + behaviour change = genuine
        // Low dwell time + no follow-up + explicit positive rating = surface acknowledgment
        // Algorithm: implicit signals dominate (3:1 weight ratio)
        let implicitScore = normalise(timeSpentReading, followUpQueries.count, behaviourChangeObserved, reAccessCount)
        let explicitScore = normalise(explicitRating, dismissedSections.count)
        return (implicitScore * 0.75) + (explicitScore * 0.25)
    }
}

enum ExplicitFeedback: Int, Codable {
    case dismissed = -1
    case neutral = 0
    case useful = 1
}
```

---

## ALGORITHMS

### Alert frequency management (preventing fatigue)

```
// ICU research: only 5-13% of clinical alarms are actionable
// Cybersecurity research: 90% of analysts probability-match — if they expect false alarms, they ignore all alarms
// Goal: maintain >80% actionability rate to prevent cry-wolf desensitisation

func shouldDeliverAlert(_ candidate: AlertCandidate, state: AlertFrequencyState, history: [AlertOutcome]) -> AlertDecision {
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
        // System is alerting too aggressively — raise threshold dynamically
        let adjustedThreshold = AlertCandidate.interruptThreshold * 1.3
        guard candidate.compositeScore > adjustedThreshold else { return .queueForBriefing }
    }
    
    // Gate 4: Cognitive state window check
    guard candidate.cognitiveStatePermit > 0.6 else { return .deferUntilWindow }
    
    return .deliverNow
}

enum AlertDecision {
    case deliverNow
    case deferUntilWindow      // Wait for next low-cost interrupt window
    case queueForBriefing      // Include in next scheduled briefing
    case discard               // Below threshold, not worth tracking
}
```

### Timing logic for interruptions

```
// Gloria Mark (UC Irvine): average recovery time from interruption = 23 minutes 15 seconds
// Implication: every interruption costs ~23 min of productive capacity
// Only interrupt when the insight value exceeds the 23-min recovery cost

struct InterruptWindowDetector {
    // Low-cost interrupt signals (any of these = window is open)
    let taskTransitionDetected: Bool        // App switch, document close
    let postMeetingGap: Bool                // 2-3 min after calendar event ends
    let applicationIdle: TimeInterval       // No keyboard/mouse for >60s
    let betweenDeepWorkBlocks: Bool         // Gap between focused sessions
    
    // High-cost interrupt signals (any of these = window is closed)
    let inDeepWork: Bool                    // Sustained single-app focus >15 min
    let inMeeting: Bool                     // Calendar event active
    let backToBackMeetings: Bool            // No gap between current and next event
    let recentInterrupt: Bool               // Another alert delivered <60 min ago
    
    var windowOpen: Bool {
        let hasOpenSignal = taskTransitionDetected || postMeetingGap || applicationIdle > 60 || betweenDeepWorkBlocks
        let hasBlockSignal = inDeepWork || inMeeting || backToBackMeetings || recentInterrupt
        return hasOpenSignal && !hasBlockSignal
    }
}
```

### Delivery format adaptation based on engagement signals

```
// Phased learning: cold-start defaults → observed preferences → personalised delivery

struct DeliveryPreferenceModel {
    var preferredFormat: DeliveryFormat      // .bullets, .narrative, .visual, .voice
    var preferredDepth: ContentDepth         // .headline, .summary, .detailed
    var preferredTiming: DeliveryTiming      // .earlyMorning, .preMeeting, .onDemand
    var confidenceInPreferences: Double      // 0.0 (cold start) to 1.0 (converged)
    
    // Adaptation from engagement signals
    mutating func updateFromFeedback(_ feedback: DeliveryFeedback) {
        // High dwell time on narrative sections → increase narrative preference
        // Quick scan + expand on bullets → increase bullet preference
        // Voice re-listens → increase voice preference
        // Section skips → reduce that category's inclusion weight
        
        // Exponential moving average: recent feedback weighted more heavily
        let alpha = 0.15  // Learning rate — slow enough to avoid oscillation
        // Update each preference dimension with alpha-weighted signal
    }
}

enum DeliveryFormat: String, Codable {
    case bullets        // Structured, scannable (cold-start default)
    case narrative      // Prose-style analysis
    case visual         // Charts, timelines, spatial layout
    case voice          // Spoken briefing
}
```

### Cold-start delivery preferences

```
// Cold-start strategy: use research-backed defaults, not guesses
// Phase 1 (days 1-30): All briefings use structured bullets (highest baseline engagement across executives)
// Phase 2 (days 31-90): Begin A/B testing — alternate formats on low-stakes items
// Phase 3 (days 91-180): Format preferences converge — switch to personalised delivery
// Phase 4 (days 181-365): Content personalisation — not just format but what categories this executive engages with
// Phase 5 (365+): Compounding model — delivery evolves with the executive's changing cognitive patterns

struct ColdStartConfig {
    static let defaultFormat: DeliveryFormat = .bullets
    static let defaultDepth: ContentDepth = .summary
    static let defaultTiming: DeliveryTiming = .earlyMorning
    static let abTestStartDay: Int = 31
    static let formatConvergenceDay: Int = 90
    static let contentConvergenceDay: Int = 180
    static let fullModelDay: Int = 365
    
    // During cold start, use the ICD 203 approach to uncertainty:
    // Numeric probabilities with verbal anchors (66% comprehension vs 32% for verbal-only)
    static let uncertaintyFormat: UncertaintyPresentation = .numericWithVerbalAnchor
}
```

---

## APIS & FRAMEWORKS

### CIA PDB design principles applicable to Timed
- **Consumer-driven tailoring.** The PDB adapted format for every president: Eisenhower wanted crisp military-style briefs; Kennedy wanted narrative analysis; Trump wanted bullet points with visuals. Timed must do the same — adapt to observed executive preferences, not a fixed template.
- **Lead with the lead.** PDB always opens with the single most important item. The analyst hierarchy decides what is "most important" based on (a) immediate threat, (b) presidential decision pending, (c) novel intelligence that changes a known assessment. Map to Timed: salience scoring must weight pending-decision items and pattern-breaking observations.
- **Confidence language (ICD 203).** The Intelligence Community Directive 203 standardised probability language — numeric probability with verbal anchors ("likely, ~70%") produces 66% comprehension vs 32% for verbal-only. Timed must use numeric + verbal for all moderate-confidence items.
- **Brevity as editorial discipline.** PDB is typically 10-15 pages for the leader of the free world. Compression is an editorial act, not a formatting trick. Every sentence must earn its place. The 610-word target for Timed's morning brief mirrors this principle.
- **Never cry wolf.** CIA's internal research documents that a single false alarm damages trust more than ten accurate predictions build it. Timed must maintain >80% actionability rate on alerts.

### Military intelligence briefing methodology
- **NATO intelligence preparation (COPD framework):** distinguishes time-critical intelligence (requires immediate action) from strategic intelligence (shapes understanding over time). Map to Timed: real-time alerts are time-critical; morning briefs are strategic. Different structure for each.
- **BLUF doctrine (Bottom Line Up Front):** mandatory in all military intelligence communication. The first sentence contains the conclusion. Supporting evidence follows. Never bury the lead. Every Timed output — briefing section, alert, voice statement — must BLUF.
- **Operational briefing layers:** Commander's summary (3 sentences) -> Situation overview (1 paragraph) -> Detailed analysis (available on demand). Map to Timed: lead insight -> briefing body -> drill-down data available but never forced.

### TTS systems for executive voice delivery
- **Apple AVSpeechSynthesizer:** on-device, zero latency, no network dependency, privacy-preserving. Adequate for structured information delivery. Limited prosody control — rate, pitch, volume adjustable but no fine-grained emotional prosody.
- **Research finding:** aligned prosody (rate, pitch matching content emotional valence) drives 66%+ higher human-likeness perception scores. Trust acoustic correlates modeled with R^2=0.71 — lower pitch, moderate rate, consistent volume = higher trust.
- **Timed recommendation:** use AVSpeechSynthesizer for all standard delivery. For uncomfortable insights, slow rate by 10-15%, lower pitch slightly, add micro-pauses before key observations. These adjustments are available in the AVSpeechUtterance API.

### Apple AVSpeechSynthesizer capabilities
- `AVSpeechUtterance.rate` — 0.0 to 1.0, default 0.5. Use 0.42-0.48 for trust-building delivery, 0.5 for standard.
- `AVSpeechUtterance.pitchMultiplier` — 0.5 to 2.0, default 1.0. Use 0.95-0.98 for uncomfortable insights.
- `AVSpeechUtterance.preUtteranceDelay` — seconds of silence before speaking. Use 0.3-0.5s before key observations to create anticipatory attention.
- `AVSpeechUtterance.postUtteranceDelay` — silence after speaking. Use 1.0-2.0s after uncomfortable observations to allow processing.
- `AVSpeechSynthesisVoice` — use premium voices (`.premium` quality) for executive context. Siri voices with neural engine produce highest naturalness.
- SSML not supported natively. Prosody manipulation is per-utterance, not per-word. Break complex deliveries into multiple utterances with varying parameters.

---

## NUMBERS

### Optimal briefing length and information density
- **~610 words** for the full morning brief (7 sections). Hard cap 800 words.
- **5-7 distinct insights** per briefing. Each compressed to 1-2 sentences + one supporting data point.
- **~60-70% novel information** per briefing. Remaining 30-40% is contextualising (connecting to known patterns). Above 70% novel = overwhelming. Below 50% novel = stale.
- **ICD 203 finding:** numeric probability with verbal anchor produces **66% comprehension** vs **32% for verbal-only** uncertainty expressions.

### Alert fatigue thresholds
- **ICU alarm research:** only **5-13% of clinical alarms** are actionable. The rest are noise that trains clinicians to ignore all alarms.
- **Cybersecurity research:** **90% of analysts** probability-match their response rates to their expected true-alarm frequency. If they believe most alerts are false, they treat all alerts as false.
- **Timed ceiling:** **3 alerts/day hard cap**, target **0-1/day**. Maintain **>80% actionability rate** across rolling 20-alert window.
- **Minimum inter-alert gap:** 60 minutes (based on recovery time research).

### Working memory limits
- **Miller's law (1956):** 7 +/- 2 items — but this is for simple items (digits, letters).
- **Cowan's revision (2001):** **3-5 chunks** for complex, meaningful information in expert populations. This is the operative number for Timed.
- **Implication:** morning brief sections must each be a single cognitive chunk. Alert must be a single chunk. Voice interaction: max 3 chunks per conversational turn.

### Retention rates by delivery modality
- **Text-only (reading):** ~10% retention after 72 hours without re-access.
- **Dual-coding (text + visual):** ~65% retention (Paivio's dual-coding theory). Briefings with embedded data visualisation retain significantly better.
- **Voice + text (multimodal):** highest retention for insight-type content. Voice creates emotional encoding; text provides reference-ability.
- **Gloria Mark's interruption recovery:** **23 minutes 15 seconds** average to return to equivalent depth of focus after interruption.
- **Prosody-trust research:** aligned prosody produces **66%+ higher human-likeness perception**, with trust acoustic model achieving **R^2 = 0.71**.

---

## ANTI-PATTERNS

### Information overload patterns that cause disengagement
- **Data dump briefings.** Presenting everything the system knows instead of the 5-7 items that earned inclusion. Executives stop reading entirely.
- **Context without conclusion.** Providing supporting data without the BLUF. Executive has to do the analytical work themselves — they won't.
- **Equal-weight presentation.** Treating all insights as equally important. When everything is highlighted, nothing is highlighted. Use explicit salience hierarchy.
- **Novel-only briefings.** Zero familiar anchoring context. Executive can't connect new observations to known patterns. Maintain 30-40% contextualising information.

### Cry-wolf effect from too many low-confidence alerts
- **Crossing the 3/day threshold.** Every alert beyond 1/day reduces the perceived importance of all alerts. At 5+/day, executives begin ignoring the notification channel entirely.
- **Including moderate-confidence items in real-time alerts.** Reserve real-time for high-confidence + high-salience only. Moderate-confidence items go in the briefing with explicit uncertainty language.
- **Alerting on patterns that don't require immediate action.** If the executive can't do anything about it right now, it's not an alert — it's a briefing item.
- **The 90% probability-matching finding.** If the executive learns that most Timed alerts don't lead to action, they will unconsciously calibrate their response rate down to match. One month of over-alerting can take three months to recover trust.

### Voice delivery patterns that trigger defensiveness
- **Leading with the negative observation.** Skipping the affirmation step. Executive hears criticism before context, triggering ego defense.
- **Judgmental framing.** "You tend to avoid difficult conversations" vs "The data shows a pattern where difficult conversations get rescheduled." First triggers defensiveness. Second invites curiosity.
- **Stacking uncomfortable observations.** More than one challenging insight per voice session overwhelms the executive's capacity for self-reflection. One per session, maximum.
- **Not leaving space for the executive's interpretation.** Delivering the conclusion instead of the data. Executives who reach their own conclusions show higher behaviour change than those who are told what to do.
- **Failing to repair.** When the executive pushes back and the system doubles down or goes silent. Must acknowledge, reframe, or explicitly defer.

### Generic advice that erodes trust
- **Non-specific observations.** "You seem stressed today" — every executive is stressed every day. Specificity is the currency of trust. "Your email response latency increased 340% after the board meeting" is specific.
- **Advice the executive already knows.** "Consider delegating more" — useless. "You've handled 14 of the 22 client escalations personally this month when your direct reports resolved the other 8 with 94% satisfaction" — shows the executive something they couldn't see.
- **Insight without temporal context.** "Your meeting load is heavy" vs "Your meeting density this week is 40% above your 90-day average, and the last time it hit this level you reported decision fatigue by Thursday." Temporal context makes generic observations specific.
- **Recommendations that ignore the executive's constraints.** The system must model what the executive can actually change, not what an ideal executive would do. Trust erodes when advice is technically correct but practically impossible.
