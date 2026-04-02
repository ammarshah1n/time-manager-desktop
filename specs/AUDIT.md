# Timed Spec Library Audit Report

> Audited: 50 documents in `/Users/integrale/timed-docs/staging/`
> Auditor: Claude Opus 4.6 (1M context)
> Date: 2026-04-02

---

## 1. Contradictions

### C-01: Reflection engine stage count disagrees across docs

- **reflection-architecture.md** Section 5: Defines a **4-stage** pipeline (Episodic Summarisation, First-Order Pattern Extraction, Second-Order Synthesis, Rule Generation) plus a 5th deterministic stage (Memory Updates).
- **reflection-prompts.md** Section 1: States a **6-stage pipeline** (`episodic_summarisation | first_order_extraction | second_order_synthesis | rule_generation | model_update | morning_session_script`).
- **build-sequence.md** Phase 4: References a **6-stage pipeline** (Stages 1-6).
- **build-state.md** Layer 3: References a "4-pass Opus reflection" for NightlyReflectionEngine.
- **memgpt-context.md** Section 6.1: Lists a **5-pass** nightly structure (Event Review, Pattern Detection, Model Update, Rule Generation, Core Memory Rewrite).

**Impact:** A developer cannot know whether to build 4, 5, or 6 stages. The stages themselves differ in naming and ordering across docs.

### C-02: Reflection stage model assignments conflict

- **reflection-architecture.md** Section 5: All stages use **Opus**. Stage 1 explicitly says "Model: Opus."
- **build-sequence.md** Phase 4: Stage 1 uses **Sonnet** for episodic summarisation. Stage 2 uses **Sonnet** for first-order extraction. Only Stages 3-4 use **Opus**.

**Impact:** Substantial cost and quality difference. The docs must agree on which model handles each stage.

### C-03: Memory tier naming and entity naming inconsistencies

- **data-models.md**: Uses CoreData entity names `CDEpisodicMemory`, `CDSemanticMemory`, `CDProceduralMemory`. Semantic memory uses `key`/`value` fields, a `SemanticCategory` enum, and `isActive` boolean.
- **episodic-memory.md**: Defines a completely different schema — the struct is called `Episode` (not `EpisodicMemory`), uses fields like `source: EpisodeSource`, `eventType`, `entityId`, `entityType`, and stores data in Supabase table `episodes`.
- **semantic-memory.md**: Defines `SemanticFact` with fields `factType: FactType`, `category: FactCategory`, `subject`, `content`, `status: FactStatus`. The Supabase table is `semantic_facts`. This does not match `CDSemanticMemory` in data-models.md which uses `key`/`value`/`category: SemanticCategory`/`isActive`.
- **procedural-memory.md**: Defines `ProceduralRule` with `triggerConditions: [TriggerCondition]`, `action: RuleAction`, `status: RuleStatus` (proposed/active/suspended/deprecated). The CoreData entity in data-models.md is `CDProceduralMemory` with `conditionJson`/`actionJson`/`status` (different RuleStatus values) and `sourcePattern: CDPattern`.
- **memory-promotion.md** Section 9: Introduces a `MemoryRecord` extension with `status: MemoryStatus` enum using `.active | .candidate | .stale | .archived`, plus ALTER TABLE on a `memories` table that does not exist in any other doc's schema.

**Impact:** A developer would not know which schema to implement. The per-tier memory specs define one model; data-models.md defines a different one. memory-promotion.md introduces a third unified `memories` table. These are irreconcilable without a decision.

### C-04: Core memory buffer size conflict

- **data-models.md**: CoreMemoryEntry buffer is **50 entries, ~4K tokens**.
- **memgpt-context.md** Section 2.1: Core memory is **~2000 tokens maximum** (hard limit).
- **build-sequence.md** Phase 3: Core memory is **20 entries max, ~4,000 tokens**.

**Impact:** 20 vs 50 entries, 2K vs 4K tokens. These produce fundamentally different context management behaviour.

### C-05: Memory retrieval scoring formula conflicts

- **data-models.md** `CDEpisodicMemory.retrievalScore()`: `recency = 1.0 / (1.0 + hoursSinceAccess * 0.01)`. Multiplicative: `recency * importance * relevance`.
- **episodic-memory.md** Section 9.1.3: `recencyDecay = exp(-0.01 * hours)`. Additive weighted: `0.3 * recency + 0.2 * importance + 0.5 * similarity`.
- **memory-retrieval.md** Section 2.1: `recency = 0.995 ^ hours_since_access`. Configurable weights (default 0.2, 0.3, 0.5).
- **build-sequence.md** Phase 3: `recency = 0.995 ^ hours_since_access`. Weights `(0.2, 0.3, 0.5)`.
- **claude-skills.md** (memory-layer skill): `recency = 0.995 ^ hours_since_access`. Weights `(0.2, 0.3, 0.5)`.

**Impact:** Three different recency functions and two different combination methods (multiplicative vs additive). A developer implementing retrieval will get different rankings depending on which doc they follow.

### C-06: EMA alpha value conflicts

- **ema-estimation.md**: Alpha = **0.25** (recommended, fixed for v1).
- **signal-task-interaction.md** Section 5.2: Alpha = **0.3** ("responsive to recent data, smoothed over ~7 completions").
- **day-plan-generation.md** Section 2.2: Alpha = **0.3** (default).
- **focus-timer.md** Section 7.1: Alpha = **0.3** (default, learnable per category).
- **cold-start.md** Section 6.3: Uses **0.5** (day 1), **0.4** (days 2-7), **0.35** (days 8-14), **0.3** (day 15+).

**Impact:** The dedicated EMA spec says 0.25; most consumer docs say 0.3. Cold-start uses a schedule that ends at 0.3, never reaching 0.25.

### C-07: Thompson sampling category taxonomy conflicts

- **thompson-sampling.md**: `TaskCategory` enum with 20 categories (strategicPlanning, creativeWork, analysis, oneOnOne, emailBatch, recovery, etc.).
- **cold-start.md**: Archetype priors use a 6-category taxonomy: `.strategic`, `.operational`, `.relational`, `.administrative`, `.creative`, `.deepAnalysis`.

**Impact:** The cold-start priors cannot be applied to the 20-category Thompson model. The mapping between the two taxonomies is undefined.

### C-08: Nightly reflection trigger time conflicts

- **reflection-architecture.md** Section 3.1: Default **2:00 AM** local time.
- **build-state.md** Layer 3: ReflectionScheduler triggers at **22:00** (nightly) and Sunday 03:00 (weekly).
- **architecture.md** Data Flow: Nightly reflection at **22:00**.
- **memgpt-context.md** Section 5.1: Pre-assembly runs at **5:30 AM**.
- **memory-promotion.md** Section 7.1: Nightly consolidation at **2:00 AM**.

**Impact:** 22:00 vs 02:00 is a 4-hour difference that affects the morning session pipeline. If reflection runs at 22:00, morning session prep at 05:30 has ample time. If reflection runs at 02:00, the window is tighter.

### C-09: Architecture protocol names disagree with CLAUDE.md template

- **architecture.md**: Defines `SignalWritePort`, `EpisodicMemoryReadPort`, `MemoryWritePort`, `EmbeddingPort`, `PatternQueryPort`, `UserProfilePort`, `ReflectionEngine`, `MorningDirector`, `AlertEngine`, `SignalAgent`, `ImportanceClassifier`.
- **claude-md.md** (CLAUDE.md template): References `SignalEmitting`, `MemoryStoring`, `MemoryQuerying`, `MemoryWriting`, `IntelligencePayload`, `UserInteractionSignal`, `ReflectionRunning`, `IntelligenceDelivering`.
- **claude-code-config.md**: References `SignalEmitting`, `MemoryStoring`, `MemoryQuerying`, `MemoryWriting`.
- **build-sequence.md** Phase 1: References `SignalEmitting`, `MemoryStoring`, `MemoryQuerying`, `ReflectionRunning`, `IntelligenceDelivering`.

**Impact:** Two completely different protocol naming schemes exist. architecture.md (the definitive architecture spec) uses one set; the CLAUDE.md template and build docs use another.

### C-10: Supabase project reference conflicts

- **claude-md.md**: Supabase project `fpmjuufefhtlwbfinxlx`.
- **coredata-migration.md**: Supabase project `fpmjuufefhtlwbfinxlx`.
- **build-state.md**: References `SupabaseClient.swift` with 12 operations but no project ref.

This needs reconciliation with the user's actual Supabase instance.

### C-11: Email polling interval conflicts

- **graph-integration.md** Section 7.3: Mail polling every **5 min** foreground.
- **signal-email.md** Section 2.3: Sync every **5 minutes** via TimedScheduler.
- **background-agents.md**: EmailSentinelAgent polls every **15 minutes**.
- **build-sequence.md** Phase 2: Email agent polls every **60 seconds**.

**Impact:** 60s vs 5min vs 15min produce very different API usage patterns and battery impact.

### C-12: App focus minimum session threshold conflicts

- **signal-app-focus.md** Section 3.3: Minimum **2 seconds**.
- **background-agents.md** BehaviourObserverAgent: Ignores sessions **< 5 seconds**.

### C-13: Pattern lifecycle status names conflict

- **first-order-patterns.md**: `emerging | developing | established | confirmed | fading | deprecated`.
- **build-sequence.md** Phase 4: `emerging | confirmed | fading | archived`.
- **architectural-decisions.md** ADR-007: `testing | active` for procedural rules.
- **procedural-memory.md**: `proposed | active | suspended | deprecated` for rules.

### C-14: Semantic memory confidence decay rate conflicts

- **semantic-memory.md** Section 4.3: Decay rate depends on fact type (0.002-0.005 per day, with 14-day grace period).
- **build-sequence.md** Phase 3: `confidence -= 0.01 per week without reinforcement (floor: 0.1)`.
- **claude-skills.md** memory-layer skill: `min(0.1, (1.0 - current) * 0.2)` for reinforcement; `-0.01 per week` for decay.
- **architectural-decisions.md** ADR-007: Deactivation at `confidence < 0.3 after contradictionCount >= 3`.
- **data-models.md**: Deactivation threshold at `confidence < 0.3 after contradictionCount >= 3`.
- **semantic-memory.md**: Weakened status transition at `confidence < 0.25`.

**Impact:** Decay rate (0.01/week vs 0.002-0.005/day), floor (0.05 vs 0.1), and deactivation threshold (0.25 vs 0.3) all disagree.

---

## 2. Gaps

### G-01: `PrivacyAbstractor` referenced everywhere, never specified

- **claude-md.md**, **claude-code-config.md**, **claude-skills.md** all mandate that every LLM API call passes through `PrivacyAbstractor.sanitise()`. No spec defines this component: what it sanitises, how it tokenises names, how it restores them, what NER model it uses, or how it handles edge cases.
- **privacy-spec.md** describes the three-tier data classification and the `DeviceOnlyData` marker protocol, but does not spec the sanitisation pipeline itself.

### G-02: `Pattern` / `CDPattern` entity missing from data-models.md

- **data-models.md** Entity Relationship Overview references `Pattern` extensively (Pattern -> Rule, EpisodicMemory M:M Pattern). The entity relationship diagram shows `Pattern ──1:M──► Rule`. But there is no `CDPattern` entity definition anywhere in data-models.md. The entity is simply missing.

### G-03: No spec for `SignalBus` / signal routing

- **build-sequence.md** Phase 1 mentions a `SignalBus` actor. **architecture.md** defines `SignalWritePort`. Multiple docs reference signals flowing from Layer 1 to Layer 2. But no spec document defines the signal bus: how signals are routed, buffered, prioritised, or how back-pressure works.

### G-04: No spec for the AI Router / `ClaudeClient`

- **build-sequence.md** Phase 1 mentions `ClaudeClient` actor with `.classify`, `.analyse`, `.reflect` entry points.
- **build-state.md** lists `AIModelRouter` as NOT STARTED.
- No spec document defines: how model selection works, how rate limits are handled, how the privacy pipeline integrates, how fallback works, or the API client's retry logic.

### G-05: No `UserProfile` / `CDUserProfile` entity definition

- **data-models.md** mentions `UserProfile ──1:1──► (singleton per workspace)` in the ER diagram but never defines the entity or its attributes.
- Multiple docs reference user profile data (chronotype, energy curve, archetype) without a canonical schema.

### G-06: Episodic memory local storage mechanism undefined

- **episodic-memory.md** Section 5.2: States episodes are stored locally as date-partitioned JSON files in `~/Library/Application Support/Timed/episodes/`. Also references a `DataStore` with specific method signatures.
- **data-models.md**: Defines `CDEpisodicMemory` as a CoreData entity.
- **coredata-migration.md**: Describes migrating from JSON to CoreData.
- The gap: no doc clearly states which storage mechanism is canonical for v1. The episodic memory spec describes JSON files; data-models describes CoreData. These are mutually exclusive implementations.

### G-07: `BehaviourRule` to `ProceduralRule` migration path undefined

- **procedural-memory.md** Section 10 describes bridging from the existing `BehaviourRule` struct to the new `ProceduralRule` system via `toEngineBehaviourRule()`.
- But the existing `PlanningEngine.swift` `BehaviourRule` struct and the new `ProceduralRule` have different schemas. The migration strategy from one to the other during development is not specified.

### G-08: Embedding offline fallback undefined

- **memgpt-context.md** Section 8: States "The Jina embedding model must have a Core ML conversion for local inference" as a P0 requirement.
- No spec defines how to build, package, or use this Core ML model. No spec addresses what happens if the Jina model cannot be converted to Core ML.

### G-09: `MLModelState` entity referenced but never defined

- **data-models.md** ER diagram mentions `MLModelState (singleton per model type)` in Layer 4. No entity definition exists.

### G-10: `DriftDetectorAgent` in background-agents.md not in any other doc

- **background-agents.md** defines a `DriftDetectorAgent` that runs every 2 hours using Haiku for anomaly detection.
- No other doc references this agent. It is not in build-sequence.md, build-state.md, or the architecture layer definitions.

### G-11: No spec for how the morning session script is cached and delivered

- **morning-voice.md** Section 3.3 says the session is pre-generated overnight and cached as `morning_session_cache` (local JSON).
- **morning-session.md** Section 9 shows the data flow but does not define the caching mechanism.
- No spec defines the cache format, invalidation logic, or how the pre-generated script maps to the voice delivery phases.

---

## 3. Vagueness

### V-01: memory-promotion.md Section 3.2 — Semantic fact generation model

States "Generator: Haiku 3.5" for semantic fact generation during promotion. But **semantic-memory.md** Section 3.3 says "Fact content is generated by the reflection engine (Opus at max effort)." The promotion spec also describes a prompt template that could be either, with no clear indication of when Haiku vs Opus is used for this task.

### V-02: avoidance-detector.md Signal 2 — Draft-then-delete detection

The draft-delete signal depends on detecting draft creation and deletion events from Microsoft Graph. But **graph-integration.md** and **signal-email.md** only spec read access to messages (not drafts). The Graph `Mail.Read` scope provides access to drafts in the Drafts folder, but the delta sync in signal-email.md filters `isDraft eq false`. No mechanism exists to observe draft lifecycle events.

### V-03: cognitive-load-model.md Signal 1 — Email first-opened tracking

The spec says "Track via Graph read receipt or app open" for `firstOpenedAt`. But Timed has read-only Graph access and does not control Outlook. There is no mechanism to know when the executive opens an email in Outlook. The Graph `isRead` boolean is the only signal, and it doesn't include a timestamp.

### V-04: chronotype-model.md Section 4.4 — Bayesian update formula

The aggregation formula `alpha_new = alpha_old * decay + score * weight` is not a standard Bayesian update. It is ad hoc. The spec does not define what `weight` is, how `score` is normalised to [0,1], or how this interacts with the Beta distribution interpretation claimed in the same section.

### V-05: reflection-prompts.md — Incomplete (Stage 4-6 prompts missing)

The document defines prompts for Stages 1, 2, and 3 in detail (with system prompts, injection formats, output schemas, and few-shot examples). Stages 4, 5, and 6 are not defined. The doc ends mid-Stage 3.

### V-06: cold-start.md archetype category taxonomy is disconnected

The 5 archetypes use category keys like `.strategic`, `.operational`, `.relational`, `.creative`, `.deepAnalysis` — but there is no mapping to the 20-category `TaskCategory` enum in thompson-sampling.md or the 4-type taxonomy in chronotype-model.md (`analytical`, `creative`, `interpersonal`, `administrative`). Three different taxonomies exist with no translation layer.

### V-07: coredata-migration.md — No CoreData relationships in v1.0

The spec explicitly says "No CoreData relationships in v1.0. Cross-references use UUID foreign keys." But **data-models.md** defines extensive CoreData relationships (1:1, 1:M, M:M with join entities). These two docs are describing different schemas.

---

## 4. Innovation Opportunities

### I-01: Replace brute-force vector search with HNSW index from day 1

Multiple docs (architectural-decisions.md ADR-004, build-sequence.md Phase 3) defer vector indexing to Phase 6 with USearch as a fallback. Apple's Accelerate framework for brute-force cosine similarity will degrade at scale. Given that the `usearch` Swift package provides in-process HNSW indexing with <1ms query at 100K vectors and <5MB memory overhead, integrating it from Phase 3 would eliminate the Phase 6 rework and prevent performance cliffs during the critical first-user period.

### I-02: Use Swift structured concurrency `AsyncStream` for signal pipeline

The current design routes signals through a `SignalBus` actor with buffered writes. Swift's `AsyncStream` would provide a cleaner reactive pipeline: each agent produces an `AsyncStream<Signal>`, and the memory store consumes from a merged stream. This eliminates the custom buffer management described in background-agents.md's `MemoryWriter` actor and aligns with modern Swift concurrency patterns.

### I-03: Core ML embedding model for true offline capability

The P0 requirement for offline embeddings (memgpt-context.md Section 8) could be satisfied by Apple's `NLEmbedding` framework (available macOS 13+) as an immediate fallback, with a distilled Jina model via `coremltools` for production quality. `NLEmbedding` provides 512-dim embeddings on-device today, which could serve as a bridge until a 1024-dim Core ML model is ready.

### I-04: SwiftData `@ModelActor` for Phase 6 migration readiness

While CoreData is the correct choice for v1 (ADR-001), the repository pattern could be designed with a `ModelActor`-compatible interface so that a future SwiftData migration only requires swapping the storage backend. This costs nothing today and saves days later.

---

## 5. Verdict Per Document

| File | Verdict |
|------|---------|
| architecture.md | ⚠️ Protocol names must be reconciled with claude-md.md and build docs. Layer 3 protocol definitions reference `PatternDTO`, `ProceduralRuleDTO` — neither is defined. |
| architectural-decisions.md | ✅ Ready to build from. Clear decisions with reversal costs. |
| audit-prompt.md | ✅ Meta-document. Not a build artifact. |
| avoidance-detector.md | ⚠️ Draft-delete signal (Signal 2) depends on Graph draft observation not supported by the email spec. Uses `@Model` (SwiftData) for CoreData entities — contradicts ADR-001. |
| background-agents.md | ⚠️ DriftDetectorAgent is orphaned — not referenced elsewhere. Email polling at 15min conflicts with signal-email.md (5min) and build-sequence.md (60s). App focus minimum session threshold (5s) conflicts with signal-app-focus.md (2s). XPC for reflection engine contradicts build-sequence which keeps everything in-process. |
| build-sequence.md | ⚠️ Reflection stages use Sonnet for Stages 1-2, contradicting reflection-architecture.md (all Opus). Protocol names use the CLAUDE.md set, not the architecture.md set. |
| build-state.md | ⚠️ References "4-pass Opus reflection" (should be 4-6 stages). AppFocusSignalAgent listed as Phase 3 but build-sequence.md has it in Phase 2. Reflection scheduled at 22:00, contradicting reflection-architecture.md (02:00). |
| chronotype-model.md | ⚠️ Bayesian update formula (Section 4.4) is non-standard and incompletely specified. Uses `@Model` (SwiftData) — contradicts ADR-001. Task type taxonomy (4 types) is disconnected from Thompson sampling taxonomy (20 types). |
| claude-code-config.md | ⚠️ CLAUDE.md template uses different protocol names from architecture.md. Directory structure differs between this doc and the CLAUDE.md template within it (`Sources/Timed/Layer1/` vs `Sources/Core/Services/Agents/`). |
| claude-md.md | ⚠️ Protocol names, directory structure, and file naming conventions disagree with architecture.md. Two different file structures coexist. Supabase project ref needs verification. |
| claude-skills.md | ⚠️ memory-layer skill specifies retrieval scoring and decay rates that conflict with semantic-memory.md and episodic-memory.md. References `MemoryStoring.swift` protocol name that doesn't exist in architecture.md. |
| cognitive-load-model.md | ⚠️ Email firstOpenedAt tracking (V-03) has no implementation path. Uses `@Model` (SwiftData) — contradicts ADR-001. |
| cold-start.md | ⚠️ Category taxonomy (6 categories) is incompatible with Thompson sampling taxonomy (20 categories). EMA alpha schedule ends at 0.3, contradicting ema-estimation.md (0.25). CoreData entity uses `@objc(CDColdStartState)` (correct CoreData style). |
| coredata-migration.md | ⚠️ "No relationships in v1.0" directly contradicts data-models.md which defines extensive relationships. Schema entities (e.g., `CoreMemoryEntity` as singleton) conflict with data-models.md's `CDCoreMemoryEntry` (50-entry buffer). |
| data-models.md | ❌ Needs reconciliation. Entity schemas conflict with the per-tier memory specs (episodic-memory.md, semantic-memory.md, procedural-memory.md). Missing `CDPattern` entity. Missing `CDUserProfile` entity. The ER diagram promises relationships that coredata-migration.md says won't exist in v1. |
| day-plan-generation.md | ⚠️ EMA alpha (0.3) contradicts ema-estimation.md (0.25). References `CalendarGap` and `GapType` types not defined in any data model doc. |
| ema-estimation.md | ⚠️ Alpha value (0.25) contradicts most consumer docs (0.3). Uses `@Model` (SwiftData) for CoreData entity — contradicts ADR-001. Otherwise thorough and implementation-ready. |
| episodic-memory.md | ⚠️ Schema (`Episode` struct, `episodes` Supabase table) completely diverges from data-models.md (`CDEpisodicMemory`). Fields, naming, and storage approach differ. Local storage as JSON files conflicts with CoreData decision. |
| first-order-patterns.md | ✅ Ready to build from. Thorough taxonomy, evidence thresholds, confidence math, and lifecycle management. |
| focus-timer.md | ⚠️ EMA alpha (0.3) contradicts ema-estimation.md (0.25). Otherwise comprehensive and buildable. |
| graph-integration.md | ✅ Ready to build from. Thorough OAuth, rate limiting, delta sync, and read-only enforcement. Correctly flags existing write scopes that must be removed. |
| intelligence-report.md | ✅ Ready to build from. Clear structure, maturity examples, and metric definitions. |
| memgpt-context.md | ⚠️ Core memory size (2000 tokens) conflicts with data-models.md (50 entries, ~4K tokens) and build-sequence.md (20 entries, ~4K tokens). Nightly reflection pass structure (5 passes) conflicts with other reflection docs. Offline embedding P0 requirement has no implementation spec. |
| memory-promotion.md | ❌ Needs rewrite. Introduces a unified `memories` table via ALTER TABLE that doesn't exist in any schema doc. `MemoryRecord` extension with `MemoryStatus` enum conflicts with per-tier status enums. Haiku for semantic fact generation contradicts semantic-memory.md (Opus). Confidence threshold for promotion (0.6) contradicts semantic-memory.md initial confidence (0.5 for observations). |
| memory-retrieval.md | ⚠️ Recency formula (`0.995^hours`) and importance scale (1-10 normalised to 0-1) conflict with episodic-memory.md (exponential decay with lambda=0.01, 0-1 importance). Otherwise solid. |
| menu-bar.md | ✅ Ready to build from. Clear design philosophy and three-level information density model. |
| model-versioning.md | ✅ Ready to build from. Snapshot, diff, rollback, and drift detection are well-defined. |
| morning-session.md | ⚠️ References `semantic_memories` table with `morning_surface` flag for pattern storage — this table/flag doesn't exist in any schema doc. Otherwise strong design. |
| morning-voice.md | ⚠️ References `en-AU` locale and names the user "Yasser" in Section 5.1 — this is the primary user's father, not a generic executive. The locale is appropriate but the hardcoded name reference should be parameterised. |
| named-patterns.md | ✅ Ready to build from. 28 archetypes with detection signals, evidence thresholds, and example surface text. |
| onboarding-flow.md | ✅ Ready to build from. Clear 8-step flow, privacy-first, under 5 minutes. |
| privacy-spec.md | ⚠️ PrivacyAbstractor is referenced but its sanitisation pipeline is not defined (G-01). The three-tier classification and compile-time enforcement via `DeviceOnlyData` protocol is excellent. |
| proactive-alerts.md | ✅ Ready to build from. Rarity principle, interrupt-value equation, and severity tiers are well-defined. |
| procedural-memory.md | ⚠️ Schema diverges significantly from data-models.md `CDProceduralMemory`. Rule actions use rich enum types (`RuleAction` with 5 cases) not representable in data-models.md's `actionJson: Data`. Otherwise thorough. |
| query-interface.md | ✅ Ready to build from. Clear query types, retrieval strategy, and response format. |
| reflection-architecture.md | ⚠️ Stage count and model assignment must be reconciled with reflection-prompts.md and build-sequence.md. The `SemanticModel`, `SemanticFact`, `ProceduralRule` structs defined here differ from those in semantic-memory.md and procedural-memory.md. |
| reflection-prompts.md | ⚠️ Only Stages 1-3 are fully specified. Stages 4-6 are missing (doc appears truncated). The 6-stage naming disagrees with reflection-architecture.md's 4+1 stage structure. |
| relationship-scorer.md | ✅ Ready to build from. Strong scientific foundation and per-contact signal model. |
| rule-generation.md | ✅ Ready to build from. Clear IF-THEN schema, confidence scoring, and lifecycle rules. |
| second-order-synthesis.md | ✅ Ready to build from. Clear correlation matrix approach and named insight structure. |
| semantic-memory.md | ⚠️ Schema conflicts with data-models.md. Otherwise the most thorough memory tier spec with clear confidence math, contradiction handling, and decay logic. |
| session-log-template.md | ✅ Ready to use. Clear template structure. |
| settings-preferences.md | ✅ Ready to build from. Correctly separates configurable from invariant. |
| signal-app-focus.md | ✅ Ready to build from. Thorough privacy constraints, session tracking, and battery management. |
| signal-calendar.md | ✅ Ready to build from. Comprehensive computed fields, chronotype feed, and observation-only enforcement. |
| signal-email.md | ✅ Ready to build from. Complete delta sync, computed fields, deduplication, and privacy enforcement. |
| signal-task-interaction.md | ⚠️ EMA alpha (0.3) contradicts ema-estimation.md (0.25). Base importance scores for episodic bridge don't match episodic-memory.md's scoring table. |
| signal-voice.md | ✅ Ready to build from. Clear pipeline, session types, metadata extraction, and privacy enforcement. |
| test-strategy.md | ✅ Ready to build from. Per-layer coverage targets, longitudinal fixtures, and LLM output testing approach. |
| thompson-sampling.md | ⚠️ Uses `@Model` (SwiftData) for `TaskCategoryPrior` persistence — contradicts ADR-001. 20-category taxonomy has no mapping to cold-start's 6-category archetypes. Otherwise excellent bandit formulation. |

---

## Summary of Critical Actions Required Before Coding

1. **Unify the memory entity schemas.** Pick ONE canonical schema for each tier (episodic, semantic, procedural, core memory) and update ALL docs. data-models.md and the per-tier specs must match exactly.

2. **Fix the reflection pipeline stage count and model assignment.** Decide: 4, 5, or 6 stages? Which model runs each stage? Update reflection-architecture.md, reflection-prompts.md, build-sequence.md, build-state.md, and memgpt-context.md.

3. **Reconcile protocol naming.** Pick either the architecture.md names (`SignalWritePort`, `EpisodicMemoryReadPort`, etc.) or the CLAUDE.md names (`SignalEmitting`, `MemoryStoring`, etc.). Update all docs.

4. **Fix the retrieval scoring formula.** Pick one recency function and one combination method. Update data-models.md, episodic-memory.md, memory-retrieval.md, build-sequence.md, and claude-skills.md.

5. **Decide EMA alpha.** 0.25 or 0.3. Update ema-estimation.md and all consumer docs.

6. **Define the `CDPattern` entity.** It's referenced in data-models.md's ER diagram but never defined.

7. **Spec the PrivacyAbstractor.** Every LLM call depends on it. It has no spec.

8. **Unify task category taxonomy.** Map the 6-category archetypes, 4-type chronotype taxonomy, and 20-category Thompson sampling taxonomy to one canonical system with translation functions.

9. **Fix `@Model` vs CoreData.** thompson-sampling.md, ema-estimation.md, chronotype-model.md, cognitive-load-model.md, and avoidance-detector.md all use `@Model` (SwiftData macro). ADR-001 chose CoreData. These entities need `@objc(CD...)` NSManagedObject subclasses.

10. **Fix core memory buffer spec.** 20 entries at ~4K tokens or 50 entries at ~4K tokens or ~2K tokens? One answer, everywhere.
