# ARCHITECTURE-SIGNALS.md — Signal Ingestion & Cognitive Science Layer

Definitive specification for everything Timed observes, how it extracts intelligence, and what cognitive models it builds. Synthesised from extractions 02, 04, 07, 08, and 09.

Last updated: 2026-04-03

---

## 1. Complete Signal Taxonomy

### Master Signal Table

| Signal | Source | macOS API / Integration | Extraction Method | What It Encodes | Validated Accuracy | Permission Required | Tier |
|--------|--------|------------------------|-------------------|-----------------|-------------------|-------------------|------|
| **Email response latency** (by sender, time-of-day, thread depth) | Outlook | Microsoft Graph `/me/messages` (delta) | Match reply to parent via `conversationId`; latency = sent(reply) − received(parent); per-sender rolling distribution (mean, P50, P90) | Relationship priority, cognitive load, avoidance, decision confidence | Predicts turnover/relationship deterioration (longitudinal, statistically significant) | `Mail.Read` (OAuth) | 1 |
| **Thread topology** (depth, branching, CC additions) | Outlook | Graph API: thread IDs, recipients per message | Track CC additions within threads; flag threads where participant count increases by >2 (escalation) | Decision-making style, escalation patterns, organisational dynamics | — | `Mail.Read` | 1 |
| **Communication reciprocity** (initiation vs response ratio) | Outlook | Graph API: sender/recipient fields | Per-dyad initiation ratio; flag asymmetry outside 0.35–0.65 range | Power dynamics, influence, isolation risk | 87.58% accuracy for dominance pair classification from metadata alone | `Mail.Read` | 1 |
| **Send-time distribution** (after-hours, weekends, circadian) | Outlook | Graph API: sentDateTime | Bin send-times into hourly buckets; fit circadian model; compute weekly after-hours ratio | Chronotype, cognitive peak, work-life boundary erosion, burnout risk | Single best burnout predictor (52,190-email, 5-month study) | `Mail.Read` | 1 |
| **Email volume trends** (daily/weekly) | Outlook | Graph API: message count + timestamps | Rolling daily/weekly count; pair with latency for meaning | Executive overwhelm, coping strategy (batch vs continuous) | — | `Mail.Read` | 1 |
| **Subject line metadata** (length, question frequency, urgency markers) | Outlook | Graph API: subject field | Parse for RE:, URGENT, FYI, ?, length | Communication urgency, decisiveness | — | `Mail.Read` | 1 |
| **Meeting density + fragmentation** | Outlook Calendar | Graph API: `/me/calendarView` (delta) | Compute MLI, FBR, BTBCI, fragmentation index (see §2) | Maker vs manager time, context-switch cost, deep work availability | 23 min average recovery per context switch (Mark et al.) | `Calendars.Read` | 1 |
| **Meeting cancellation + modification rate** | Outlook Calendar | Graph API: event modifications, isCancelled, lastModifiedDateTime | Track cancellations, rescheduling, last-minute changes (<2hr before start) | Overcommitment, prioritisation failure, avoidance | — | `Calendars.Read` | 1 |
| **Meeting composition** (size, internal/external, 1:1/group) | Outlook Calendar | Graph API: attendees list, organizer field | Classify events by attendee count, internal/external domain, organiser | Leadership style, delegation, isolation risk | — | `Calendars.Read` | 1 |
| **Calendar compression** (density trend over weeks) | Outlook Calendar | Graph API: event density time series | 12-week rolling average; slope computation for meeting inflation | Burnout early warning, strategic drift | — | `Calendars.Read` | 1 |
| **App usage** (active app, duration, switch frequency) | macOS | `NSWorkspace.shared.notificationCenter` (`didActivateApplicationNotification`), `frontmostApplication`, `bundleIdentifier` | Log app switches with timestamps; categorise by domain; compute switch frequency per 30-min window | Attention allocation, distraction patterns, context-switching cost | — | None | 1 |
| **First/last keyboard activity** (daily) | macOS | `CGEvent` tap (Accessibility API) — timestamps only | Record daily first and last keyDown timestamps; separate weekdays/weekends | Chronotype inference (r = 0.74–0.80 with sleep onset/offset) | r = 0.74–0.80 correlation with sleep timing | Accessibility (`kTCCServiceAccessibility`) | 1 |
| **Keystroke inter-key interval (IKI)** | macOS | Accessibility API (`CGEvent.tapCreate`) | Capture keyDown/keyUp timestamps (never key values); compute IKI per keystroke; aggregate into 60s windows | Cognitive load (longer IKI = higher load), fatigue | Reliable with personal calibration; cross-subject fails (CMU, n=116) | Accessibility | 2 |
| **Keystroke dwell time + flight time** | macOS | Accessibility API | Key hold duration; time between key release and next press | Hesitation, motor fatigue | — | Accessibility | 2 |
| **Backspace/error rate** | macOS | Accessibility API | backspace_count / total_keystrokes per window | Decision uncertainty, cognitive interference | — | Accessibility | 2 |
| **Typing speed (WPM)** | macOS | Accessibility API | Words per minute rolling average per 60s window | Flow state vs distraction, fatigue onset | — | Accessibility | 2 |
| **Pause patterns** (>2s gaps) | macOS | Accessibility API | Count and total duration of pauses >2000ms per window; disambiguate with app context | Deep thought vs distraction | — | Accessibility | 2 |
| **Bigraph latencies** (top-20 character pairs) | macOS | Accessibility API | Track latencies for th, he, in, er, etc.; most stable personal fingerprint | Personal calibration anchor; most sensitive to cognitive state changes | — | Accessibility | 2 |
| **F0 (pitch) mean, variance, contour** | Microphone | AVAudioEngine → eGeMAPS (openSMILE via C++ bridge) | Autocorrelation or YIN algorithm on 25ms frames, 10ms hop; aggregate per utterance | Emotional valence, stress, confidence, engagement | ~70% population; higher with personal baseline; F0 stress SMD=0.55 | Microphone (`kTCCServiceMicrophone`) | 2 |
| **Jitter** (F0 cycle-to-cycle variation) | Microphone | AVAudioEngine → eGeMAPS | eGeMAPS jitter_local; cycle-to-cycle F0 variation | Chronic stress, fatigue, cognitive decline | Tracks episodic memory over 10 years (Framingham); normal <1.04% | Microphone | 2 |
| **Shimmer** (amplitude variation) | Microphone | AVAudioEngine → eGeMAPS | eGeMAPS shimmer_local; cycle-to-cycle amplitude variation | Stress, emotional regulation, vocal fatigue | Normal <3.81%; fatigue increases shimmer | Microphone | 2 |
| **HNR** (harmonics-to-noise ratio) | Microphone | AVAudioEngine → eGeMAPS | eGeMAPS HNR extraction | Voice quality degradation under stress/fatigue | Validated in clinical voice assessment | Microphone | 2 |
| **Speaking time ratio + turn-taking** | Microphone | AVAudioEngine → VAD segmentation | Segment audio into user/other/silence; compute speaking ratio, turn count, interruptions (overlap >200ms) | Power dynamics, rapport, meeting effectiveness | — | Microphone | 2 |
| **MFCCs** (coefficients 1–13) | Microphone | AVAudioEngine → Accelerate (vDSP) FFT → Mel filterbank → DCT | 25ms frames, 10ms hop; lower coefficients (1–5) carry more emotional info | Speaker state classification foundation | Foundation for most SER models | Microphone | 2 |
| **Speech rate** (syllables/sec) + variance | Microphone | Whisper word timestamps → syllable estimation | Rolling window stats; acceleration = anxiety/excitement, deceleration = fatigue/deliberation | Cognitive load, engagement/disengagement | Moderate; confounded by topic complexity | Microphone | 2 |
| **Disfluency rate** (um/uh per minute) | Microphone | Whisper transcription → disfluency token detection + pause analysis | Count disfluency tokens; compare to personal baseline (~6 per 100 words population avg) | Cognitive overload, uncertainty, word-finding difficulty | Baseline-dependent; 3x individual variation | Microphone + Speech Recognition (`kTCCServiceSpeechRecognition`) | 2 |
| **Spectral centroid** | Microphone | AVAudioEngine → vDSP FFT → weighted frequency mean | Per-frame spectral centroid; aggregate per utterance | Voice brightness/energy; lower = fatigue/sadness | Moderate as supplementary feature | Microphone | 2 |
| **Formant frequencies** (F1–F3) | Microphone | eGeMAPS or LPC analysis | Per-utterance formant extraction; reduced formant space = fatigue | Articulatory precision; longitudinal deviation from baseline required | Requires personal baseline | Microphone | 2 |
| **F0 terminal contour** (rising vs falling) | Microphone | Prosodic contour analysis on utterance-final segments | Classify final intonation pattern; falling = assertion/confidence, rising = uncertainty/hedge | Confidence/certainty detection | Well-validated linguistically | Microphone | 2 |
| **System/device idle time** | macOS | IOKit: `IOServiceGetMatchingService` for `IOHIDSystem` | Poll every 60s; inactivity >10 min = break candidate | Break detection for energy model recovery | — | None | 1 |
| **WavLM/HuBERT neural embeddings** | Microphone | Core ML (quantised INT8 WavLM Large) | Raw waveform → 24-layer hidden representations → layers 12–24 → mean-pool → 768/1024-dim embedding | Deep emotion/cognitive state features beyond hand-crafted acoustics | Arousal CCC ~0.80; Valence CCC ~0.734 (ensemble); executive speech UNKNOWN | Microphone | 3 |
| **Advanced longitudinal voice tracking** | Microphone | Core ML + eGeMAPS | 90-day personal model: stress signature discovery, context-specific baselines, fine-tuned WavLM head | Personal vocal biomarker library; predictive state modelling | Months 4–12 capability milestones (see §4) | Microphone | 3 |
| **Full multi-modal fusion indices** (CCLI, BEWI, RDS, DQEI) | All sources | Multimodal Bottleneck Transformer (Core ML) | Late fusion of 5 modality embeddings via 4–8 bottleneck tokens; composite index heads (see §7) | Composite cognitive load, burnout risk, relationship deterioration, decision quality | Requires 3+ modalities agreeing; convergent validity threshold | All above | 3 |

### Implementation Sequencing

**Tier 1 — Implement first (weeks 1–4):** Email metadata (Graph API), calendar structure (Graph API), app usage (NSWorkspace), first/last activity timestamps, system idle time. These require only OAuth + zero macOS permissions beyond standard. Highest intelligence-per-engineering-effort.

**Tier 2 — Implement second (weeks 5–10):** Keystroke dynamics (Accessibility API), basic voice features (AVAudioEngine + eGeMAPS/openSMILE), VAD + conversational dynamics. Require Accessibility and Microphone permissions. Enable cognitive load, fatigue, and energy modelling.

**Tier 3 — Implement third (weeks 11+):** WavLM/HuBERT neural embeddings, advanced longitudinal voice tracking, full multi-modal fusion via Bottleneck Transformer. Require months of accumulated personal baseline data to become meaningful. Deliver compound intelligence.

---

## 2. Email & Calendar Intelligence

### 2.1 Organisational Network Analysis (ONA)

Architecture: directed multigraph from email metadata. Nodes = people. Edges = communication events (one edge per email, preserving directionality).

Theoretical foundations: Rob Cross ONA (UVA) — map information flow, not org chart; Aral & Van Alstyne diversity-bandwidth tradeoff; Pentland social physics; Gloor "honest signals"; Burt structural holes; Granovetter weak ties.

#### Node Schema

```
ona_nodes:
  id: uuid (PK)
  email: text (unique, canonical identifier)
  display_name: text
  inferred_role: text (nullable)
  inferred_organisation: text (nullable)
  inferred_department: text (nullable)
  first_seen_at: timestamptz
  last_seen_at: timestamptz
  total_emails_sent: int           -- to executive
  total_emails_received: int       -- from executive
  avg_response_latency_ms: float   -- to executive's emails
  communication_frequency: float   -- emails/week, rolling 4-week
  importance_tier: int (1-5)       -- computed from centrality + frequency + executive context
  degree_centrality: float
  in_degree_centrality: float
  out_degree_centrality: float
  betweenness_centrality: float
  closeness_centrality: float
  eigenvector_centrality: float
  pagerank: float
  relationship_health_score: float (0-100)
  health_trend: text               -- 'improving' | 'stable' | 'declining' | 'critical'
  last_computed_at: timestamptz
```

#### Edge Schema

```
ona_edges:
  id: uuid (PK)
  from_node_id: uuid (FK → ona_nodes)
  to_node_id: uuid (FK → ona_nodes)
  direction: text                  -- 'sent' | 'received'
  timestamp: timestamptz
  response_latency_ms: int (nullable)
  thread_id: text
  thread_depth: int
  recipient_position: text         -- 'to' | 'cc' | 'bcc'
  is_initiated: boolean            -- first message in thread from this sender
  has_attachment: boolean
  message_graph_id: text           -- Microsoft Graph message ID for dedup
  created_at: timestamptz
```

#### Centrality Metrics — Executive Interpretation

| Metric | Formula Context | What It Tells the Executive |
|--------|----------------|----------------------------|
| **Degree centrality** (in + out) | Raw communication volume | Who is over-relied-upon (hub identification) |
| **In-degree centrality** | Received communication volume | High in-degree + low response = bottleneck |
| **Out-degree centrality** | Initiated communication volume | High out-degree = information broadcaster or micromanager |
| **Betweenness centrality** | Shortest-path intermediary count | Single points of failure; if this person leaves, communication paths break (Cross's primary ONA finding) |
| **Closeness centrality** | Inverse distance to all nodes | Low closeness = emerging silo risk |
| **Eigenvector centrality** | Connected to well-connected people | Influence through network position, not title; maps "who actually drives decisions" |
| **PageRank** | Directed eigenvector variant | Whose attention is disproportionately sought; high PageRank + no formal authority = hidden influencer |

#### Graph Computation Cadence

- Degree centrality: recomputed every ingest batch
- Betweenness, eigenvector, PageRank: recomputed daily
- Entity resolution (alias dedup, role inference): on each batch via Haiku
- Path-finding and transitive closure: PostgreSQL recursive CTEs (network is hundreds to low-thousands of nodes — no graph DB needed)

#### Graph Storage

Supabase Postgres with recursive CTEs. Rationale: single-executive network is small (hundreds to low-thousands of nodes). Reserve Neo4j only if network exceeds ~50K nodes. Use pgvector for embedding-based similarity search on relationship patterns, not graph traversal.

### 2.2 Relationship Health Scoring

Every dyadic relationship scored 0–100 combining:

```
relationships:
  id: uuid (PK)
  executive_id: uuid (FK)
  contact_node_id: uuid (FK → ona_nodes)
  relationship_type: text          -- 'direct_report' | 'peer' | 'superior' | 'external' | 'inferred'
  strength: float (0-1)           -- after decay applied
  raw_strength: float (0-1)       -- before decay
  decay_rate: float               -- personalised per relationship
  reciprocity_ratio: float        -- 0.5 = balanced; outside 0.35-0.65 = flag (Avrahami & Hudson)
  response_latency_z: float       -- RTL_z per dyad vs own baseline (NOT global average)
  thread_depth_avg: float         -- rolling 4-week
  thread_depth_trend: float       -- slope; shortening = transactional, lengthening = deepening or escalating
  cc_inclusion_rate: float
  dependency_direction: text       -- 'executive_depends' | 'contact_depends' | 'mutual' | 'unclear'
  communication_channel_mix: jsonb -- {"email": 0.7, "calendar": 0.3}
  last_interaction_at: timestamptz
  days_since_contact: int
  maintenance_alert_threshold_days: int  -- 2x natural inter-contact interval
  rdi_score: float                -- Relationship Disengagement Index (0-1)
  sws_score: float                -- Selective Withdrawal Score (0-1)
  health_score: float (0-100)
  health_trajectory: float[]      -- last 12 weekly scores
  is_dormant: boolean
  is_strategically_important: boolean    -- executive-flagged or inferred
  updated_at: timestamptz
```

#### Relationship Decay Functions

**Primary — Burt's power function:** `Y = (T + 1) ^ (gamma + kappa * KIN + lambda * WORK)` where T = days since last contact, KIN/WORK = relationship type indicators. Fits 95% of variance across 19 studies.

**Fallback — Exponential decay:** `strength = initial_strength * e^(-lambda * days_since_contact)` where lambda is personalised from historical contact frequency.

**Alerting — Step function:** Active (<14 days) → Cooling (14–30) → At Risk (30–60) → Dormant (>60). Thresholds personalised from executive's own cadence per relationship. Alert at 2x the natural inter-contact interval.

### 2.3 Disengagement Detection

**RDI (Relationship Disengagement Index)** — five weighted components:
- Response rate decline: weight 0.25
- Response latency increase: weight 0.25
- Initiated contact decline: weight 0.20
- CC inclusion decline: weight 0.15
- Meeting participation decline: weight 0.15

Thresholds: RDI > 0.4 over 4+ weeks = flag. RDI > 0.6 = high-confidence disengagement.

**SWS (Selective Withdrawal Score)** — distinguishes disengagement from busyness:
- Compute person's response metrics toward executive AND toward other visible contacts
- If metrics decline only toward executive: SWS high → selective disengagement
- If declining globally: SWS low → general busyness/overload
- `SWS = |RDI_toward_executive - RDI_toward_others| / max(RDI_toward_executive, RDI_toward_others)`

**Executive self-disengagement:** Same RDI computation measuring executive's own patterns toward each contact. Flag when executive's latency to contact X is >1.5 sigma above their own mean and trending upward — unconscious avoidance of strategically important relationship.

**Key quiet quitting signature:** 39% lower response rates (Chen et al., 847-worker study).

**Temporal requirements:** 12-week baseline before any detection activates. Minimum 4 weeks of declining trend to flag.

### 2.4 Calendar Analytics

#### Daily Metrics Schema

```
calendar_daily_metrics:
  date: date
  total_meetings: int
  total_meeting_minutes: int
  mli: float                       -- Meeting Load Index (meeting hours / available hours)
  fbr: float                       -- Focus Block Ratio (blocks >= 90min / total available)
  btbci: float                     -- Back-to-Back Chain Index (longest consecutive chain in hours)
  oar: float                       -- Organiser-Attendee Ratio (organised / attended)
  str: float                       -- Strategic Time Ratio (self-scheduled / total)
  attendee_entropy: float          -- Shannon entropy of attendee distributions
  attendee_drift: float            -- composition change vs 4-week baseline
  rmd: float                       -- Recurring Meeting Decay (% of recurring meetings held)
  calendar_health_score: float     -- 0-100 weighted composite
  fragmentation_index: float       -- context switches / available hours
  meetings_cancelled: int
  meetings_declined: int
  meetings_added_reactively: int   -- added < 24h before start
```

#### Calendar Health Score (CHS)

`CHS = 0.25 * MLI_norm + 0.25 * FBR_norm + 0.15 * BTBCI_norm + 0.20 * STR_norm + 0.15 * fragmentation_norm`

Normalisation (100 = optimal):
- MLI_norm: 100 when MLI < 0.4; 0 when MLI > 0.8
- FBR_norm: 100 when FBR > 0.3; 0 when FBR = 0
- BTBCI_norm: 100 when max chain < 2h; 0 when > 5h
- STR_norm: 100 when STR > 0.3; 0 when < 0.05
- fragmentation_norm: 100 when < 4 switches/day; 0 when > 12

**Meeting inflation detection:** Slope of weekly total_meeting_hours over rolling 12 weeks. Slope > 0.5 hours/week sustained for 4+ weeks = statistically significant inflation. Detectable after 8 weeks of data.

**Calendar density thresholds (personalised — not absolute):**
- MLI > 0.6 = cognitive overload zone
- MLI > 0.8 = crisis territory
- FBR < 0.1 = deep work impossible
- BTBCI > 4 hours = cognitive fatigue threshold

### 2.5 Email Metadata Feature Schema

```
EmailSignalRecord {
  message_id: String
  thread_id: String                -- conversationId
  timestamp_sent: DateTime
  timestamp_received: DateTime
  timestamp_read: DateTime?
  sender: ContactHash              -- hashed identifier
  recipients_to: [ContactHash]
  recipients_cc: [ContactHash]
  recipients_bcc: [ContactHash]
  subject_length: Int
  subject_has_question: Bool
  subject_urgency_markers: [String]  -- RE:, URGENT, FYI, etc.
  thread_depth: Int
  thread_participants_added: Int   -- CC escalation count
  is_after_hours: Bool             -- based on learned schedule
  response_latency_seconds: Int?
  folder_action: String?           -- moved to archive, flagged, etc.
}
```

### 2.6 Email Processing Pipeline

1. **Ingest** — Poll Graph API `/me/messages` delta endpoint every 5 minutes.
2. **Entity resolution** — Deduplicate contacts by email; resolve aliases (Haiku); upsert `ona_nodes`; insert `ona_edges`.
3. **Response latency computation** — Match reply to parent via `conversationId`. Store per-sender rolling distribution (mean, P50, P90).
4. **Norm violation detection** — Z-score against sender's historical latency distribution. Flag |z| > 2.0. Positive z = delayed (avoidance/overload); negative z = unusually fast (urgency/anxiety).
5. **Network topology** — Build ego-network graph monthly. Compute all seven centrality metrics.
6. **Temporal pattern extraction** — Bin send-times hourly; fit circadian model; flag after-hours deviation.
7. **Thread escalation detection** — Track CC additions within threads. Flag participant count increase > 2.

### 2.7 Communication Pattern Anomaly Detection

- 12-week learning window (hard requirement — no anomaly scores before this)
- Per-dyad baseline: mean + std of weekly email count, response latency, thread depth, reciprocity ratio
- Anomaly score: number of standard deviations from baseline per metric
- Compound anomaly: 3+ metrics for same dyad simultaneously > 1.5 sigma = high-priority flag
- Communication burst detection: > 3 sigma spike in 48-hour window with specific person → correlate with calendar

---

## 3. Keystroke Dynamics Pipeline

### 3.1 Capture

Register global event tap via Accessibility API (`CGEvent.tapCreate`). Capture keyDown/keyUp timestamps only. **Never capture key values — this is a trust boundary enforced in code, not policy.** The callback extracts timestamps and discards `keyCode`/`characters` fields.

**Privacy constraint is absolute:** If the executive discovers key logging, the product is dead.

### 3.2 Feature Schema

```
KeystrokeWindow {
  window_start: DateTime
  window_end: DateTime
  window_duration_ms: Int          -- 60-second non-overlapping windows
  active_app: String
  total_keystrokes: Int
  mean_iki_ms: Float               -- inter-key interval
  std_iki_ms: Float
  median_iki_ms: Float
  mean_dwell_ms: Float             -- key hold time
  mean_flight_ms: Float            -- release-to-next-press
  error_rate: Float                -- backspace_count / total_keystrokes
  pause_count: Int                 -- pauses > 2000ms
  pause_total_ms: Int
  wpm: Float
  bigraph_latencies: [String: Float]  -- top-20 bigraph mean latencies
}
```

### 3.3 Processing Pipeline

1. **Windowing** — Aggregate raw timestamps into 60-second non-overlapping windows. Compute statistical moments: mean, std, median, skewness of IKI and dwell distributions.
2. **Baseline calibration** — First 14 days = calibration period. Compute personal baseline distributions. After calibration, all features expressed as z-scores against personal baseline.
3. **Cognitive load signal** — Composite of z-scores: `cognitive_load = 0.40 * iki_z + 0.35 * error_rate_z + 0.25 * pause_frequency_z`
4. **Bigraph calibration** — Track latencies for top-20 most frequent character bigraphs (th, he, in, er, etc.). Most stable personal fingerprint; most sensitive to cognitive state changes.
5. **Fatigue detection** — AUC 72–80% from typing dynamics. Key features: IKI (mean, variance), hold time, flight time, backspace rate. Disambiguate flow vs fatigue: flow = velocity stable/rising + error rate stable; fatigue = velocity declining + error rate rising.

### 3.4 macOS API Detail

| API | Usage | Entitlement |
|-----|-------|-------------|
| `CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)` | Global event tap for keyDown/keyUp timestamps | Accessibility (`kTCCServiceAccessibility`) |
| `AXIsProcessTrusted()` | Check if permission granted | None |
| `NSWorkspace.shared.frontmostApplication` | Correlate keystrokes with active app | None |

**Permission flow:** App must be added to System Preferences > Privacy > Accessibility. Prompt user on first launch. Cannot be granted programmatically — user must manually navigate and toggle.

**No App Sandbox:** Accessibility event taps are incompatible with App Sandbox. Timed must be distributed outside Mac App Store (developer ID + notarisation). This is a hard architectural constraint.

### 3.5 Validated Numbers

- Intra-subject stress detection: reliable with personal calibration (CMU, n=116). Cross-subject = near-chance.
- Minimum calibration: 14 days of normal typing
- Cognitive load effect: IKI increases 15–40% under high load (varies by individual)
- Reliable inference window: 60-second minimum for stable IKI statistics; 5-minute for error rate
- Fatigue classification: AUC 72–80%

---

## 4. Voice Analysis Pipeline

### 4.1 On-Device Architecture

```
Stage 1: CAPTURE
  AVAudioEngine.inputNode.installTap(bufferSize: 4096, format: 16kHz mono)
  → Circular buffer (30s default, overwrite-on-full)
  → VAD gate: only process voiced segments (saves ~60-70% processing)

Stage 2: FEATURE EXTRACTION (parallel paths)
  Path A — eGeMAPS (interpretable):
    Audio buffer → vDSP (Accelerate framework) for FFT
    → 88 eGeMAPS features per frame (25ms window, 10ms hop):
       F0, jitter, shimmer, HNR, formants (F1-F3), MFCCs (1-13),
       spectral centroid, speech rate, loudness
    → Aggregate per utterance: mean, std, percentiles (20th, 50th, 80th)
    → Output: VoiceFeatureVector (88 dimensions + aggregates)

  Path B — Neural embeddings:
    Audio buffer → Core ML WavLM Large (quantised INT8, ~300MB)
    → Layers 12-24 representations (emotion-salient)
    → Mean-pool across time
    → Output: EmbeddingVector (768 or 1024 dim)

  Path C — Transcription (on-demand, not continuous):
    Audio buffer → Whisper-large-v3 (Core ML, ~800MB) OR SFSpeechRecognizer (on-device)
    → Word-level timestamps + confidence scores
    → Disfluency token detection (um, uh, false starts)
    → Output: TranscriptionResult

Stage 3: MODEL INFERENCE
  VoiceFeatureVector + EmbeddingVector → Core ML emotion classifier
    → Dimensional: [arousal, valence, dominance] (continuous)
    → Categorical: probability distribution over
       {fatigue, stress, confidence, engagement, frustration, clarity}
  TranscriptionResult → Rule-based linguistic analysis
    → Hedging frequency, question ratio, assertive language ratio

Stage 4: STATE ESTIMATION
  Merge dimensional + categorical + linguistic
  → Compare against personal rolling baseline
  → Compute deviation z-scores
  → Output: CognitiveStateEstimate {
       states: [StateProbability],      // e.g. fatigue: 0.72
       confidence: Float,
       deviationFromBaseline: Float,
       timestamp: Date
     }
  → THIS is what leaves the device. Everything upstream is discarded.
```

### 4.2 Acoustic Features — What Each Encodes

| Feature | What It Indicates | Normal Range | Signal Behaviour |
|---------|------------------|-------------|-----------------|
| **F0 mean** | Arousal/stress — higher = higher activation | Person-dependent | SMD=0.55 for stress |
| **F0 variance** | Emotional intensity; low = suppressed/controlled | Person-dependent | Reliable for arousal; confounded by speaking style |
| **F0 terminal contour** | Falling = assertion/confidence; Rising = uncertainty/hedge | — | Well-validated linguistically; directly actionable |
| **MFCCs (1-13)** | Speaker state classification; lower coefficients carry more emotional info | — | Foundation for SER models; not interpretable alone |
| **Speech rate** | Acceleration = anxiety/excitement; deceleration = fatigue/deliberation | ~150 wpm English | Moderate; confounded by topic complexity |
| **Speech rate variance** | Monotone = disengagement; variable = engaged or agitated | Person-dependent | Requires personal baseline |
| **Jitter** | Vocal tension, stress, fatigue | <1.04% (normal) | >1.04% = pathological; stress elevates within normal range |
| **Shimmer** | Vocal fatigue, respiratory | <3.81% (normal) | Fatigue increases shimmer |
| **Disfluency rate** | Cognitive overload, uncertainty | ~6 per 100 words (population avg) | 3x individual variation; personal baseline is the signal |
| **Pause structure** | Silent before content words = retrieval difficulty; filled (um/uh) = planning | — | Requires longitudinal baseline |
| **Spectral centroid** | Voice brightness; lower = fatigue/sadness | Person-dependent | Supplementary feature |
| **HNR** | Voice clarity; lower = breathy/strained | Person-dependent | Validated clinically |
| **Formant frequencies (F1-F3)** | Articulatory precision; reduced space = fatigue | Person-dependent | Longitudinal deviation required |

### 4.3 Model Selection Per Cognitive State

| Target State | Primary Model | Accuracy (Naturalistic) | On-Device Feasible | Fallback |
|-------------|--------------|------------------------|-------------------|----------|
| **Cognitive fatigue** | WavLM Large + eGeMAPS (jitter, shimmer, speech rate decline, HNR drop) | Clinical ~75-80% sensitivity; exec speech UNKNOWN | Yes (quantised Core ML) | eGeMAPS longitudinal deviation |
| **Stress/arousal** | WavLM Large fine-tuned MSP-Podcast (arousal dimension) | CCC ~0.75-0.80 (MSP-Podcast); F0 SMD=0.55 | Yes | eGeMAPS F0 mean + variance + jitter |
| **Confidence/uncertainty** | Prosodic contour (F0 terminal) + disfluency rate + speech rate | No unified benchmark; linguistically validated | Yes (rule-based + lightweight model) | Whisper → linguistic hedging detection |
| **Engagement/disengagement** | Speech rate variance + F0 variance + response latency | Research-validated features | Yes | Silence ratio + backchannel frequency |
| **Frustration** | WavLM (high arousal + negative valence) + speech rate increase + F0 spike | Valence CCC ~0.55-0.73 (hard problem) | Yes | eGeMAPS arousal features + disfluency spike |
| **Mental clarity** | Composite: low disfluency + stable rate + normal F0 variance + high HNR | No benchmark; inferred from absence of degradation | Yes (composite of other detectors) | Baseline = clarity |

### 4.4 Fusion Within Voice Pipeline

Late fusion of WavLM and eGeMAPS outputs:
- Weights learned during domain adaptation phase
- **Conflict resolution:** When models disagree, report lower confidence and bias toward eGeMAPS (more stable for longitudinal tracking)
- Personal calibration layer subtracts rolling baseline and applies personal scaling factors from first 30 days

### 4.5 Longitudinal Baseline Building

**Days 1–7:** Collect raw feature distributions. Store per-session mean, std, min, max for all 88 eGeMAPS features + WavLM embedding centroid. Minimum: 10 sessions of 5+ minutes voiced speech.

**Days 8–30:** Build stable baseline. Rolling mean + std per feature. Personal range (5th–95th percentile). Flag outlier sessions (>2 std). Compute personal covariance matrix.

**Day 31+ (ongoing deviation detection):**
1. Extract features per session
2. Z-score per feature against personal rolling baseline
3. Composite deviation: `0.20 * F0_variance_z + 0.15 * speech_rate_z + 0.15 * jitter_z + 0.15 * disfluency_z + 0.10 * shimmer_z + 0.10 * HNR_z + 0.15 * spectral_z`
4. Composite > 1.5 std → "notable state change"
5. Composite > 2.0 std → "significant — consider alerting"

**Baseline drift (adaptive):** 90-day rolling window with exponential decay. If 5+ consecutive sessions show same-direction deviation, trigger recalibration review.

### 4.6 Personal Voice Model Adaptation Timeline

| Month | Capability | Confidence |
|-------|-----------|------------|
| 1 | Personal feature ranges. Population model + personal offset. Basic deviation detection. | Low-moderate |
| 2–3 | Stress signatures discovered. Context-specific baselines (meeting vs dictation). Time-of-day patterns. Few-shot WavLM fine-tuning (~100 validated segments). | Moderate |
| 4–6 | Decision-state correlation. Cross-modal convergence (voice + email + calendar). Predictive engagement modelling. | Moderate-high |
| 7–12 | Predictive state modelling. Personal vocal biomarker library. Health change detection. Conversation evolution tracking. | High (established); Experimental (health) |

### 4.7 Privacy Architecture

- **Raw audio:** Never leaves device, never persisted beyond circular processing buffer
- **Transcripts:** On-device only (Whisper local or Apple Speech on-device mode), never sent to backend
- **What leaves device:** State probability vectors (e.g. `{fatigue: 0.72, stress: 0.45}`) and aggregate acoustic statistics (mean F0, speech rate, disfluency count per session)
- **Audio buffers:** Circular, configurable retention (default: 0 — discard immediately after extraction)
- **Legal:** One-party consent jurisdictions: executive records own meetings. Two-party consent: require all-party notification. App must surface jurisdiction-aware consent flow.
- **Multi-party meetings:** Default to processing only the executive's own speech. Consider acoustic source separation to isolate executive's voice.
- **Executive speech caveat:** C-suite executives practice vocal control (suppressed expression, measured pace). Off-the-shelf models will systematically underestimate arousal and overestimate confidence. Domain adaptation required from day 1. No published study validates SER on executive speech.

### 4.8 On-Device Processing Budget (Apple Silicon)

| Operation | Latency (M1/M2/M3) | Battery Impact |
|-----------|-------------------|----------------|
| eGeMAPS extraction (88 features/utterance) | <5ms | Negligible (CPU via Accelerate/vDSP) |
| WavLM Large inference (3s audio, INT8) | 50–100ms | ~2-3% additional drain over 8hr continuous |
| Whisper-large-v3 transcription (30s audio) | 3–8s | Moderate; trigger selectively on voiced segments |
| Full pipeline (capture + features + inference) | <200ms per utterance | 3-5% total for continuous monitoring |

---

## 5. Chronobiology & Energy Model

### 5.1 Chronotype Inference

**Primary signal (Tier 1):** First/last keyboard activity timestamps. Correlation with sleep onset/offset: r = 0.74–0.80. Use GRSVD method to extract diurnal rhythms from typing patterns.

**Secondary signal (Tier 2):** Email send-time distributions. Validated at population level from Twitter activity timing. Not peer-reviewed specifically for executive email — reasonable but unvalidated inference.

**Tertiary signals (Tier 3, unvalidated):** Message length variation across day, creative output timing, response latency patterns. Use for enrichment after Tier 1/2 calibrate.

#### Algorithm

1. **Collect:** First and last keyboard activity timestamps daily. Separate weekdays from weekends.
2. **Initialise prior:** Roenneberg population distribution (MSFsc mean ~4:00 AM, SD ~1.5h). If age known, shift ~30 min per decade after 20.
3. **Daily Bayesian update:** Observe first-activity. Likelihood: Normal(observed | MSFsc − sleep_duration/2, sigma_obs). Conjugate Normal-Normal: `mu_post = (mu_0/sigma_0² + x/sigma_obs²) / (1/sigma_0² + 1/sigma_obs²)`.
4. **Weekend weighting:** Weekend observations weighted 2x (closer to true chronotype, less alarm-driven).
5. **GRSVD cross-validation (weekly):** Apply Generalised Regularised SVD to 7-day keystroke timing. Phase angle cross-validates Bayesian MSFsc.
6. **Convergence:** Useful when posterior SD < 45 minutes. Typically 10–14 days.
7. **Drift detection:** 7-day rolling mean shifts > 45 min and sustained 5+ days → re-estimate with doubled prior SD.

#### Chronotype Schema

```
ChronotypeModel {
  user_id: UUID
  estimated_chronotype: Float       -- MSFsc (continuous scale)
  chronotype_category: Enum         -- extreme_morning | moderate_morning | intermediate | moderate_evening | extreme_evening
  confidence: Float (0-1)
  observation_days: Int
  features: {
    first_activity_mean: Time       -- rolling 14-day
    first_activity_std: Duration
    last_activity_mean: Time
    last_activity_std: Duration
    email_send_peak_hour: Float
    keystroke_rhythm_phase: Float   -- GRSVD-extracted
    weekend_vs_weekday_shift: Duration  -- social jet lag indicator
  }
  prior_distribution: { mean: Float, variance: Float }
  last_updated: DateTime
  re_estimation_trigger: Bool
}
```

#### Confounders

- **Jet lag:** Exclude from updates for N days = timezones crossed. Detect from calendar travel signals.
- **Illness:** Pause updates when daily activity < 50% of 14-day rolling mean.
- **DST transitions:** Use UTC internally. Apply DST as clock correction, not model update.
- **Alarm-driven waking:** Weekday-weekend gap (social jet lag) is itself a chronotype signal.
- **Seasonal light exposure:** 15–30 min MSFsc shift winter → summer. Real variation — track, don't suppress.

### 5.2 Ultradian Rhythm Detection

Monitor 90–120 minute BRAC (Basic Rest-Activity Cycle) via keystroke velocity, app switching, email clustering, and activity pauses.

#### Algorithm

1. **Feature stream:** 5-minute rolling statistics of keystroke IKI, app-switch count, activity gap duration.
2. **Autocorrelation:** Every 30 minutes, over past 4 hours. Look for peaks in 80–130 min lag band.
3. **Phase estimation:** If period P detected (autocorrelation peak > 0.3): `phase = (minutes_since_last_trough mod P) / P`.
4. **Trough detection:** IKI z-score > 1.5 AND app-switch rate below baseline AND natural pause > 5 min.
5. **Confidence:** Report autocorrelation peak value. Below 0.2: suppress ultradian estimates entirely.

**Evidence strength:** Weaker than circadian. Lavie's research shows attentional peaks/troughs exist but individual variation is high. Treat as probabilistic. 15-minute temporal resolution realistic; sub-5-minute is not.

### 5.3 Energy Depletion Model

#### Five Depletion Drivers

| Driver | Detection Proxy | Base Weight | Compounding |
|--------|---------------|-------------|-------------|
| **Consecutive meetings** | Calendar: back-to-back events | 0.15 per 30-min meeting | +0.05 per consecutive (+0.33 compounding intensity) |
| **Context switching** | App-switch to different domain (email → spreadsheet → browser) | 0.08 per switch | Per 30-min window count |
| **Decision density** | Sent emails classified as substantive (not replies/forwards) | 0.05 per decision-class email | Per 30-min window |
| **Emotional labour** | Calendar: meeting with flagged difficult contacts (historical pattern) | 0.12 per instance | — |
| **Information overload** | Inbox volume spike (std dev above daily mean) | 0.03 per sigma above mean | — |

#### Decay and Recovery

- **Depletion:** Every 5 minutes: `delta_E = -sum(active_driver_weights * driver_intensity)`
- **Recovery:** Inactivity > 10 min triggers recovery. Rate: 0.01/min first 10 min, 0.005/min thereafter (diminishing returns). Lunch (>30 min): recovers 0.25–0.35. Overnight: reset to 1.0 (or 0.85 if previous day terminal E < 0.3).
- **Morning initialisation:** E(0) = 1.0; or 0.85 if previous terminal < 0.3.

#### Cross-Validation with Keystrokes

Compare E(t) with keystroke fatigue signals. If keystrokes indicate fatigue (IKI z-score > 1.0, backspace elevated) but E(t) > 0.6, the model is underweighting a depletion driver — log for calibration.

#### Energy Schema

```
EnergyState {
  user_id: UUID
  timestamp: DateTime
  current_energy: Float (0-1)
  phase: Enum                      -- ramp_up | peak | plateau | declining | depleted | recovering
  depletion_drivers: [
    {
      driver_type: Enum
      weight: Float                -- individually calibrated
      accumulated_cost: Float
      last_event: DateTime
    }
  ]
  ultradian_estimate: {
    cycle_position: Float (0-1)
    minutes_to_next_trough: Int
    confidence: Float
  }
  recovery_events_today: [
    { type: Enum, start: DateTime, duration: Duration, energy_recovered: Float }
  ]
  keystroke_fatigue_signals: {
    interkey_interval_zscore: Float
    backspace_rate_zscore: Float
    hold_time_zscore: Float
    degradation_asymmetry: Enum    -- accuracy_only | speed_and_accuracy | none
  }
  terminal_energy_yesterday: Float
}
```

**Presentation rule:** Internal model uses continuous float. External presentation uses 4-level categorical: high / moderate / low / depleted. Never present precise numbers to executive (AUC 72–80% means 20–28% error rate).

**Theoretical note:** Do NOT use ego depletion as theoretical frame (replication failure — Carter et al. 2015 reduced d=0.62 to d=0.20). Use motivation-shift model: fatigue shifts motivation toward low-effort choices, manifesting as task avoidance and satisficing.

### 5.4 Delivery Timing Framework

#### Cognitive Scheduling Recommendations

| Work Type | Optimal Timing | Evidence |
|-----------|---------------|----------|
| **Analytical / executive-function** | Circadian peak (morning for morning types) | 15–30% performance variation peak-to-trough |
| **Insight / creative** | Circadian OFF-peak (Wieth & Zacks inversion) | Solve rate 0.42 off-peak vs 0.33 at peak (27% better) |
| **Routine / administrative** | Ultradian troughs or post-meeting recovery | Low demand, high completion satisfaction |
| **Strategic decisions** | First 2 hours of peak period, protected | Porter & Nohria: uninterrupted strategy blocks = higher effectiveness |
| **Batching candidates** | Email, approvals, one-on-ones | ~23 min attention residue per context switch (Leroy 2009) |

#### Timing-Aware Insight Delivery Decision Tree

```
IF insight_type == urgent_alert:
  → deliver_now (with caveat if E(t) < 0.4)

IF flow_detected AND NOT urgent:
  → hold (expiry = flow_end + 15 min)

IF creative_framing:
  IF circadian OFF-peak AND E(t) > 0.3: deliver_now
  ELSE: hold_for_off_peak

IF strategic_recommendation OR uncomfortable_pattern OR relationship_warning:
  IF circadian peak AND E(t) > 0.6 AND consecutive_meetings < 2: deliver_now
  ELIF E(t) > 0.6: deliver_now (non-peak acceptable)
  ELSE: hold_for_peak (expiry = end of next business day)

IF routine_briefing:
  IF E(t) > 0.3 AND NOT flow_detected: deliver_now
  ELSE: queue_for_tomorrow (morning ramp-up)

DEFAULT: hold_for_peak
```

**Flow protection rule:** If sustained focus detected (keystroke velocity stable/rising, low app switching, E(t) > 0.5), hold ALL non-urgent insights. Flow state is more valuable than optimal delivery timing.

**Uncomfortable insights rule:** Deliver during peak E(t), never during troughs. Emotional regulation capacity highest when energy is high. Never after 3+ consecutive meetings.

---

## 6. Cognitive Science Framework

### 6.1 Bias Detection (Ranked by Detectability × Impact)

| Rank | Bias | Detectability | Impact | Observable Signals | Detection Feasibility |
|------|------|--------------|--------|-------------------|---------------------|
| 1 | **Sunk cost escalation** | HIGH | HIGH | Growing meeting cadence on stalled initiatives, increasing email thread length on flagged projects, resource allocation patterns | Calendar + email metadata sufficient |
| 2 | **Planning fallacy** | HIGH | HIGH | Systematic gap between stated milestone dates and actual completion; calendar block durations vs actual task times | Longitudinal tracking makes this trivially detectable |
| 3 | **Overconfidence** | MEDIUM-HIGH | HIGHEST | Compressed deliberation windows, shrinking consultation radius, declining response latency on high-stakes | Requires baseline calibration period |
| 4 | **Confirmation bias** | MEDIUM | HIGH | Narrowing email recipient diversity, declining engagement with dissenting contacts, source homogeneity | Requires communication graph baseline |
| 5 | **Groupthink** | MEDIUM | HIGH | Decreasing participant diversity, shorter meeting durations for major decisions, absence of dissent patterns | Calendar participant analysis + meeting duration trends |
| 6 | **Availability bias** | LOW-MEDIUM | MEDIUM | Temporal correlation between dramatic events and meeting/email spikes, then decay | Calendar + email time-series |
| 7 | **Status quo bias** | LOW | MEDIUM | Decision deferral patterns, "approve as-is" rates, absence of change-related calendar activity | Manifests as absence — hardest to detect |
| 8 | **Anchoring** | LOW-MEDIUM | HIGH | Correlation between first-mentioned figures and final decisions | Needs email content analysis — metadata alone insufficient |

**Biases that CANNOT be detected from digital behaviour alone:** anchoring (needs first-number visibility), representativeness heuristic (no digital signal), framing effects (often verbal), hindsight bias (post-hoc), Dunning-Kruger (needs domain competence assessment).

### 6.2 Detection Algorithms

#### Sunk Cost Detection
```
FOR each tracked initiative:
  IF meeting_frequency is increasing
  AND project_health_signals are declining (budget overrun, timeline slip)
  AND executive engagement is NOT decreasing:
    → sunk_cost_risk = HIGH
    → Intervention: surface cumulative investment + pre-mortem prompt
```

#### Overconfidence Detection
```
Maintain personal_calibration_score:
  FOR each forecasted outcome (timeline, budget, deal close):
    calibration_error = |predicted - actual| / predicted
    rolling_calibration = EMA(calibration_error, alpha=0.1)

IF rolling_calibration > 0.3 AND executive entering new commitment:
  → overconfidence_risk = HIGH
  → Intervention: "Your last 10 estimates averaged 1.4x actuals"
```

#### Confirmation Bias Detection
```
FOR each decision domain:
  Track unique_contacts_consulted, source_diversity, dissent_ratio

IF unique_contacts trending down for active decision
AND contacts consulted historically agree with executive:
  → confirmation_bias_risk = MEDIUM-HIGH
  → Intervention: "Consultation set is 40% less diverse than your typical strategic decision"
```

### 6.3 Decision Fatigue Estimation

```
Input: executive's digital signal stream for current day
Output: fatigue_score (0.0 - 1.0), confidence (0.0 - 1.0)

1. Personal baselines (rolling 30-day):
   morning_response_latency, morning_email_length,
   morning_deferral_rate, morning_delegation_rate

2. Current-window signals (rolling 90 min):
   current_response_latency, current_email_length,
   current_deferral_rate, current_delegation_rate,
   hours_since_last_break (>15 min gap),
   continuous_meeting_hours, decision_count_today

3. Drift ratios:
   latency_drift = current / morning
   brevity_drift = morning_length / current_length
   deferral_drift = current_rate / max(morning_rate, 0.01)

4. fatigue_score = 0.25 * latency_drift
                 + 0.20 * brevity_drift
                 + 0.25 * deferral_drift
                 + 0.15 * hours_since_break (normalised 0-1 over 4h)
                 + 0.15 * continuous_meeting_hours (normalised 0-1 over 6h)

5. Confidence:
   <7 days baseline: cap 0.3
   7-30 days: cap 0.6
   >30 days: cap 0.9
   Multiply by signal_completeness (fraction available)

6. Alert: fatigue_score > 0.7 AND confidence > 0.5
   AND upcoming decision-requiring event in next 2 hours
```

Evidence: Danziger et al. (2011) — favourable decisions dropped 65% → ~0% within sessions, reset after breaks (N=1,112 decisions). Time-of-day effects: 10–40% quality degradation morning to late afternoon, moderated by breaks.

### 6.4 Cognitive Mode Detection

| Observable State | Timed Signals | Cognitive Mode | Risk Profile |
|-----------------|--------------|---------------|-------------|
| Fast response, short messages, no info-seeking, immediate delegation | Latency <P25, word count <0.6x mean, no outgoing queries | **RPD / System 1** | LOW risk in high-validity domains. HIGH risk in novel/strategic |
| Slow response, multiple queries, document engagement, extended blocks | Latency >P75, 2+ queries, dedicated calendar blocks | **Deliberative / System 2** | Appropriate for strategic. Risk: analysis paralysis if >48h |
| Declining quality late-day, increasing deferral, status quo defaults | Latency drift >1.5x morning, word count declining | **Fatigue-Degraded System 2** | HIGHEST risk — believes deliberating but quality impaired |
| Rapid group consensus, short decision meetings, no dissent | Meeting durations shorter than complexity warrants, participant homogeneity | **Groupthink-Susceptible** | HIGH for strategic/novel decisions |
| Context switching >8x/hour, fragmented calendar, erratic responses | Fragmentation >P90, thread abandonment elevated | **High Cognitive Load** | MEDIUM-HIGH; higher decision reversal rates |

Classification uses threshold-based rules refined with executive-specific data. Anchored in Kahneman & Klein (2009): two conditions for trustworthy intuition — (1) environment has valid cues, (2) executive has had opportunity to learn them. Both must hold.

### 6.5 Intervention Design Principles

1. **Frame as pattern, not accusation** — "Your deliberation time on deals >$10M has compressed 40% this quarter" not "You're being overconfident"
2. **Compare to self, never population norms** — Executives dismiss "most executives" but attend to their own drift
3. **Pre-decision timing only** — Post-commitment triggers defensive rationalisation. Window is during information-gathering
4. **AI source advantage** — AI-delivered threatening information produces LESS reactance than human-delivered (no perceived status threat)
5. **Questions over statements** — "Have you consulted anyone who would argue against this?" > "You may be exhibiting confirmation bias"
6. **Probabilistic language** — "Decisions under similar conditions have a 70% reversal rate" not "This will fail"
7. **Surface cognitive mode, not bias name** — "You're operating in fast-decision mode on a decision type where your historical accuracy is 40%"
8. **Batch low-stakes, protect high-stakes** — Max 2–3 cognitive insights per day. Reserve intervention capital for highest stakes × detection confidence
9. **Never infer from single signal** — Require 2+ co-occurring signals from different categories before surfacing. Present all inferences with explicit confidence and evidence counts
10. **Metacognitive not prescriptive** — The system observes; the human concludes. Never "you should"; always "here's what I'm seeing"

### 6.6 Key Anti-Pattern: Oversimplified Inference

- Fast response ≠ bias (may be legitimate expertise via RPD)
- Narrow consultation ≠ confirmation bias (may have gathered input offline)
- Meeting brevity ≠ groupthink (team may be genuinely aligned)
- Decision deferral ≠ fatigue (may be strategic patience)
- Speed is only a risk signal when combined with low-validity environment + high stakes + deviation from personal norms

---

## 7. Multi-Signal Fusion

### 7.1 Architecture: Late Fusion with Bottleneck Attention

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
     (per-modality: 2-layer FFN, 64-dim hidden → 32-dim embedding)
     (features z-scored against 30-day personal rolling baseline)
         |       |       |       |       |
         +---+---+---+---+---+---+---+---+
             |               |
       [Bottleneck Tokens]   |
       (4-8 learned tokens,  |
        cross-modal attention)|
             |               |
         +---+---+           |
         | Fusion |<----------+
         | Layer  |
         +---+---+
             |
    +--------+--------+--------+
    |        |        |        |
  [CCLI]  [BEWI]   [RDS]   [DQEI]
```

**Why late fusion:** Google NeurIPS 2021 (Multimodal Bottleneck Transformer) demonstrated that late-layer cross-modal attention with bottleneck tokens outperforms both early fusion and full cross-attention for temporal behavioural data. Maps directly to Timed's five signal branches.

**Per-modality encoding:** Each modality's z-scored features for a 1-hour time window pass through a small feedforward encoder (2 layers, 64-dim hidden) producing a 32-dim embedding.

**Bottleneck fusion:** 4–8 learned bottleneck tokens attend to all 5 modality embeddings via cross-attention. Forces information compression; prevents modality dominance.

**Training signal:** Self-supervised from longitudinal consistency. Never asks executive to label their state. Uses convergent validity: if 3+ signals agree on a state change, reinforce composite weights.

### 7.2 Four Composite Intelligence Indices

#### CCLI — Composite Cognitive Load Index
```
ccli = 0.35 * email_response_latency_z
     + 0.30 * keystroke_iki_mean_z
     + 0.20 * voice_f0_variance_z
     + 0.15 * app_switch_frequency_z
```
What it measures: real-time cognitive load from converging email, keystroke, voice, and app-switching signals.

#### BEWI — Burnout Early Warning Index
```
bewi = 0.30 * calendar_fragmentation_z
     + 0.25 * after_hours_email_ratio_z
     + 0.20 * keystroke_error_rate_z
     + 0.15 * voice_hnr_decline_z
     + 0.10 * weekend_activity_z
```
What it measures: medium-term burnout trajectory from calendar pressure, boundary erosion, typing degradation, and voice quality decline.

#### RDS — Relationship Deterioration Score (per-contact)
```
rds(contact) = 0.35 * response_latency_deviation_z(contact)
             + 0.25 * meeting_cancellation_rate_z(contact)
             + 0.25 * voice_tension_z(contact)
             + 0.15 * cc_escalation_frequency_z(contact)
```
What it measures: per-relationship health from multi-modal convergence of email avoidance, calendar avoidance, and voice tension with specific contacts.

#### DQEI — Decision Quality Estimation Index
```
dqei = 0.30 * email_decision_speed_z
     + 0.25 * keystroke_hesitation_z       // inverse of pre-send pause duration
     + 0.25 * voice_certainty_z            // low F0 variance + high HNR
     + 0.20 * thread_resolution_speed_z
```
What it measures: decision quality proxy from speed, confidence markers, and resolution patterns.

### 7.3 Z-Score and Alert Framework

All z-scores computed against executive's own 30-day rolling baseline. Positive values indicate deviation above baseline.

| Threshold | Level | Action |
|-----------|-------|--------|
| z > 1.5 | Notable | Log for pattern tracking |
| z > 2.0 | Significant | Surface if 3+ modalities agree |
| z > 2.5 | Critical | Alert regardless of timing |

**Convergent validity requirement:** Require 3+ modalities agreeing on state change before alerting. This reduces false positives to acceptable levels for executive-facing product.

### 7.4 Baseline Windows Summary

| Signal Domain | Initial Calibration | Rolling Baseline | Trend Detection |
|--------------|-------------------|-----------------|----------------|
| Email patterns | 12 weeks | 30-day per-sender | 90-day |
| Keystroke dynamics | 14 days | 30-day rolling | 90-day |
| Voice features | 2–3 weeks (10–15 sessions) | 30-day rolling (90-day adaptive) | 90-day |
| Calendar metrics | 4 weeks | 4-week rolling | 12-week |
| Chronotype | 10–14 days (useful) | Continuous Bayesian update | Re-estimate on 45-min shift |
| ONA / relationships | 12 weeks (hard requirement) | 4-week rolling | 12-week |

---

## 8. macOS API Reference

### 8.1 Complete API Table

| Capability | API / Framework | Key Classes/Methods | Permission / Entitlement | Grant Mechanism | Distribution Constraint |
|-----------|----------------|-------------------|------------------------|----------------|----------------------|
| **Email metadata** | Microsoft Graph API | `GET /me/messages` (delta), `GET /me/messages/{id}` | `Mail.Read` (OAuth) | MSAL auth flow; token in Keychain | None (network API) |
| **Calendar events** | Microsoft Graph API | `GET /me/calendarView` (delta), `GET /me/events` (delta) | `Calendars.Read` (OAuth) | MSAL auth flow | None |
| **Local calendar (fallback)** | EventKit | `EKEventStore` | `NSCalendarsUsageDescription` + `kTCCServiceCalendar` | System dialog | None |
| **Keystroke timing** | Accessibility API | `CGEvent.tapCreate(...)` for keyDown/keyUp | Accessibility (`kTCCServiceAccessibility`) | User manually enables in System Preferences > Privacy > Accessibility | **No App Sandbox. Must distribute outside Mac App Store.** |
| **Accessibility check** | Accessibility API | `AXIsProcessTrusted()` | None | — | — |
| **Active app detection** | NSWorkspace | `NSWorkspace.shared.frontmostApplication`, `didActivateApplicationNotification` | None | — | — |
| **App bundle ID** | NSWorkspace | `NSRunningApplication.bundleIdentifier` | None | — | — |
| **System idle time** | IOKit | `IOServiceGetMatchingService` for `IOHIDSystem` | None | — | — |
| **Microphone capture** | AVFoundation | `AVAudioEngine.inputNode.installTap(bufferSize:format:block:)` | `NSMicrophoneUsageDescription` + `kTCCServiceMicrophone` | System dialog on first use | Persistent orange menu bar dot (Sequoia+) |
| **Audio routing** | AVFoundation | `AVAudioSession` | None | — | — |
| **On-device speech recognition** | Speech framework | `SFSpeechRecognizer(locale:)`, `recognitionTask(with:)`, `requiresOnDeviceRecognition = true` | `NSSpeechRecognitionUsageDescription` + `kTCCServiceSpeechRecognition` | System dialog on first use | macOS 13+ required |
| **System audio capture** | CoreAudio | `AudioDeviceID`, `AudioObjectPropertyAddress` | Screen Recording or Audio Recording permission (macOS 15+) | System Preferences > Privacy (manual) | Monthly re-prompt on Sequoia+ |
| **FFT / spectral analysis** | Accelerate | `vDSP.FFT`, `vDSP_meanSquare`, `vDSP_rmsqv` | None | — | Hardware-accelerated on Apple Silicon |
| **ML inference** | Core ML | `MLModel`, `MLMultiArray`, `MLFeatureProvider`, `MLComputeUnits.all` | None | — | Use Neural Engine for WavLM/HuBERT |
| **Sound classification** | SoundAnalysis | `SNAudioStreamAnalyzer`, `SNClassifySoundRequest` | None (beyond microphone) | — | macOS 12+ |
| **eGeMAPS features** | openSMILE 3.x (C++) | Static library, bridged via Swift C interop (`-import-c-header`) | None | — | Compile as static lib; open-source (audEERING) |

### 8.2 Permission UX Flow

| Step | Permission | User Experience |
|------|-----------|----------------|
| 1 (onboarding) | Microsoft OAuth | MSAL browser flow → Outlook consent screen |
| 2 (onboarding) | Accessibility | App calls `AXIsProcessTrusted()`, directs user to System Preferences > Privacy > Accessibility. No system dialog — manual toggle required. |
| 3 (onboarding) | Microphone | System dialog: "Timed analyses your voice to understand cognitive patterns. Audio never leaves your device." |
| 4 (optional) | Speech Recognition | System dialog: "Timed transcribes speech on-device to detect communication patterns. Transcripts stay on your Mac." |
| 5 (optional) | System audio | System Preferences > Privacy > Screen Recording (manual). Monthly re-prompt on Sequoia+. |

**Design decision on speech recognition permission:** Consider implementing energy-threshold VAD instead of `SFSpeechRecognizer` for voice activity detection to avoid the second permission (Speech Recognition). Use `SFSpeechRecognizer` only when disfluency detection (Path C) is needed.

### 8.3 Sequoia (macOS 15) and Tahoe (macOS 26) Considerations

- **Screen recording permission re-prompts monthly** (Sequoia+). Does not directly affect Timed unless system audio capture is enabled for meeting analysis.
- **Persistent orange menu bar indicator** when microphone is active. Not suppressible. Frame as: "Timed is listening to how you sound, not what you say."
- **Accessibility permission** unchanged — still requires manual toggle, no programmatic grant.
- **ScreenTime API** (`DeviceActivityReport`): designed for parental controls, requires Family Sharing context. Not useful for Timed — avoid entirely.
- **IOKit for input monitoring:** Deprecated/restricted for keystroke capture. Accessibility API is the supported path.
- **IOKit for idle time:** Still available and unrestricted for `IOHIDSystem` idle time polling.

### 8.4 Distribution Constraints

Timed **cannot be distributed via Mac App Store** because:
1. Accessibility event taps (`CGEvent.tapCreate`) are incompatible with App Sandbox
2. Global keystroke monitoring requires out-of-sandbox execution

**Required distribution path:** Developer ID signing + Apple notarisation + direct download. This enables all required permissions without sandboxing.

### 8.5 Token and Credential Storage

- MSAL OAuth tokens: Keychain only (`SecKeychain` / `KeychainAccess`). Never UserDefaults, plist, or plain files.
- MSAL handles silent token refresh. Store refresh token in Keychain.
- Graph API rate limits: 10,000 requests per 10 minutes per app. Delta queries reduce consumption dramatically.

### 8.6 Trust Boundaries (Non-Negotiable)

1. **Never capture key characters.** Accessibility API provides them; Timed must architecturally prevent capture. The `CGEvent` callback extracts timestamps only, discards `keyCode`/`characters`.
2. **Never fetch email body content.** Use `$select` on all Graph queries to explicitly exclude `body`/`bodyPreview`. Exception: `bodyPreview` (first 255 chars) may be used for length estimation only, never content analysis.
3. **Never store raw audio.** Extract features in real-time, discard buffers immediately. Only `CognitiveStateEstimate` vectors and aggregate acoustic statistics persist.
4. **Never store transcripts beyond processing.** On-device only, ephemeral.
5. **Never analyse other participants' audio** without explicit consent framework and jurisdiction-aware flow.

---

## Conflict Resolutions

### openSMILE vs Accelerate/vDSP for eGeMAPS

Extract-02 specifies openSMILE (C++ library bridged via Swift C interop) as the eGeMAPS extraction method. Extract-09 specifies vDSP (Accelerate framework) for FFT as the foundation for eGeMAPS extraction. **Resolution:** Use both. vDSP handles the low-level FFT and spectral computation (hardware-accelerated on Apple Silicon, <5ms per utterance). openSMILE provides the standardised eGeMAPS feature extraction pipeline on top of raw spectral data. In practice, openSMILE compiled as static C++ library is the primary extraction tool, with Accelerate/vDSP used for performance-critical inner loops where the openSMILE defaults are too slow for real-time processing.

### Voice baseline: 30-day vs 90-day rolling window

Extract-02 specifies 30-day rolling for voice baseline. Extract-09 specifies 90-day rolling with exponential decay for baseline drift prevention. **Resolution:** Use 90-day with exponential decay (recent sessions weighted higher) as the primary baseline window, consistent with extract-09's more detailed voice analysis. The 30-day window from extract-02 is the minimum-viable baseline for initial z-score computation during months 1–3; the system transitions to 90-day adaptive after sufficient data accumulates.

### VAD implementation: SFSpeechRecognizer vs energy-threshold

Extract-02 suggests `SFSpeechRecognizer` for VAD segmentation. Extract-09 notes this requires a second macOS permission (`kTCCServiceSpeechRecognition`). **Resolution:** Default to energy-threshold VAD (no additional permission) for voice activity detection. Use `SFSpeechRecognizer` only when disfluency detection (Path C) is actively needed, since disfluency detection requires word-level transcription anyway.

### Whisper inclusion

Extract-02 does not mention Whisper. Extract-09 includes Whisper-large-v3 for transcription and encoder embeddings. **Resolution:** Include Whisper as Tier 2/3 capability. It is not needed for Tier 1 (email/calendar) or basic voice features (eGeMAPS). Deploy when disfluency detection and linguistic analysis are implemented. On-device only (`requiresOnDeviceRecognition = true` equivalent). Never send audio to cloud.

### Email baseline: 12-week (extract-08) vs 30-day (extract-02)

Extract-08 requires 12-week baseline for ONA anomaly detection. Extract-02 uses 30-day rolling for email response latency. **Resolution:** Both are correct for different purposes. 30-day rolling is sufficient for per-sender response latency z-scores (extract-02's signal). 12-week is required for ONA centrality computation, disengagement detection, and communication anomaly scoring (extract-08's network intelligence). The 12-week requirement is the binding constraint — no relationship or network insights generated before 12 weeks of data.

### Hume AI prosody model

Extract-09 lists Hume AI as supplementary but cloud-only. **Resolution:** Exclude from the architecture. Timed's privacy architecture requires on-device processing. Hume AI's cloud-only constraint violates the "raw audio never leaves device" trust boundary. WavLM Large + eGeMAPS covers the same capability space on-device.
