# Memory Retrieval Engine — Implementation Spec

> Timed v1 Intelligence Layer | Last updated: 2026-04-02

---

## 1. Purpose

The Memory Retrieval Engine is the query interface to Timed's three-tier memory store (episodic, semantic, procedural). Every time the system needs context — morning briefing assembly, mid-day proactive alert, nightly reflection input selection — it passes through this engine. The engine must return the most cognitively relevant memories in under 200ms, regardless of store size.

---

## 2. Three-Axis Scoring Model

Every candidate memory receives a composite relevance score computed from three orthogonal axes. Each axis produces a normalised value in [0, 1].

### 2.1 Recency — Time-Decay Function

**Formula (Stanford Generative Agents, Park et al. 2023):**

```
recency(m) = decay_rate ^ hours_since_access(m)
```

- `decay_rate = 0.995` per hour (from the original paper — produces a half-life of ~138 hours / ~5.8 days)
- `hours_since_access(m)` = wall-clock hours since the memory was last retrieved or written
- Uses *last access* time, not creation time — retrieval refreshes recency (consistent with human reconsolidation)

**Decay curve properties:**
| Hours elapsed | Recency score |
|---------------|---------------|
| 0             | 1.000         |
| 12            | 0.942         |
| 24            | 0.887         |
| 72 (3 days)   | 0.698         |
| 168 (1 week)  | 0.428         |
| 720 (30 days) | 0.027         |

**Implementation note:** Store `last_accessed_at` as a Unix timestamp on every memory record. Recency is computed at query time, never pre-computed — it changes with every passing hour.

### 2.2 Importance — LLM-Assigned at Write Time

**Assignment:** When a memory is written (episodic event logged, semantic fact extracted, procedural rule generated), the writing agent assigns an importance score on a 1-10 integer scale, normalised to [0, 1] by dividing by 10.

**Prompt pattern for importance scoring (Haiku-tier, inline with memory creation):**

```
On a scale of 1 to 10, where 1 is purely routine (e.g. "ate lunch") and 10 is 
life-altering (e.g. "fired the CFO"), rate the importance of this memory to the 
executive's professional life:

Memory: {memory_content}

Respond with only the integer.
```

**Calibration anchors (included in system prompt for consistency):**
| Score | Example |
|-------|---------|
| 1     | Routine calendar event, standard email reply |
| 3     | Completed a regular task, minor schedule change |
| 5     | Key stakeholder meeting, significant email exchange, deadline met/missed |
| 7     | Strategic decision made, pattern detected in behaviour, conflict with direct report |
| 9     | Board-level decision, major pivot, career-affecting event |
| 10    | Crisis event, resignation, acquisition |

**Immutability:** Importance scores are set once at write time and do not decay. A board decision from 6 months ago is still importance=9 — recency handles its temporal relevance separately. Exception: the nightly reflection engine may upgrade importance if it discovers that a previously low-importance event was actually a precursor to a significant pattern.

### 2.3 Relevance — Cosine Similarity of Embeddings

**Embedding model:** Jina AI `jina-embeddings-v3`, 1024-dimensional vectors.

**At write time:** Every memory's textual content is embedded and stored alongside the memory record.

**At query time:** The query string (e.g., morning briefing topic, user question, reflection prompt) is embedded with the same model, and cosine similarity is computed against all candidate memories.

```
relevance(m, q) = cosine_similarity(embed(m.content), embed(q))
```

**Cosine similarity range:** [-1, 1] in theory, but real text embeddings cluster in [0.2, 0.9]. Normalise to [0, 1] via:

```
relevance_norm = max(0, cosine_similarity)
```

Negative similarities are clamped to 0 — they indicate anti-relevance and should never boost a memory.

---

## 3. Composite Score and Dynamic Weighting

### 3.1 Weighted Combination

```
score(m, q, context) = w_r * recency(m) + w_i * importance(m) + w_v * relevance(m, q)
```

Where `w_r + w_i + w_v = 1.0`.

### 3.2 Dynamic Weight Profiles

Weights shift based on the retrieval context. The calling subsystem declares its context type, and the engine selects the corresponding weight profile.

| Context Type | w_r (recency) | w_i (importance) | w_v (relevance) | Rationale |
|--------------|---------------|-------------------|-----------------|-----------|
| `morning_briefing` | 0.45 | 0.25 | 0.30 | Morning needs yesterday's events, weighted recent |
| `proactive_alert` | 0.40 | 0.35 | 0.25 | Alerts trigger on important + recent signals |
| `nightly_reflection` | 0.20 | 0.35 | 0.45 | Reflection needs thematic relevance across time |
| `monthly_review` | 0.10 | 0.45 | 0.45 | Long-range pattern detection — recency deprioritised |
| `user_query` | 0.15 | 0.20 | 0.65 | Direct questions demand semantic match |
| `conflict_resolution` | 0.10 | 0.40 | 0.50 | Contradictions need relevant + important evidence |
| `procedural_lookup` | 0.05 | 0.30 | 0.65 | Rule matching is almost pure relevance |

**Default profile** (if no context declared): `{ 0.30, 0.30, 0.40 }` — balanced with slight relevance bias.

### 3.3 Future Enhancement: ACAN Adaptive Cross-Attention

The static weight profiles above are a V1 heuristic. The planned V2 enhancement replaces them with an **Adaptive Cross-Attention Network (ACAN)** that learns optimal weights per-query:

- **Architecture:** Small transformer encoder (2 layers, 256-dim) that takes the query embedding + context features (time of day, day of week, query type, user state) and outputs 3 softmax-normalised weights.
- **Training signal:** User engagement with surfaced memories — did the executive reference it, dismiss it, or act on it? Implicit reward from downstream actions.
- **Training requirement:** Minimum 500 retrieval events with implicit feedback before ACAN replaces static profiles.
- **Fallback:** Static profiles remain as the cold-start and fallback mechanism. ACAN weights are bounded to stay within ±0.15 of the static profile to prevent degenerate solutions.

This is a V2 item. Do not build until the static system has been validated in production.

---

## 4. Retrieval Pipeline

### 4.1 Two-Phase Retrieval

Scoring all memories on all three axes is computationally infeasible at scale. The pipeline uses a two-phase approach:

**Phase 1 — Candidate Generation (vector search, <100ms target)**

1. Embed the query using Jina v3 (1024-dim).
2. Perform approximate nearest-neighbour search to retrieve the top-K candidates by cosine similarity.
3. K = 100 (retrieves 100 candidates regardless of final return count).

**Phase 2 — Re-ranking (three-axis scoring, <100ms target)**

1. For each of the K candidates, compute recency and importance (both O(1) lookups).
2. Compute composite score using the context-appropriate weight profile.
3. Sort by composite score descending.
4. Return top-N results (N varies by caller — see Section 5).

### 4.2 Vector Search Implementation

**Decision: Local-first with USearch, Supabase pgvector as sync/backup.**

| Option | Latency (p50) | Latency (p99) | Offline? | Implementation complexity |
|--------|---------------|---------------|----------|---------------------------|
| **USearch (local, recommended)** | 1-5ms | 10ms | Yes | Low — single Swift package, HNSW index |
| FAISS (local) | 1-5ms | 10ms | Yes | Medium — C++ bridge, more complex build |
| Supabase pgvector | 20-80ms | 200ms | No | Low — SQL query, but network-bound |

**Recommendation: USearch** for all primary retrieval. Reasons:
- Swift-native bindings available (`usearch` SPM package)
- HNSW index supports 1024-dim vectors efficiently
- Sub-10ms queries for up to 1M vectors on Apple Silicon
- Works fully offline — critical for executive privacy and reliability
- Memory footprint: ~4KB per vector × 100K memories = ~400MB (fits comfortably in RAM on any Mac)

**pgvector role:** Supabase stores the authoritative copy of all memories + embeddings. Sync on write. pgvector is the backup retrieval path if local index is corrupted, and enables future cross-device sync. Never the primary query path for latency-sensitive retrieval.

**Index configuration (USearch HNSW):**
- `metric: .cosine`
- `dimensions: 1024`
- `connectivity: 16` (M parameter — 16 is standard for this dimensionality)
- `expansion_add: 128` (ef_construction)
- `expansion_search: 64` (ef_search — trade latency vs recall; 64 gives >95% recall@100)

### 4.3 Tier-Specific Candidate Pools

Not all queries search all tiers:

| Context Type | Tiers Searched | Rationale |
|--------------|----------------|-----------|
| `morning_briefing` | episodic + semantic + procedural | Full context assembly |
| `proactive_alert` | episodic + semantic | Alerts are about events and facts, not rules |
| `nightly_reflection` | episodic (primary), semantic (secondary) | Reflection builds FROM episodic INTO semantic |
| `user_query` | All tiers | User questions can be about anything |
| `procedural_lookup` | procedural only | Looking for operating rules |
| `conflict_resolution` | semantic + episodic | Checking facts against new evidence |

---

## 5. Result Counts Per Query Type

How many memories to surface depends on the consumer:

| Consumer | N (memories returned) | Rationale |
|----------|----------------------|-----------|
| Morning briefing assembly | 25-40 | Opus needs rich context to build a cognitive briefing. Tokens are cheap here — intelligence quality is the priority. |
| Proactive alert generation | 5-10 | Alert needs supporting evidence, not exhaustive history |
| Nightly reflection — per reflection prompt | 50-75 | Deep reflection requires broad episodic input. Multiple passes with different prompts. |
| User direct query | 10-20 | Conversational response with supporting evidence |
| Procedural rule lookup | 3-5 | Looking for the most relevant operating rules |
| Conflict resolution | 15-25 | Need enough evidence to adjudicate contradictions |

**Token budget awareness:** Each memory averages ~150 tokens. At N=50, that's ~7,500 tokens of memory context. The caller is responsible for fitting retrieved memories into the LLM context window — the retrieval engine returns scored results and lets the caller truncate if needed.

---

## 6. Latency Targets and Performance Budget

**End-to-end retrieval target: <200ms (p95)**

| Phase | Budget | Notes |
|-------|--------|-------|
| Query embedding (Jina v3) | <80ms | Local inference if possible; API call if not. Cache repeated queries. |
| USearch ANN lookup (K=100) | <10ms | HNSW on Apple Silicon, 1024-dim, up to 500K vectors |
| Three-axis scoring + sort | <5ms | 100 candidates × 3 multiplications + sort = trivial |
| Total | <95ms | Well within 200ms budget |

**Embedding latency mitigation:**
- **Option A (preferred):** Run Jina v3 locally via Core ML converted model. 1024-dim embedding of a ~100 token query on M-series: ~20-40ms. No network dependency.
- **Option B (fallback):** Jina API call. ~50-150ms depending on network. Acceptable but adds variance.
- **Caching:** Cache query embeddings for repeated or similar queries within a session. Morning briefing uses ~5 distinct query prompts — embed once, reuse.

---

## 7. Memory Record Schema

Each memory record in CoreData (local) and Supabase (remote) contains:

```swift
struct MemoryRecord {
    let id: UUID
    let tier: MemoryTier           // .episodic | .semantic | .procedural
    let content: String            // Human-readable memory text
    let embedding: [Float]         // 1024-dim Jina v3 embedding
    let importance: Float          // 0.0-1.0 (LLM-assigned at write time)
    let createdAt: Date            // When the memory was first created
    var lastAccessedAt: Date       // Updated on every retrieval (drives recency)
    let sourceType: SourceType     // .email | .calendar | .voice | .task | .reflection | .user_correction
    let sourceId: String?          // Reference to originating event/email/etc.
    var accessCount: Int           // How many times retrieved (for analytics)
    let metadata: [String: String] // Flexible key-value for tier-specific data
}

enum MemoryTier: String, Codable, CaseIterable, Sendable {
    case episodic    // Raw events: "Met with Sarah at 2pm, discussed Q3 pipeline"
    case semantic    // Learned facts: "Executive avoids people decisions after 3pm"
    case procedural  // Operating rules: "IF deadline < 48h AND importance > 7 THEN surface in morning briefing"
}
```

**CoreData model:** Maps directly. `embedding` stored as `Transformable` with `[Float]` value transformer. Indexed on `tier` and `lastAccessedAt`.

**Supabase table:**

```sql
create table memories (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users not null,
    tier text not null check (tier in ('episodic', 'semantic', 'procedural')),
    content text not null,
    embedding vector(1024) not null,
    importance float not null check (importance >= 0 and importance <= 1),
    created_at timestamptz not null default now(),
    last_accessed_at timestamptz not null default now(),
    source_type text not null,
    source_id text,
    access_count int not null default 0,
    metadata jsonb default '{}'::jsonb
);

-- HNSW index for pgvector (backup retrieval path)
create index memories_embedding_idx on memories 
    using hnsw (embedding vector_cosine_ops) 
    with (m = 16, ef_construction = 128);

-- Composite index for tier-scoped queries
create index memories_tier_accessed_idx on memories (tier, last_accessed_at desc);

-- RLS: users can only access their own memories
alter table memories enable row level security;
create policy "users_own_memories" on memories 
    for all using (auth.uid() = user_id);
```

---

## 8. Edge Cases and Failure Modes

### 8.1 Cold Start (< 50 memories)
When the memory store has fewer than 50 records, retrieval returns all memories without scoring. The three-axis model is meaningless with tiny candidate pools. Switch to scored retrieval once the store exceeds 50 episodic memories.

### 8.2 Embedding Model Change
If Jina v3 is replaced with a different embedding model (different dimensionality or semantic space), all existing embeddings must be re-computed. Store the embedding model version on each record. On model change, queue a background re-embedding job and maintain dual indices during migration.

### 8.3 Recency Bias Mitigation
Pure time-decay can bury critical old memories. Safeguards:
- Importance score is independent of time — a high-importance memory retains its importance forever.
- The nightly reflection engine periodically queries with `monthly_review` weights (low recency weight) specifically to surface forgotten but important memories.
- Procedural memories are exempt from recency decay — rules don't expire by default. They are only invalidated explicitly by the reflection engine.

### 8.4 Stale Procedural Rules
Procedural rules generated months ago may no longer apply (executive changed roles, changed habits). The reflection engine runs a monthly procedural audit: retrieves all procedural memories, tests each against the last 30 days of episodic evidence, and flags rules with no supporting evidence for review/deletion.

### 8.5 Retrieval Returns Only Low-Scoring Results
If the top-scoring result has a composite score below 0.15, the retrieval engine returns an empty result set with a `low_confidence` flag. The caller should fall back to a broader query or proceed without memory context rather than inject irrelevant memories.

---

## 9. API Surface

```swift
protocol MemoryRetrievalEngine {
    /// Primary retrieval: returns scored memories for a query in a given context
    func retrieve(
        query: String,
        context: RetrievalContext,
        tiers: Set<MemoryTier>,
        limit: Int,
        minScore: Float
    ) async throws -> [ScoredMemory]
    
    /// Batch retrieval: multiple queries in a single call (morning briefing assembly)
    func retrieveBatch(
        queries: [(query: String, context: RetrievalContext, tiers: Set<MemoryTier>, limit: Int)],
        minScore: Float
    ) async throws -> [[ScoredMemory]]
    
    /// Update last_accessed_at for retrieved memories (call after consumption)
    func markAccessed(memoryIds: [UUID]) async throws
    
    /// Rebuild local USearch index from CoreData (startup, recovery)
    func rebuildIndex() async throws
}

struct ScoredMemory {
    let memory: MemoryRecord
    let compositeScore: Float
    let recencyScore: Float
    let importanceScore: Float
    let relevanceScore: Float
}

enum RetrievalContext: String {
    case morningBriefing
    case proactiveAlert
    case nightlyReflection
    case monthlyReview
    case userQuery
    case conflictResolution
    case proceduralLookup
}
```

---

## 10. Testing Strategy

- **Unit tests:** Verify three-axis scoring math — decay curve values at known time offsets, importance normalisation, cosine similarity bounds.
- **Integration tests:** Write 100 synthetic memories with known properties, verify retrieval ordering matches expected ranking for each context type.
- **Latency benchmarks:** Measure p50/p95/p99 retrieval latency with 1K, 10K, 100K, 500K memories in USearch index. Fail the test if p95 exceeds 200ms at any scale.
- **Weight profile validation:** For each context type, construct scenarios where the "correct" memory to surface is obvious, verify the weight profile produces it.
- **Regression guard:** Golden test set of 20 query-memory pairs with expected top-3 results. Run on every change to scoring logic.
