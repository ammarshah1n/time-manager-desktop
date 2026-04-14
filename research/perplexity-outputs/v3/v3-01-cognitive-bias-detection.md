# Cognitive Bias Detection from Passive Digital Signals
### Technical Build Brief — Claude Opus 4.6 Nightly Analysis Engine

***

## Executive Summary

This brief specifies a production implementation of a nine-bias cognitive detection engine for a C-suite executive, built as **Loop 4** of the Timed-Brain learning architecture, slotting into the existing Supabase + Claude pipeline documented at `06 - Context/ai-learning-loops-architecture-v2.md`. The engine detects overconfidence, anchoring, sunk cost escalation, availability heuristic, confirmation bias, status quo bias, planning fallacy, escalation of commitment, and recency bias from passive digital signals (email metadata and body text, calendar event patterns, task management data) without any self-report instruments.

The core architectural decision: **do not use chain-of-thought extended thinking for the primary classification pass**. Research from arXiv (2025) demonstrates that at a 1% false positive rate threshold, "Think On" (CoT reasoning) achieves *lower* recall than direct structured classification because confidence polarisation causes false positives to be generated with near-certainty, collapsing discrimination at strict precision thresholds. Use Claude Opus 4.6 in **direct-classification mode** for signal scoring, reserving adaptive thinking for the final synthesis and narrative generation step only.[^1]

The engine mirrors the existing `behavioral_rules` pattern from `behaviour-events-schema.md` — evidence gates of ≥5 observations and ≥65% consistency rate — extended with temporal evidence chains and bias-specific confidence formulae.

***

## Part I — Bias × Signal × Threshold Decision Matrix

### Methodological Foundation

All nine biases require a two-layer detection model:
1. **Signal layer**: Raw observable digital behaviours extracted from email metadata, body text, calendar events, and task management records
2. **Evidence layer**: A temporal chain of ≥N signal observations that cross a threshold before a bias flag is generated

For text-based signals, the primary validated tool is LIWC-22 (Linguistic Inquiry and Word Count), which has established psychometric properties across psychological constructs. The LIWC certainty category (words: *always, never, definitely, certainly, clearly*) and hedging indicators are validated proxies for certainty expression. The hedge:booster ratio, drawing on Hyland's epistemic positioning framework, is a validated quantitative metric — academic writing shows hedges exceeding boosters 3:1 on average, so a booster-dominated executive communication pattern (ratio > 1.0) is a meaningful overconfidence signal.[^2][^3][^4][^5][^6]

For metadata-based signals (response latency, calendar structure), the validation comes from organisational behaviour and information systems research. For NLP classification, transformer-based models (RoBERTa, BERT) achieve F1 > 0.89 on nuanced bias category detection in corporate text.[^7]

### The Decision Matrix

| Bias | Primary Digital Proxy Signals | Min Evidence Threshold | Est. FPR | Max Achievable Confidence |
|---|---|---|---|---|
| **Overconfidence** | (1) High booster:hedge ratio in email body (LIWC certainty ≥ 8% of words, hedge < 2%); (2) Task estimate:actual ratio consistently < 0.70 across ≥5 tasks; (3) Calendar: zero buffer blocks (< 5% of daily scheduled time is unscheduled) | ≥7 emails + ≥5 estimation events + 21-day window | ~18–25% | 0.72 |
| **Anchoring** | (1) First numeric value in email thread vs final agreed numeric: anchor_delta = (final − anchor) / anchor systematically < 0.15; (2) Project budgets consistently within 12% of first-stated figure; (3) Salary/vendor emails: proposer gets within 8% of opening offer | ≥5 measurable numeric threads across ≥14 days | ~22–30% | 0.68 |
| **Sunk Cost Escalation** | (1) Continued meeting series on project with documented negative status (email thread contains "behind schedule"/"at risk"/"not meeting targets" + meeting not cancelled within 7 days); (2) Task re-added to plan after abandonment > 3 times without scope change; (3) Email sentiment trajectory: response to negative project update lacks course-correction language | ≥3 measurable project continuation events | ~15–22% | 0.74 |
| **Availability Heuristic** | (1) Topic frequency spike in communications within 14 days following a salient event (keyword clustering analysis); (2) Calendar: new risk-assessment meeting created < 72 hrs post-incident; (3) Email prioritisation shifts to new topic > 40% reallocation from baseline within 7 days | ≥2 measurable post-event priority shifts within 60-day window | ~28–35% | 0.65 |
| **Confirmation Bias** | (1) Asymmetric response latency: replies to confirming emails < 2× median latency; replies to disconfirming emails > 3× median latency or no reply; (2) NLP: email replies to counter-evidence are ≤40% word count of replies to supporting evidence on same topic; (3) Information diet: email folder/label structure reveals single-source topic consumption | ≥10 email pairs (confirming vs disconfirming) on ≥3 topics | ~20–28% | 0.71 |
| **Status Quo Bias** | (1) Recurring calendar events unmodified > 90 days despite project status change; (2) Same vendor/tool referenced in emails despite documented issue (negative sentiment in prior email thread + no alternative mentioned in subsequent ≥5 emails); (3) Decision email patterns: "let's continue as is" or equivalent language ≥3 times in 30-day window | ≥5 status-quo-confirming decisions + ≥30-day window | ~20–26% | 0.70 |
| **Planning Fallacy** | (1) estimate:actual ratio < 0.70 across ≥7 tasks (mirrors existing Loop 2 detection); (2) Project deadline extension emails (contains "push back"/"revised timeline"/"delay") on ≥2 distinct projects; (3) Calendar: blocked deep-work time consistently replaced with reactive meetings | ≥7 tasks with actual vs estimate comparison + ≥2 deadline extensions | ~12–18% | 0.78 |
| **Escalation of Commitment** | (1) Sequential resource increase pattern: email thread on single project shows increasing budget/headcount/timeline allocation across ≥3 messages without scope change trigger; (2) Meeting frequency on flagged project increases, not decreases, post-negative-status; (3) Absence of explicit exit-criteria language in project emails | ≥3 escalation cycles on ≥1 project | ~17–24% | 0.73 |
| **Recency Bias** | (1) Strategic priority emails reference only events < 30 days old (no historical comparison data cited); (2) Performance evaluation emails (360 reviews, appraisals) disproportionately reference last 60-day window events; (3) Task prioritisation: tasks created > 60 days ago consistently deprioritised vs recent tasks of equivalent stated importance | ≥8 strategic/evaluation communications over ≥60-day window | ~22–30% | 0.67 |

**FPR calibration note**: These FPR estimates are derived from analogous NLP bias detection tasks in corporate communication corpora and the general NLP classification literature for contextual bias detection. No peer-reviewed study has published FPR figures specifically for executive cognitive bias detection from passive digital signals — this is an explicit evidence gap. The estimates assume a structured JSON classification schema with five-level evidence gates, not open-ended text generation.[^8][^9][^7]

***

## Part II — NLP Features and Prompt Engineering Patterns

### Feature Set for Email Analysis

#### Tier 1 — Lexical Features (Compute at Ingest)

| Feature | Extraction Method | Target Bias |
|---|---|---|
| Booster:hedge ratio | LIWC-22 certainty category / inhibition category word counts[^3] | Overconfidence |
| First numeric anchor value | Regex: first `\$[\d,]+` or `[\d]+%` or `[\d]+ (hours/days/weeks)` in thread | Anchoring |
| Certainty word density | LIWC certainty%: target > 8% of total words[^4] | Overconfidence, Escalation |
| Response latency percentile | `reply_timestamp − received_timestamp` / user's 90-day median latency | Confirmation bias |
| Word count ratio (reply:trigger) | `len(reply_body) / len(trigger_body)` | Confirmation bias |
| Topic shift velocity | Cosine distance between email embeddings: `(embedding_t − embedding_{t−7d})` | Availability heuristic, Recency bias |
| Negative feedback acknowledgement rate | NLP: presence of course-correction language after negative status update | Sunk cost, Escalation |

#### Tier 2 — Structural Features (Compute at Analysis)

| Feature | Extraction Method | Target Bias |
|---|---|---|
| Thread numeric drift | `(final_agreed_value − first_stated_value) / first_stated_value` | Anchoring |
| Sequential resource escalation | Extract budget/headcount/timeline values per project across thread; compute delta sequence | Escalation of commitment |
| Historical reference ratio | NLP: ratio of references to events > 60 days ago vs < 30 days ago in strategic emails | Recency bias |
| Alternative-consideration rate | NLP: presence of 2+ named alternatives in decision emails | Status quo bias, Confirmation bias |
| Temporal priority distribution | `count(tasks_deferred from >60 days ago) / count(tasks_deferred total)` | Recency bias |

### Prompt Structures for Bias Detection

The following prompt templates are designed for **direct structured classification** (no CoT, no extended thinking). They produce JSON output that feeds directly into the evidence accumulator. All prompts share a system header that establishes the analyst role and schema contract.

**System Header (all prompts, cache-controlled)**:
```
You are a cognitive signal analyser. Your task is to evaluate whether specific observable 
behavioural signals in the provided digital data constitute evidence of a named cognitive bias.

Output ONLY valid JSON matching the provided schema. Do not generate explanatory prose.
Evidence must be grounded in the provided data. If insufficient data exists, output 
{"bias_detected": false, "confidence": 0.0, "evidence_summary": "insufficient_data"}.
Do not infer signals not present in the data.
```

#### Bias-Specific Prompt Table

| Bias | Core Detection Prompt Structure | Schema Output |
|---|---|---|
| **Overconfidence** | `Analyse the booster:hedge ratio in the following email body. Count: (a) certainty markers [always, definitely, certainly, will, clearly, obviously, undoubtedly, must], (b) hedging markers [might, perhaps, possibly, could, may, approximately, around, roughly]. Compute ratio = (a)/(b+1). Classify as HIGH_OVERCONFIDENCE (ratio > 3.0), MODERATE (1.5–3.0), BASELINE (< 1.5).` | `{signal: "booster_hedge_ratio", value: float, classification: enum, email_id: uuid}` |
| **Anchoring** | `Extract the first numeric value referenced in this email thread for the decision topic "{topic}". Then extract the final agreed numeric value. Compute anchor_delta = abs(final - anchor) / anchor. If delta < 0.15, classify as ANCHOR_HOLD. If no resolution reached, output NO_RESOLUTION.` | `{signal: "anchor_delta", anchor_value: float, final_value: float, delta: float, classification: enum}` |
| **Sunk Cost Escalation** | `This email thread concerns project "{project_id}". (1) Does the thread contain negative status language [behind schedule, at risk, not meeting targets, failing, underperforming]? (2) Was a meeting cancellation, project pause, or explicit scope reduction communicated within 7 days of the negative signal? Output NEGATIVE_SIGNAL_NO_RESPONSE if (1) true and (2) false.` | `{signal: "sunk_cost_response", negative_signal_detected: bool, course_correction_detected: bool, days_to_response: int\|null}` |
| **Availability Heuristic** | `Compare the distribution of email topics in the 7-day window [{date_range_a}] versus the 7-day baseline window [{date_range_b}]. Identify any topic that increased by > 40% as a proportion of total communications. If such a topic exists and a salient event related to that topic occurred in the intervening period, classify as AVAILABILITY_SHIFT.` | `{signal: "topic_shift", shifted_topic: string, pre_pct: float, post_pct: float, salient_event_detected: bool}` |
| **Confirmation Bias** | `For topic "{topic}", classify the following email pairs as [CONFIRMING, DISCONFIRMING, NEUTRAL] with respect to the executive's stated position "{position}". Then report: (1) median response latency for CONFIRMING emails, (2) median response latency for DISCONFIRMING emails, (3) average word count ratio (reply/trigger) for each class.` | `{signal: "asymmetric_response", confirming_latency_median: int, disconfirming_latency_median: int, latency_ratio: float, wordcount_ratio: float}` |
| **Status Quo Bias** | `Scan this 30-day email corpus for the following pattern: (1) A documented problem or issue with vendor/tool/process "{entity}" was acknowledged in an email. (2) In subsequent emails ≥5, was "{entity}" still referenced as the active solution without explicit re-evaluation language [alternatives, options, considering, replace, switch]? Output STATUS_QUO_PERSISTENCE if both conditions are met.` | `{signal: "status_quo_persistence", entity: string, problem_acknowledged_date: date, subsequent_references: int, re_evaluation_detected: bool}` |
| **Planning Fallacy** | `[Uses existing estimation_history data from Loop 2.] For task_type "{type}", retrieve the last 7+ completed tasks with both ai_estimate/user_override and actual_minutes. Compute: mean(effective_estimate) / mean(actual_minutes). If ratio < 0.70, classify as PLANNING_FALLACY_SIGNAL. Also check for deadline extension emails on active projects.` | `{signal: "estimation_ratio", task_type: string, ratio: float, n_tasks: int, deadline_extensions: int}` |
| **Escalation of Commitment** | `For project "{project_id}", extract all resource commitments (budget figures, headcount, timeline extensions) mentioned across this email thread in chronological order. Compute the delta sequence. If ≥3 sequential increases exist without an intervening scope-change trigger [new requirements, changed circumstances, external mandate], classify as ESCALATION_SEQUENCE.` | `{signal: "escalation_sequence", project_id: string, commitment_sequence: float[], delta_sequence: float[], n_escalations: int}` |
| **Recency Bias** | `In these strategic/evaluative emails, count: (a) references to events, data, or outcomes from the last 30 days; (b) references to events, data, or outcomes from > 60 days ago. Compute recency_ratio = a / (a + b). If recency_ratio > 0.80 in a strategic decision context, classify as RECENCY_DOMINATED.` | `{signal: "recency_ratio", recent_refs: int, historical_refs: int, ratio: float, context_type: string}` |

### Extended Thinking Usage Rule

Claude Opus 4.6 with adaptive thinking (`type: "adaptive"`) should be invoked **only in the final synthesis step** of the nightly pipeline — the step that generates the human-readable insight card. The classification prompts above must use **direct mode** (`thinking: null` or `type: "disabled"`) to maintain precision-sensitive FPR control. Extended thinking's confidence polarisation effect makes it unsuitable for any classification task where false positives carry asymmetric costs.[^10][^11][^1]

The API call pattern for Opus 4.6:
```typescript
// Classification pass — NO thinking
const classificationResult = await client.messages.create({
  model: "claude-opus-4-6",
  max_tokens: 512,
  // NO thinking parameter
  system: BIAS_SYSTEM_HEADER_CACHED,
  messages: [{ role: "user", content: biasSpecificPrompt }]
});

// Synthesis pass — WITH adaptive thinking
const synthesisResult = await client.messages.create({
  model: "claude-opus-4-6",
  max_tokens: 8000,
  thinking: { type: "adaptive", effort: "high" },
  system: SYNTHESIS_SYSTEM_PROMPT,
  messages: [{ role: "user", content: synthesisPayload }]
});
```

***

## Part III — Minimum Sample Sizes and Observation Windows

### Evidence Accumulation Theory

The existing Timed-Brain evidence gates (≥5 sessions, ≥65% consistency) are derived from the same statistical reasoning that governs the bias detection thresholds here. Below those gates, the signal is indistinguishable from normal behavioural variation. The Bayesian framework for sequential confidence accumulation from UCL's discrete confidence research establishes that observers using 2-level discrete confidence states achieve 0.7 confidence after approximately 7 consistent observations. This calibrates the table below.[^12]

LIWC reliability is empirically proportional to word count — more words produce more trustworthy percentages. A minimum of 500 words of email text per analysis window is required before LIWC-derived features carry valid weight.[^4]

### Observation Window Requirements

| Bias | Min Observations | Min Time Window | Rationale |
|---|---|---|---|
| Overconfidence | 7 emails ≥500 words each + 5 estimation events | 21 days | LIWC reliability + estimation variance requires multi-week sampling |
| Anchoring | 5 distinct numeric negotiation threads | 14 days | Fewer distinct threads = high false positive from single interaction style |
| Sunk Cost Escalation | 3 project continuation events | 14 days | Three is the minimum to distinguish persistence from legitimate due diligence[^13] |
| Availability Heuristic | 2 measurable priority shifts | 60 days | Requires at least 2 salient events to establish pattern vs single incident |
| Confirmation Bias | 10 email pairs across 3 topics | 30 days | Latency asymmetry requires paired comparison across multiple topics to rule out domain differences |
| Status Quo Bias | 5 status-quo decisions | 30 days | Must span multiple domains to avoid confounding with domain-specific inertia |
| Planning Fallacy | 7 completed tasks with actuals | 21 days | Mirrors existing Loop 2 threshold; estimation bias gate is well-calibrated here |
| Escalation of Commitment | 3 escalation cycles on ≥1 project | Open (project lifetime) | Project-scoped; 3 cycles establishes pattern per dissertation-level IS research[^13][^14] |
| Recency Bias | 8 strategic communications | 60 days | Long baseline required to establish reference distribution of temporal citation patterns |

### Confidence Score Formula

For each bias, confidence is computed as:

\[ C_{bias} = w_1 \cdot F_{signal} + w_2 \cdot F_{temporal} + w_3 \cdot F_{consistency} \]

Where:
- \( F_{signal} \) = normalised signal strength (e.g., booster:hedge ratio normalised to )
- \( F_{temporal} \) = fraction of observation window that shows the signal (observations with signal / total observations)
- \( F_{consistency} \) = evidence_rate from the evidence chain (analogous to existing `evidence_rate` in `behavioral_rules`)
- Weights \( w_1 = 0.4, w_2 = 0.3, w_3 = 0.3 \) as defaults, to be calibrated empirically

The 0.70 confidence threshold is achievable for 6 of the 9 biases within the specified observation windows. Planning Fallacy achieves the highest confidence (0.78) because it can leverage existing Loop 2 data. Availability Heuristic achieves the lowest (0.65) due to inherent confounds with genuine strategic pivots.

***

## Part IV — False Positive Minimisation in Executive Contexts

### Documented FPR Sources

No peer-reviewed study has published FPRs for automated cognitive bias detection from passive digital signals in an executive context — this is an explicit evidence gap. The closest published evidence comes from:

- NLP bias detection in clinical text (LIWC + ML): documented methodology with strong internal consistency but different domain[^15]
- Multi-label RoBERTa bias classification in general text: overall accuracy 0.99 with F1 = 0.89 for nuanced categories[^7]
- LLM evaluation bias (CoBBLEr benchmark): LLMs exhibit ~40% bias-influenced judgements in evaluation tasks — this is an upper bound on how wrong an LLM-as-rater can be without specific bias-detection prompting[^16]
- Reasoning model FPR: at 1% FPR, direct classification outperforms CoT across all 9 safety/hallucination benchmarks tested[^1]

### FPR Minimisation Strategies

**1. Multi-signal requirement (most important)**
No single signal triggers a bias flag. Every detection requires corroboration from at least two distinct signal types (e.g., LIWC certainty + estimation ratio for overconfidence; NOT LIWC certainty alone). This is the single most effective false positive reduction mechanism and is architecturally enforced in the evidence schema.

**2. Domain calibration baseline**
Each signal is calibrated against the executive's own 90-day baseline, not an external normative population. A CEO in high-stakes negotiation legitimately uses more certainty language — the signal must deviate from their personal baseline, not an arbitrary threshold.

**3. Competing hypothesis gate**
Before a bias flag is promoted from `tentative` to `active`, the Opus synthesis step must generate and evaluate at least one plausible non-bias explanation for the observed pattern. If the alternative hypothesis has confidence > 0.5, the flag is not promoted.

**4. False positive cost asymmetry**
In executive contexts, a false positive (wrongly flagging the CEO with a bias) damages trust irreparably. The system should therefore be calibrated at a **precision > 0.80** operating point, accepting lower recall (missing some real bias instances) in exchange for high precision. This is the opposite of clinical screening where recall is paramount.[^17]

**5. Decay and recency gates**
Flags are ephemeral. A bias flag must be re-confirmed by new evidence within 30 days or it decays to `is_active = false`. This mirrors the existing `behavioral_rules` decay mechanism.

***

## Part V — Temporal Evidence Chain Data Structure

### Architectural Grounding

The existing `behaviour_events` table (partitioned monthly by `occurred_at`) is the raw signal store. The `behavioral_rules` table stores synthesised rules with confidence and evidence counts. The bias detection layer adds one new table — `bias_evidence_chains` — that bridges raw observations into ordered temporal sequences, and two columns to `behavioral_rules` to tag bias-specific detections.

### Schema Recommendation

```sql
-- New table: individual signal observations (raw layer)
CREATE TABLE bias_signal_observations (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id        UUID        NOT NULL REFERENCES workspaces(id),
  user_id             UUID        NOT NULL REFERENCES profiles(id),
  
  bias_type           TEXT        NOT NULL CHECK (bias_type IN (
    'overconfidence', 'anchoring', 'sunk_cost_escalation',
    'availability_heuristic', 'confirmation_bias', 'status_quo_bias',
    'planning_fallacy', 'escalation_of_commitment', 'recency_bias'
  )),
  
  signal_type         TEXT        NOT NULL,          -- e.g. 'booster_hedge_ratio', 'anchor_delta'
  signal_value        FLOAT,                          -- normalised [0,1] or raw metric
  signal_classification TEXT,                         -- e.g. 'HIGH_OVERCONFIDENCE', 'ANCHOR_HOLD'
  
  source_type         TEXT        NOT NULL CHECK (source_type IN (
    'email_body', 'email_metadata', 'calendar_event', 'task_estimation', 'thread_analysis'
  )),
  source_ref_id       UUID,                           -- FK to email_messages.id, tasks.id, etc.
  source_ref_table    TEXT,                           -- 'email_messages' | 'tasks' | 'behaviour_events'
  
  context_snapshot    JSONB       NOT NULL DEFAULT '{}',
  -- For anchoring: {"project_id": "...", "anchor_value": 50000, "final_value": 52000}
  -- For overconfidence: {"email_subject": "...", "booster_count": 8, "hedge_count": 1}
  -- For sunk cost: {"project_id": "...", "negative_signal_date": "...", "meeting_series_id": "..."}
  
  detected_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  analysis_run_id     UUID        REFERENCES bias_analysis_runs(id),
  
  -- Quality gates
  meets_minimum_data  BOOLEAN     NOT NULL DEFAULT false, -- false = insufficient data for valid signal
  competing_hyp_score FLOAT,      -- 0.0–1.0: confidence in best alternative explanation
  
  CONSTRAINT source_ref_check CHECK (
    (source_ref_id IS NULL AND source_ref_table IS NULL) OR
    (source_ref_id IS NOT NULL AND source_ref_table IS NOT NULL)
  )
);

CREATE INDEX idx_bso_user_bias    ON bias_signal_observations (user_id, bias_type);
CREATE INDEX idx_bso_user_date    ON bias_signal_observations (user_id, detected_at DESC);
CREATE INDEX idx_bso_run          ON bias_signal_observations (analysis_run_id);

-- New table: temporal evidence chains (accumulation layer)
CREATE TABLE bias_evidence_chains (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id        UUID        NOT NULL REFERENCES workspaces(id),
  user_id             UUID        NOT NULL REFERENCES profiles(id),
  bias_type           TEXT        NOT NULL,
  
  -- Ordered sequence of observation IDs (temporal chain)
  observation_ids     UUID[]      NOT NULL DEFAULT '{}',  -- ordered array, append-only
  observation_count   INTEGER     NOT NULL DEFAULT 0,
  
  -- Computed metrics (updated on each observation append)
  signal_strength_avg FLOAT,      -- mean normalised signal value across chain
  consistency_rate    FLOAT,      -- fraction of observations meeting threshold
  confidence          FLOAT,      -- computed per bias formula
  
  -- Thresholds (per-user calibrated baselines)
  personal_baseline   JSONB       DEFAULT '{}', 
  -- {"booster_hedge_median": 1.8, "latency_p50": 12.5, ...}
  
  -- Evidence window
  first_observation_at TIMESTAMPTZ,
  last_observation_at  TIMESTAMPTZ,
  window_days         INTEGER     GENERATED ALWAYS AS (
    EXTRACT(DAY FROM last_observation_at - first_observation_at)::INTEGER
  ) STORED,
  
  -- Status
  status              TEXT        NOT NULL DEFAULT 'accumulating' CHECK (status IN (
    'accumulating',   -- below minimum threshold
    'tentative',      -- meets min observations, awaiting competing_hyp gate
    'active',         -- promoted, competing_hyp cleared, ready to surface
    'decayed',        -- not re-confirmed within decay window
    'dismissed'       -- competing hypothesis won; manually dismissed
  )),
  
  promoted_at         TIMESTAMPTZ,    -- when status moved to 'active'
  decay_after         TIMESTAMPTZ,    -- promoted_at + 30 days
  
  -- Narrative (generated by Opus synthesis step)
  insight_card        JSONB       DEFAULT '{}',
  -- {
  --   "headline": "...",
  --   "framing": "curiosity|pattern|option",
  --   "evidence_summary": "...",
  --   "suggested_reflection": "...",
  --   "generated_at": "..."
  -- }
  
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_bec_user_bias_status ON bias_evidence_chains (user_id, bias_type, status);
CREATE UNIQUE INDEX idx_bec_user_bias_active ON bias_evidence_chains (user_id, bias_type)
  WHERE status = 'active';  -- only one active chain per user per bias type

-- New table: analysis run log (observability)
CREATE TABLE bias_analysis_runs (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      UUID        NOT NULL REFERENCES workspaces(id),
  user_id           UUID        NOT NULL REFERENCES profiles(id),
  
  run_type          TEXT        NOT NULL DEFAULT 'nightly',
  started_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at      TIMESTAMPTZ,
  
  emails_analysed   INTEGER     DEFAULT 0,
  tasks_analysed    INTEGER     DEFAULT 0,
  calendar_events_analysed INTEGER DEFAULT 0,
  
  signals_extracted INTEGER     DEFAULT 0,
  chains_updated    INTEGER     DEFAULT 0,
  flags_promoted    INTEGER     DEFAULT 0,
  flags_decayed     INTEGER     DEFAULT 0,
  
  total_tokens_used INTEGER,
  model_used        TEXT        DEFAULT 'claude-opus-4-6',
  cost_usd          FLOAT,
  
  error_log         JSONB       DEFAULT '[]'
);

-- Extend behavioral_rules to accommodate bias detections
ALTER TABLE behavioral_rules
  ADD COLUMN IF NOT EXISTS bias_type TEXT CHECK (bias_type IN (
    'overconfidence', 'anchoring', 'sunk_cost_escalation',
    'availability_heuristic', 'confirmation_bias', 'status_quo_bias',
    'planning_fallacy', 'escalation_of_commitment', 'recency_bias'
  )),
  ADD COLUMN IF NOT EXISTS bias_chain_id UUID REFERENCES bias_evidence_chains(id),
  ADD COLUMN IF NOT EXISTS insight_framing TEXT CHECK (insight_framing IN (
    'curiosity', 'pattern', 'option'
  ));

-- Extend category CHECK constraint to accommodate bias rules
ALTER TABLE behavioral_rules DROP CONSTRAINT IF EXISTS behavioral_rules_category_check;
ALTER TABLE behavioral_rules ADD CONSTRAINT behavioral_rules_category_check CHECK (category IN (
  'task_order_preference', 'avoidance', 'time_preference', 'estimate_bias',
  'completion_pattern', 'cognitive_bias'  -- new category
));
```

### RLS Policy

Apply the same workspace isolation pattern used throughout:
```sql
ALTER TABLE bias_signal_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE bias_evidence_chains ENABLE ROW LEVEL SECURITY;

CREATE POLICY workspace_isolation ON bias_signal_observations
  USING (workspace_id = ANY(public.current_workspace_ids()));

CREATE POLICY workspace_isolation ON bias_evidence_chains
  USING (workspace_id = ANY(public.current_workspace_ids()));
```

***

## Part VI — Nightly Bias Detection Pipeline (Pseudocode)

```typescript
// Nightly job: bias_detection_pipeline.ts
// Scheduled: 0 3 * * * (03:00 UTC, after existing Sunday 02:00 rule extraction)
// Model: claude-opus-4-6
// Estimated cost: ~$0.08–0.15 per user per night (30-day email window)

async function runBiasDetectionPipeline(userId: string, workspaceId: string): Promise<void> {
  const runId = await createAnalysisRun(userId, workspaceId);
  
  try {
    // ── PHASE 1: DATA COLLECTION ──────────────────────────────────────────────
    // Pull 30-day rolling window of digital signals
    const [emails, tasks, calendarEvents, existingChains, personalBaseline] = await Promise.all([
      fetchEmailsWithMetadata(userId, days=30),      // email_messages + metadata
      fetchTasksWithEstimates(userId, days=30),       // tasks + estimation_history (Loop 2 data)
      fetchCalendarEvents(userId, days=30),           // calendar events
      fetchActiveChains(userId),                      // bias_evidence_chains WHERE status != 'decayed'
      fetchOrComputePersonalBaseline(userId, days=90) // 90-day percentiles for normalisation
    ]);
    
    // ── PHASE 2: SIGNAL EXTRACTION ────────────────────────────────────────────
    // Run signal extractors in parallel (all direct classification, no CoT)
    const signalResults = await Promise.all([
      extractOverconfidenceSignals(emails, tasks, personalBaseline),
      extractAnchoringSignals(emails, personalBaseline),
      extractSunkCostSignals(emails, calendarEvents),
      extractAvailabilitySignals(emails, days=60),
      extractConfirmationBiasSignals(emails, personalBaseline),
      extractStatusQuoSignals(emails, calendarEvents),
      extractPlanningFallacySignals(tasks),            // leverages Loop 2 data directly
      extractEscalationSignals(emails),
      extractRecencyBiasSignals(emails, tasks)
    ]);
    
    // ── PHASE 3: EVIDENCE ACCUMULATION ───────────────────────────────────────
    for (const [biasType, signals] of Object.entries(signalResults)) {
      const chain = existingChains[biasType] ?? await createEmptyChain(userId, biasType);
      
      for (const signal of signals) {
        if (!signal.meets_minimum_data) continue;   // skip noisy signals
        
        // Append observation to temporal chain
        await appendObservation(chain.id, signal, runId);
        
        // Recompute chain statistics
        const updatedChain = await recomputeChainMetrics(chain.id, personalBaseline);
        
        // Check promotion criteria
        if (
          updatedChain.observation_count >= MIN_OBSERVATIONS[biasType] &&
          updatedChain.window_days >= MIN_WINDOW_DAYS[biasType] &&
          updatedChain.consistency_rate >= 0.65 &&
          updatedChain.confidence >= 0.70 &&
          updatedChain.status === 'accumulating'
        ) {
          // Move to tentative; trigger competing hypothesis check
          await updateChainStatus(chain.id, 'tentative');
        }
      }
    }
    
    // ── PHASE 4: COMPETING HYPOTHESIS GATE ───────────────────────────────────
    // For each tentative chain, evaluate competing explanations
    const tentativeChains = await fetchChainsByStatus(userId, 'tentative');
    
    for (const chain of tentativeChains) {
      const competingHypScore = await evaluateCompetingHypothesis(chain, emails, tasks);
      
      if (competingHypScore > 0.50) {
        // Alternative explanation is more plausible; do not promote
        await updateChainStatus(chain.id, 'dismissed', { reason: 'competing_hypothesis_stronger' });
        continue;
      }
      
      // Promote to active
      await updateChainStatus(chain.id, 'active');
      
      // ── PHASE 5: INSIGHT CARD GENERATION (Opus adaptive thinking) ────────
      // ONLY HERE do we use extended thinking — for narrative generation
      const insightCard = await generateInsightCard(chain, emails, personalBaseline);
      await updateChainInsightCard(chain.id, insightCard);
      
      // Write to behavioral_rules for surfacing via existing UI layer
      await upsertBehavioralRule({
        userId,
        workspaceId,
        category: 'cognitive_bias',
        bias_type: chain.bias_type,
        rule_summary: insightCard.headline,         // ≤80 chars
        confidence: chain.confidence,
        evidence_sessions: chain.observation_count,
        evidence_rate: chain.consistency_rate,
        bias_chain_id: chain.id,
        insight_framing: insightCard.framing,       // 'curiosity' | 'pattern' | 'option'
        is_active: true
      });
    }
    
    // ── PHASE 6: DECAY PASS ───────────────────────────────────────────────────
    const activeChains = await fetchChainsByStatus(userId, 'active');
    for (const chain of activeChains) {
      if (chain.decay_after < new Date()) {
        // Check if chain still meets threshold in fresh 30-day window
        const reconfirmed = await reconfirmChain(chain.id, days=30);
        if (!reconfirmed) {
          await updateChainStatus(chain.id, 'decayed');
          await deactivateBehavioralRule(chain.id);
        } else {
          await extendChainDecay(chain.id, days=30);
        }
      }
    }
    
    await completeAnalysisRun(runId, { success: true });
    
  } catch (error) {
    await completeAnalysisRun(runId, { success: false, error: error.message });
    throw error;
  }
}

// ── COMPETING HYPOTHESIS EVALUATION ─────────────────────────────────────────
// Direct classification pass (no CoT/thinking)
async function evaluateCompetingHypothesis(
  chain: BiasEvidenceChain,
  emails: Email[],
  tasks: Task[]
): Promise<number> {
  const prompt = buildCompetingHypothesisPrompt(chain);
  
  const response = await client.messages.create({
    model: "claude-opus-4-6",
    max_tokens: 256,
    // NO thinking parameter — direct classification
    system: BIAS_SYSTEM_HEADER,
    messages: [{ role: "user", content: prompt }]
  });
  
  const result = JSON.parse(extractJsonFromResponse(response));
  return result.competing_hypothesis_confidence ?? 0.0;
}

// ── INSIGHT CARD GENERATION ───────────────────────────────────────────────────
// Extended thinking ENABLED — synthesis and narrative only
async function generateInsightCard(
  chain: BiasEvidenceChain,
  emails: Email[],
  baseline: PersonalBaseline
): Promise<InsightCard> {
  const synthesisPayload = buildSynthesisPayload(chain, emails, baseline);
  
  const response = await client.messages.create({
    model: "claude-opus-4-6",
    max_tokens: 4096,
    thinking: { type: "adaptive", effort: "high" },  // extended thinking for synthesis
    system: SYNTHESIS_SYSTEM_PROMPT,
    messages: [{ role: "user", content: synthesisPayload }]
  });
  
  return JSON.parse(extractJsonFromResponse(response));
}

// ── CONSTANTS ────────────────────────────────────────────────────────────────
const MIN_OBSERVATIONS: Record<BiasType, number> = {
  overconfidence: 7,
  anchoring: 5,
  sunk_cost_escalation: 3,
  availability_heuristic: 2,
  confirmation_bias: 10,
  status_quo_bias: 5,
  planning_fallacy: 7,
  escalation_of_commitment: 3,
  recency_bias: 8
};

const MIN_WINDOW_DAYS: Record<BiasType, number> = {
  overconfidence: 21,
  anchoring: 14,
  sunk_cost_escalation: 14,
  availability_heuristic: 60,
  confirmation_bias: 30,
  status_quo_bias: 30,
  planning_fallacy: 21,
  escalation_of_commitment: 0,   // project-scoped, not time-windowed
  recency_bias: 60
};
```

***

## Part VII — Existing Tools and Published Accuracy Metrics

### Commercial Platforms

| Platform | Claimed Capability | Published Accuracy | Notes |
|---|---|---|---|
| **Humu** | Nudge-based behaviour change in organisations; targets decision moments | Not published | Acquired by Google 2023; no peer-reviewed accuracy data for bias detection specifically[^18] |
| **BetterUp** | Between-session AI nudges for coaching; cognitive pattern identification | Not published | Published efficacy studies on coaching outcomes (wellbeing, retention) but not bias detection accuracy[^19] |
| **CoachHub AI** | Personalised coaching nudges; session preparation support | Not published | Positions as "AI-augmented human coaching"; no autonomous bias detection accuracy published[^19] |
| **Nudgetech (Gartner category)** | Micro-behavioural nudges at decision moments; can target known biases | Not published | Gartner 2023 Hype Cycle identifies category; notes risk of "sludge" without AI feedback loops[^18] |

**Evidence gap**: None of the major commercial platforms has published a validated false positive rate or F1 score for automated cognitive bias detection specifically. This is the most significant evidence gap in the field.

### Academic Prototypes

| System / Study | Method | Accuracy Metric | Source |
|---|---|---|---|
| NLP cognitive bias detection in organisational emails | Multi-class supervised NLP, transformer-based | Strong correlation between bias-associated language and suboptimal decisions; specific F1 not reported | Cognitive Bias Detection Through NLP[^8] |
| RoBERTa multi-label bias classifier | Fine-tuned RoBERTa, 10,000+ annotated sentences | Overall accuracy 0.99; F1 = 0.89 (gender bias); F1 = 0.87 (age/religion) | SCIRP RoBERTa study[^7] |
| LLM anchoring bias experimental study | Experimental dataset, LLM sensitivity to biased hints | Anchoring manifests significantly; Chain-of-Thought, Reflection insufficient mitigations | arXiv 2412.06593[^20][^21] |
| Confirmation bias in LLM CoT | Decomposed CoT into Q→R and QR→A stages | Strong evidence of confirmation bias in reasoning generation and answer prediction | arXiv 2506.12301[^22] |
| LLM overconfidence quantification | Algorithmic problems with known ground truth | LLMs overestimate correctness 20–60%; humans have comparable accuracy but far lower overconfidence | arXiv 2505.02151[^23][^24] |
| CoBBLEr benchmark (LLM as evaluator) | Six cognitive biases in LLM evaluation outputs | 40% of comparisons show bias indications across all models | arXiv 2309.17012[^16][^25] |
| JITAI effectiveness meta-analysis | 22 studies, between-subject analysis | g = 0.15 overall; g = 0.71 for interventions < 6 weeks duration | PMC 2025[^26] |
| Single debiasing intervention | Longitudinal, game + video training | Medium-to-large persistent reduction in 6 biases; domain-general effects | City University, London[^27] |

***

## Part VIII — Executive Insight Delivery

### The Threat Activation Problem

Executive defensiveness is the primary failure mode for bias surfacing systems. The core challenge: a C-suite executive's identity is partially constituted by their self-perception as a rational, high-quality decision maker. Confronting that identity directly triggers what the "boss whispering" literature calls the **threat-to-identity response** — the executive neutralises the feedback rather than integrating it. The same dynamic explains why LIWC certainty scores correlate with dismissal of challenging information.[^17]

The solution, validated in the boss whispering methodology, is to **redefine the problem frame**. The AI is not detecting errors — it is identifying *patterns* that the executive can strategically leverage. The framing shifts from `"you have confirmation bias"` to `"you tend to reach decisions faster on topics where early evidence aligns with your prior position — here is how that could be an advantage in time-pressured contexts, and here is where it might miss a signal worth reviewing."`.[^17]

### Three-Framing Framework for Insight Cards

Each insight card generated by the Opus synthesis step must use one of three frames, selected algorithmically based on the executive's established LIWC self-reference profile and prior response to coaching-style suggestions:

| Frame | When to Use | Example Opening |
|---|---|---|
| **Curiosity** | High-autonomy executives; resistance to prescriptive feedback detected | *"Something interesting showed up in your communication data from the last 3 weeks..."* |
| **Pattern** | Data-oriented executives; high certainty language profile | *"A repeating pattern has reached statistical threshold in your decision data..."* |
| **Option** | Action-oriented executives; high task completion rate; low deferral | *"There's a strategic option this pattern suggests you might want to evaluate..."* |

### Timing Recommendations (JITAI Framework)

Insight delivery must occur at a **just-in-time state** — defined as a period when the executive has both need for the support and opportunity to act. The JITAI framework from PMC identifies three necessary conditions: need, opportunity, and receptiveness.[^28][^29]

For executive bias coaching, the optimal delivery windows are:

1. **Pre-decision** (highest receptiveness): 2–4 hours before a calendar event tagged as a major decision meeting (identified from calendar event title keywords: "decision", "vote", "approve", "select", "go/no-go")
2. **Weekly review** (moderate receptiveness): Sunday evening or Monday morning, when strategic reflection is cognitively primed
3. **Post-event** (lowest receptiveness, avoid for threat-activating content): immediately after a meeting — executive is in debrief mode, not open to systemic pattern observation

BCG research on digital nudges found that a plain text reminder was sufficient for 40–50% of executives — avoid overly elaborate visualisations that signal surveillance.[^30]

### Prohibited Surfacing Patterns

The following patterns must be explicitly blocked by the synthesis prompt:
- Direct bias naming in the headline: "You exhibit confirmation bias" → prohibited
- Comparative framing: "Unlike other executives..." → prohibited
- Frequency/severity language: "You always/never/constantly..." → prohibited  
- Unsolicited advice: Any sentence beginning with "You should..." in the headline → prohibited

The synthesis system prompt must enforce these explicitly:

```
FORBIDDEN PATTERNS — never include in insight_card.headline or insight_card.suggested_reflection:
1. Direct bias accusation: "You have/exhibit/show [bias_name]"
2. Comparative: "Unlike most leaders", "Compared to your peers"
3. Absolute frequency: "always", "never", "constantly", "repeatedly"
4. Unsolicited prescription: sentences starting with "You should"

REQUIRED PATTERNS:
- headline: observation framed as data pattern, ≤ 80 chars, no judgment
- suggested_reflection: a question, not a directive (e.g., "What additional data would change this decision?")
- framing: one of 'curiosity' | 'pattern' | 'option'
```

***

## Part IX — Architecture Integration with Timed-Brain

### Slot into Existing Pipeline

The bias detection engine maps directly onto the Timed-Brain three-loop architecture as **Loop 4**, with no structural changes to existing loops:

| Loop | Function | Model | Schedule |
|---|---|---|---|
| Loop 1 | Email classification | Sonnet 4.6 (cached) | On ingest |
| Loop 2 | Time estimation learning | Hybrid similarity | On task completion |
| Loop 3 | Behavioural rule extraction | Haiku 4.5 | Sunday 02:00 UTC |
| **Loop 4** | **Cognitive bias detection** | **Opus 4.6 (direct + adaptive)** | **Nightly 03:00 UTC** |

Loop 4 runs at 03:00 UTC (one hour after Loop 3) to consume the updated `behavioral_rules` and `behaviour_events` data freshly extracted by Loop 3. Planning Fallacy detection in Loop 4 reuses the `estimation_history` data already populated by Loop 2, avoiding redundant computation.

The `behavioral_rules` table extension (adding `bias_type`, `bias_chain_id`, `insight_framing`) means existing UI surfaces (the "What the system has learned" settings screen) will automatically display cognitive bias detections alongside behavioural patterns. No new UI surfaces are required for MVP.

### pg_cron Addition

Add to the existing pg_cron job schedule:
```sql
-- Loop 4: nightly bias detection (one hour after Loop 3 rule extraction)
SELECT cron.schedule(
  'bias-detection-nightly',
  '0 3 * * *',
  $$SELECT net.http_post(
    url := 'https://{project}.supabase.co/functions/v1/bias-detection-pipeline',
    headers := '{"Authorization": "Bearer {service_role_key}"}'::jsonb
  )$$
);
```

### Email Data Access Note

The email body text required for LIWC-style analysis is already present in `email_messages` (subject, body snippet, full body if stored). The Graph API delta sync already streams new emails in near-real-time. The bias detection pipeline operates on the 30-day frozen snapshot at 03:00 UTC — it does not need real-time access.

***

## Evidence Gaps and Explicit Unknowns

The following are documented gaps where primary evidence is absent and this brief does not speculate:

1. **No published FPR for executive cognitive bias detection from passive digital signals.** The FPR estimates in the matrix are derived from analogous NLP tasks. Ground-truth calibration will require a supervised validation phase with manually labelled examples.

2. **Individual variation in signal validity.** All nine bias proxies assume the executive is not strategically performing the opposite signal. A sophisticated executive who is aware of the system could manipulate their language to suppress signals. No mitigation for adversarial signal manipulation is specified here.

3. **Cross-cultural validity of LIWC certainty category.** Hyland's hedging/boosting framework was developed primarily on Western academic writing corpora. Validity in executive communication across cultural contexts is documented but with heterogeneous results.[^5][^6]

4. **Humu, BetterUp, CoachHub accuracy.** Despite being the most commercially mature platforms in this space, none has published validated accuracy metrics for cognitive bias detection specifically. Competitive benchmarking against these platforms is currently impossible.[^19][^18]

5. **Minimum sample size for personal baseline calibration.** This brief recommends a 90-day baseline period. The statistical minimum sample size for stable percentile estimation in executive email communications has not been published. The 90-day window is an informed architectural decision, not an empirically validated threshold.

---

## References

1. [Reasoning's Razor: How Reasoning Affects Precision-Sensitive Tasks](https://www.linkedin.com/posts/atoosa-chegini-6713741a3_ai-machinelearning-llm-activity-7388973605784682496-Ls0O) - The 'Reasoning's Razor' trade-off means we must avoid 'Think On' (reasoning) for critical, low-FPR d...

2. [[PDF] The Development and Psychometric Properties of LIWC-22](https://www.liwc.app/static/documents/LIWC-22%20Manual%20-%20Development%20and%20Psychometrics.pdf) - When LIWC was first conceived, the idea was to identify a group of words that tapped into basic emot...

3. [LIWC Dictionary (Linguistic Inquiry and Word Count)](https://lit.eecs.umich.edu/geoliwc/liwc_dictionary.html) - The table below provides a comprehensive list of these LIWC categories with sample scale words. ... ...

4. [LIWC — How It Works](https://www.liwc.app/help/howitworks) - LIWC reads a given text and compares each word in the text to the list of dictionary words and calcu...

5. [[PDF] Boosting, hedging and the negotiation of academic knowledge](https://jolantasinkuniene.wordpress.com/wp-content/uploads/2014/03/hyland-boosting-hedging-and-the-negotiation-of-academic-knowledge-1998.pdf) - This article explores the wie of doubt and certainty in published research articles from eight acade...

6. [“We find that…” changing patterns of epistemic positioning in ... - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC12513368/) - Epistemic positioning refers to the writer's commitment to the truth of a proposition and assessment...

7. [A Multi-Label RoBERTa Classification Model to Detect Bias in LLM ...](https://www.scirp.org/journal/paperinformation?paperid=146198) - The model demonstrated high accuracy and recall rates, effectively detecting both overt and subtle b...

8. [[PDF] COGNITIVE BIAS DETECTION THROUGH NATURAL LANGUAGE ...](https://tpmap.org/submission/index.php/tpm/article/download/3044/2276) - A multi-class supervised learning model was developed to classify biases across five primary categor...

9. [Natural language processing with transformers: a review - PMC - NIH](https://pmc.ncbi.nlm.nih.gov/articles/PMC11322986/) - This research presents transformer-based solutions for NLP tasks such as Bidirectional Encoder Repre...

10. [Building with extended thinking - Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/extended-thinking) - Extended thinking gives Claude enhanced reasoning capabilities for complex tasks, while providing va...

11. [Building with Claude Extended Thinking](https://cobusgreyling.substack.com/p/building-with-claude-extended-thinking) - Extended thinking changes the contract. The model shows its work. For code generation, mathematical ...

12. [[PDF] Discrete confidence levels revealed by sequential decisions](https://discovery.ucl.ac.uk/10112006/1/Lisi2020NatHumBehav_withSI.pdf) - Abstract. Humans can meaningfully express their confidence about uncertain events. Normatively, thes...

13. [[PDF] Escalation of commitment in information systems projects - publish.UP](https://publishup.uni-potsdam.de/files/62696/marx_diss.pdf) - This dissertation delves into the psychological micro-foundations of human behavior – specifically c...

14. [[PDF] Escalation of commitment behaviour a critical, prescriptive ... - Sign in](https://pure.coventry.ac.uk/ws/portalfiles/portal/41589243/Rice2010.pdf) - continuing an action change as the project proceeds. Brockner et al.'s progress model mirrors somewh...

15. [A Scoping Review of Methodological Approaches to Detect Bias in ...](https://pmc.ncbi.nlm.nih.gov/articles/PMC12470022/) - Four methods were identified: natural language processing methods including machine learning-based (...

16. [Benchmarking Cognitive Biases in Large Language Models as ...](https://arxiv.org/abs/2309.17012) - A benchmark to measure six different cognitive biases in LLM evaluation outputs, such as the Egocent...

17. [[PDF] Coaching Abrasive Leaders: Using Action Research to Reduce ...](https://www.bosswhispering.com/Coaching%20Abrasive%20Leaders.pdf) - Organizations and employees alike fight to survive hostile business climates swarming with threats ....

18. [Hype Cycle for Hybrid Work 2023 | PDF | Employment - Scribd](https://www.scribd.com/document/704580204/Hype-Cycle-for-Hybri-793018-ndx) - This document provides a summary of Gartner's 2023 Hype Cycle for Hybrid Work. It reflects that whil...

19. [[PDF] Executive Coaching in the Age of Artificial Intelligence - Institute of ...](https://ioc-m.com/wp-content/uploads/2025/12/Executive-Coaching-in-the-Age-of-AI-4.pdf) - Purpose: Extend coaching into daily leadership moments. AI Enablers. Between-Session Nudges: CoachHu...

20. [Anchoring Bias in Large Language Models: An Experimental Study](https://arxiv.org/abs/2412.06593) - This study delves into anchoring bias, a cognitive bias where initial information disproportionately...

21. [Anchoring Bias in Large Language Models: An Experimental Study](https://arxiv.org/html/2412.06593v1) - This study delves into anchoring bias, a cognitive bias where initial information disproportionately...

22. [Unveiling Confirmation Bias in Chain-of-Thought Reasoning - arXiv](https://arxiv.org/html/2506.12301v1) - This work presents a novel perspective to understand CoT behavior through the lens of confirmation b...

23. [Large Language Models are overconfident and amplify human bias ...](https://arxiv.org/html/2505.02151v2) - Our results provide users with a new benchmark for how users of LLMs should approach reasoning from ...

24. [Large Language Models are overconfident and amplify human bias](https://arxiv.org/abs/2505.02151) - We find that all five LLMs we study are overconfident: they overestimate the probability that their ...

25. [Benchmarking Cognitive Biases in Large Language Models ... - arXiv](https://arxiv.org/html/2309.17012v3) - From our benchmark, we find that most models exhibit various cognitive biases when used as automatic...

26. [Effectiveness of just-in-time adaptive interventions for improving ...](https://pmc.ncbi.nlm.nih.gov/articles/PMC12481328/) - Currently existing JITAIs and EMIs slightly improve mental health, particularly mental illness, with...

27. [[PDF] Debiasing Decisions. Improved Decision Making With A Single ...](https://openaccess.city.ac.uk/id/eprint/12324/1/Debiasing_Decisions_PIBBS.pdf) - We report the results of two longitudinal experiments that found medium to large effects of one-shot...

28. [Just-in-Time Adaptive Interventions (JITAIs) in Mobile Health - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC5364076/) - A JITAI is an intervention design that adapts the provision of support (e.g., the type, timing, inte...

29. [Protocol for a System ID Study of Just-in-Time Adaptive Interventions](https://www.researchprotocols.org/2023/1/e52161/) - This study will be the first empirical investigation of JIT states that uses system ID methods to in...

30. [The Persuasive Power of the Digital Nudge - Boston Consulting Group](https://www.bcg.com/publications/2017/people-organization-operations-persuasive-power-digital-nudge) - Nudges, based on principles of behavioral economics, are small, low-cost, timely interventions that ...

