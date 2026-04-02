# MemGPT-Style Context Management — Implementation Spec

> Timed v1 Intelligence Layer | Last updated: 2026-04-02

---

## 1. Purpose

LLMs have finite context windows. The executive's memory store will contain thousands of memories totalling millions of tokens. This spec defines how Timed manages what goes into the LLM context window at any given moment, inspired by MemGPT's three-tier virtual context architecture (Packer et al. 2023).

The core insight from MemGPT: treat the LLM's context window like an operating system treats RAM. There's a fixed working set (core memory), a fast-access searchable store (recall memory), and a deep archive (archival memory). The system actively manages what's loaded where.

---

## 2. Three Operational Tiers

```
┌─────────────────────────────────────────────┐
│              LLM Context Window              │
│  ┌─────────────────────────────────────────┐ │
│  │         CORE MEMORY (~2000 tokens)       │ │
│  │  Always present in every LLM call.       │ │
│  │  Executive identity, active rules,       │ │
│  │  current priorities, key relationships.  │ │
│  └─────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────┐ │
│  │     WORKING CONTEXT (variable, ≤6000)    │ │
│  │  Retrieved memories for current task.    │ │
│  │  Loaded from recall/archival on demand.  │ │
│  └─────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────┐ │
│  │     SYSTEM PROMPT + INSTRUCTIONS         │ │
│  │  Model instructions, tool schemas, etc.  │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
         ↑ search ↓ write-back
┌─────────────────────────────────────────────┐
│           RECALL MEMORY (searchable)         │
│  Recent episodic memories. Indexed for fast  │
│  retrieval. Last 7-30 days of events.        │
│  Access: vector search + recency filter.     │
└─────────────────────────────────────────────┘
         ↑ search ↓ write-back
┌─────────────────────────────────────────────┐
│         ARCHIVAL MEMORY (deep store)         │
│  All semantic facts, procedural rules,       │
│  older episodic memories, patterns, insights.│
│  Access: vector search (retrieval engine).   │
└─────────────────────────────────────────────┘
```

### 2.1 Core Memory

**What it contains:**
Core memory is a structured document that is injected into every LLM call's system prompt. It is the system's persistent understanding of who this executive is.

**Sections:**

```
<core_memory>
  <identity>
    Name: [executive name]
    Role: [title, company]
    Reports to: [board/CEO/etc.]
    Direct reports: [key names and roles]
    Tenure: [time in role]
    Key context: [1-2 sentences about their situation]
  </identity>
  
  <priorities>
    [Ranked list of current priorities — max 7 items]
    [Updated by reflection engine, user corrections, morning interviews]
    1. [Priority] — [deadline if any] — [status: on-track/at-risk/blocked]
    2. ...
  </priorities>
  
  <relationships>
    [Top 5-8 key relationships with status]
    - Sarah Chen (CFO): Strong alignment. Last contact: 2 days ago. Key topic: Q3 budget.
    - Marcus Webb (Board Chair): Requires careful management. Last contact: 12 days ago. ⚠️
    ...
  </relationships>
  
  <active_rules>
    [Top 5-8 most relevant procedural rules currently active]
    - Avoid scheduling people decisions after 3pm (confidence: 0.85)
    - Surface Asia-related emails with elevated priority (confidence: 0.78)
    ...
  </active_rules>
  
  <behavioural_model>
    Chronotype: [morning/evening/intermediate]
    Peak deep work: [time range]
    Decision style: [key patterns]
    Known blind spots: [1-3 items]
    Current stress level: [low/moderate/high — inferred]
  </behavioural_model>
  
  <session_context>
    Today: [day of week, date]
    Calendar summary: [meeting count, key meetings]
    Yesterday's key events: [1-2 sentences]
    Open items requiring attention: [brief list]
  </session_context>
</core_memory>
```

**Size constraint:** ~2000 tokens maximum. This is a hard limit. Core memory competes with the system prompt and working context for the context window.

**Update frequency:** Core memory is rewritten by the nightly reflection engine every night. Intra-day updates happen only for:
- User corrections ("Actually, my top priority changed to X")
- Calendar-driven session context updates
- Relationship status changes triggered by detected events

**Storage:** Core memory is a single structured text document stored in CoreData and Supabase. Versioned — every rewrite creates a new version. Old versions are retained (they are part of the executive's model evolution history).

### 2.2 Recall Memory

**What it contains:** Recent episodic memories — the events of the last 7-30 days. These are the memories most likely to be relevant for day-to-day context.

**Access pattern:** Searched on demand when the LLM needs context beyond what's in core memory. The LLM (or the orchestrating code) issues a search query, the retrieval engine (see memory-retrieval.md) returns scored results, and they are injected into the working context.

**Scope boundaries:**
- Default window: last 7 days of episodic memories
- Extended window: last 30 days (used when 7-day results are insufficient)
- Beyond 30 days: falls through to archival memory

**Index:** Recall memories are indexed in the local USearch instance for sub-10ms retrieval. The recall index is a subset of the full index, pre-filtered by `created_at > now() - 30d AND tier = 'episodic'`.

**Eviction:** Episodic memories older than 30 days are evicted from the recall tier (their index entries in the "hot" recall index are removed). They remain in archival memory and the full index. This is a logical eviction — the data doesn't move, only the index membership changes.

### 2.3 Archival Memory

**What it contains:** Everything. All episodic memories (including those evicted from recall), all semantic facts, all procedural rules, all archived/superseded memories. The complete memory store.

**Access pattern:** Searched when recall doesn't have sufficient results, or when the query requires long-range context (monthly reviews, pattern detection, conflict resolution).

**Index:** The full USearch index, covering all memories regardless of tier or age.

**Size expectations:**
| Timeframe | Estimated memories | Index size (4KB/vector) |
|-----------|--------------------|-------------------------|
| Month 1   | 500-1,000          | ~4 MB                   |
| Month 6   | 5,000-10,000       | ~40 MB                  |
| Year 1    | 15,000-25,000      | ~100 MB                 |
| Year 3    | 50,000-80,000      | ~320 MB                 |

All comfortably within Mac memory constraints, even at Year 3 scale.

---

## 3. Context Window Budget

Timed uses Anthropic models. Context window sizes (as of 2026):

| Model | Context Window | Use Case |
|-------|---------------|----------|
| Haiku 3.5 | 200K tokens | Real-time classification, signal extraction |
| Sonnet 4 | 200K tokens | Daily pattern analysis, email understanding |
| Opus 4.6 | 200K tokens | Nightly reflection, morning briefing |

**200K tokens is abundant.** But larger context ≠ better output. Research shows that LLMs attend poorly to information in the middle of very long contexts ("lost in the middle" problem — Liu et al. 2023). Timed's context management prioritises **quality over quantity** — inject the right 8K tokens, not every available 100K token.

### 3.1 Context Window Allocation

For a typical Opus call (morning briefing or nightly reflection):

| Segment | Token Budget | Notes |
|---------|-------------|-------|
| System prompt + instructions | ~1,500 | Model behaviour, output format, constraints |
| Core memory | ~2,000 | Always present, structured |
| Working context (retrieved memories) | ~4,000-8,000 | Variable — depends on task complexity |
| Conversation/task input | ~500-2,000 | User's morning input, today's events, etc. |
| Output buffer | ~2,000-4,000 | Reserved for the model's response |
| **Total used** | **~10,000-17,500** | Fraction of available 200K |
| **Headroom** | **~182K-190K** | Available for extended retrieval if needed |

**The headroom is intentional.** We do not fill the context window. We use the minimum context needed for high-quality output. More context = more noise = worse attention allocation by the model.

### 3.2 Working Context Construction

When the system prepares an LLM call, the working context is assembled:

```swift
func assembleWorkingContext(
    task: LLMTask,
    coreMemory: CoreMemory,
    retrievalEngine: MemoryRetrievalEngine
) async throws -> WorkingContext {
    
    // 1. Determine retrieval queries from the task
    let queries = task.retrievalQueries  // e.g., morning briefing has 5-7 queries
    
    // 2. Batch retrieve from recall + archival
    let results = try await retrievalEngine.retrieveBatch(
        queries: queries.map { ($0, task.retrievalContext, task.searchTiers, task.memoryLimit) },
        minScore: 0.15
    )
    
    // 3. Deduplicate across queries (same memory may match multiple queries)
    let uniqueMemories = deduplicateByID(results.flatMap { $0 })
    
    // 4. Sort by composite score descending
    let ranked = uniqueMemories.sorted { $0.compositeScore > $1.compositeScore }
    
    // 5. Truncate to token budget
    let budgetTokens = task.workingContextBudget  // e.g., 6000
    var selected: [ScoredMemory] = []
    var tokenCount = 0
    
    for memory in ranked {
        let memTokens = estimateTokens(memory.memory.content)
        if tokenCount + memTokens > budgetTokens { break }
        selected.append(memory)
        tokenCount += memTokens
    }
    
    // 6. Re-sort selected memories by temporal order (most recent last)
    // This places the most recent events closest to the prompt — 
    // exploiting recency bias in LLM attention
    selected.sort { $0.memory.createdAt < $1.memory.createdAt }
    
    // 7. Mark accessed
    try await retrievalEngine.markAccessed(
        memoryIds: selected.map { $0.memory.id }
    )
    
    return WorkingContext(memories: selected, tokenCount: tokenCount)
}
```

**Key design decision in Step 6:** Retrieved memories are re-sorted chronologically with most recent last. This places the freshest, most relevant context immediately before the model's generation point — maximising attention (primacy/recency effect in transformer attention).

---

## 4. Context Pressure and Write-Back

### 4.1 When Context Pressure Occurs

Context pressure happens when the working context budget is insufficient for the task. Signals:
- The retrieval engine returns 50 scored memories but only 20 fit in the budget
- The task requires cross-referencing multiple time periods (30-day review needs broad context)
- A user query is broad ("How have my priorities evolved this quarter?")

### 4.2 Interrupt-Driven Write-Back

When context pressure is detected, the system uses a MemGPT-inspired interrupt mechanism:

**Step 1 — Summarise and evict.**
Before the main LLM call, run a Haiku call to summarise the memories that won't fit:

```
Summarise these {n} memories into a concise context summary of ≤500 tokens.
Preserve: key facts, names, dates, decisions, outcomes.
Discard: routine details, duplicate information, low-importance events.

{overflow_memories}
```

**Step 2 — Inject summary instead of raw memories.**
The summary replaces the overflow memories in the working context, freeing token budget.

**Step 3 — Store the summary as a new episodic memory.**
The summary itself is stored (type: `source_type: .context_summary`) so future retrieval can find it. This prevents the summarisation work from being lost.

### 4.3 Multi-Pass Retrieval

For complex tasks (nightly reflection), the system may make multiple LLM calls, each with a different working context:

```
Pass 1: Core memory + today's episodic memories → first-order observations
Pass 2: Core memory + Pass 1 output + this week's semantic facts → pattern detection  
Pass 3: Core memory + Pass 2 output + relevant procedural rules → rule evaluation
Pass 4: Core memory + all pass outputs → final synthesis and model update
```

Each pass has its own working context, assembled fresh. The output of each pass is fed as input to the next, effectively allowing the system to "page through" far more memories than fit in a single context window.

---

## 5. Morning Session Context Assembly

The morning session is the flagship interaction. Here's exactly how context is assembled:

### 5.1 Pre-Assembly (runs before the executive opens the app)

**Trigger:** 5:30 AM local time (or configurable). Background process.

**Step 1 — Refresh core memory session context:**
```
Update <session_context> block:
- Today's date, day of week
- Calendar events from Outlook (via Microsoft Graph)
- Meeting count, key meetings (attendees with >0.7 relationship importance)
- Any overnight emails flagged high-importance by the email sentinel
```

**Step 2 — Retrieve yesterday's key events:**
```swift
let yesterdayEvents = try await retrievalEngine.retrieve(
    query: "Key events and decisions from yesterday",
    context: .morningBriefing,
    tiers: [.episodic],
    limit: 15,
    minScore: 0.20
)
```

**Step 3 — Retrieve relevant patterns and rules:**
```swift
let patterns = try await retrievalEngine.retrieve(
    query: "Patterns relevant to today's schedule: {today_calendar_summary}",
    context: .morningBriefing,
    tiers: [.semantic, .procedural],
    limit: 10,
    minScore: 0.25
)
```

**Step 4 — Retrieve open threads:**
```swift
let openThreads = try await retrievalEngine.retrieve(
    query: "Unresolved items, pending decisions, follow-ups due",
    context: .morningBriefing,
    tiers: [.episodic, .semantic],
    limit: 10,
    minScore: 0.20
)
```

**Step 5 — Retrieve relationship maintenance alerts:**
```swift
// Find key relationships where last_contact exceeds their cadence threshold
let staleRelationships = coreMemory.relationships
    .filter { $0.daysSinceContact > $0.expectedCadenceDays * 1.5 }
```

### 5.2 Morning Opus Call

All retrieved context is assembled into a single Opus call:

```
<system>
You are the intelligence engine for {executive_name}'s cognitive operating system.
You deliver a morning briefing that demonstrates deep understanding of this person.
You are not a task list. You are a cognitive briefing from a system that has spent 
the night thinking about them.

{model_instructions}
</system>

<core_memory>
{full_core_memory_document}
</core_memory>

<yesterday_events>
{formatted_yesterday_events}
</yesterday_events>

<active_patterns>
{formatted_patterns_and_rules}
</active_patterns>

<open_threads>
{formatted_open_threads}
</open_threads>

<relationship_alerts>
{formatted_stale_relationships}
</relationship_alerts>

<today_calendar>
{formatted_calendar}
</today_calendar>

<user_input>
{executive_morning_voice_input — transcribed}
</user_input>

Generate the morning cognitive briefing. Structure:
1. Open with the most important pattern or insight — not "good morning"
2. Today's cognitive landscape: what demands deep thinking vs what's routine
3. Named patterns detected: state them explicitly with evidence
4. Avoidance check: anything being deferred that shouldn't be?
5. Relationship alerts if any
6. Today's plan: tasks ranked by intelligence, not just urgency
7. One question for the executive that will make them think
```

**Token budget for this call:**
- System prompt: ~500
- Core memory: ~2,000
- Working context (all retrieved memories): ~5,000-7,000
- Calendar + user input: ~1,000
- Output: ~2,000-3,000
- **Total: ~10,500-13,500 tokens** — well within limits

### 5.3 Post-Morning Updates

After the morning session:
1. The executive's voice input is stored as an episodic memory.
2. Any corrections the executive makes ("No, my priority today is X, not Y") trigger core memory updates.
3. The generated briefing is stored as a special episodic memory (`source_type: .morning_briefing`) for future reference.
4. Mark all retrieved memories as accessed (updates `last_accessed_at` for recency scoring).

---

## 6. Nightly Reflection Context Assembly

The nightly reflection is a multi-pass process with distinct context needs per pass.

### 6.1 Pass Structure

| Pass | Input Context | Output | Model |
|------|---------------|--------|-------|
| 1: Event Review | Core memory + all today's episodic memories | First-order observations: what happened, what's notable | Opus |
| 2: Pattern Detection | Core memory + Pass 1 output + last 7 days' semantic facts | Second-order patterns: what recurs, what's changing | Opus |
| 3: Model Update | Core memory + Pass 2 output + current full semantic model | Updated semantic facts, new facts, conflicts detected | Opus |
| 4: Rule Generation | Core memory + Pass 3 output + current procedural rules | New/modified procedural rules, deactivation recommendations | Opus |
| 5: Core Memory Rewrite | All pass outputs + current core memory | Updated core memory document for tomorrow | Opus |

**Total nightly token budget:** ~50,000-80,000 tokens across all passes. At Opus pricing, this is the cost of intelligence. No cap.

### 6.2 Context Assembly Per Pass

Each pass follows the same assembly pattern:
1. Core memory (always present — 2,000 tokens)
2. Previous pass output (variable — 1,000-3,000 tokens)
3. Retrieved memories specific to this pass's task (3,000-6,000 tokens)
4. Pass-specific instructions (500-1,000 tokens)

The multi-pass approach is critical: it allows the system to process far more memory than fits in a single context window, with each pass distilling and focusing the information.

---

## 7. Core Memory Update Protocol

Core memory is the most critical document in the system. Updates must be controlled.

### 7.1 Who Can Update Core Memory

| Source | Update Scope | Frequency |
|--------|-------------|-----------|
| Nightly reflection engine (Opus) | Full rewrite of all sections | Nightly |
| User corrections | `<priorities>`, `<relationships>`, `<active_rules>` | On demand |
| Calendar sync | `<session_context>` only | Morning pre-assembly |
| Email sentinel | `<session_context>` open items only | When high-importance email arrives |

**No other subsystem may modify core memory.** Haiku agents, background observers, and the retrieval engine are read-only consumers.

### 7.2 Rewrite Constraints

The nightly rewrite prompt includes explicit constraints:

```
Rewrite the executive's core memory document based on tonight's reflection.

CONSTRAINTS:
- Total size must not exceed 2000 tokens
- <identity> section: change only if the executive's role/situation has changed
- <priorities> section: maximum 7 items, ranked
- <relationships> section: maximum 8 people, include last-contact date
- <active_rules> section: maximum 8 rules, highest confidence first
- <behavioural_model> section: update only with evidence from this week
- <session_context> section: leave blank (filled at morning pre-assembly)
- NEVER remove information without logging what was removed and why
```

### 7.3 Version History

Every core memory version is stored:

```swift
struct CoreMemoryVersion {
    let id: UUID
    let version: Int
    let content: String
    let createdAt: Date
    let createdBy: CoreMemorySource  // .nightlyReflection | .userCorrection | .calendarSync
    let changeLog: String            // What changed and why
    let previousVersion: Int
}
```

This enables:
- Tracking how the executive's model evolves over time
- Rollback if a rewrite was wrong
- The monthly "model evolution report" (what changed in the last 30 versions)

---

## 8. Offline Behaviour

Timed must work fully offline. Context management implications:

| Component | Online Behaviour | Offline Behaviour |
|-----------|-----------------|-------------------|
| Core memory | Synced to Supabase after every update | Local CoreData only; syncs on reconnection |
| Recall retrieval | USearch local index (primary) | USearch local index (same — no degradation) |
| Archival retrieval | USearch local index (primary) | USearch local index (same — no degradation) |
| Embedding generation | Jina API or local Core ML model | Local Core ML model (mandatory offline path) |
| LLM calls (Opus/Sonnet/Haiku) | Anthropic API | **Degraded mode**: queue the reflection, deliver cached last-known briefing, flag that nightly reflection was skipped |

**Critical offline requirement:** The Jina embedding model must have a Core ML conversion for local inference. Without local embeddings, the retrieval engine cannot function offline. This is a P0 requirement for the embedding pipeline.

---

## 9. Data Model

```swift
struct CoreMemory {
    let version: Int
    let content: String               // The full structured document
    let identity: IdentityBlock
    let priorities: [PriorityItem]
    let relationships: [RelationshipItem]
    let activeRules: [RuleReference]
    let behaviouralModel: BehaviouralModel
    var sessionContext: SessionContext  // Mutable — updated intra-day
    let lastRewrittenAt: Date
    let lastRewrittenBy: CoreMemorySource
}

struct SessionContext {
    var date: Date
    var calendarSummary: String
    var meetingCount: Int
    var keyMeetings: [MeetingSummary]
    var overnightAlerts: [String]
    var openItems: [String]
}

enum CoreMemorySource: String {
    case nightlyReflection
    case userCorrection
    case calendarSync
    case emailSentinel
}
```

---

## 10. Testing Strategy

- **Context budget tests:** Verify that assembled context never exceeds the declared token budget for any task type. Use tiktoken-equivalent for accurate counting.
- **Core memory size enforcement:** Write a test that fails if any core memory version exceeds 2,000 tokens (with 5% tolerance for edge cases).
- **Morning assembly latency:** The full morning pre-assembly (4 retrieval calls + context formatting) must complete in <2 seconds. Benchmark regularly.
- **Multi-pass coherence:** For nightly reflection, verify that each pass's output is coherent with the previous pass's output. No contradictions between passes.
- **Offline mode:** Disable network, run full morning assembly and verify it completes with local resources only (except the LLM call, which queues).
- **Version history integrity:** Verify that every core memory update creates a new version and the change log accurately describes what changed.
- **Working context ordering:** Verify that memories in working context are ordered chronologically with most recent last (recency-optimised attention position).
