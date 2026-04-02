# Consistency Fixes Log

> Generated: 2026-04-02
> Scope: All 50 docs in /Users/integrale/timed-docs/staging/

---

### architecture.md
- **What changed:** Nightly reflection trigger time changed from 22:00 to 2:00 AM in the Data Flow diagram and Nightly Path section.
- **Why:** Contradiction with reflection-architecture.md (2:00 AM), memory-promotion.md (2:00 AM), morning-voice.md (2:00-4:00 AM completion), and build-sequence.md (2:00 AM). The 2:00 AM time is used by 4 of 5 docs and aligns with the design rationale in reflection-architecture.md (runs while the executive sleeps, before 6 AM morning session). 22:00 is too early -- the executive may still be working.

### architecture.md
- **What changed:** Added note clarifying that `SignalAgent` is the agent lifecycle protocol and `SignalWritePort` is the write interface protocol -- they serve different purposes and both are correct.
- **Why:** build-sequence.md references `SignalEmitting` as the L1->L2 boundary protocol, but architecture.md defines `SignalWritePort` for this purpose and `SignalAgent` for agent lifecycle. Standardised: `SignalWritePort` is the write interface, `SignalAgent` is the agent contract.

### build-sequence.md
- **What changed:** Replaced all references to `SignalEmitting` with `SignalWritePort` for the L1->L2 write boundary protocol. Kept `SignalAgent` for agent lifecycle.
- **Why:** architecture.md and claude-md.md consistently use `SignalWritePort` for this boundary. `SignalEmitting` was a naming variant used only in build-sequence.md and claude-code-config.md.

### claude-code-config.md
- **What changed:** Replaced `SignalEmitting` with `SignalWritePort` in the layer boundary table.
- **Why:** Consistency with architecture.md, claude-md.md, and the corrected build-sequence.md.

### build-sequence.md
- **What changed:** Reflection pipeline Stage 1-2 model changed from Sonnet to Opus. All 6 stages now use Opus.
- **Why:** reflection-architecture.md, reflection-prompts.md, and first-order-patterns.md all specify Opus for every stage. build-sequence.md was the sole outlier claiming Stages 1-2 use Sonnet. The design rationale in reflection-architecture.md Section 2.2 explicitly states "Haiku or Sonnet cannot perform second-order synthesis with the depth required" and "No cost cap on intelligence."

### build-sequence.md
- **What changed:** Core memory buffer size changed from 20 entries to 50 entries.
- **Why:** data-models.md defines CDCoreMemoryEntry with "Hard cap: 50 entries" and ~4K tokens. build-sequence.md said "20 entries max, ~4,000 tokens". 50 entries at ~80 tokens each = ~4K tokens, so the token budget is consistent. The entry count was the error.

### episodic-memory.md
- **What changed:** Renamed `EpisodeSource` enum to `SignalSource` and updated case values to match the canonical `SignalSource` enum defined in data-models.md.
- **Why:** data-models.md defines `SignalSource` as the canonical enum with cases {email, calendar, voice, appFocus, task, system, userCorrection}. episodic-memory.md defined a separate `EpisodeSource` enum with different case naming (e.g., `taskSignal` vs `task`). The Episode struct's `source` field now uses `SignalSource` for cross-doc consistency.

### reflection-architecture.md
- **What changed:** Renamed `MemorySource` to `SignalSource` in the EpisodicMemory struct used within the reflection architecture.
- **Why:** `MemorySource` with values {.email, .calendar, .task, .focus, .voice, .behaviour, .system} was only used in reflection-architecture.md. The canonical enum is `SignalSource` from data-models.md. Values aligned: .focus -> .appFocus, .behaviour -> .system (system observations cover behavioural signals).

### memory-promotion.md
- **What changed:** Renamed `MemoryStatus` to `PromotionStatus` to disambiguate from the per-tier status enums, and added a note clarifying its relationship to `FactStatus` (semantic-memory.md) and `RuleStatus` (procedural-memory.md).
- **Why:** memory-promotion.md defined `MemoryStatus` with {active, candidate, stale, archived}. semantic-memory.md defines `FactStatus` with {active, weakened, contradicted, deprecated}. procedural-memory.md defines `RuleStatus` with {proposed, active, suspended, deprecated}. These are deliberately different per tier -- the promotion spec's `MemoryStatus` is a cross-tier tracking field for the promotion system, distinct from the per-tier status enums. Renaming to `PromotionStatus` eliminates the naming collision.

### data-models.md
- **What changed:** Added clarifying note on the CDRule / CDProceduralMemory relationship, stating CDRule is a planning-engine-facing projection and CDProceduralMemory is the authoritative memory-tier entity.
- **Why:** Both entities exist in data-models.md with overlapping fields (ruleText, ruleKey, status, confidenceScore, activationCount). The existing inline comment partially explains this but the note was buried. Made the architectural relationship explicit: CDProceduralMemory is Layer 2, CDRule is a Layer 4 projection derived from it.

### build-state.md
- **What changed:** Nightly reflection trigger time in ReflectionScheduler entry changed from 22:00 to 02:00.
- **Why:** Consistency with reflection-architecture.md (2:00 AM default) and the resolved architecture.md.

### architecture.md
- **What changed:** Nightly path estimated cost updated from "$0.30-$1.50" to "$1.50-$5.00" to match reflection-architecture.md.
- **Why:** reflection-architecture.md and reflection-prompts.md both estimate $2.60-$3.95 per nightly run. architecture.md's $0.30-$1.50 was based on an earlier 2-pass design (fewer stages). The 6-stage pipeline costs more.

### build-sequence.md
- **What changed:** Reflection pipeline Stage 1 description updated: summary is done via Opus grouping, not a separate Sonnet call.
- **Why:** reflection-prompts.md Stage 1 prompt is explicitly an Opus prompt for episodic summarisation. build-sequence.md incorrectly described it as "Summarises each group via Sonnet."

### architecture.md
- **What changed:** Updated nightly path description from "2 Opus calls" to "6-stage Opus pipeline" to match the 6-stage architecture in reflection-architecture.md.
- **Why:** architecture.md described the nightly path as 2 Opus calls (observations + synthesis). reflection-architecture.md, reflection-prompts.md, and build-sequence.md all describe a 6-stage pipeline. The 2-call description was from an earlier draft.

### memory-retrieval.md
- **What changed:** Added `Sendable` conformance to `MemoryTier` enum to match data-models.md definition. Added `CaseIterable` and `Codable`.
- **Why:** data-models.md defines `MemoryTier` as `String, Codable, CaseIterable, Sendable`. memory-retrieval.md defined it as just `String`. The protocols should match since this is the same type.

### cognitive-load-model.md
- **What changed:** Corrected reference from "reflection Stage 2" to "reflection Stage 2 (First-Order Pattern Extraction)" for clarity.
- **Why:** The reference to "Stage 2" was ambiguous without naming the stage. Other docs (chronotype-model.md, relationship-scorer.md) already include the stage name.

### signal-task-interaction.md
- **What changed:** No changes needed -- already uses `TimedTask` entity name consistently.
- **Why:** Verified against data-models.md CDTask entity. The doc correctly uses `TimedTask` as the Swift-facing name (CDTask is the CoreData managed object subclass, TimedTask is the public DTO).

### semantic-memory.md
- **What changed:** Added reference to the canonical `MemoryRecord` from memory-retrieval.md in the integration section, noting that `SemanticFact` is the detailed tier-specific schema while `MemoryRecord` is the retrieval-engine-facing abstraction.
- **Why:** memory-retrieval.md defines a generic `MemoryRecord` with a `tier` field. semantic-memory.md defines `SemanticFact` with a richer schema. These are complementary, not conflicting, but the relationship was undocumented.

### procedural-memory.md
- **What changed:** Added same `MemoryRecord` relationship note as semantic-memory.md.
- **Why:** Same reason -- `ProceduralRule` is the tier-specific schema, `MemoryRecord` is the retrieval abstraction.

### memgpt-context.md
- **What changed:** Updated core memory buffer reference from "~2000 tokens" for core memory to note consistency with the 50-entry cap from data-models.md (50 entries x ~80 tokens = ~4,000 tokens for the full buffer, ~2,000 tokens for the serialised summary injected into prompts).
- **Why:** memgpt-context.md says core memory is ~2,000 tokens. data-models.md says 50 entries at 500 chars max each. These are reconcilable: the 2,000 token limit is for the serialised XML-like core memory document injected into prompts, while the 50 entries include structured fields that compress. Added clarifying note.

### background-agents.md
- **What changed:** Verified `SignalAgent` protocol definition matches architecture.md exactly.
- **Why:** background-agents.md redefines the `SignalAgent` protocol. Confirmed the interface matches: `agentId`, `startObserving()`, `stopObserving()`, `isHealthy`, `lastSignalAt` -- all present in both.
