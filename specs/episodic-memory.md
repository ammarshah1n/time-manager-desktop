# PRD: Episodic Memory Store

> Layer: Memory Store (Tier 1 of 3)
> Status: Implementation-ready
> Dependencies: Signal Ingestion layer, Jina Embeddings API, Supabase (pgvector), DataStore
> Swift target: 5.9+ / macOS 14+
> Reference: Park et al. 2023 (Generative Agents), MemGPT (Packer et al. 2023)

---

## 1. Purpose

Episodic memory is the raw event log of the executive's digital life. Every signal — task interaction, email arrival, calendar event, voice capture, focus session, system observation — is recorded as a timestamped episode. This is the ground truth layer. It does not interpret, summarise, or abstract. It stores what happened, when, from which source, and with what importance score.

The reflection engine reads episodic memory to extract patterns. Semantic memory stores what those patterns mean. Procedural memory stores what to do about them. Episodic memory is the foundation that makes both possible.

---

## 2. What Constitutes an Episode

An episode is a single, atomic, timestamped event from any signal source. One action = one episode.

### 2.1 Episode Sources

| Source | Example episodes |
|--------|-----------------|
| Task signals | Task created, deferred, completed, deleted, priority changed, edited, viewed |
| Email signals | Email received, classified, triage correction, email opened (future) |
| Calendar signals | Event added, cancelled, rescheduled, meeting started, meeting ended |
| Voice capture | Morning interview transcript segment, ad-hoc voice note |
| Focus sessions | Focus timer started, paused, completed, abandoned |
| System observations | App became active, app went to background, day started, day ended |
| User corrections | "That's wrong" feedback on any AI output, manual override of any AI decision |

### 2.2 What is NOT an Episode

- Derived insights (those go to semantic memory)
- Operating rules (those go to procedural memory)
- Aggregate statistics (those are computed on-demand from episodes)
- Raw API responses (episodes are extracted from API responses, not the responses themselves)

---

## 3. Schema

### 3.1 Core Episode Record

```swift
struct Episode: Identifiable, Codable, Sendable {
    let id: UUID                          // unique episode ID
    let workspaceId: UUID                 // multi-tenant key
    let profileId: UUID                   // user key
    let occurredAt: Date                  // when the event happened (UTC)
    let source: SignalSource               // which signal source produced this (canonical enum from data-models.md)
    let eventType: String                 // hierarchical: "task.deferred", "email.received", "calendar.eventAdded"
    let entityId: UUID?                   // primary entity involved (task ID, email ID, event ID)
    let entityType: String?               // "task", "email", "calendar_event", "voice_capture"
    let summary: String                   // human-readable 1-line description (generated at write time)
    let rawData: Data                     // full JSON payload from the signal source
    let importanceScore: Float            // 0.0 to 1.0, computed at write time
    let embedding: [Float]?               // 1024-dim Jina embedding (nil until generated)
    let embeddingGeneratedAt: Date?       // when embedding was computed
    let isProcessed: Bool                 // has the reflection engine consumed this episode?
    let processedAt: Date?                // when reflection consumed it
    let createdAt: Date                   // server write time
}

/// Uses the canonical SignalSource enum from data-models.md.
/// Maps to: .email, .calendar, .voice, .appFocus, .task, .system, .userCorrection
/// Note: focusSession signals use .appFocus, system observations use .system.
typealias EpisodeSource = SignalSource
```

### 3.2 Supabase Table

```sql
CREATE TABLE episodes (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id          UUID NOT NULL REFERENCES workspaces(id),
    profile_id            UUID NOT NULL REFERENCES profiles(id),
    occurred_at           TIMESTAMPTZ NOT NULL,
    source                TEXT NOT NULL,
    event_type            TEXT NOT NULL,
    entity_id             UUID,
    entity_type           TEXT,
    summary               TEXT NOT NULL,
    raw_data              JSONB NOT NULL,
    importance_score      REAL NOT NULL DEFAULT 0.5,
    embedding             vector(1024),
    embedding_generated_at TIMESTAMPTZ,
    is_processed          BOOLEAN NOT NULL DEFAULT false,
    processed_at          TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Query patterns: reflection engine reads unprocessed, retrieval searches by similarity + recency + importance
CREATE INDEX idx_episodes_unprocessed ON episodes(profile_id, is_processed) WHERE is_processed = false;
CREATE INDEX idx_episodes_occurred ON episodes(profile_id, occurred_at DESC);
CREATE INDEX idx_episodes_entity ON episodes(entity_id) WHERE entity_id IS NOT NULL;
CREATE INDEX idx_episodes_type ON episodes(profile_id, event_type);

-- pgvector index for similarity search (IVFFlat — suitable for < 1M rows per user)
CREATE INDEX idx_episodes_embedding ON episodes USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

**RLS policy:** `profile_id = auth.uid()` for SELECT and INSERT. No UPDATE or DELETE from the client — episodes are immutable append-only records. Only the service role (reflection engine) can UPDATE `is_processed` and `processed_at`.

---

## 4. What Triggers a New Episode

### 4.1 Trigger Rules

Every signal that arrives at the Memory Store layer creates exactly one episode. There is no batching, merging, or deduplication at the episodic level — that is the signal layer's responsibility (see `signal-task-interaction.md` Section 4).

The episode writer receives a pre-deduplicated signal and:
1. Generates the `summary` string from the signal payload.
2. Computes the `importanceScore`.
3. Writes the episode to local store and queues for Supabase sync.
4. Queues the episode for embedding generation (async, non-blocking).

### 4.2 Summary Generation

Summaries are generated deterministically from signal type + payload. No LLM call. Templates:

| Event type | Summary template |
|------------|-----------------|
| `task.created` | "Created task '{title}' in {bucket} bucket (source: {sourceType})" |
| `task.deferred` | "Deferred '{title}' from {oldDate} to {newDate} (defer #{count})" |
| `task.completed` | "Completed '{title}' — {actual}min actual vs {estimated}min estimated" |
| `task.deleted` | "Deleted '{title}' after {age} days and {deferCount} deferrals" |
| `task.priorityChanged` | "Changed priority of '{title}' from {old} to {new}" |
| `email.received` | "Email from {sender}: '{subject}' — classified as {bucket}" |
| `calendar.eventAdded` | "Calendar: '{subject}' added at {start}" |
| `calendar.eventCancelled` | "Calendar: '{subject}' cancelled" |
| `focus.completed` | "Focus session: {duration}min on '{taskTitle}'" |
| `voice.captured` | "Voice note: '{firstWords}...'" |
| `correction.triage` | "Corrected triage of '{subject}' from {oldBucket} to {newBucket}" |

These summaries serve two purposes: human-readable audit trail, and text input for embedding generation.

---

## 5. Write Protocol

### 5.1 Write Path

```
Signal arrives (from Signal Ingestion layer)
  │
  ├─ 1. EpisodeWriter.write(signal) — synchronous local write
  │     └─ Generates summary, computes importance, writes to local DataStore buffer
  │
  ├─ 2. Queue for Supabase sync (async, via SyncManager)
  │     └─ Batched writes every 30 seconds or when buffer > 50 episodes
  │
  └─ 3. Queue for embedding generation (async, via EmbeddingQueue)
        └─ Batched: up to 20 summaries per Jina API call
        └─ On success: update episode with embedding + embeddingGeneratedAt
        └─ On failure: leave embedding nil, retry in next batch cycle
```

### 5.2 Local Storage

Episodes are stored locally in `~/Library/Application Support/Timed/episodes/` as date-partitioned JSON files:

```
episodes/
  2026-04-02.json    ← today's episodes
  2026-04-01.json    ← yesterday's
  ...
```

Each file contains an array of `Episode` records for that day. Date partitioning keeps individual files manageable and enables efficient date-range queries without loading the full history.

**DataStore additions:**
```swift
func appendEpisode(_ episode: Episode) throws
func loadEpisodes(for date: Date) throws -> [Episode]
func loadEpisodes(from: Date, to: Date) throws -> [Episode]
func loadUnprocessedEpisodes(limit: Int) throws -> [Episode]
func markProcessed(ids: Set<UUID>) throws
```

### 5.3 Immutability

Episodes are append-only. Once written, an episode is never modified except for:
- `embedding` and `embeddingGeneratedAt` (set asynchronously after write)
- `isProcessed` and `processedAt` (set by the reflection engine after consumption)

No other field is ever updated. No episode is ever deleted (see Retention Policy, Section 6).

---

## 6. Retention Policy

### 6.1 Retention Tiers

| Age | Storage | Detail level |
|-----|---------|--------------|
| 0-30 days | Full episode: all fields, raw payload, embedding | Everything preserved |
| 31-180 days | Full episode: all fields, raw payload archived, embedding preserved | `raw_data` moved to cold storage (Supabase Storage bucket) and replaced with a reference URI |
| 181-365 days | Summary + embedding + metadata only | `raw_data` reference kept for audit, not readily queryable |
| 365+ days | Aggregated into semantic memory, episodic record tombstoned | Episode summary retained as evidence chain link, raw data purged |

### 6.2 Retention Exceptions

Episodes with `importanceScore >= 0.8` are never aged out. These represent significant behavioural events (chronic avoidance, major corrections, breakthrough patterns) that the reflection engine should be able to reference indefinitely.

### 6.3 Implementation

A nightly maintenance job (Supabase Edge Function or scheduled Swift task) handles tier transitions:
1. Move `raw_data` to cold storage for episodes > 30 days.
2. Tombstone episodes > 365 days that have `importanceScore < 0.8`.
3. Verify all tombstoned episodes have been consumed by the reflection engine (`isProcessed == true`). Never tombstone unprocessed episodes.

---

## 7. Importance Scoring

### 7.1 Scoring at Write Time

Every episode receives an importance score (0.0 to 1.0) at write time. This score determines retrieval priority and retention behaviour.

### 7.2 Scoring Rules

**Base scores by event type:**

| Event type | Base score | Rationale |
|------------|------------|-----------|
| `task.created` | 0.30 | Routine |
| `task.viewed` | 0.10 | Noise unless repeated |
| `task.deferred` | 0.50 | Behavioural signal |
| `task.completed` | 0.40 | Learning signal |
| `task.deleted` | 0.30 | Mildly interesting |
| `task.priorityChanged` | 0.40 | User disagrees with AI |
| `email.received` | 0.20 | High volume, low per-item value |
| `email.triageCorrected` | 0.70 | User correcting AI = high value |
| `calendar.eventAdded` | 0.25 | Routine |
| `calendar.eventCancelled` | 0.40 | Potential stress/reprioritisation signal |
| `focus.completed` | 0.35 | Learning signal |
| `focus.abandoned` | 0.50 | Possible distraction or avoidance |
| `voice.captured` | 0.60 | Executive chose to speak — high intent |
| `correction.*` | 0.80 | Any user correction of AI is critical |
| `system.dayStarted` | 0.10 | Timestamp marker only |
| `system.dayEnded` | 0.15 | Slight interest for work-hours analysis |

**Modifiers (additive, capped at 1.0):**

| Condition | Modifier | Rationale |
|-----------|----------|-----------|
| Task defer count >= 3 | +0.20 | Chronic avoidance |
| Task defer count >= 5 | +0.30 | Severe avoidance (replaces +0.20) |
| Completion with focus timer (high-confidence actual) | +0.10 | Higher data quality |
| Actual vs estimated delta > 50% | +0.15 | Significant estimation error |
| Email from VIP sender (top 10 by communication frequency) | +0.15 | Stakeholder importance |
| Event outside normal work hours (before 7am or after 8pm) | +0.10 | Anomaly signal |
| First occurrence of a new event type for this profile | +0.20 | Novel behaviour |

### 7.3 Recalibration

Importance scores are static after write. They are NOT retroactively adjusted. If the reflection engine determines an episode was more important than initially scored, it records that insight in semantic memory with an evidence chain pointing back to the episode ID. The episodic score is a fast heuristic for retrieval ranking, not a definitive importance measure.

---

## 8. Embedding Generation

### 8.1 Model

Jina AI `jina-embeddings-v3`, 1024 dimensions. Cosine similarity for retrieval.

### 8.2 Input

The `summary` field is the embedding input. Not `rawData` — the summary is a normalised, consistent-length text representation suitable for embedding.

For voice captures, the full transcript (up to 500 tokens) is embedded instead of just the summary, since the transcript contains richer semantic content.

### 8.3 Batch Pipeline

```
EmbeddingQueue (actor):
  - Accumulates episodes without embeddings
  - Every 60 seconds OR when queue reaches 20 items:
    - Extract summaries
    - POST to Jina API: /v1/embeddings with input array
    - On success: update episodes in DataStore + queue Supabase update
    - On failure: log error, retry in next cycle (episodes remain in queue)
  - Rate limit: max 100 embeddings/minute (Jina free tier)
  - Backpressure: if queue exceeds 200 items, increase batch size to 50
```

### 8.4 Cost Estimate

At ~100-150 episodes/day and ~20 tokens/summary average:
- ~2,000-3,000 tokens/day for embeddings
- Jina free tier: 1M tokens/month → ~330-500 days of usage per month's allocation
- Effectively free for a single user

---

## 9. Query Interface for Reflection Engine

### 9.1 Query Methods

The reflection engine needs four query patterns:

#### 9.1.1 Unprocessed Episodes (Batch Read)

```swift
func fetchUnprocessedEpisodes(profileId: UUID, limit: Int = 500) async throws -> [Episode]
```

Returns episodes where `isProcessed == false`, ordered by `occurredAt ASC`. The reflection engine calls this nightly to get the day's events.

#### 9.1.2 Recency-Weighted Retrieval

```swift
func fetchRecentEpisodes(
    profileId: UUID,
    since: Date,
    eventTypes: [String]? = nil,
    minImportance: Float = 0.0,
    limit: Int = 100
) async throws -> [Episode]
```

Returns episodes within a time window, optionally filtered by type and minimum importance. Ordered by `occurredAt DESC`.

#### 9.1.3 Semantic Similarity Search

```swift
func searchEpisodes(
    profileId: UUID,
    queryEmbedding: [Float],
    topK: Int = 20,
    minImportance: Float = 0.0,
    maxAge: TimeInterval? = nil
) async throws -> [EpisodeSearchResult]
```

Uses pgvector cosine similarity to find episodes semantically similar to a query. Returns results ranked by a composite score:

```
retrievalScore = (recencyWeight * recencyDecay) + (importanceWeight * importanceScore) + (similarityWeight * cosineSimilarity)
```

Where:
- `recencyDecay = exp(-lambda * hoursSinceEpisode)`, lambda = 0.01 (half-life ~69 hours)
- `recencyWeight = 0.3`
- `importanceWeight = 0.2`
- `similarityWeight = 0.5`

This follows the Park et al. (2023) retrieval scoring: recency x importance x relevance.

```swift
struct EpisodeSearchResult: Sendable {
    let episode: Episode
    let cosineSimilarity: Float
    let retrievalScore: Float
}
```

#### 9.1.4 Entity History

```swift
func fetchEntityHistory(
    profileId: UUID,
    entityId: UUID,
    limit: Int = 50
) async throws -> [Episode]
```

Returns all episodes for a specific entity (task, email thread, calendar event), ordered chronologically. Used by the reflection engine to build the full lifecycle narrative of a specific item.

### 9.2 Supabase RPC Functions

For server-side queries (used by Edge Functions / reflection engine):

```sql
-- Semantic search with composite scoring
CREATE OR REPLACE FUNCTION match_episodes(
    p_profile_id UUID,
    p_query_embedding vector(1024),
    p_top_k INT DEFAULT 20,
    p_min_importance REAL DEFAULT 0.0,
    p_max_age_hours INT DEFAULT NULL
) RETURNS TABLE (
    id UUID,
    occurred_at TIMESTAMPTZ,
    event_type TEXT,
    summary TEXT,
    importance_score REAL,
    cosine_similarity REAL,
    retrieval_score REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id,
        e.occurred_at,
        e.event_type,
        e.summary,
        e.importance_score,
        1 - (e.embedding <=> p_query_embedding) AS cosine_similarity,
        (0.3 * exp(-0.01 * EXTRACT(EPOCH FROM (now() - e.occurred_at)) / 3600.0))
        + (0.2 * e.importance_score)
        + (0.5 * (1 - (e.embedding <=> p_query_embedding))) AS retrieval_score
    FROM episodes e
    WHERE e.profile_id = p_profile_id
      AND e.importance_score >= p_min_importance
      AND e.embedding IS NOT NULL
      AND (p_max_age_hours IS NULL OR e.occurred_at >= now() - make_interval(hours := p_max_age_hours))
    ORDER BY retrieval_score DESC
    LIMIT p_top_k;
END;
$$ LANGUAGE plpgsql STABLE;
```

---

## 10. Relationship to Semantic and Procedural Tiers

### 10.1 Data Flow

```
Episodic Memory (this spec)
    │
    │  Reflection Engine reads episodes nightly
    │  Extracts patterns, facts, rules
    │
    ├──► Semantic Memory
    │    "This executive defers HR tasks on Mondays"
    │    Evidence: [episode_id_1, episode_id_2, episode_id_3]
    │
    └──► Procedural Memory
         "IF task is HR-related AND day is Monday THEN schedule for Tuesday morning"
         Evidence: [episode_id_1, episode_id_2, episode_id_3]
```

### 10.2 Evidence Chains

Every fact in semantic memory and every rule in procedural memory MUST include an evidence chain — an array of episodic `id` values that the reflection engine used to derive it. This enables:
- **Explainability:** "Why does Timed think I avoid HR tasks?" → here are the 7 episodes that formed this conclusion.
- **Confidence decay:** If the source episodes are old and no new supporting episodes arrive, the derived fact's confidence decays.
- **Contradiction detection:** If new episodes contradict a derived fact, the evidence chain makes the conflict explicit.

### 10.3 Cross-Reference Integrity

The episodic store does not reference semantic or procedural memory. Data flows one direction: episodic → reflection engine → semantic/procedural. This keeps the episodic layer a clean, immutable event log with no circular dependencies.

---

## 11. Performance Requirements

### 11.1 Write Throughput

- **Target:** Handle 1,000+ episodes per day without degradation.
- **Burst:** Handle 50 episodes in 1 second (e.g., batch import of historical calendar events during onboarding).
- **Write latency:** Local write < 5ms. Supabase sync is async and does not block the write path.

### 11.2 Read Performance

- **Unprocessed batch read:** < 200ms for 500 episodes.
- **Recency query:** < 100ms for 100 most recent episodes with type filter.
- **Semantic search:** < 100ms for top-20 results via pgvector IVFFlat index.
- **Entity history:** < 50ms for 50 episodes of a single entity.

### 11.3 Storage Estimate

Per episode: ~2KB (metadata + summary) + ~4KB (embedding, 1024 float32) + ~500B (raw_data average) = ~6.5KB

At 150 episodes/day:
- Per day: ~1MB
- Per month: ~30MB
- Per year: ~365MB
- Supabase free tier includes 500MB database + 1GB storage — sufficient for 1+ years with cold storage offloading.

---

## 12. Acceptance Criteria

1. **Every signal produces an episode** — Emit a task signal. Verify an episode exists in the local store within 1 second with correct `source`, `eventType`, `entityId`, `summary`, and `importanceScore`.

2. **Importance scoring is deterministic** — Same signal payload produces same importance score every time. No randomness. Verified by unit test with 10+ signal types.

3. **Embeddings are generated asynchronously** — Write 20 episodes rapidly. All 20 are persisted immediately with `embedding == nil`. Within 120 seconds, all 20 have embeddings populated.

4. **Semantic search returns relevant results** — Insert 100 episodes with known topics. Query with a topic-related embedding. The top-5 results include the expected episodes. Retrieval score correctly weights recency, importance, and similarity.

5. **Unprocessed query is correct** — Insert 50 episodes. Mark 30 as processed. Query unprocessed. Exactly 20 returned, ordered by `occurredAt ASC`.

6. **Entity history is complete** — Create a task. Defer it 3 times. Complete it. Query entity history for that task ID. Returns exactly 5 episodes (1 created + 3 deferred + 1 completed) in chronological order.

7. **Evidence chains are referenceable** — Semantic memory fact cites episodic IDs. All cited IDs exist in the episodic store and match the expected events.

8. **Retention policy respects importance** — Run the retention job on episodes older than 365 days. Episodes with `importanceScore >= 0.8` are NOT tombstoned. Episodes with `importanceScore < 0.8` that are processed ARE tombstoned.

9. **Immutability holds** — Attempt to update an episode's `summary`, `importanceScore`, or `rawData` via the client API. The operation is rejected (RLS blocks UPDATE on those columns, or the Swift API simply does not expose mutation methods).

10. **Performance targets met** — Load test with 1,500 episodes in the store. Semantic search returns top-20 in < 100ms. Unprocessed batch read returns 500 in < 200ms. Verified with XCTest `measure {}` blocks.
