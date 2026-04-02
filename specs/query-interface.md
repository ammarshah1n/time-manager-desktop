# Query Interface Spec

**Status:** Implementation-ready
**Layer:** 4 (Intelligence Delivery) — reads from Layer 2 (Memory Store)
**Owner:** QueryEngine
**Depends on:** UserIntelligenceStore, EmbeddingService, Haiku (intent classification), Sonnet (response synthesis)

---

## 1. Purpose

Allow the executive to ask free-form natural language questions about their own behaviour, history, relationships, and patterns at any point during the day. The system searches across all three memory tiers — episodic, semantic, procedural — ranks results, synthesises an answer, and returns it within 3 seconds.

This is not a chatbot. It is a retrieval interface into the executive's own cognitive model. The system answers from what it has observed and learned, not from general knowledge.

---

## 2. Interaction Surface

### 2.1 Entry Points

| Entry Point | Trigger | Context |
|---|---|---|
| Command Palette | `Cmd+K` or `Cmd+Shift+Space` (global hotkey) | Text input, full query |
| Morning Session | Voice during morning interview | Conversational, follow-up to briefing |
| Menu Bar | Click → type query | Quick lookup, glanceable response |

### 2.2 Input Format

- Free-form natural language text (typed or transcribed from voice)
- No structured query syntax — the system must handle natural phrasing
- Minimum input: 3 words (below this, prompt for clarification)
- Maximum input: 500 characters (truncate beyond this — if the executive needs to write an essay, it is not a query)

---

## 3. Query Classification

Every query is first classified by Haiku to determine intent and route to the appropriate retrieval strategy.

### 3.1 Query Types

```swift
enum QueryType {
    case factual          // "When did I last talk to Sarah?"
    case pattern          // "What's my decision pattern on hiring?"
    case comparison       // "How does this quarter compare to last?"
    case relationship     // "Who have I been meeting with most?"
    case temporal         // "What was I working on last Tuesday?"
    case procedural       // "What rules has the system learned about me?"
    case meta             // "How confident are you in this answer?"
    case unsupported      // future predictions, queries about unobserved people, etc.
}
```

### 3.2 Classification Prompt (Haiku)

```
You are a query classifier for a personal intelligence system. Classify the following query into exactly one type.

Query: "{user_query}"

Types:
- factual: Asks about a specific event, date, person, or fact from observed history
- pattern: Asks about recurring behaviour, tendencies, or habits
- comparison: Asks to compare two time periods, behaviours, or outcomes
- relationship: Asks about interactions with specific people or groups
- temporal: Asks about what happened at a specific time or period
- procedural: Asks about learned rules or operating patterns
- meta: Asks about the system's own confidence or knowledge state
- unsupported: Cannot be answered from observation data

Respond with only the type name and a confidence score (0.0-1.0).
```

**Latency budget:** < 300ms (Haiku classification is fast)

---

## 4. Memory Tier Search Strategy

After classification, the QueryEngine searches across memory tiers. The search strategy varies by query type.

### 4.1 Search Routing

| Query Type | Primary Tier | Secondary Tier | Tertiary Tier |
|---|---|---|---|
| factual | Episodic | Semantic | — |
| pattern | Semantic | Procedural | Episodic (for evidence) |
| comparison | Episodic (both periods) | Semantic (for context) | — |
| relationship | Episodic (filtered by person) | Semantic (relationship facts) | Procedural (interaction rules) |
| temporal | Episodic (time-filtered) | — | — |
| procedural | Procedural | Semantic (supporting facts) | — |
| meta | All tiers (metadata only) | — | — |

### 4.2 Retrieval Mechanism

**Step 1 — Embed the query.**

Generate a 1024-dim embedding of the query using Jina AI jina-embeddings-v3 (same embedding model used for memory storage, ensuring aligned vector spaces).

**Step 2 — Vector search across relevant tiers.**

For each tier in the search route:
- Query the Supabase vector store (pgvector) with cosine similarity
- Return top-K results per tier:
  - Episodic: K=20 (many events, need broad coverage)
  - Semantic: K=10 (fewer, more distilled facts)
  - Procedural: K=5 (rules are specific)

**Step 3 — Re-rank results.**

Apply the retrieval scoring function adapted from Stanford Generative Agents:

```
score = (recency_weight * recency) + (importance_weight * importance) + (relevance_weight * relevance)
```

Where:
- `recency` = exponential decay from current time. `exp(-decay_rate * hours_since_creation)`. Decay rate: 0.01 for semantic (slow decay — facts persist), 0.05 for episodic (faster decay — events fade), 0.02 for procedural (moderate — rules persist but can become stale).
- `importance` = stored importance score (0.0–1.0) assigned at memory creation. High-stakes decisions, emotional events, and rule violations have high importance.
- `relevance` = cosine similarity between query embedding and memory embedding.

**Weight configuration by query type:**

| Query Type | Recency Weight | Importance Weight | Relevance Weight |
|---|---|---|---|
| factual | 0.2 | 0.2 | 0.6 |
| pattern | 0.1 | 0.3 | 0.6 |
| comparison | 0.1 | 0.3 | 0.6 |
| relationship | 0.3 | 0.2 | 0.5 |
| temporal | 0.5 | 0.1 | 0.4 |
| procedural | 0.1 | 0.4 | 0.5 |
| meta | 0.1 | 0.1 | 0.8 |

**Step 4 — Deduplicate and merge.**

- Remove duplicate memories that reference the same underlying event
- Merge episodic memories that are part of the same sequence (e.g., three emails in the same thread → one consolidated reference)
- Cap final result set at 15 memories total

**Step 5 — Assemble context window.**

Format the retrieved memories into a structured context block for the response synthesiser.

---

## 5. Response Synthesis

### 5.1 Model Selection

| Query Complexity | Model | Rationale |
|---|---|---|
| Simple factual ("When did I last...") | Haiku | Fast, deterministic lookup — no reasoning needed |
| Pattern / comparison / relationship | Sonnet | Requires reasoning across multiple memories |
| Deep meta / complex comparison | Sonnet | Needs nuanced synthesis but not Opus-level depth |

Opus is reserved for nightly reflection and morning sessions. Mid-day queries use Sonnet at most to preserve the latency target.

### 5.2 Synthesis Prompt Structure

```
You are the query engine for Timed, a personal intelligence system. You answer questions about the executive based ONLY on retrieved memories. Never fabricate information. If the memories don't contain the answer, say so.

## Executive Profile (from core memory)
{core_memory_snapshot}

## Retrieved Memories
{formatted_memories_with_source_tier_and_scores}

## Query
{user_query}

## Instructions
- Answer directly. No preamble.
- Cite specific dates, events, and people from the memories.
- If you see a pattern across memories, name it.
- If confidence is low (few memories, low relevance scores), say: "Low confidence — I have limited data on this."
- If the query is about something you haven't observed, say: "I haven't observed enough about [topic] to answer this."
- Keep the response under 150 words for factual queries, under 300 words for pattern/comparison queries.
```

### 5.3 Response Format

```swift
struct QueryResponse {
    let id: UUID
    let query: String
    let queryType: QueryType
    let answer: String
    let confidence: Float           // 0.0–1.0, derived from retrieval scores
    let memoriesUsed: [MemoryReference]  // citations
    let modelUsed: ModelTier        // .haiku, .sonnet
    let latencyMs: Int
    let timestamp: Date
}

struct MemoryReference {
    let memoryID: UUID
    let tier: MemoryTier            // .episodic, .semantic, .procedural
    let relevanceScore: Float
    let excerpt: String             // brief excerpt shown as citation
    let originalDate: Date
}
```

---

## 6. What the System Can Answer

### 6.1 Factual Queries About Past Behaviour

- "When did I last talk to Sarah about the pipeline?" → Searches episodic memories for events involving "Sarah" and "pipeline", returns the most recent with date and context.
- "How many hours did I spend in meetings last week?" → Aggregates calendar data from episodic store.
- "What did I decide about the vendor contract?" → Searches for decision-related memories tagged with "vendor contract".

### 6.2 Pattern Queries

- "What's my decision pattern on hiring?" → Searches semantic memory for learned patterns about hiring decisions, cross-references episodic evidence.
- "When do I procrastinate most?" → Retrieves procedural rules about avoidance + episodic evidence of task deferral patterns.
- "What's my energy like on Mondays?" → Returns the Monday segment of the chronotype performance curve with supporting evidence.

### 6.3 Comparison Queries

- "How does this month compare to last month in terms of deep work?" → Aggregates focus session data across both periods from episodic store, synthesises comparison.
- "Am I spending more time with the product team than last quarter?" → Filters meeting data by attendees, compares volumes.

### 6.4 Relationship Queries

- "Who am I neglecting?" → Cross-references expected communication cadence (from semantic memory) with actual communication (from episodic memory), surfaces gaps.
- "Show me my interaction history with the board." → Filtered episodic retrieval for board member interactions.

### 6.5 Procedural Queries

- "What rules has the system learned about me?" → Dumps active procedural rules with confidence scores.
- "Why does the system schedule my deep work in the morning?" → Returns the procedural rule and the episodic evidence that generated it.

### 6.6 Meta Queries

- "How confident are you about my performance curve?" → Returns the curve with its confidence score and the number of data points backing it.
- "What don't you know about me yet?" → Identifies semantic memory gaps — categories with few facts or low confidence scores.

---

## 7. What the System Cannot Answer

### 7.1 Future Predictions with <60% Confidence

The system will not generate predictions when its model confidence is below 60%. Instead:

"I don't have enough data to predict that reliably. I'd need [X more weeks / more data on Y] to give you a useful answer."

### 7.2 Queries About Unobserved People

If the executive asks about someone who does not appear in their communication history:

"I haven't observed any interactions between you and [person]. I can only answer about people who appear in your email, calendar, or voice sessions."

### 7.3 Queries Requiring External Knowledge

The system does not have general knowledge. It cannot answer "What's the market cap of [company]?" or "What's the best approach to [business strategy]?" — it answers only from the executive's own observed data.

"That's a question about the world, not about your patterns. I can only answer from what I've observed about you."

### 7.4 Queries About Deleted or Expired Memories

If a memory has been archived or decayed below retrieval threshold:

"I may have had information about this, but it's outside my current memory window. My earliest accessible memories on this topic are from [date]."

### 7.5 Emotional or Therapeutic Queries

"How am I feeling?" or "Am I burned out?" — the system will present behavioural data (signal patterns consistent with stress/overload) but will not diagnose emotional states.

"I can't tell you how you're feeling. What I can tell you is that your behavioural signals this week — [specific data] — are consistent with patterns I've previously seen when you reported feeling overloaded."

---

## 8. Latency Targets

| Stage | Budget |
|---|---|
| Query classification (Haiku) | 300ms |
| Embedding generation (Jina) | 200ms |
| Vector search (Supabase pgvector) | 500ms |
| Re-ranking + dedup | 100ms |
| Response synthesis (Haiku or Sonnet) | 1500ms (Haiku) / 2000ms (Sonnet) |
| **Total (factual, Haiku)** | **< 2.5s** |
| **Total (pattern, Sonnet)** | **< 3.0s** |

### 8.1 Optimisation Strategies

- **Local embedding cache:** Cache embeddings for frequently queried terms (names, projects, recurring topics). Saves the 200ms Jina round-trip on repeat queries.
- **Pre-computed aggregations:** For common temporal queries ("last week", "this month"), pre-compute meeting hours, focus hours, email volumes daily and store as materialized views. These bypass the full retrieval pipeline.
- **Streaming response:** For Sonnet-synthesised answers, stream the response token-by-token so the executive sees text appearing within 1 second even if full generation takes 2 seconds.
- **Core memory always in context:** The executive's core memory snapshot (fixed-size, ~2000 tokens) is always loaded into the synthesis prompt. This means the system can answer basic profile questions without any retrieval at all.

---

## 9. Feedback Loop

### 9.1 Implicit Feedback

Every query and response is logged as a Layer 1 signal:

```swift
struct QuerySignal: Signal {
    let timestamp: Date
    let query: String
    let queryType: QueryType
    let memoriesRetrieved: Int
    let responseConfidence: Float
    let latencyMs: Int
    let userDismissedQuickly: Bool   // < 2 seconds viewing → probably not useful
    let userAskedFollowUp: Bool     // follow-up query within 60 seconds → incomplete answer
}
```

The reflection engine uses query signals to:
- Identify gaps in the model ("The executive asks about [topic] frequently but the system has low-confidence answers → prioritise observation of this area")
- Detect retrieval failures ("queries about [person] consistently return low-relevance results → the embedding for that person may need re-indexing")
- Learn query preferences ("this executive prefers quantified answers → increase data citation density")

### 9.2 Explicit Feedback

After each response, the interface offers a minimal feedback mechanism:
- Thumbs up (confirm useful)
- Thumbs down (mark unhelpful)
- "That's wrong" (opens a correction input — the correction is stored as high-importance episodic memory and the semantic/procedural memories that produced the wrong answer are flagged for review)

---

## 10. Connection to Memory Tiers

### 10.1 Episodic Memory

The raw event store. Every email received, meeting attended, task completed, focus session run, voice session transcribed, and app focus change is stored as an episodic memory with:
- Timestamp
- Source modality
- Raw content (or content summary for long items)
- Importance score
- Embedding vector

Episodic memory is the primary source for factual and temporal queries. It is the "what happened" layer.

### 10.2 Semantic Memory

Learned facts about the executive. Distilled from episodic memories by the reflection engine. Examples:
- "Prefers to handle board communications before 10am" (confidence: 0.78)
- "Average deep work session: 47 minutes before interruption" (confidence: 0.85)
- "Relationship with [person]: high-frequency, positive sentiment, strategic ally" (confidence: 0.72)

Semantic memory is the primary source for pattern and relationship queries. It is the "what we've learned" layer.

### 10.3 Procedural Memory

Operating rules the system has generated. Derived from confirmed patterns. Examples:
- "IF Tuesday AND after 2pm THEN avoid scheduling deep work (performance drops 35%)" (confidence: 0.81)
- "IF email from [board member] AND unread > 4 hours THEN flag as priority" (confidence: 0.68)

Procedural memory is the primary source for procedural queries and is consulted by the day plan generator. It is the "how to operate" layer.

### 10.4 Cross-Tier Queries

Most non-trivial queries touch multiple tiers. The QueryEngine assembles a unified context by:
1. Retrieving from each relevant tier independently
2. Interleaving results by score (not by tier)
3. Annotating each memory with its tier of origin so the synthesis model can reference it appropriately

This means a query like "What's my relationship with Sarah?" might return:
- Episodic: Last 5 interactions with Sarah (meetings, emails)
- Semantic: "Strong professional relationship, monthly cadence, focus on product strategy"
- Procedural: "Prioritise Sarah's emails — historically, delayed responses to her correlate with downstream project delays"

The synthesis model weaves these into a coherent answer.

---

## 11. Privacy and Boundaries

- Queries are processed entirely through the existing AI pipeline (Haiku/Sonnet). No additional data leaves the system that wouldn't already be sent during normal operation.
- Query logs are stored locally in CoreData. They sync to Supabase only if the executive has enabled cloud sync.
- The system never volunteers information the executive didn't ask for through the query interface. Proactive intelligence is delivered only through the morning session and low-frequency alerts — the query interface is pull-only.
- Raw email body text used for retrieval is never returned verbatim in responses. The system summarises and cites, it does not reproduce.

---

## 12. CoreData Entities

```swift
@objc(CDQueryLog)
class CDQueryLog: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var timestamp: Date
    @NSManaged var queryText: String
    @NSManaged var queryType: String
    @NSManaged var responseText: String
    @NSManaged var confidence: Float
    @NSManaged var latencyMs: Int16
    @NSManaged var modelUsed: String
    @NSManaged var memoriesUsedJSON: Data    // encoded [MemoryReference]
    @NSManaged var feedbackRating: Int16     // -1 (down), 0 (none), 1 (up)
    @NSManaged var correctionText: String?   // if user said "that's wrong"
    @NSManaged var followUpQueryID: UUID?    // links to the follow-up query if one occurred
}
```

---

## 13. Edge Cases

| Scenario | Behaviour |
|---|---|
| Query during morning session (voice) | Route through same pipeline, but return spoken response via morning director. Latency budget relaxed to 5s since the executive is already in conversation. |
| Rapid-fire queries (<5s apart) | Batch classification. If queries are related, treat as multi-turn conversation and maintain context across them. |
| Query about data from before system installation | "I don't have observations from before [install date]. I can only answer about the period since I started observing." |
| Ambiguous person reference ("Sarah") | If multiple "Sarah" contacts exist, ask: "I know Sarah Chen from product and Sarah Williams from the board. Which Sarah?" |
| Empty retrieval (zero relevant memories) | "I don't have any observations related to that. This might be something that happened outside my observation window, or it may not have generated a signal I could capture." |
