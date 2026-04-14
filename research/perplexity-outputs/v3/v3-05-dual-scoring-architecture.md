# Dual-Scoring Architecture for Timed-Brain: Score Conflict Resolution, Latency-Accuracy Tradeoffs, and Production Implementation

## Executive Summary

The dual-scoring architecture — real-time Haiku at ingestion, nightly Sonnet with full-day context — is structurally identical to the two-stage retrieval-reranking paradigm dominant in information retrieval and the fast/slow layer pattern in Lambda Architecture. The published literature is unambiguous on the primary principle: **the batch score is epistemically superior because it has more context, but the real-time score is operationally superior because it arrives in time to act**. Conflict resolution therefore depends entirely on the downstream use case, not on a single unified policy.

The core architectural finding: no existing primary research describes a production system that silently overwrites real-time scores with batch scores for alert-generating pipelines. Every documented production system — clinical decision support, SOC alert management, information retrieval cascade — treats the two scores as serving different functions and applies use-case-specific resolution logic. This report specifies that logic for each of the four downstream consumers in Timed-Brain, provides pseudocode for the reconciliation pipeline, a database schema extension built on the existing `emails`/`ai_pipeline_runs` tables, and a latency-accuracy tradeoff analysis grounded in primary sources.

***

## 1. Published Precedents: Dual-Pass and Cascaded Classification

### 1.1 Information Retrieval: Retrieve-and-Rerank

The canonical two-stage cascade in information retrieval uses a fast bi-encoder retriever (BM25, bi-encoder with dot-product similarity) as stage 1 and a slower, higher-accuracy cross-encoder reranker as stage 2. The design principle maps directly to the Timed-Brain architecture: stage 1 produces a fast approximate score enabling immediate downstream action (result selection); stage 2 refines within a candidate set. A critical architectural property documented in this literature: **the reranker cannot recover from a miss in stage 1** — if a document is not retrieved in stage 1, stage 2 cannot resurface it. The analogue in Timed-Brain is that if Haiku misses a high-importance observation entirely (scores it below the alert threshold), the Sonnet batch pass cannot retroactively alert.[^1][^2]

MICE (Minimal Interaction Cross-Encoders, arXiv 2026) demonstrates a fourfold latency reduction while preserving reranker accuracy by limiting cross-attention to top retrieved tokens. This is structurally a confidence-gated cascade: expensive inference only activates above a retrieval confidence threshold.[^2]

### 1.2 LLM Inference: Early Exit and Speculative Decoding

LayerSkip (Meta AI/ACL 2024) trains LLMs with layer dropout and an early-exit loss, enabling inference to exit at earlier transformer layers and verify with remaining layers via self-speculative decoding. The key finding from LayerSkip experiments: accuracy at early exit layers degrades gracefully but measurably — earlier exits trade accuracy for latency, and the tradeoff curve is monotonic but non-linear. There are accuracy "cliffs" at specific layer depths where performance drops sharply. This is directly analogous to the Haiku/Sonnet difference: Haiku is, in effect, a shallow-exit version of the Sonnet computation, but without shared weights. The practical implication is that Haiku's errors are not uniformly distributed across importance levels — it tends to misclassify at precisely the uncertain mid-range (0.55–0.75), which is why the existing architecture already routes that band to Sonnet.[^3][^4]

Early-exiting Speculative Decoding (EESD, arXiv 2024) formalizes the draft-verify pattern: a segment of the LLM generates draft tokens, and the full model validates them in a single forward pass. In the Timed-Brain context, this is conceptually equivalent to: Haiku issues a "draft score," Sonnet verifies it with full context at batch time. However, the key distinction is that EESD provides lossless acceleration (the output distribution is identical to the full model), whereas dual-model scoring with different context windows introduces genuine epistemic disagreement, not just computational approximation.[^5]

### 1.3 Clinical Decision Support: Staged Alert Architecture

The clinical decision support literature provides the richest precedent for alert-generation conflict resolution. A semi-automated CDSS study published in the *Swiss Medical Weekly* (2023) found that fully automated direct alerts achieved 89.8% physician acceptance, while pharmacist-reviewed alerts (equivalent to the batch pass in Timed-Brain) achieved 68.4% acceptance — demonstrating that intermediate human/model review does not automatically improve trust or accuracy from the user's perspective when it introduces latency.[^6]

A landmark review on clinical decision support stewardship (PMC/JAMIA, 2022) establishes the core principle: "Humans are adept at probability matching and identify unreliable alerts after only a small number of exposures". Alert credibility is established or destroyed at the system level — users calibrate to the alert stream's false-positive rate, not to individual alerts. An alert system that generates false positives at a rate above approximately 30–40% will trigger alert fatigue in which true-positive alerts are also ignored.[^7][^8][^9]

The REACT model (Reliable, Evaluated, Actionable, Correct, Timely) from the security operations literature identifies the five qualities of an effective alert. In dual-scoring architectures, the conflict between R (reliable = Sonnet) and T (timely = Haiku) is precisely the design tension this document resolves.[^9]

### 1.4 Panther Security Platform: Real-Time + Scheduled Rule Combination

The Panther security platform (Jack Naglieri, 2024) uses a three-mode detection architecture: atomic real-time rules for high-confidence single-event indicators, scheduled rules for aggregate historical analysis, and correlation/sequence detection rules. This maps almost exactly onto the Timed-Brain architecture: Haiku handles atomic high-confidence scoring, Sonnet handles pattern detection across the day's full context. Panther's design explicitly avoids using batch aggregate results to retract real-time atomic alerts — the two are treated as complementary signal sources answering different questions.[^10]

***

## 2. Decision Matrix: Score Trust by Use Case

The following matrix specifies which score to trust for each downstream consumer, the conflict resolution strategy when scores disagree, and the rationale derived from the literature.

| Use Case | Primary Score | Conflict Strategy | Rationale |
|---|---|---|---|
| **Alert Generation** | Haiku real-time (if ≥ 0.85) | Do NOT retract; annotate if batch downgrades to < 0.5 | Alert latency is irreversible — a 2am batch confirmation cannot recover a 2pm missed action. Clinical CDS evidence: alert trust is built by reliability of the alert stream, not by individual retroactive corrections[^7]. |
| **Daily Summary Weighting** | Sonnet batch (authoritative) | Replace Haiku weight; no notification to user | Summary generation happens after batch completes. Using Sonnet score improves summary quality at zero trust cost — user never sees the intermediate Haiku score in summary context. |
| **Memory Retrieval Ranking** | Sonnet batch (authoritative) | Replace Haiku weight with logged delta | Memory retrieval happens at query time, well after batch pass. Using Sonnet score yields more accurate retrieval. Delta logged for drift analysis. |
| **Pattern Detection / Anomaly Detection** | Haiku real-time (as event stream) + Sonnet batch (as validated signal) | Two separate signals; do not merge | Anomaly detection requires the real-time signal to detect intra-day anomalies. Sonnet batch signal is input to nightly pattern extraction. Merging destroys temporal signal granularity needed for drift detection. |

**Critical override rule**: If `haiku_score ≥ 0.90` AND `sonnet_score ≤ 0.35` (a large conflict), this is a sentinel event requiring logging to a `score_discrepancy_audit` table and a weekly review. It indicates either Haiku prompt calibration drift or Sonnet context causing systematic downgrade of a true category. This should not be silently reconciled.

***

## 3. Recency Bias Analysis and Debiasing Strategies

### 3.1 The Recency Bias Mechanism

Real-time Haiku scoring is structurally susceptible to recency bias in the following specific way: each observation is scored in isolation, without knowledge of how many similar observations have already arrived that day. An email from a board member at 9am scores differently than the same email at 4pm (when a dozen board communications have already been processed), but Haiku cannot distinguish these contexts. This is not a model quality issue — it is a context gap by design.

A secondary form of recency bias emerges from scoring order within a burst ingestion event. If 50 emails arrive at morning sync, Haiku scores each independently; if those emails collectively signal an escalating crisis (thread escalation, multiple stakeholders, increasing urgency cues), the accumulation signal is lost. Sonnet sees all 50 before scoring.

This pattern is a form of concept drift in classification: the appropriate importance score for an observation depends on the distributional context of that day's observation set. The D3A (Concept Drift Detection and Adaptation) framework addresses this via error rate monitoring — when the error rate between real-time and batch scores exceeds a statistical threshold, the real-time model's calibration should be updated.[^11][^12]

### 3.2 Debiasing Strategies

**Strategy 1: Day-context injection at ingestion (Recommended).**
Pass a compact day-context bundle with every Haiku scoring call. This does not require Sonnet — it is structured metadata: `{hour_of_day, day_of_week, observations_ingested_today: N, observation_types_today: {email: N, calendar: N, app: N}, top_domains_today: [...]}`. This eliminates the context gap for quantifiable signals without waiting for batch. Cost: ~100 additional input tokens per call at Haiku rates ($1/MTok) = $0.0001/observation.

**Strategy 2: Running mean-normalization.**
Maintain a rolling 7-day importance distribution per observation type. Normalize Haiku raw scores against the trailing distribution: `normalized_score = (raw_score - rolling_mean) / rolling_std`. Store both raw and normalized scores. This prevents the first email of a new type being scored against population priors that do not reflect the user's current context. Implements the distributional anchoring described in online Bayesian updating frameworks.[^13][^14]

**Strategy 3: Score velocity monitoring.**
Track the rate at which Haiku scores trend high or low within a session. If > 60% of observations in the first 2 hours score above 0.75, suppress incremental alerts but maintain the score for downstream use. This addresses burst recency bias — the user is unlikely to take 30 simultaneous actions on 30 high-importance items.

**Strategy 4 (advanced): Bayesian posterior update.**
Treat the Haiku score as a prior and the Sonnet batch context as likelihood evidence. The posterior score is:

\[ P(importance \mid obs, day\text{-}context) \propto P(day\text{-}context \mid importance) \cdot P(importance \mid obs) \]

In practice, implement this as a weighted combination:

\[ score_{authoritative} = w_{haiku} \cdot score_{haiku} + w_{sonnet} \cdot score_{sonnet} \]

where \(w_{haiku} = 0.3\) and \(w_{sonnet} = 0.7\) as starting weights, calibrated monthly against user feedback (corrections, alert dismissals). This is structurally identical to the hybrid similarity scorer in the existing Loop 2 architecture — extend the same weighting framework here.

**Evidence gap**: No primary research exists that specifically measures recency bias magnitude in LLM-based sequential observation scoring for personal productivity applications. The above strategies are derived from adjacent literature (concept drift, online Bayesian updating, distributional normalization). Empirical calibration against Timed-Brain's own historical data is required after 4+ weeks of dual-scoring operation.

***

## 4. Alert Threshold Analysis: Real-Time vs. Deferred Batch Confirmation

### 4.1 The Core Latency-Accuracy Tradeoff

The Clipper prediction serving system (NSDI 2017) articulates the fundamental principle: **"rendering a late prediction is worse than rendering an inaccurate prediction"** for time-sensitive decisions. The system's adaptive batching component uses this principle to set SLOs (service level objectives) — it accepts lower accuracy in exchange for bounded latency. This is the production evidence base for the Timed-Brain threshold decision.[^15]

The specific tradeoff for a 2pm email with Haiku score 0.9:

- **If the alert fires at 2pm and the batch confirms it at 2am**: The user had 12 hours to act. Alert was useful.
- **If the alert fires at 2pm and the batch downgrades it at 2am**: The user received an interruption but the information was available. Trust degrades by some increment (see Section 5).
- **If the alert is held until 2am confirmation**: The user missed the action window entirely. Worse outcome regardless of batch score accuracy.

The only scenario where waiting for batch confirmation is superior to immediate alerting is when the alert would generate an action that is harmful if taken prematurely (e.g., a draft communication that should not be sent before verification). For Timed-Brain's alert function (notification to executive, not automated action), immediate alerting is always at least as good as deferred, provided the false-positive rate is tolerable.

### 4.2 Threshold Recommendations by Observation Type

The following thresholds are grounded in the alarm recognition research (PMC 2025) which demonstrates that high-priority alarm discrimination depends on perceptual contrast between alarm levels, and in the SOC false positive data (Vectra 2026) which shows that >46% false positive rates disable trust.[^8][^16]

| Haiku Score Band | Alert Action | Rationale |
|---|---|---|
| **≥ 0.90** | Alert immediately; no batch gate | At this confidence, Haiku's cross-model accuracy is high enough that waiting costs more than it saves. Comparable to SAS routing system's τ=0.70 crossover at 97%/93% precision/recall[^17]. |
| **0.80–0.89** | Alert with confidence indicator shown | Alert fires but UI labels it "Preliminary — confirmed by end of day". Reduces trust damage from downgrades (see Section 5). |
| **0.75–0.79** | Queue for batch confirmation; no immediate alert | In the uncertain band but above the existing 0.75 upper limit. Batch Sonnet will re-score; alert fires if Sonnet confirms ≥ 0.75. |
| **0.55–0.74** | Existing uncertain band behavior; Sonnet batch only | No change from current architecture. |
| **< 0.55** | No alert; record for pattern detection | Below uncertain band; use only for nightly Haiku pass statistics. |

**Special case — calendar/deadline proximity modifier**: Observations within 48 hours of a detected deadline should have their effective threshold lowered by 0.10 (i.e., a score of 0.80 triggers immediate alert if a related deadline is imminent). Implement as a post-scoring modifier, not a model parameter.

### 4.3 Latency Budget for Supabase Edge Function Architecture

The existing pipeline returns HTTP response in <100ms and processes in `waitUntil` up to 400s. Haiku's median latency on a 200-token classification call at current API rates is approximately 300–800ms (no primary benchmark for Haiku 4.5 as of April 2026; use conservative end). The `classify-email-worker` processes 5 emails per invocation every 10 seconds. This means:

- **Time from Graph notification to Haiku score**: < 15 seconds (2 pg_cron cycles + Haiku latency)
- **Time from Graph notification to Sonnet batch score**: up to 26 hours (nightly 2am batch)

The latency gap between the two scoring events is therefore 25–26 hours for most observations. Any alert that requires Sonnet confirmation is effectively a next-day alert — architecturally unsuitable for intraday operational decisions.

***

## 5. Surfacing Score Revisions: Alert Retraction, Annotation, or Silent Update

### 5.1 Primary Research on Alert Revision Trust

The most directly applicable primary source is Yang et al. (MIT CSAIL/HRI 2017), which measured real-time trust dynamics in human-automation interaction with alarm systems. The key finding: **"When the threat detector gave false alarms, Trust\_t decreased"** and the decrement was measured as immediate and significant. Critically, likelihood alarms (probabilistic confidence shown) resulted in initial overtrust followed by trust adjustment, whereas binary alarms produced monotonic trust increase. For Timed-Brain, this argues strongly for showing confidence indicators rather than binary alerts.[^18]

The notification trust study (UserIntuition 2025) established that 52% of users who disable notifications never re-enable them, making a single notification failure mode potentially permanent. The ACM notification preference research (CHI 2022) found that users prefer suppression over deferral when managing undesired interruptions.[^19][^20]

Airship's 2023 study found that once users disable notifications, they rarely re-enable even when the product improves. This asymmetric trust dynamic (trust lost faster than gained) is confirmed in broader trust literature: "trust is built slowly but lost quickly".[^21][^19]

### 5.2 Recommended Alert Revision Policy

Based on the above evidence, three policies apply depending on the scenario:

**Policy 1: Silent update (DO USE for summary/memory/pattern)**
When batch score diverges from real-time score for downstream uses that are not user-facing (summary weighting, memory ranking, anomaly detection), silently update `authoritative_score` in the database. Log the delta to `score_audit_log`. Never surface this to the user. These are system-internal quality improvements; exposing them creates noise without value.

**Policy 2: Annotation (DO USE for batched alert downgrade)**
When an alert was sent at real-time (Haiku ≥ 0.85) and Sonnet downgrades to < 0.65, append an annotation to the alert record: `"Context updated: our model has revised the importance of this item."` Do not retract the alert message already delivered. Retraction of delivered notifications is uniquely trust-damaging because it creates meta-uncertainty ("should I trust alerts that might be retracted?"). Nielsen Norman Group's progressive disclosure guidelines confirm: users should be able to discover corrections without the corrections being forced into their attention stream.[^22]

**Policy 3: Never retract (DO USE universally for push notifications)**
Once a push notification has been delivered to the executive's device, it should never be retracted. The retraction mechanism itself causes a notification (the retraction), doubling the interruption while also eroding the user's mental model of what the system knows. The correct architecture is: fire a reliable notification stream with well-calibrated thresholds rather than retract after the fact. If the false-positive rate is high enough to justify retraction, the threshold is wrong — reduce the threshold instead.

**Exception**: If the batch pass reveals that a real-time alert was triggered by a known bad signal (e.g., a phishing email misclassified as important), the appropriate response is to add an explanatory annotation and flag it as a correction event that feeds Loop 1 retraining.

***

## 6. Data Structures and Schema for Dual-Scored Observations

### 6.1 Schema Extension to Existing Tables

The current `emails` table has `classification_confidence FLOAT` and `classified_at TIMESTAMPTZ`. The existing `ai_pipeline_runs` table records `model_used`, `result_confidence`, and `result_label`. The schema extension adds dual-scoring fields to `email_messages` (and analogously to any future `observations` table), a score audit log, and an alert state tracker.

#### Migration: `email_messages` Dual-Scoring Extension

```sql
-- Add dual-scoring fields to email_messages
ALTER TABLE email_messages
  ADD COLUMN rt_score            FLOAT,          -- Haiku real-time score (0-1)
  ADD COLUMN rt_scored_at        TIMESTAMPTZ,    -- when Haiku scored it
  ADD COLUMN rt_model            TEXT DEFAULT 'claude-haiku-4-5-20251001-v1:0',
  ADD COLUMN batch_score         FLOAT,          -- Sonnet batch score (0-1)
  ADD COLUMN batch_scored_at     TIMESTAMPTZ,
  ADD COLUMN batch_model         TEXT DEFAULT 'claude-sonnet-4-6-20250929-v1:0',
  ADD COLUMN authoritative_score FLOAT           -- active score for all queries
    GENERATED ALWAYS AS (
      COALESCE(batch_score, rt_score)            -- batch wins when available
    ) STORED,
  ADD COLUMN score_source        TEXT            -- 'realtime' | 'batch' | 'user_override'
    GENERATED ALWAYS AS (
      CASE
        WHEN batch_score IS NOT NULL THEN 'batch'
        WHEN rt_score IS NOT NULL    THEN 'realtime'
        ELSE NULL
      END
    ) STORED,
  ADD COLUMN score_conflict      BOOLEAN         -- true when |rt - batch| > 0.30
    GENERATED ALWAYS AS (
      CASE
        WHEN rt_score IS NOT NULL AND batch_score IS NOT NULL
          AND ABS(rt_score - batch_score) > 0.30
        THEN true
        ELSE false
      END
    ) STORED,
  ADD COLUMN score_delta         FLOAT           -- signed delta (batch - rt)
    GENERATED ALWAYS AS (
      batch_score - rt_score
    ) STORED,
  ADD COLUMN alert_fired_at      TIMESTAMPTZ,    -- when alert was sent
  ADD COLUMN alert_score         FLOAT,          -- score at time of alert
  ADD COLUMN alert_model         TEXT;           -- which model triggered alert
```

**Note**: `authoritative_score` is a generated column — it automatically points to `batch_score` once that column is populated, and falls back to `rt_score` before batch completes. All downstream queries (summary weighting, memory retrieval) that join on `authoritative_score` are automatically correct without application-layer reconciliation.

#### Score Audit Log Table

```sql
CREATE TABLE score_audit_log (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      UUID        NOT NULL REFERENCES workspaces(id),
  observation_id    UUID        NOT NULL,    -- references email_messages.id or future obs table
  observation_type  TEXT        NOT NULL CHECK (observation_type IN ('email', 'calendar', 'app_usage')),
  
  -- Score event
  event_type        TEXT        NOT NULL CHECK (event_type IN (
    'realtime_scored',
    'batch_scored',
    'user_override',
    'conflict_detected',
    'alert_fired',
    'alert_annotated'
  )),
  score_value       FLOAT       NOT NULL,
  model_id          TEXT        NOT NULL,    -- full model version string
  context_tokens    INT,                     -- how many context tokens fed to model
  
  -- Conflict metadata (populated on conflict_detected events)
  prior_score       FLOAT,
  prior_model       TEXT,
  delta_abs         FLOAT GENERATED ALWAYS AS (ABS(score_value - COALESCE(prior_score, 0))) STORED,
  conflict_severity TEXT GENERATED ALWAYS AS (
    CASE
      WHEN ABS(score_value - COALESCE(prior_score, 0)) >= 0.50 THEN 'critical'
      WHEN ABS(score_value - COALESCE(prior_score, 0)) >= 0.30 THEN 'major'
      WHEN ABS(score_value - COALESCE(prior_score, 0)) >= 0.15 THEN 'minor'
      ELSE 'negligible'
    END
  ) STORED,
  
  pipeline_run_id   UUID        REFERENCES ai_pipeline_runs(id),
  occurred_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  metadata          JSONB       DEFAULT '{}'
) PARTITION BY RANGE (occurred_at);

-- Monthly partitions (extend behaviour_events partition pattern)
CREATE INDEX idx_sal_workspace_obs     ON score_audit_log (workspace_id, observation_id);
CREATE INDEX idx_sal_conflict_severity ON score_audit_log (conflict_severity, occurred_at DESC)
  WHERE event_type = 'conflict_detected';
CREATE INDEX idx_sal_occurred          ON score_audit_log (occurred_at DESC);
```

#### Alert State Table

```sql
CREATE TABLE alert_states (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id     UUID        NOT NULL REFERENCES workspaces(id),
  observation_id   UUID        NOT NULL,
  observation_type TEXT        NOT NULL,
  
  -- Alert lifecycle
  status           TEXT        NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'fired', 'confirmed', 'downgraded', 'annotated', 'dismissed')),
  fired_at         TIMESTAMPTZ,
  fire_score       FLOAT,                    -- score at time of firing
  fire_model       TEXT,
  
  -- Batch reconciliation
  batch_score      FLOAT,
  batch_reconciled_at TIMESTAMPTZ,
  reconciliation_action TEXT               -- 'confirmed' | 'annotated' | 'none'
    CHECK (reconciliation_action IN ('confirmed', 'annotated', 'none')),
  annotation_text  TEXT,
  
  -- User response
  user_dismissed_at  TIMESTAMPTZ,
  user_action_taken  BOOLEAN DEFAULT false,
  
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_alert_states_workspace    ON alert_states (workspace_id, status, fired_at DESC);
CREATE INDEX idx_alert_states_observation  ON alert_states (observation_id);
CREATE UNIQUE INDEX idx_alert_states_obs_unique ON alert_states (observation_id) 
  WHERE status NOT IN ('dismissed');
```

### 6.2 Indexing Strategy for Dual-Score Queries

Four query patterns must be efficient:

**Pattern 1 — Alert generation** (real-time, hot path):
```sql
-- Query: new observations above RT alert threshold not yet alerted
SELECT id, rt_score, rt_scored_at, subject, sender_email
FROM email_messages
WHERE workspace_id = $workspace_id
  AND rt_score >= 0.85
  AND alert_fired_at IS NULL
  AND rt_scored_at > now() - interval '10 seconds';

-- Index:
CREATE INDEX idx_em_rt_alert_candidates ON email_messages 
  (workspace_id, rt_score DESC, rt_scored_at DESC) 
  WHERE alert_fired_at IS NULL AND rt_score >= 0.75;
```

**Pattern 2 — Summary weighting** (nightly batch, uses authoritative_score):
```sql
-- Query: today's observations ordered by authoritative score for summary
SELECT id, subject, sender_email, authoritative_score, score_source
FROM email_messages
WHERE workspace_id = $workspace_id
  AND received_at >= date_trunc('day', now())
ORDER BY authoritative_score DESC NULLS LAST;

-- Index: authoritative_score is GENERATED STORED, so it's indexable
CREATE INDEX idx_em_authoritative_daily ON email_messages 
  (workspace_id, authoritative_score DESC, received_at DESC);
```

**Pattern 3 — Conflict monitoring** (observability):
```sql
-- Query: all conflicts in the last 7 days for calibration review
SELECT observation_id, rt_score, batch_score, score_delta, score_conflict
FROM email_messages
WHERE workspace_id = $workspace_id
  AND score_conflict = true
  AND batch_scored_at >= now() - interval '7 days'
ORDER BY ABS(score_delta) DESC;

-- Index:
CREATE INDEX idx_em_score_conflicts ON email_messages 
  (workspace_id, batch_scored_at DESC) 
  WHERE score_conflict = true;
```

**Pattern 4 — Memory retrieval ranking** (pgvector + score):
```sql
-- Hybrid query: semantic similarity + authoritative score
SELECT id, subject, authoritative_score,
  1 - (embedding <=> $query_embedding) AS semantic_sim,
  (0.6 * authoritative_score + 0.4 * (1 - (embedding <=> $query_embedding))) AS combined_rank
FROM email_messages
WHERE workspace_id = $workspace_id
  AND authoritative_score >= 0.5
ORDER BY combined_rank DESC
LIMIT 20;

-- Existing HNSW index on embedding covers the vector component
-- Add partial filter index for authoritative_score threshold:
CREATE INDEX idx_em_memory_candidates ON email_messages 
  (workspace_id) INCLUDE (authoritative_score, embedding)
  WHERE authoritative_score >= 0.5;
```

### 6.3 Supabase Realtime Integration for Score Updates

When `batch_score` is written by the nightly Sonnet pipeline, the `authoritative_score` generated column updates atomically. The Mac client, subscribed to `postgres_changes` on `email_messages`, receives the UPDATE event. The client-side handler should:[^23][^24]

1. If `alert_fired_at` is NOT NULL (alert already sent) AND `batch_score` is populated: check `score_delta`. If `score_delta < -0.30` (major downgrade), update the in-app alert badge with annotation. Do not push a new notification.
2. If `alert_fired_at` IS NULL AND `batch_score >= 0.85` (batch confirms importance not caught by RT): fire a deferred alert with label `"Flagged after review"`.

```typescript
// Supabase Realtime handler for score updates
const channel = supabase
  .channel('score-updates')
  .on('postgres_changes', {
    event: 'UPDATE',
    schema: 'public',
    table: 'email_messages',
    filter: `workspace_id=eq.${workspaceId}`,
  }, (payload) => {
    const { new: updated, old: previous } = payload;
    
    // Batch score just arrived (batch_score was null, now set)
    if (!previous.batch_score && updated.batch_score !== null) {
      handleBatchScoreArrival(updated);
    }
  })
  .subscribe();

function handleBatchScoreArrival(obs: EmailMessage) {
  const delta = (obs.batch_score ?? 0) - (obs.rt_score ?? 0);
  
  if (obs.alert_fired_at && delta < -0.30) {
    // Major downgrade of a fired alert → annotate in-app only
    annotateAlert(obs.id, `Importance revised after full-day context review.`);
    logAuditEvent(obs.id, 'alert_annotated', obs.batch_score);
  } else if (!obs.alert_fired_at && obs.batch_score >= 0.85) {
    // Batch confirmed important, RT missed it → deferred alert
    fireAlert(obs.id, obs.batch_score, 'batch', 'Flagged after review');
  }
}
```

***

## 7. Score Reconciliation Pipeline: Pseudocode

### 7.1 Real-Time Ingestion Path (Haiku Classification Worker)

```typescript
// Extends existing classify-email-worker (06 - Context/edge-function-pipeline-architecture.md)
async function classifyObservationRealtime(
  obs: Observation,
  supabase: SupabaseClient
): Promise<void> {
  
  // 1. Build day-context bundle (recency bias mitigation)
  const dayContext = await getDayContext(supabase, obs.workspace_id);
  // dayContext = {hour_of_day, obs_count_today, obs_types_today, top_senders_today}
  
  // 2. Haiku classification call with prompt caching
  const response = await anthropic.messages.create({
    model: 'claude-haiku-4-5-20251001-v1:0',
    max_tokens: 64,
    system: [
      { type: 'text', text: IMPORTANCE_SCORING_SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }
    ],
    messages: [{
      role: 'user',
      content: buildScoringPayload(obs, dayContext)
    }]
  });
  
  const rtScore = parseScoreFromResponse(response);
  const rtScoredAt = new Date().toISOString();
  
  // 3. Write RT score to email_messages
  await supabase.from('email_messages')
    .update({
      rt_score: rtScore,
      rt_scored_at: rtScoredAt,
      rt_model: 'claude-haiku-4-5-20251001-v1:0'
    })
    .eq('id', obs.id);
  
  // 4. Log to score_audit_log
  await supabase.from('score_audit_log').insert({
    workspace_id: obs.workspace_id,
    observation_id: obs.id,
    observation_type: obs.type,
    event_type: 'realtime_scored',
    score_value: rtScore,
    model_id: 'claude-haiku-4-5-20251001-v1:0',
    context_tokens: response.usage.input_tokens,
    pipeline_run_id: currentPipelineRunId
  });
  
  // 5. Alert evaluation (only for RT scores above high-confidence threshold)
  if (rtScore >= 0.85) {
    await evaluateAndFireAlert(obs, rtScore, 'claude-haiku-4-5-20251001-v1:0', supabase);
  }
}

async function evaluateAndFireAlert(
  obs: Observation,
  score: number,
  model: string,
  supabase: SupabaseClient
): Promise<void> {
  // Idempotency check: don't alert if already alerted for this observation
  const existing = await supabase.from('alert_states')
    .select('id')
    .eq('observation_id', obs.id)
    .neq('status', 'dismissed')
    .single();
  
  if (existing.data) return; // Already alerted
  
  // Apply deadline proximity modifier
  const effectiveThreshold = await getEffectiveAlertThreshold(obs, supabase);
  
  if (score >= effectiveThreshold) {
    // Insert alert state
    await supabase.from('alert_states').insert({
      workspace_id: obs.workspace_id,
      observation_id: obs.id,
      observation_type: obs.type,
      status: 'fired',
      fired_at: new Date().toISOString(),
      fire_score: score,
      fire_model: model
    });
    
    // Update email_messages alert tracking
    await supabase.from('email_messages')
      .update({ alert_fired_at: new Date().toISOString(), alert_score: score, alert_model: model })
      .eq('id', obs.id);
    
    // Dispatch push notification
    await dispatchPushNotification(obs, score, model);
    
    await supabase.from('score_audit_log').insert({
      workspace_id: obs.workspace_id,
      observation_id: obs.id,
      observation_type: obs.type,
      event_type: 'alert_fired',
      score_value: score,
      model_id: model
    });
  }
}
```

### 7.2 Nightly Batch Refinement Path (Sonnet Pass)

```typescript
// Runs at 02:00 UTC via pg_cron → Supabase Edge Function
async function runNightlyBatchScoring(
  workspaceId: string,
  supabase: SupabaseClient
): Promise<void> {
  
  // 1. Fetch today's observations that need batch scoring
  const { data: observations } = await supabase
    .from('email_messages')
    .select('*')
    .eq('workspace_id', workspaceId)
    .gte('received_at', getTodayStart())
    .lte('received_at', getTodayEnd())
    .is('batch_score', null)  // Not yet batch-scored
    .order('rt_score', { ascending: false });
  
  // 2. Build full-day context bundle for Sonnet (the key advantage over RT)
  const fullDayContext = buildFullDayContext(observations);
  // fullDayContext includes: all senders, thread relationships,
  // calendar events today, detected topic clusters, RT score distribution
  
  // 3. Batch Sonnet scoring — uncertain band first, then full set
  // Priority order: uncertain band (0.55-0.75) first, then others
  const sortedObs = [
    ...observations.filter(o => o.rt_score >= 0.55 && o.rt_score <= 0.75),
    ...observations.filter(o => o.rt_score < 0.55 || o.rt_score > 0.75)
  ];
  
  for (const obs of sortedObs) {
    const batchScore = await scoreSonnet(obs, fullDayContext);
    
    await supabase.from('email_messages')
      .update({
        batch_score: batchScore,
        batch_scored_at: new Date().toISOString(),
        batch_model: 'claude-sonnet-4-6-20250929-v1:0'
      })
      .eq('id', obs.id);
    
    // Log batch score
    await supabase.from('score_audit_log').insert({
      workspace_id: workspaceId,
      observation_id: obs.id,
      observation_type: obs.type,
      event_type: 'batch_scored',
      score_value: batchScore,
      model_id: 'claude-sonnet-4-6-20250929-v1:0',
      prior_score: obs.rt_score,
      prior_model: obs.rt_model,
      context_tokens: /* from Sonnet response */
    });
    
    // 4. Conflict detection and resolution
    await reconcileScores(obs, batchScore, workspaceId, supabase);
  }
  
  // 5. After all batch scores written: update pattern detection inputs
  await updatePatternDetectionSignals(workspaceId, supabase);
}
```

### 7.3 Conflict Reconciliation Function

```typescript
async function reconcileScores(
  obs: Observation & { rt_score: number; alert_fired_at: string | null },
  batchScore: number,
  workspaceId: string,
  supabase: SupabaseClient
): Promise<void> {
  
  const rtScore = obs.rt_score ?? 0;
  const delta = batchScore - rtScore;
  const absDelta = Math.abs(delta);
  
  // No conflict: within 0.15 tolerance
  if (absDelta < 0.15) return;
  
  const severity = absDelta >= 0.50 ? 'critical' : absDelta >= 0.30 ? 'major' : 'minor';
  
  // Log conflict detection event
  await supabase.from('score_audit_log').insert({
    workspace_id: workspaceId,
    observation_id: obs.id,
    observation_type: obs.type,
    event_type: 'conflict_detected',
    score_value: batchScore,
    model_id: 'claude-sonnet-4-6-20250929-v1:0',
    prior_score: rtScore,
    prior_model: obs.rt_model
  });
  
  // Alert reconciliation
  if (obs.alert_fired_at) {
    const alertWasFired = true;
    const majorDowngrade = delta <= -0.30; // Batch says less important
    
    if (majorDowngrade && alertWasFired) {
      // Annotate the alert — do NOT retract
      await supabase.from('alert_states')
        .update({
          status: 'annotated',
          batch_score: batchScore,
          batch_reconciled_at: new Date().toISOString(),
          reconciliation_action: 'annotated',
          annotation_text: 'Context updated: importance revised after full-day review.'
        })
        .eq('observation_id', obs.id);
      
      await supabase.from('score_audit_log').insert({
        workspace_id: workspaceId,
        observation_id: obs.id,
        observation_type: obs.type,
        event_type: 'alert_annotated',
        score_value: batchScore,
        model_id: 'claude-sonnet-4-6-20250929-v1:0'
      });
    } else {
      // Batch confirms or minor delta — mark as confirmed
      await supabase.from('alert_states')
        .update({
          status: 'confirmed',
          batch_score: batchScore,
          batch_reconciled_at: new Date().toISOString(),
          reconciliation_action: 'confirmed'
        })
        .eq('observation_id', obs.id);
    }
  }
  
  // Critical conflicts (|delta| >= 0.50) → flag for weekly calibration review
  if (severity === 'critical') {
    await supabase.from('score_audit_log').insert({
      workspace_id: workspaceId,
      observation_id: obs.id,
      observation_type: obs.type,
      event_type: 'conflict_detected',
      score_value: batchScore,
      model_id: 'claude-sonnet-4-6-20250929-v1:0',
      prior_score: rtScore,
      metadata: { severity: 'critical', requires_review: true }
    });
  }
}
```

***

## 8. Anthropic API Configuration for Dual-Scoring

### 8.1 Haiku Real-Time Call Configuration

Model: `claude-haiku-4-5-20251001-v1:0` (latest as of April 2026)[^25]

```typescript
const haiku_scoring_call = {
  model: 'claude-haiku-4-5-20251001-v1:0',
  max_tokens: 64,  // Score output is a single float + brief reasoning
  temperature: 0,  // Deterministic scoring
  system: [
    {
      type: 'text',
      text: SYSTEM_PROMPT_IMPORTANCE_SCORING,
      cache_control: { type: 'ephemeral' }  // Cache across calls in same session
    }
  ],
  // Headers required:
  // 'anthropic-version': '2023-06-01'
  // 'x-api-key': process.env.ANTHROPIC_API_KEY
};
```

Prompt caching behavior: `cache_control: { type: 'ephemeral' }` caches content for minimum 5 minutes (standard) or 60 minutes (extended), refreshed on each cache hit. For high-volume ingestion periods (morning email burst), cache hit rates should approach 95%+, reducing effective Haiku call cost to ~$0.03/MTok (cache read price) rather than $1.00/MTok (standard).[^26][^27]

### 8.2 Sonnet Batch Call Configuration

Model: `claude-sonnet-4-6-20250929-v1:0`[^25]

```typescript
const sonnet_batch_call = {
  model: 'claude-sonnet-4-6-20250929-v1:0',
  max_tokens: 128,  // Score + full-day context reasoning
  temperature: 0,
  system: [
    {
      type: 'text',
      text: SYSTEM_PROMPT_BATCH_SCORING,
      cache_control: { type: 'ephemeral' }  // Cache per workspace per night
    }
  ],
  messages: [{
    role: 'user',
    content: [
      {
        type: 'text',
        text: FULL_DAY_CONTEXT_JSON,
        cache_control: { type: 'ephemeral' }  // Cache day context across obs in same batch
      },
      {
        type: 'text',
        text: `Score the following observation:\n${obsPayload}`
        // NOT cached — unique per observation
      }
    ]
  }]
};
```

By marking `FULL_DAY_CONTEXT_JSON` with `cache_control`, the nightly Sonnet batch amortizes the full-day context load across all 50–300 observations. For a 200-token day context and 250 observations, without caching this costs 200 × 250 × $3/MTok = $0.15. With caching (only one cache write + 249 cache reads), cost drops to ~$0.023.

***

## 9. Pattern Detection with Dual-Score Signals

Pattern detection should consume both signals, not just the authoritative score, because the score delta itself is an informative signal. A systematic pattern where Haiku consistently overestimates a specific sender's importance (large positive deltas after batch revision) indicates a learned miscalibration — an exploitable signal for Loop 1 refinement.

### 9.1 Extended `behaviour_events` for Score Signals

```sql
-- Add to the existing email_correction event type in behaviour_events
-- New event type: 'score_revision'
ALTER TABLE behaviour_events
  ADD CONSTRAINT check_event_type CHECK (event_type IN (
    'task_completed','task_deferred','task_abandoned','plan_order_override',
    'estimate_override','email_correction','session_started','session_ended',
    'mood_context_set','task_split_accepted',
    'score_revision'  -- NEW: fired when batch_score diverges from rt_score
  ));

-- The score_revision event uses existing float fields:
-- ai_confidence = rt_score
-- new_estimate = batch_score (reuse for score delta tracking)
-- metadata JSONB = { delta, severity, alert_was_fired, sender_domain }
```

### 9.2 Weekly Calibration Query

```sql
-- Identify systematic Haiku miscalibration by sender domain
SELECT
  em.sender_domain,
  COUNT(*) AS observations,
  ROUND(AVG(em.rt_score)::numeric, 3) AS avg_rt_score,
  ROUND(AVG(em.batch_score)::numeric, 3) AS avg_batch_score,
  ROUND(AVG(em.score_delta)::numeric, 3) AS avg_delta,
  COUNT(*) FILTER (WHERE em.score_conflict = true) AS conflicts,
  COUNT(*) FILTER (WHERE em.alert_fired_at IS NOT NULL AND em.score_delta < -0.30) AS false_alerts
FROM email_messages em
WHERE em.workspace_id = $workspace_id
  AND em.batch_scored_at >= now() - interval '7 days'
  AND em.batch_score IS NOT NULL
GROUP BY em.sender_domain
HAVING COUNT(*) >= 5
ORDER BY ABS(AVG(em.score_delta)) DESC;
```

This query feeds the nightly Haiku prompt calibration (Loop 1 in the existing architecture). Senders with systematic `avg_delta < -0.20` should be added to the few-shot correction examples to reduce Haiku overestimation.

***

## 10. Architecture Variant Ranking

Three dual-scoring architectures are viable. They are ranked here with explicit rationale.

### Architecture A: Lambda-style Batch + Speed Layer (Recommended)

**Description**: Real-time Haiku produces `rt_score` for immediate action; nightly Sonnet produces `batch_score` as authoritative; serving layer resolves via generated column `authoritative_score = COALESCE(batch_score, rt_score)`. Conflicts are resolved by use-case-specific policy (Section 2).[^28][^29]

**Rank: 1** — Best fit for Timed-Brain because: (a) the two scoring events are genuinely temporally separated (12–26 hours apart), making a pure streaming/Kappa approach inappropriate; (b) the existing Supabase infrastructure already implements the serving layer via the `emails` table and pgmq queue; (c) cost is minimal (Haiku for RT, Sonnet for batch, amortized via prompt caching).

### Architecture B: Speculative Confirmation Gate

**Description**: Haiku fires real-time score; Sonnet runs within 2 hours (not overnight) as a verification pass; alerts only fire after Sonnet confirms. Structurally analogous to EESD draft-verify.[^5]

**Rank: 2** — Higher accuracy, but latency of 2 hours makes it unsuitable for intraday alerts. Appropriate for a "medium confidence" lane (0.75–0.85) where waiting 2 hours is acceptable but waiting 26 hours is not. Can be implemented as a third model tier.

### Architecture C: Real-Time Only with Periodic Recalibration

**Description**: Abandon batch pass; use Haiku exclusively with weekly Sonnet recalibration of Haiku's scoring prompt.

**Rank: 3** — Simpler but loses the epistemically superior full-day context that is the primary value of the Sonnet batch pass. Appropriate only if Haiku's accuracy calibrates to within 0.10 of Sonnet on validation data after 4 weeks of operation.

***

## Knowledge Gaps and Evidence Absences

The following specific claims in this document lack primary peer-reviewed support and should be treated as engineering heuristics derived from adjacent domains:

1. **Magnitude of recency bias in LLM-based personal observation scoring**: No primary study measures this directly. Debiasing strategy recommendations are derived from concept drift and online learning literature, not from LLM scoring-specific research.

2. **Optimal weights for Bayesian score blending (\(w_{haiku} = 0.3\), \(w_{sonnet} = 0.7\))**: These starting weights are structural heuristics based on the Loop 2 hybrid similarity scorer weights in the existing architecture. Empirical calibration is required against Timed-Brain's own validation data.

3. **Trust impact of score annotation vs. retraction in productivity AI**: The existing evidence base (clinical CDS, security alerts) is in enterprise/clinical settings with different stakes than executive productivity. The annotation recommendation in Section 5 is conservative and drawn from the direction of the evidence, but no direct user study exists for this specific context.

4. **Haiku 4.5 vs. Sonnet accuracy delta on importance scoring tasks**: The Claude Haiku 4.5 system card documents a 5.3% asymmetric response rate vs. 10% with extended thinking, but does not publish head-to-head accuracy benchmarks for importance scoring specifically. The claim that Haiku's errors cluster in the 0.55–0.75 band is an inference from the existing system behavior, not a documented benchmark.[^30]

---

## References

1. [Cascading retrieval with multi-vector representations - Pinecone](https://www.pinecone.io/blog/cascading-retrieval-with-multi-vector-representations/) - In this post, we explored multi-vector reranking as a strategy to balance efficiency and effectivene...

2. [MICE : Minimal Interaction Cross-Encoders for efficient Re-ranking](https://arxiv.org/html/2602.16299v1) - We extensively evaluate MICE across both in-domain (ID) and out-of-domain (OOD) datasets. MICE decre...

3. [Enabling Early Exit Inference and Self-Speculative Decoding - Meta AI](https://ai.meta.com/research/publications/layerskip-enabling-early-exit-inference-and-self-speculative-decoding/) - We present LayerSkip, an end-to-end solution to speed-up inference of large language models (LLMs). ...

4. [[PDF] Enabling Early Exit Inference and Self-Speculative Decoding](https://aclanthology.org/2024.acl-long.681.pdf) - We present LayerSkip, an end-to-end solution to speed-up inference of large language mod- els (LLMs)...

5. [Speculative Decoding via Early-exiting for Faster LLM Inference with ...](https://arxiv.org/abs/2406.03853) - To address these challenges, we propose a novel approach called Early-exiting Speculative Decoding (...

6. [Tackling alert fatigue with a semi-automated clinical decision ...](https://pubmed.ncbi.nlm.nih.gov/37454289/) - Study aims: Clinical decision support systems (CDSS) embedded in hospital electronic health records ...

7. [Clinical Decision Support Stewardship: Best Practices and ... - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC9132737/) - In this review, we discuss the evidence for effective alert stewardship as well as practices and met...

8. [Alert fatigue: causes, real cost, and how to fix it - Vectra AI](https://www.vectra.ai/topics/alert-fatigue) - Learn what alert fatigue is, why it costs SOCs billions, and how to fix it. Covers causes, KPIs, reg...

9. [The Hidden Risks of False Positives: How to Prevent Alert Fatigue in ...](https://www.stamus-networks.com/blog/the-hidden-risks-of-false-positives-how-to-prevent-alert-fatigue-in-your-organization) - Alert fatigue is one of the leading factors in security breaches. Learn how false positives contribu...

10. [GitHub Start Up Wednesday with Jack Naglieri - YouTube](https://www.youtube.com/watch?v=6seLh9Lwk_A) - Join us for an exciting Start Up Wednesday featuring Jack Naglieri, Founder and CTO of Panther. Disc...

11. [Addressing Concept Shift in Online Time Series Forecasting - arXiv](https://arxiv.org/html/2403.14949v1) - Concept drift implies that future data may exhibit patterns different from those observed in the pas...

12. [[PDF] Learning with Drift Detection - Universidade de Aveiro › SWEET](https://sweet.ua.pt/gladys/Papers/GamaMedasCastilloRodriguesSBIA04.pdf) - We present a method for detection of changes in the probability distribution of exam- ples. The idea...

13. [Bayesian Inference and Online Sequential Updating - Emergent Mind](https://www.emergentmind.com/topics/bayesian-inference-and-online-sequential-updating) - Explore how Bayesian inference and online sequential updating combine prior beliefs with streaming d...

14. [[PDF] 2 Sequential Bayesian updating for Big Data - UC Irvine](https://sites.socsci.uci.edu/~zoravecz/bayes/data/Articles/Oravecz2016SBUFB.pdf) - In the Bayesian approach, we summarize the current state of knowledge regarding parameters in terms ...

15. [Clipper: A low-latency online prediction serving system](https://paper.lingyunyang.com/reading-notes/conference/nsdi-2017/clipper) - Three crucial properties of model serving system. Low latency. High throughput. Improved accuracy. T...

16. [User-Centered Redesign of Monitoring Alarms: A Pre–Post Study on ...](https://pmc.ncbi.nlm.nih.gov/articles/PMC12692177/) - 1. Introduction. Alarm sounds in patient monitoring are primarily intended to enhance patient safety...

17. [1. Introduction - arXiv](https://arxiv.org/html/2604.08412v1) - We refer to this setting as Sequential Device-Addressed Routing (SDAR), in which the system decides ...

18. [[PDF] Evaluating Effects of User Experience and System Transparency on ...](https://people.csail.mit.edu/unhelkar/files/preprints/2017_Yang_HRI.pdf) - Hits, misses, false alarms and correct rejections were illustrated during the eight practice trials ...

19. [Notifications That Help, Not Harm: Researching Relevance](https://www.userintuition.ai/reference-guides/notifications-that-help-not-harm-researching-relevance/) - When notification systems fail, they create what we might call “notification debt” - a cumulative er...

20. [Alert Now or Never: Understanding and Predicting Notification ...](https://dl.acm.org/doi/10.1145/3478868) - We found that users prefer mitigating undesired interruptions by suppressing alerts over deferring t...

21. [A harm reduction approach to improving peer review by ...](https://www.facetsjournal.com/doi/10.1139/facets-2024-0102) - It is important to note that the erosion of trust is mainly in the general public; researchers conti...

22. [Progressive Disclosure - NN/G](https://www.nngroup.com/articles/progressive-disclosure/) - Progressive disclosure defers advanced or rarely used features to a secondary screen, making applica...

23. [Realtime - Postgres changes | Supabase Features](https://supabase.com/features/realtime-postgres-changes) - Supabase's Realtime Postgres Changes feature allows you to listen to database changes in real-time u...

24. [Realtime | Supabase Docs](https://supabase.com/docs/guides/realtime) - Send and receive messages to connected clients. Supabase provides a globally distributed Realtime se...

25. [Global cross-Region inference for latest Anthropic Claude Opus ...](https://aws.amazon.com/blogs/machine-learning/global-cross-region-inference-for-latest-anthropic-claude-opus-sonnet-and-haiku-models-on-amazon-bedrock-in-thailand-malaysia-singapore-indonesia-and-taiwan/) - Sonnet 4.6 and Haiku 4.5 support extended thinking, where the model generates intermediate reasoning...

26. [Prompt caching - Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) - There are two ways to enable prompt caching: Automatic caching: Add a single cache_control field at ...

27. [Anthropic Messages API - Vercel](https://vercel.com/docs/ai-gateway/sdks-and-apis/anthropic-messages-api) - Prompt caching. The gateway passes through the cache_control parameter to Anthropic's prompt caching...

28. [Does Kappa architecture improve on Lambda ... - Materialize](https://materialize.com/blog/does-kappa-architecture-improve-on-lambda/) - Learn how Kappa architecture improves on Lambda, reduces operational complexity, and when dual-pipel...

29. [Lambda Architecture 101: Unpacking batch, speed and serving ...](https://www.flexera.com/blog/finops/lambda-architecture/) - It consists of three layers: Batch Layer, Speed Layer and ...

30. [[PDF] Claude Haiku 4.5 System Card - Anthropic](https://www.anthropic.com/claude-haiku-4-5-system-card) - This system card introduces Claude Haiku 4.5, a new hybrid reasoning large language model from Anthr...

