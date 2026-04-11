# Extraction 01 — Memory Architecture

> Source: `research/perplexity-outputs/v2/v2-01-memory-architecture.md`
> Extracted: 2026-04-03
> Constraint filter: Swift/macOS, Supabase/Postgres, Claude API (Haiku/Sonnet/Opus), single-user longitudinal 12+ months

---

## DECISIONS

- **We will use a purpose-built composite architecture** because no single existing system is adequate for single-user longitudinal modelling. The composition is: Zep's bi-temporal fact model for contradiction handling + Stanford Generative Agents' importance scoring for retrieval + MAGMA's intent-aware multi-graph traversal for query routing + ICLR 2026 neuroscience precision scalar for trait stability + SleepGate's conflict tagger in the consolidation pipeline.

- **We will use a 5-tier memory hierarchy** (Tier 0 raw observation, Tier 1 daily summary, Tier 2 weekly/monthly behavioural signature, Tier 3 personality trait with valence vector and precision scalar, plus an active context buffer) because the research shows 3-tier systems (episodic/semantic/procedural) lose the intermediate abstraction levels needed for compounding intelligence. Tier 2 (behavioural signatures) is the critical missing layer that enables pattern-over-patterns.

- **We will use Voyage AI embedding models** — specifically `voyage-context-3` for contextual/conversational memories and `voyage-3-large` for factual/trait-level memories — because these outperform text-embedding-3-large and Cohere embed v3 on longitudinal behavioural data retrieval benchmarks. This replaces the current Jina v3 1024-dim decision in the existing specs.

- **We will use HNSW indexes (not IVFFlat)** for pgvector because HNSW provides consistent sub-10ms query latency without periodic re-clustering, and the report specifies tier-tuned HNSW parameters (m=16 for Tier 0 high-volume raw observations, m=48 for Tier 3 low-volume high-value traits).

- **We will use a bi-temporal data model** (from Zep) for all semantic/trait-level memories — every fact has both a `valid_from`/`valid_to` temporal range (when the fact was true about the executive) and a `recorded_at` timestamp (when the system learned it). This is the foundation for handling contradictions without catastrophic forgetting.

- **We will use a precision scalar** (from ICLR 2026 neuroscience architecture) on Tier 3 personality traits to represent confidence-as-stability. High precision = stable trait (risk-averse for 6 months). Low precision = volatile trait (still fluctuating). The precision scalar replaces simple 0-1 confidence scores at the trait level and drives the cathartic update formula for handling contradictions.

- **We will use intent-aware retrieval** (from MAGMA) rather than uniform vector search. Queries are classified into 5 intent types (WHAT, WHEN, WHY, PATTERN, CHANGE) and each type triggers a different retrieval strategy with different weight profiles across the 5 scoring dimensions.

- **We will adopt Stanford Generative Agents' importance scoring** mechanism (1-10 LLM-assigned at write time, normalised to 0-1) with calibration anchors. Importance is immutable after write. This is already in the existing specs and the research confirms it as the correct approach.

- **We will reject MemGPT's page-in/page-out mechanism** as the primary architecture because it was designed for multi-turn conversation, not longitudinal modelling. Its virtual context management is useful for the active context buffer tier only, not for the consolidation/retrieval system. MemOS is rejected for the same reason — its memory bus is over-engineered for a single-user system.

- **We will reject O-Mem** (the observation-only memory system) because it lacks the consolidation/reflection mechanism needed for compounding. Its strength is real-time observation logging, which our Tier 0 already handles.

---

## DATA STRUCTURES

### Tier 0 — Raw Observation (~50 tokens)

```json
{
  "id": "uuid",
  "occurred_at": "2026-04-02T14:32:00Z",
  "source": "email",
  "event_type": "email.response_sent",
  "entity_id": "uuid-of-email-thread",
  "summary": "Responded to CFO email in 45 seconds (typical: 8 minutes)",
  "raw_data": { /* structured signal payload */ },
  "importance_score": 0.7,
  "embedding": [/* voyage-context-3 vector */],
  "is_processed": false
}
```

Token budget: ~50 tokens per object. High volume (100-200/day). Append-only, immutable after write (except embedding backfill and processing flag).

### Tier 1 — Daily Summary (200-400 tokens)

```json
{
  "id": "uuid",
  "date": "2026-04-02",
  "profile_id": "uuid",
  "day_narrative": "A fragmented day dominated by reactive email and two back-to-back board prep meetings. Strategic work attempted between 9-10:30am but interrupted by CFO call. Deferred the Head of Sales 1:1 for the 4th consecutive day.",
  "significant_events": [
    {
      "event_summary": "4th consecutive deferral of Head of Sales 1:1",
      "significance": "chronic avoidance pattern — people-management deferral",
      "source_tier0_ids": ["uuid1", "uuid2", "uuid3", "uuid4"]
    }
  ],
  "anomalies": [
    {
      "description": "45-second response to CFO email (baseline: 8 minutes)",
      "deviation_type": "positive_surprise"
    }
  ],
  "energy_profile": {
    "peak_window": "09:00-10:30",
    "trough_window": "14:00-16:00",
    "overall_load": "high"
  },
  "embedding": [/* voyage-context-3 vector */],
  "generated_by": "haiku",
  "source_tier0_count": 147
}
```

Token budget: 200-400 tokens. Generated nightly by Haiku during consolidation Phase 3.

### Tier 2 — Behavioural Signature (500-1000 tokens)

```json
{
  "id": "uuid",
  "profile_id": "uuid",
  "period_type": "weekly|monthly",
  "period_start": "2026-03-25",
  "period_end": "2026-03-31",
  "signature_name": "The People Freeze",
  "description": "Systematic avoidance of people-management decisions under calendar compression. When meeting density exceeds 6/day for 3+ consecutive days, HR and personnel tasks are deferred at 4.2x the normal rate. Recovery takes 48-72 hours after calendar normalises.",
  "cross_domain_correlations": [
    {
      "domain_a": "calendar",
      "domain_b": "task",
      "pattern": "meeting_density > 6/day correlates with HR deferral rate r=0.83"
    }
  ],
  "supporting_tier1_ids": ["uuid1", "uuid2", "uuid3", "uuid4"],
  "confidence": 0.78,
  "first_observed": "2026-02-15",
  "last_reinforced": "2026-03-31",
  "status": "confirmed",
  "embedding": [/* voyage-3-large vector */],
  "generated_by": "sonnet"
}
```

Token budget: 500-1000 tokens. Generated by Sonnet during weekly pattern detection (consolidation Phase 4). Must draw from minimum 2 domains and span minimum 14 days.

### Tier 3 — Personality Trait (with valence vector and precision scalar)

```json
{
  "id": "uuid",
  "profile_id": "uuid",
  "trait_name": "Confrontation-Avoidant Decision Maker",
  "description": "Makes rapid, confident decisions on technical/operational matters but systematically delays interpersonal confrontation. Average decision latency: 2.1 hours (technical) vs 6.2 days (interpersonal). The delay is not procrastination — it is active avoidance accompanied by compensatory busyness.",
  "valence_vector": {
    "risk_appetite": -0.3,
    "interpersonal_comfort": -0.7,
    "operational_confidence": 0.8,
    "strategic_depth": 0.5,
    "delegation_tendency": 0.2
  },
  "precision": 0.85,
  "valid_from": "2026-01-15",
  "valid_to": null,
  "recorded_at": "2026-03-31",
  "evidence_chain": {
    "supporting_tier2_ids": ["uuid1", "uuid2"],
    "supporting_tier1_ids": ["uuid1", "uuid2", "uuid3"],
    "direct_tier0_ids": ["uuid1"]
  },
  "contradiction_log": [],
  "supersedes": null,
  "superseded_by": null,
  "embedding": [/* voyage-3-large vector */],
  "generated_by": "opus"
}
```

Precision scalar semantics: 0.0 = maximally uncertain/volatile, 1.0 = maximally stable. Updated via the cathartic update formula (see ALGORITHMS). Generated by Opus during monthly trait reflection (consolidation Phase 5).

### Active Context Buffer (~2000 tokens)

Injected into every LLM call's system prompt. Structured document, not a memory object:

```
<core_memory>
  <identity> name, role, company, tenure, direct reports </identity>
  <priorities> top 5-7 current priorities with status </priorities>
  <relationships> top 5-8 key relationships with health scores </relationships>
  <active_rules> top 5-8 procedural rules, highest confidence </active_rules>
  <behavioural_model> chronotype, peak hours, decision style, blind spots, stress level </behavioural_model>
  <session_context> today's date, day of week, recent events </session_context>
</core_memory>
```

Updated by the reflection engine after each nightly run. Read-only for all other components.

### pgvector Table Schema

5 tables, one per tier plus the context buffer:

```sql
-- Tier 0: Raw observations
CREATE TABLE tier0_observations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES profiles(id),
    occurred_at TIMESTAMPTZ NOT NULL,
    source TEXT NOT NULL,
    event_type TEXT NOT NULL,
    entity_id UUID,
    entity_type TEXT,
    summary TEXT NOT NULL,
    raw_data JSONB NOT NULL,
    importance_score REAL NOT NULL DEFAULT 0.5,
    embedding vector(1024),
    is_processed BOOLEAN NOT NULL DEFAULT false,
    processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_t0_embedding ON tier0_observations
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 128);
CREATE INDEX idx_t0_unprocessed ON tier0_observations(profile_id, is_processed)
    WHERE is_processed = false;
CREATE INDEX idx_t0_occurred ON tier0_observations(profile_id, occurred_at DESC);
CREATE INDEX idx_t0_type ON tier0_observations(profile_id, event_type);
-- BRIN index for temporal range scans on high-volume tier
CREATE INDEX idx_t0_occurred_brin ON tier0_observations USING brin (occurred_at);

-- Tier 1: Daily summaries
CREATE TABLE tier1_daily_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES profiles(id),
    summary_date DATE NOT NULL,
    day_narrative TEXT NOT NULL,
    significant_events JSONB NOT NULL DEFAULT '[]',
    anomalies JSONB NOT NULL DEFAULT '[]',
    energy_profile JSONB,
    embedding vector(1024),
    generated_by TEXT NOT NULL DEFAULT 'haiku',
    source_tier0_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(profile_id, summary_date)
);

CREATE INDEX idx_t1_embedding ON tier1_daily_summaries
    USING hnsw (embedding vector_cosine_ops) WITH (m = 24, ef_construction = 128);
CREATE INDEX idx_t1_date ON tier1_daily_summaries(profile_id, summary_date DESC);

-- Tier 2: Behavioural signatures
CREATE TABLE tier2_signatures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES profiles(id),
    period_type TEXT NOT NULL CHECK (period_type IN ('weekly', 'monthly')),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    signature_name TEXT NOT NULL,
    description TEXT NOT NULL,
    cross_domain_correlations JSONB NOT NULL DEFAULT '[]',
    supporting_tier1_ids UUID[] NOT NULL DEFAULT '{}',
    confidence REAL NOT NULL DEFAULT 0.5,
    first_observed DATE NOT NULL,
    last_reinforced DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'emerging'
        CHECK (status IN ('emerging', 'developing', 'confirmed', 'fading', 'archived')),
    embedding vector(1024),
    generated_by TEXT NOT NULL DEFAULT 'sonnet',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_t2_embedding ON tier2_signatures
    USING hnsw (embedding vector_cosine_ops) WITH (m = 32, ef_construction = 128);
CREATE INDEX idx_t2_status ON tier2_signatures(profile_id, status);
CREATE INDEX idx_t2_period ON tier2_signatures(profile_id, period_start DESC);
-- GIN index for array-based evidence chain queries
CREATE INDEX idx_t2_tier1_refs ON tier2_signatures USING gin (supporting_tier1_ids);

-- Tier 3: Personality traits (bi-temporal)
CREATE TABLE tier3_traits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES profiles(id),
    trait_name TEXT NOT NULL,
    description TEXT NOT NULL,
    valence_vector JSONB NOT NULL DEFAULT '{}',
    precision REAL NOT NULL DEFAULT 0.5,
    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ,  -- NULL = currently valid
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    evidence_chain JSONB NOT NULL DEFAULT '{}',
    contradiction_log JSONB NOT NULL DEFAULT '[]',
    supersedes UUID REFERENCES tier3_traits(id),
    superseded_by UUID REFERENCES tier3_traits(id),
    embedding vector(1024),
    generated_by TEXT NOT NULL DEFAULT 'opus',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_t3_embedding ON tier3_traits
    USING hnsw (embedding vector_cosine_ops) WITH (m = 48, ef_construction = 200);
CREATE INDEX idx_t3_active ON tier3_traits(profile_id)
    WHERE valid_to IS NULL;  -- partial index: only current traits
CREATE INDEX idx_t3_temporal ON tier3_traits(profile_id, valid_from DESC, valid_to);

-- Active context buffer (single row per profile, overwritten each nightly cycle)
CREATE TABLE active_context_buffer (
    profile_id UUID PRIMARY KEY REFERENCES profiles(id),
    core_memory_document TEXT NOT NULL,
    identity JSONB NOT NULL,
    priorities JSONB NOT NULL,
    relationships JSONB NOT NULL,
    active_rules JSONB NOT NULL,
    behavioural_model JSONB NOT NULL,
    session_context JSONB NOT NULL,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### RLS Policies

```sql
-- All tier tables: profile_id scoped
ALTER TABLE tier0_observations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_observations" ON tier0_observations
    FOR ALL USING (profile_id = auth.uid());

-- Tier 0: client can SELECT and INSERT, no UPDATE/DELETE (append-only)
-- Service role only for UPDATE is_processed/processed_at

-- Tiers 1-3: client can SELECT only. INSERT/UPDATE restricted to service role
-- (reflection engine runs via Edge Functions with service role key)

-- Active context buffer: client can SELECT only. Service role writes.
```

### Combined Retrieval Function

```sql
CREATE OR REPLACE FUNCTION retrieve_memories(
    p_profile_id UUID,
    p_query_embedding vector(1024),
    p_intent_type TEXT,  -- 'WHAT', 'WHEN', 'WHY', 'PATTERN', 'CHANGE'
    p_tiers INT[],       -- which tiers to search: {0,1,2,3}
    p_top_k INT DEFAULT 25,
    p_min_importance REAL DEFAULT 0.0,
    p_temporal_start TIMESTAMPTZ DEFAULT NULL,
    p_temporal_end TIMESTAMPTZ DEFAULT NULL
) RETURNS TABLE (
    memory_id UUID,
    tier INT,
    content TEXT,
    importance REAL,
    occurred_at TIMESTAMPTZ,
    cosine_similarity REAL,
    composite_score REAL
) AS $$
DECLARE
    w_recency REAL;
    w_importance REAL;
    w_relevance REAL;
    w_temporal REAL;
    w_tier_boost REAL;
BEGIN
    -- Intent-aware weight selection
    CASE p_intent_type
        WHEN 'WHAT' THEN
            w_recency := 0.15; w_importance := 0.20; w_relevance := 0.50;
            w_temporal := 0.05; w_tier_boost := 0.10;
        WHEN 'WHEN' THEN
            w_recency := 0.10; w_importance := 0.15; w_relevance := 0.25;
            w_temporal := 0.40; w_tier_boost := 0.10;
        WHEN 'WHY' THEN
            w_recency := 0.10; w_importance := 0.25; w_relevance := 0.40;
            w_temporal := 0.10; w_tier_boost := 0.15;
        WHEN 'PATTERN' THEN
            w_recency := 0.05; w_importance := 0.30; w_relevance := 0.30;
            w_temporal := 0.10; w_tier_boost := 0.25;
        WHEN 'CHANGE' THEN
            w_recency := 0.20; w_importance := 0.20; w_relevance := 0.30;
            w_temporal := 0.20; w_tier_boost := 0.10;
        ELSE  -- default balanced
            w_recency := 0.20; w_importance := 0.25; w_relevance := 0.35;
            w_temporal := 0.10; w_tier_boost := 0.10;
    END CASE;

    -- Union across requested tiers, score, and rank
    RETURN QUERY
    WITH candidates AS (
        -- Tier 0
        SELECT t0.id AS memory_id, 0 AS tier, t0.summary AS content,
               t0.importance_score AS importance, t0.occurred_at,
               1 - (t0.embedding <=> p_query_embedding) AS cosine_similarity
        FROM tier0_observations t0
        WHERE 0 = ANY(p_tiers)
          AND t0.profile_id = p_profile_id
          AND t0.importance_score >= p_min_importance
          AND t0.embedding IS NOT NULL
          AND (p_temporal_start IS NULL OR t0.occurred_at >= p_temporal_start)
          AND (p_temporal_end IS NULL OR t0.occurred_at <= p_temporal_end)
        ORDER BY t0.embedding <=> p_query_embedding LIMIT p_top_k * 2

        UNION ALL

        -- Tier 1
        SELECT t1.id, 1, t1.day_narrative, 0.6, t1.summary_date::TIMESTAMPTZ,
               1 - (t1.embedding <=> p_query_embedding)
        FROM tier1_daily_summaries t1
        WHERE 1 = ANY(p_tiers)
          AND t1.profile_id = p_profile_id
          AND t1.embedding IS NOT NULL
          AND (p_temporal_start IS NULL OR t1.summary_date >= p_temporal_start::DATE)
          AND (p_temporal_end IS NULL OR t1.summary_date <= p_temporal_end::DATE)
        ORDER BY t1.embedding <=> p_query_embedding LIMIT p_top_k

        UNION ALL

        -- Tier 2
        SELECT t2.id, 2, t2.description, t2.confidence, t2.period_start::TIMESTAMPTZ,
               1 - (t2.embedding <=> p_query_embedding)
        FROM tier2_signatures t2
        WHERE 2 = ANY(p_tiers)
          AND t2.profile_id = p_profile_id
          AND t2.status IN ('developing', 'confirmed')
          AND t2.embedding IS NOT NULL
        ORDER BY t2.embedding <=> p_query_embedding LIMIT p_top_k

        UNION ALL

        -- Tier 3
        SELECT t3.id, 3, t3.description, t3.precision, t3.valid_from,
               1 - (t3.embedding <=> p_query_embedding)
        FROM tier3_traits t3
        WHERE 3 = ANY(p_tiers)
          AND t3.profile_id = p_profile_id
          AND t3.valid_to IS NULL  -- only current traits
          AND t3.embedding IS NOT NULL
        ORDER BY t3.embedding <=> p_query_embedding LIMIT p_top_k
    )
    SELECT c.memory_id, c.tier, c.content, c.importance, c.occurred_at,
           c.cosine_similarity,
           (w_recency * exp(-0.005 * EXTRACT(EPOCH FROM (now() - c.occurred_at)) / 3600.0))
           + (w_importance * c.importance)
           + (w_relevance * c.cosine_similarity)
           + (w_temporal * CASE
               WHEN p_temporal_start IS NOT NULL AND c.occurred_at BETWEEN p_temporal_start AND COALESCE(p_temporal_end, now())
               THEN 1.0 ELSE 0.3 END)
           + (w_tier_boost * CASE c.tier
               WHEN 3 THEN 1.0
               WHEN 2 THEN 0.7
               WHEN 1 THEN 0.4
               WHEN 0 THEN 0.2
               END)
           AS composite_score
    FROM candidates c
    ORDER BY composite_score DESC
    LIMIT p_top_k;
END;
$$ LANGUAGE plpgsql STABLE;
```

---

## ALGORITHMS

### Nightly Consolidation Pipeline (6 Phases)

```
TRIGGER CONDITIONS (any one triggers the pipeline):
  1. Time-based: 2:00 AM local time (primary)
  2. Volume-based: > 200 unprocessed Tier 0 observations
  3. Significance-based: any Tier 0 observation with importance >= 0.9

PHASE 1 — Importance Scoring [Haiku]
  FOR EACH unprocessed Tier 0 observation:
    IF importance_score == default (0.5):
      score = haiku_classify(observation.summary, calibration_anchors)
      UPDATE observation SET importance_score = score
    Mark as scored

PHASE 2 — Conflict Detection [Haiku]
  FOR EACH scored observation today:
    candidate_conflicts = vector_search(
      query = observation.embedding,
      tiers = [2, 3],  -- search signatures and traits
      top_k = 5,
      min_similarity = 0.75
    )
    FOR EACH candidate IN candidate_conflicts:
      contradiction_score = haiku_assess_contradiction(
        new_observation = observation,
        existing_memory = candidate
      )
      IF contradiction_score > 0.7:
        TAG observation AS "conflict:{candidate.id}"
        TAG candidate AS "challenged_by:{observation.id}"

PHASE 3 — Daily Summary Generation [Haiku]
  observations_today = FETCH all Tier 0 from today, ordered by occurred_at
  daily_summary = haiku_generate_daily_summary(
    observations = observations_today,
    existing_model = active_context_buffer
  )
  INSERT INTO tier1_daily_summaries(daily_summary)
  EMBED daily_summary with voyage-context-3
  Mark all today's Tier 0 observations as is_processed = true

PHASE 4 — Weekly Pattern Detection [Sonnet]
  IF today == Sunday OR day_count_this_week >= 5:
    last_7_summaries = FETCH tier1_daily_summaries for last 7 days
    existing_signatures = FETCH tier2_signatures WHERE status IN ('emerging', 'developing', 'confirmed')

    new_patterns = sonnet_detect_patterns(
      daily_summaries = last_7_summaries,
      existing_signatures = existing_signatures,
      cross_domain_requirement = TRUE,  -- minimum 2 domains
      minimum_span = 14 days
    )

    FOR EACH pattern IN new_patterns:
      duplicate = vector_search(pattern.embedding, tiers=[2], min_similarity=0.85)
      IF duplicate EXISTS:
        REINFORCE duplicate (increment evidence, boost confidence)
      ELSE:
        INSERT INTO tier2_signatures(pattern)
        EMBED with voyage-3-large

PHASE 5 — Monthly Trait Reflection [Opus]
  IF day_of_month == 1 OR month_boundary_crossed:
    all_confirmed_signatures = FETCH tier2_signatures WHERE status = 'confirmed'
    current_traits = FETCH tier3_traits WHERE valid_to IS NULL
    conflict_tagged = FETCH all items tagged "conflict:*" this month

    trait_updates = opus_reflect(
      signatures = all_confirmed_signatures,
      current_traits = current_traits,
      conflicts = conflict_tagged,
      instruction = "Generate/update personality traits using cathartic update formula.
                     Every trait must have a valence vector and precision scalar.
                     Explicitly handle contradictions using the three cases:
                     (1) temporary deviation — lower precision, do not update trait
                     (2) permanent shift — create new trait version, supersede old
                     (3) novel emergence — create new trait with low precision"
    )

    FOR EACH update IN trait_updates:
      CASE update.type:
        temporary_deviation:
          existing_trait.precision *= 0.9  -- reduce precision, keep trait
        permanent_shift:
          existing_trait.valid_to = now()
          existing_trait.superseded_by = new_trait.id
          INSERT new_trait with valid_from = now(), precision = 0.5
        novel_emergence:
          INSERT new_trait with precision = 0.3  -- low initial precision
    EMBED all new/updated traits with voyage-3-large

PHASE 6 — Pruning
  -- Tier 0: archive raw data for observations older than 30 days
  FOR EACH tier0 WHERE occurred_at < now() - 30 days AND importance_score < 0.8:
    MOVE raw_data to cold storage (Supabase Storage bucket)
    REPLACE raw_data with storage reference URI

  -- Tier 0: tombstone observations older than 365 days
  FOR EACH tier0 WHERE occurred_at < now() - 365 days AND importance_score < 0.8 AND is_processed = true:
    TOMBSTONE (retain summary + embedding, purge raw_data)

  -- Tier 2: fade signatures not reinforced in 60 days
  FOR EACH tier2 WHERE last_reinforced < now() - 60 days AND status = 'confirmed':
    UPDATE status = 'fading'

  -- Never prune Tier 3 traits — they are the permanent longitudinal record
  -- Superseded traits (valid_to != NULL) are archived, never deleted

  UPDATE active_context_buffer with latest Tier 3 traits + top Tier 2 signatures
```

### Retrieval Scoring Formula (5-Dimension)

```
composite_score(memory, query, intent) =
    w_recency(intent)    * recency_decay(memory)
  + w_importance(intent) * importance(memory)
  + w_relevance(intent)  * cosine_similarity(memory.embedding, query.embedding)
  + w_temporal(intent)   * temporal_match(memory, query.time_range)
  + w_tier_boost(intent) * tier_weight(memory.tier)
```

Where:
- `recency_decay(m) = exp(-0.005 * hours_since(m.occurred_at))` — half-life ~139 hours (~5.8 days)
- `temporal_match` = 1.0 if memory falls within query's temporal window, 0.3 otherwise
- `tier_weight` = {Tier 0: 0.2, Tier 1: 0.4, Tier 2: 0.7, Tier 3: 1.0}

### Intent-Aware Weight Table

| Intent | w_recency | w_importance | w_relevance | w_temporal | w_tier_boost |
|--------|-----------|-------------|-------------|------------|-------------|
| WHAT   | 0.15      | 0.20        | 0.50        | 0.05       | 0.10        |
| WHEN   | 0.10      | 0.15        | 0.25        | 0.40       | 0.10        |
| WHY    | 0.10      | 0.25        | 0.40        | 0.10       | 0.15        |
| PATTERN| 0.05      | 0.30        | 0.30        | 0.10       | 0.25        |
| CHANGE | 0.20      | 0.20        | 0.30        | 0.20       | 0.10        |

### Hierarchical Retrieval (Drill-Down)

```
FUNCTION hierarchical_retrieve(query, intent):
  // Phase 1: Search traits first (Tier 3)
  trait_matches = vector_search(query, tiers=[3], top_k=5)

  // Phase 2: For each matching trait, retrieve supporting signatures (Tier 2)
  signature_matches = []
  FOR EACH trait IN trait_matches:
    sigs = FETCH tier2_signatures WHERE id IN trait.evidence_chain.supporting_tier2_ids
    signature_matches.append(sigs)

  // Phase 3: If more detail needed, drill into daily summaries (Tier 1)
  IF intent IN ('WHY', 'CHANGE'):
    FOR EACH sig IN signature_matches:
      summaries = FETCH tier1_daily_summaries WHERE id IN sig.supporting_tier1_ids
      // Include in context

  // Phase 4: Only drill to raw observations (Tier 0) for evidence chains
  IF intent == 'WHY':
    // Fetch specific Tier 0 observations cited in evidence chains

  RETURN ranked_union(trait_matches, signature_matches, summaries)
```

### Cathartic Update Formula (Precision Scalar)

```
FOR contradiction detected against Tier 3 trait:
  prediction_error = |observed_value - trait.valence_vector[dimension]|

  IF prediction_error < 0.3:  // within expected variance
    // Temporary deviation — noise, do not update
    trait.precision *= 0.95  // slight precision reduction

  ELSE IF prediction_error >= 0.3 AND prediction_error < 0.7:
    // Significant deviation — quarantine for 14 days
    ADD to trait.contradiction_log
    IF contradiction_count_in_14_days >= 3:
      // Permanent shift confirmed
      new_precision = 1.0 / (1.0 + prediction_error^2)
      CREATE new trait version with updated valence, precision = new_precision
      SUPERSEDE old trait

  ELSE:  // prediction_error >= 0.7
    // Dramatic shift — immediate update
    CREATE new trait version
    old_trait.valid_to = now()
    new_trait.precision = 0.3  // very low — system is uncertain
```

---

## APIS & FRAMEWORKS

### Embedding Models

- **voyage-context-3**: For Tier 0 and Tier 1 memories (contextual, conversational, event-level). Optimised for retrieval where surrounding context matters. 1024 dimensions.
- **voyage-3-large**: For Tier 2 and Tier 3 memories (factual, trait-level, stable representations). Higher accuracy on factual retrieval benchmarks. 1024 dimensions.
- Both from Voyage AI. Both 1024-dim, compatible with a single pgvector column type across all tables.

### Database Features

- **pgvector**: HNSW indexes with tier-tuned parameters (m=16 for Tier 0, m=24 for Tier 1, m=32 for Tier 2, m=48 for Tier 3). Higher m values for lower-volume, higher-value tiers improve recall quality.
- **BRIN indexes**: On `occurred_at` for Tier 0 — efficient temporal range scans on high-volume append-only data.
- **GIN indexes**: On UUID array columns (`supporting_tier1_ids`, `evidence_chain`) for evidence chain lookups.
- **Partial indexes**: On `valid_to IS NULL` for Tier 3 (only current traits) and `is_processed = false` for Tier 0 (pending observations).
- **Composite indexes**: `(profile_id, status)`, `(profile_id, occurred_at DESC)` for filtered queries.

### Local Vector Search

- **USearch**: Swift-native HNSW library for local/offline retrieval. Primary query path. Sub-10ms for 500K vectors on Apple Silicon.
- pgvector is the sync/backup path, never the primary query path for latency-sensitive operations.

### Model Assignments in Pipeline

| Pipeline Phase | Model | Rationale |
|---------------|-------|-----------|
| Importance scoring | Haiku 3.5 | High volume, structured output, fast |
| Conflict detection | Haiku 3.5 | Binary classification task |
| Daily summary generation | Haiku 3.5 | Summarisation from structured input |
| Weekly pattern detection | Sonnet 4 | Cross-domain correlation requires stronger reasoning |
| Monthly trait reflection | Opus 4.6 | Deep personality modelling, cathartic updates, novel insight generation |
| Active context buffer update | Opus 4.6 | Synthesis of full model into coherent briefing document |

---

## NUMBERS

- **Tier 0 token budget**: ~50 tokens per observation
- **Tier 1 token budget**: 200-400 tokens per daily summary
- **Tier 2 token budget**: 500-1000 tokens per behavioural signature
- **Tier 3 token budget**: variable (traits are as long as they need to be)
- **Active context buffer**: ~2000 tokens (always in every LLM context window)
- **Daily observation volume**: 100-200 Tier 0 records for a C-suite executive
- **Storage per observation**: ~6.5KB (2KB metadata/summary + 4KB embedding + 0.5KB raw_data)
- **Daily storage**: ~1MB
- **Annual storage**: ~365MB (within Supabase free tier with cold storage offloading)
- **HNSW m parameter by tier**: m=16 (T0), m=24 (T1), m=32 (T2), m=48 (T3)
- **HNSW ef_construction**: 128 (T0-T2), 200 (T3)
- **HNSW ef_search**: 64 (>95% recall@100)
- **USearch local query latency**: 1-5ms p50, <10ms p99 for up to 500K vectors
- **pgvector query latency**: 20-80ms p50, 200ms p99 (backup path only)
- **Embedding dimensions**: 1024 (both Voyage models)
- **Recency decay rate**: exp(-0.005 * hours) — half-life ~139 hours (~5.8 days)
- **Retrieval candidate pool**: K=100 (ANN retrieval), then re-ranked to top-N
- **Contradiction quarantine period**: 14 days before confirming permanent shift
- **Prediction error thresholds**: <0.3 = noise, 0.3-0.7 = quarantine, >=0.7 = immediate update
- **Minimum cross-domain requirement**: 2 domains for Tier 2 signatures
- **Minimum temporal span**: 14 days for Tier 2 signature creation
- **Confidence threshold for new semantic facts**: 0.6 minimum
- **Procedural rule activation threshold**: 0.7 confidence
- **Tier 0 cold storage transition**: 30 days
- **Tier 0 tombstone threshold**: 365 days (unless importance >= 0.8)
- **Tier 2 fading threshold**: 60 days without reinforcement
- **Confidence decay grace period**: 14 days before decay begins
- **Semantic fact decay rates**: 0.002-0.005 per day depending on fact type (preference: 0.002, inference: 0.005)
- **Maximum initial confidence**: 0.75 (no fact starts higher regardless of evidence)
- **Confidence ceiling**: 0.99 (never reaches 1.0)
- **Expected mature semantic profile**: 50-200 active facts at 6+ months (5,000-20,000 tokens)
- **Episodic-to-semantic promotion rate target**: 5-15% within 30 days
- **Semantic-to-procedural promotion rate target**: 5-10% within 60 days
- **Procedural rule match rate target**: >65% for active rules
- **Low-score retrieval floor**: 0.15 composite score — below this, return empty with `low_confidence` flag

---

## ANTI-PATTERNS

- **Do not use MemGPT/Letta as the primary architecture.** Its page-in/page-out virtual context management was designed for multi-turn LLM conversations, not longitudinal human modelling. The context window management insight (core/recall/archival) is useful only for the active context buffer tier — not the consolidation or retrieval system.

- **Do not use MemOS.** Its memory bus abstraction adds complexity without benefit for a single-user system. Over-engineered for this use case.

- **Do not use O-Mem alone.** Observation-only memory systems lack the consolidation and reflection mechanisms needed for compounding. Good for Tier 0, worthless for Tiers 1-3.

- **Do not use IVFFlat indexes.** They require periodic re-clustering as data grows, which creates maintenance burden and inconsistent query performance. HNSW is strictly better for this use case.

- **Do not use a single HNSW configuration across all tiers.** Tier 0 has high volume / low per-item value (m=16 is sufficient). Tier 3 has low volume / high per-item value (m=48 for maximum recall). Using m=16 everywhere degrades Tier 3 retrieval quality. Using m=48 everywhere wastes memory on Tier 0.

- **Do not use a single embedding model for all tiers.** Contextual memories (Tier 0/1) and factual/trait memories (Tier 2/3) have different retrieval characteristics. Using one model for both compromises retrieval quality.

- **Do not store simple 0-1 confidence scores on personality traits.** A confidence score of 0.85 is ambiguous — does it mean "the system is 85% sure this trait exists" or "this trait has been stable for 85% of the observation period"? The precision scalar + bi-temporal model separates epistemic confidence from trait stability.

- **Do not handle all contradictions the same way.** Three distinct cases require different handling: temporary deviation (noise — reduce precision, don't update trait), permanent shift (genuine change — create new trait version, supersede old), novel emergence (new trait not previously modelled — create with low precision). Collapsing these into a single "handle contradiction" function produces catastrophic forgetting.

- **Do not skip the 14-day quarantine period** when a potential permanent shift is detected. Single contradicting observations are frequently noise — stress days, external constraints, one-off decisions. The quarantine requires 3+ contradictions within 14 days before confirming a shift.

- **Do not delete superseded traits.** They are the longitudinal record. The history of who the executive was at each point in time is as valuable as who they are now. Superseded traits get `valid_to` set but remain queryable for trajectory analysis ("How has their risk appetite changed over the past 6 months?").

- **Do not use recency-only retrieval.** Pure time-decay buries critical old memories. The tier_boost dimension in the scoring formula ensures high-level abstractions (Tier 2/3) remain accessible regardless of age. Procedural rules never decay by default — they are invalidated only by the reflection engine.

- **Do not run Opus for daily summarisation.** Haiku is sufficient for structured summarisation of a day's observations. Opus is reserved for monthly trait reflection and active context buffer generation — the tasks that require genuine reasoning depth. Misallocating Opus to routine summarisation wastes capacity without improving intelligence quality.

- **Do not let the active context buffer exceed ~2000 tokens.** Context pollution (too many facts loaded into every LLM call) degrades intelligence quality. The buffer should contain the most essential identity, priorities, relationships, and rules — not the full semantic model. Maximum precision, not maximum recall.

- **Do not build frequency-only promotion (episodic to semantic).** "This pattern appeared 5 times" is necessary but not sufficient. The reflection engine must also assess causal coherence (does the pattern make psychological sense?) and contextual validity (is the pattern a genuine trait or a response to a temporary external factor?). Frequency-only promotion produces spurious facts.

- **Do not store embeddings in CoreData as Transformable.** The retrieval spec mentions this but it is a performance trap. Use USearch for local vector search (Swift-native HNSW) and pgvector for remote. CoreData stores the memory metadata; the embedding lives in USearch's index file and pgvector's column.
