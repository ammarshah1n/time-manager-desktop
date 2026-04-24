# 01 — System Architecture

> **Partially superseded 2026-04-10 by `NO-COST-CAP-AUDIT.md` + `MASTER-PLAN.md`.**
> Pipeline cadence: this doc describes 6-phase real-time ingestion; current target is a 4-cron schedule (02:00 full, 05:15 refresh, 05:30 briefing, Sunday 03:00 weekly pruning). See `~/Timed-Brain/CLAUDE.md` "Pipeline Schedule Rules" for the authoritative cadence. All other layer descriptions remain current.
>
> **Updated 2026-04-03** from 14-report Deep Research synthesis.
> Detailed specs: `research/ARCHITECTURE-MEMORY.md`, `research/ARCHITECTURE-SIGNALS.md`, `research/ARCHITECTURE-DELIVERY.md`

## Mental Model: OS, Not App

Timed's architecture is an operating system for a person. Just as an OS manages
resources, memory, interrupts, and processes on a computer, Timed manages
cognitive resources, episodic records, contextual interrupts, and background
processes on a human.

## Four Functional Layers

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: DELIVERY                                          │
│  7-section morning briefing, real-time alerts (3/day cap),  │
│  voice interaction, adaptive format learning                │
│  Detail: research/ARCHITECTURE-DELIVERY.md §1-3             │
│  Cadence: on-demand + scheduled                             │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: REFLECTION ENGINE + PREDICTION                    │
│  6-phase nightly pipeline (Haiku→Sonnet→Opus),              │
│  4-gate pattern validation, BOCPD change detection,         │
│  avoidance/burnout/reversal prediction, CCR evaluation      │
│  Detail: research/ARCHITECTURE-MEMORY.md §2-6               │
│  Cadence: periodic (nightly + event-triggered)              │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: MEMORY STORE (5-tier)                             │
│  Tier 0: Raw Observation → Tier 1: Daily Summary →          │
│  Tier 2: Behavioural Signature → Tier 3: Personality Trait  │
│  + ACB (Active Context Buffer, always in LLM context)       │
│  Detail: research/ARCHITECTURE-MEMORY.md §1,3,7             │
│  Cadence: persistent, always available                      │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: SIGNAL INGESTION (30+ signals, 3 tiers)           │
│  Tier 1: Email + Calendar + App usage (weeks 1-4)           │
│  Tier 2: Keystrokes + Basic voice (weeks 5-10)              │
│  Tier 3: Neural voice + Multi-modal fusion (weeks 11+)      │
│  Detail: research/ARCHITECTURE-SIGNALS.md §1-8              │
│  Cadence: continuous, passive                               │
└─────────────────────────────────────────────────────────────┘
```

## Cross-Cutting Concerns

| Concern | Detail Location |
|---------|----------------|
| Privacy & Trust Architecture | `research/ARCHITECTURE-DELIVERY.md §5` |
| Cold Start Pipeline | `research/ARCHITECTURE-DELIVERY.md §6` |
| Cognitive Science Framework | `research/ARCHITECTURE-SIGNALS.md §6` |
| Swift/macOS Implementation | `research/ARCHITECTURE-DELIVERY.md §7` |
| Go-to-Market & Positioning | `research/ARCHITECTURE-DELIVERY.md §8` |

## The Compounding Feedback Loop

Signal Ingestion (30+ signals) → feeds Tier 0 Raw Observations →
Nightly 6-phase pipeline consolidates: Tier 0 → Tier 1 → Tier 2 → Tier 3 →
ACB updated with current executive model →
Delivery draws from ACB + retrieval across all tiers →
Human interaction (corrections, reactions) generates new signal →
Re-enters Layer 1.

**Intelligence compounds because higher memory tiers contain representations
that are structurally impossible without lower tiers having been built and
validated first. Month 6 is not month 1 with more data — it is a qualitatively
different system.**

## Layer 1: Signal Ingestion

> Full spec: `research/ARCHITECTURE-SIGNALS.md`

**Purpose:** Passively monitor and record 30+ signals across 5 modalities.
Does not interpret; only extracts features and writes Tier 0 observations.

**Signal Tiers (implementation order):**

| Tier | Signals | macOS APIs | Permissions | Timeline |
|------|---------|-----------|-------------|----------|
| 1 | Email metadata, calendar, app usage, idle time, first/last activity | Graph API, NSWorkspace, IOKit, CGEvent | OAuth (Mail.Read, Calendars.Read) | Weeks 1-4 |
| 2 | Keystroke dynamics (IKI, dwell, error rate, pauses, bigraphs), voice acoustics (F0, jitter, shimmer, HNR, MFCCs, speech rate, disfluency) | Accessibility API, AVAudioEngine + eGeMAPS/openSMILE | Accessibility, Microphone | Weeks 5-10 |
| 3 | Neural voice embeddings (WavLM), multi-modal fusion (CCLI, BEWI, RDS, DQEI) | Core ML, Bottleneck Transformer | Same as Tier 2 | Weeks 11+ |

**Key intelligence from signals:**
- 4 composite indices: Cognitive Load (CCLI), Burnout Early Warning (BEWI), Relationship Deterioration (RDS), Decision Quality (DQEI)
- ONA from email metadata (relationship graph, centrality, disengagement detection)
- Chronotype + energy model from activity timing + keystroke patterns
- 8 cognitive biases detectable from digital behaviour

**Existing code:** GraphClient, EmailSyncService, CalendarSyncService, VoiceCaptureService, VoiceResponseParser
**To build:** Keystroke dynamics service, voice feature extraction pipeline, ONA graph builder, energy model, multi-modal fusion

**Interface contract:**
```swift
protocol SignalIngestionService {
    func recordObservation(_ observation: Tier0Observation) async
}
```

## Layer 2: Memory Store (5-Tier)

> Full spec: `research/ARCHITECTURE-MEMORY.md §1, §3, §7`

**Purpose:** 5-tier persistent memory. Intelligence compounds because each tier
contains representations that are structurally impossible without the tier below.

| Tier | Name | Token Budget | Generated By | Embedding |
|------|------|-------------|-------------|-----------|
| 0 | Raw Observation | ~50 | Client (ingestion) | voyage-context-3 |
| 1 | Daily Summary | 200-400 | Haiku 3.5 | voyage-context-3 |
| 2 | Behavioural Signature | 500-1000 | Sonnet 4 | voyage-3-large |
| 3 | Personality Trait | 1000-2000 | Opus 4.6 | voyage-3-large |
| ACB | Active Context Buffer | ~2000 | Opus 4.6 | N/A (injected) |

**Key upgrades from v1 spec:**
- 5 tiers (was 3) — adds Raw Observation and Behavioural Signature as distinct levels
- Voyage AI embeddings (was Jina v3) — dual-model strategy for contextual vs factual
- HNSW indexes (was IVFFlat) — tier-tuned m parameters (16/24/32/48)
- 5-dimension retrieval (was 3-axis) — adds intent-awareness and temporal reasoning
- Bi-temporal trait model — `valid_from`/`valid_to` + `recorded_at` for contradiction handling
- Precision scalars on traits — cathartic update formula for 3 contradiction cases

**Retrieval:** 5-dimension composite scoring (recency, importance, relevance, recurrence, temporal_proximity) with intent-aware weight profiles per query type. Floor of 0.15 prevents stale-but-critical memories from disappearing.

**Existing code:** DataStore.swift, SupabaseClient.swift
**To build:** All 5 memory tier stores, retrieval engine, embedding pipeline

**Interface contract:**
```swift
protocol MemoryStore {
    func writeObservation(_ obs: Tier0Observation) async
    func retrieve(query: RetrievalQuery, intent: QueryIntent, limit: Int) async -> [ScoredMemory]
    func activeContextBuffer() async -> ACBSnapshot
}
```

## Layer 3: Reflection Engine + Prediction

> Full spec: `research/ARCHITECTURE-MEMORY.md §2, §4, §5, §6`

**Purpose:** The intelligence core. 6-phase nightly pipeline that consolidates
observations into compounding intelligence. Plus a prediction layer for
avoidance, burnout, and decision reversal forecasting.

**6-Phase Nightly Pipeline:**

| Phase | Model | Input | Output |
|-------|-------|-------|--------|
| 1. Importance Scoring | Haiku 3.5 | Unprocessed Tier 0 observations | importance_score + baseline_deviation |
| 2. Conflict Detection | Haiku 3.5 | New observations vs existing Tier 2/3 | Conflict tags (SUPPORTS / CONTRADICTS / NOVEL) |
| 3. Daily Summary | Sonnet 4 | Day's Tier 0 observations | Tier 1 daily summary with anomalies |
| 4. Pattern Detection | Sonnet 4 | Rolling Tier 1 summaries (14-day window) | Candidate Tier 2 behavioural signatures |
| 5. Deep Synthesis | Opus 4.6 (64K extended thinking) | Validated Tier 2 patterns + existing Tier 3 traits | Updated Tier 3 traits + ACB + predictions |
| 6. Pruning & Cleanup | Haiku 3.5 | All tiers | Archive low-value Tier 0, compress Tier 1 |

**Pattern Validation (4-gate protocol):**
1. Statistical significance (ARIMA-corrected Cohen's d_z ≥ 0.5)
2. Temporal stability (persists ≥ 14 days)
3. Contextual validity (not explained by external factors)
4. Psychological coherence (LLM judgment: does this make sense as a human pattern?)

**Prediction Layer:**
- Avoidance detection: 3-stream analysis + strategic delay discriminator
- Burnout forecasting: LSTM+XGBoost ensemble with triple gate (8-12 week lead time)
- Decision reversal: Cox hazards + 4-state HMM (T+4 to T+14 window)
- Evaluation: CCR (Compounding Capability Ratio) proves genuine compounding

**Change Detection:** BOCPD (Bayesian Online Change Point Detection) with 14-day quarantine before trait model updates.

**Existing code:** PlanningEngine, TimeSlotAllocator, InsightsEngine
**To build:** The entire 6-phase pipeline, prediction layer, evaluation framework

**Interface contract:**
```swift
protocol ReflectionEngine {
    func runNightlyPipeline() async -> NightlyResult
    func predictAvoidance(for profile: UUID) async -> [AvoidanceAssessment]
    func predictBurnout(for profile: UUID) async -> BurnoutAssessment
    func evaluateCompounding(for profile: UUID) async -> CompoundingMetrics
}
```

## Layer 4: Delivery

> Full spec: `research/ARCHITECTURE-DELIVERY.md §1-4`

**Purpose:** Convert intelligence into language and format the executive engages
with, acts on, and never ignores. Three delivery modes with distinct design rules.

**Morning Briefing (7 sections, ~610 words, CIA PDB design):**
1. Lead Insight (BLUF) — single highest-salience item
2. Calendar Intelligence — today's schedule risks and opportunities
3. Email Pattern Analysis — overnight shifts, relationship signals
4. Decision Quality Observations — yesterday's patterns (optional)
5. Cognitive Load Forecast — energy curve + chronotype-aware scheduling
6. Emerging Patterns — multi-week trends, avoidance, relationship dynamics
7. Recency Anchor — forward-looking question that travels with the executive

**Real-Time Alerts:**
- 5-dimension scoring: salience × confidence × time-sensitivity × actionability × cognitive state
- Hard cap: 3 alerts/day (above this → alarm fatigue, trust erosion)
- 23m15s recovery cost per interruption — only interrupt when value exceeds this

**Voice Interaction:**
- Routine briefings: measured pace, formal-conversational tone
- Uncomfortable insights: Motivational Interviewing framing, text beats voice for hardest truths
- TTS: OpenAI TTS-HD primary, AVSpeechSynthesizer offline fallback

**Coaching Integration:**
- Trust calibration: 4 stages (Days 1-30 through 180+)
- No challenging insights before Day 90
- Max 1 uncomfortable observation per briefing
- 3-attempt cap on acknowledged-but-unchanged patterns

**Existing code:** MorningInterviewPane, MenuBarManager, CommandPalette, all feature panes
**To build:** Intelligence briefing engine, alert system, voice delivery, coaching layer

**Interface contract:**
```swift
protocol IntelligenceDelivery {
    func prepareMorningBriefing() async -> MorningBriefing
    func evaluateAlertCandidates() async -> [AlertDecision]
    func respondToQuery(_ query: String, mode: DeliveryMode) async -> IntelligenceResponse
}
```

## Layer Isolation Rules

1. Signal Ingestion NEVER reads from Memory Store (it only writes)
2. Memory Store NEVER calls Reflection Engine (it only stores and retrieves)
3. Reflection Engine reads from Memory Store, writes back to Memory Store
4. Delivery reads from Memory Store and Reflection Engine output
5. Human corrections flow through Signal Ingestion back into episodic memory
6. No layer imports another layer's internal types — only interface protocols
