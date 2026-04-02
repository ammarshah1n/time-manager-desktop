# Phase-by-Phase Build Sequence

> Timed v1 Intelligence Layer | Last updated: 2026-04-02

---

## Overview

Six phases, each producing a working increment testable on a real Mac. Dependencies are strict -- no phase starts until its prerequisites pass completion criteria. The critical milestone is the end of Phase 4: that is when Timed transitions from "a macOS app" to "a system that genuinely learns about the user."

**Existing codebase state (carried forward):** Voice morning session, email triage (Graph buckets), Thompson sampling task scoring, EMA time estimation, calendar-aware slot allocator, focus timer, menu bar widget, command palette. These are UI features backed by local DataStore, NOT yet connected to the four-layer architecture. They remain usable during the rebuild but are not part of the new layer system until explicitly bridged.

**Dev environment:** Claude Code (Claude Max 20x), Comet MCP for browser automation, Obsidian for knowledge base. Single developer, AI-pair-programming for 100% of development.

---

## Phase 1: Foundation

**Goal:** CoreData schema live, layer protocols defined, signal queue operational, Microsoft auth working. The skeleton on which everything mounts.

### What Gets Built

| Component | Description | Complexity |
|-----------|-------------|------------|
| **CoreData model (full schema)** | All entities from the data model spec: Signal, EpisodicMemory, SemanticMemory, ProceduralMemory, CoreMemoryEntry, Pattern, Rule, Task, EmailSignal, CalendarEvent, AppFocusSession, VoiceSession, FocusSession, UserProfile, MLModelState. Relationships, constraints, indexes. | L |
| **Layer boundary protocols** | `SignalWritePort` (Layer 1), `MemoryStoring` / `MemoryQuerying` (Layer 2), `ReflectionRunning` (Layer 3), `IntelligenceDelivering` (Layer 4). Swift protocols with associated types. No layer imports another layer's internal types. | M |
| **Signal queue** | `SignalBus` actor. Receives `Signal` value types from any Layer 1 agent, persists to CoreData, notifies Layer 2 subscribers. Back-pressure handling: if Layer 2 is slow, queue buffers to disk (CoreData), not memory. | M |
| **Microsoft OAuth (MSAL)** | Sign-in flow: Microsoft provider via MSAL -> token storage in Keychain -> `auth.uid()` available for Supabase RLS. Scopes: `Mail.Read`, `Calendars.Read`, `offline_access`. Token refresh on 401. | M |
| **Supabase Auth bridge** | Connect MSAL token to Supabase session. Workspace + profile bootstrap on first sign-in. Dual-write toggle: local DataStore + Supabase for gradual migration. | M |
| **Anthropic API client** | `ClaudeClient` actor with three entry points: `.classify(model: .haiku)`, `.analyse(model: .sonnet)`, `.reflect(model: .opus)`. Retry with exponential backoff. Rate-limit awareness. Privacy abstraction pipeline runs before every call -- strips PII markers, replaces names with tokens. | M |
| **Jina embedding client** | `EmbeddingService` actor. Accepts text, returns `[Float]` (1024-dim). Batch endpoint for bulk embedding (up to 128 texts per call). Local cache keyed on content hash to avoid re-embedding identical text. | S |
| **Logging framework** | `OSLog` categories: `.layer1`, `.layer2`, `.layer3`, `.layer4`, `.auth`, `.api`, `.coredata`. Structured logging with subsystem `com.timed.app`. | S |
| **Error handling framework** | `TimedError` enum hierarchy: `.signal(SignalError)`, `.memory(MemoryError)`, `.reflection(ReflectionError)`, `.delivery(DeliveryError)`, `.api(APIError)`, `.auth(AuthError)`. Never force-unwrap. `Result` for expected failures, `throws` for unexpected. | S |
| **Directory structure** | `Sources/Timed/Layer1/`, `Layer2/`, `Layer3/`, `Layer4/`, `Core/`, `Models/`. `Tests/TimedTests/Layer1/`, etc. | S |

### Dependencies

None -- this is the root phase.

### Completion Criteria

1. `swift build` succeeds with zero warnings.
2. CoreData model loads in a test harness; all entities instantiate; relationships set without crash.
3. `SignalBus` accepts 1,000 signals in a unit test and persists them all to CoreData within 2 seconds.
4. `SignalWritePort` protocol has at least one mock conformer that emits test signals.
5. Microsoft OAuth flow completes end-to-end on a real Mac -- token retrieved, stored, refreshable.
6. `ClaudeClient.classify(model: .haiku, prompt: "test")` returns a response in a unit test (can be mocked for CI, real for local).
7. `EmbeddingService.embed("test text")` returns a 1024-dim vector.
8. All layer protocols compile with placeholder conformers.
9. At least 20 unit tests pass covering the above.

### Independently Testable After This Phase

- CoreData CRUD for every entity (isolated unit tests).
- Signal queue throughput and durability.
- Auth flow (manual on real Mac).
- API clients (unit tests with mocked responses + one integration test each).

---

## Phase 2: Signal Ingestion

**Goal:** All five signal agents running, observing real data, writing to the signal queue. The system can "see."

### What Gets Built

| Component | Description | Complexity |
|-----------|-------------|------------|
| **Email signal agent** | Microsoft Graph `Mail.Read` via delta queries. Polls every 60s (configurable). Extracts: sender, subject, timestamp, thread ID, is-reply, importance flag, read/unread, response latency (computed from thread). Classifies email category via Haiku (Do First / Action / Reply / Read / Ignore). Writes `EmailSignal` + `Signal` to CoreData. | L |
| **Calendar signal agent** | Microsoft Graph `Calendars.Read` via delta queries. Polls every 120s. Extracts: event metadata, attendees, duration, is-recurring, acceptance status, cancellation. Detects: new events, rescheduled events, cancelled events. Classifies meeting type via Haiku (Strategic / Operational / 1:1 / External / Admin). Writes `CalendarEvent` + `Signal`. | L |
| **App focus agent** | `NSWorkspace.shared.notificationCenter` for `didActivateApplicationNotification`. Records: bundle ID, window title (opt-in only, off by default), timestamp, duration (computed on next switch). Classifies activity type locally (no API call): deep work / shallow work / communication / break / unknown -- based on bundle ID mapping. Writes `AppFocusSession` + `Signal`. | M |
| **Voice capture agent** | Apple Speech (`SFSpeechRecognizer`) on-device only. Captures during: morning session, ad-hoc voice notes (hotkey triggered). Extracts: transcript, word count, speaking pace (WPM), detected topics (keyword extraction, no API call). Writes `VoiceSession` + `Signal`. Raw audio is NEVER stored. | M |
| **Task signal agent** | Observes internal task system events: task created, completed, deferred, re-prioritised, duration recorded. Writes `Signal` with task metadata. Feeds Thompson sampling alpha/beta updates and EMA actuals. | S |
| **Background execution infrastructure** | Login Item (LSSharedFileList / ServiceManagement) + App Nap mitigation (`NSProcessInfo.beginActivity`). Not XPC -- keep agents in-process for Phase 2 simplicity. Health monitoring: each agent reports heartbeat every 60s to `AgentHealthMonitor` actor. Stalled agents get restarted after 3 missed heartbeats. | M |
| **Sleep/wake reconciliation** | On `NSWorkspace.willSleepNotification`: persist agent state, flush queue. On `didWakeNotification`: trigger catch-up delta queries for email + calendar (fetch changes since last sync timestamp). Throttle catch-up to avoid CPU spike (max 50 items per batch, 500ms delay between batches). | M |
| **Agent resource budgets** | CPU: <2% average, <10% peak per agent. Memory: <150MB RSS total for all agents. Network: configurable polling intervals with jitter. Circuit breaker: if an agent exceeds CPU budget for 30s, pause for 5 minutes. | S |

### Dependencies

- **Phase 1 complete.** Specifically: CoreData model, `SignalBus`, `SignalWritePort` protocol, Microsoft OAuth (for email/calendar agents), `ClaudeClient` (for Haiku classification), logging framework.

### Completion Criteria

1. Email agent retrieves real emails from a test Outlook account, classifies them, and writes `EmailSignal` records to CoreData.
2. Calendar agent retrieves real calendar events, classifies them, and writes `CalendarEvent` records.
3. App focus agent records 50+ app switches in a 1-hour test period, with correct durations.
4. Voice agent captures a 60-second voice session, produces a transcript, and writes a `VoiceSession` record.
5. Task agent captures a task completion event and writes a `Signal` record.
6. `AgentHealthMonitor` shows all 5 agents healthy in a test run.
7. Sleep/wake test: put Mac to sleep for 5 minutes, wake, verify email/calendar agents catch up without data loss.
8. Resource budget: no agent exceeds 5% CPU sustained over a 30-minute test.
9. All signals have correct timestamps, modality tags, and are queryable via CoreData predicates.
10. At least 30 unit tests + 5 integration tests pass.

### Independently Testable After This Phase

- Each agent independently (mock the signal bus, verify output).
- Signal queue under load (5 agents writing simultaneously).
- Delta query catch-up after simulated sleep.
- Resource monitoring and circuit breaker.

---

## Phase 3: Memory

**Goal:** Three memory tiers operational with embedding-based retrieval. The system can "remember."

### What Gets Built

| Component | Description | Complexity |
|-----------|-------------|------------|
| **Episodic memory CRUD** | `EpisodicMemoryRepository` actor. Create from any `Signal`. Read with filtering (time range, source modality, importance threshold). Update access count + last-accessed timestamp on every retrieval. Delete (only via retention policy, never manually). Embed content at write time via `EmbeddingService`. | M |
| **Semantic memory CRUD** | `SemanticMemoryRepository` actor. Create from reflection engine output. Key-value structure with confidence score (0.0-1.0), reinforcement count, category (work_style / preferences / relationships / avoidance_patterns / energy / decision_making). Reinforce: increment count + update confidence + update `last_reinforced_at`. Contradict: flag conflict, do not auto-resolve (reflection engine resolves). Decay: confidence -= 0.01 per week without reinforcement (floor: 0.1). | M |
| **Procedural memory CRUD** | `ProceduralMemoryRepository` actor. Create from reflection engine output. Fields: rule text, confidence, activation count, conditions (when-clause), exceptions. Activate: log activation, increment count. Deactivate: set status to `fading` after 30 days without activation. Expire: set status to `archived` after 90 days without activation. Source attribution: every rule links to the reflection cycle + patterns that generated it. | M |
| **Core memory manager** | `CoreMemoryManager` actor. MemGPT-style fixed-size buffer (50 entries max, ~4,000 tokens). Each entry: content string (max 500 chars), priority rank, last updated, source memory ID. Promotion: when a semantic fact reaches confidence > 0.8 and reinforcement count > 5, it is a candidate. Demotion: lowest-priority entry evicted when buffer is full and a higher-priority candidate arrives. Always-in-context: serialised and included in every Opus/Sonnet prompt's system message. | M |
| **Memory retrieval engine** | `MemoryRetrievalEngine` actor. Three-axis scoring: `recency(m) = 0.995 ^ hours_since_access(m)`, `importance(m) = m.importance_score`, `relevance(m, q) = cosine_similarity(embed(m), embed(q))`. Composite: `score = w_recency * recency + w_importance * importance + w_relevance * relevance`. Default weights: `(0.2, 0.3, 0.5)`. Returns top-K results (default K=20) with scores. Supports per-query weight overrides (reflection wants more importance weight, morning session wants more recency weight). | L |
| **Embedding storage + vector search** | On-device vector search using Accelerate framework for cosine similarity. Embeddings stored as `Data` (binary) on CoreData entities. At query time: load candidate embeddings, compute cosine similarity via vDSP, return top-K. Performance target: <200ms for 10,000 memories. If performance degrades past 500ms at scale, Phase 6 introduces USearch index. | M |
| **Memory consolidation engine** | `MemoryConsolidationEngine` actor. Runs after every nightly reflection. Episodic -> semantic promotion: when the reflection engine identifies a recurring pattern across 3+ episodic memories, it generates a semantic fact. The episodic memories get `consolidated = true` but are NOT deleted (they remain as evidence). Semantic -> procedural promotion: when a semantic fact is confirmed by 5+ observations, it becomes a procedural rule candidate for the reflection engine. | M |
| **Memory retention policy** | Episodic: keep all for first 90 days; after 90 days, archive (move embedding to archival tier, keep metadata). Semantic: no auto-deletion (decay handles relevance). Procedural: archived rules kept for 1 year then purged. CoreData storage budget: alert user if memory store exceeds 2GB. | S |

### Dependencies

- **Phase 1 complete.** CoreData model, `EmbeddingService`, `ClaudeClient` (for importance scoring), layer protocols.
- **Phase 2 complete.** Signal agents must be writing signals for memory to ingest.

### Completion Criteria

1. Write 100 episodic memories from test signals; retrieve top-10 by relevance for a test query in <200ms.
2. Semantic memory reinforcement: create a fact, reinforce 5 times, verify confidence increases.
3. Semantic memory decay: create a fact, advance clock 4 weeks without reinforcement, verify confidence decreased by ~0.04.
4. Procedural memory lifecycle: create -> activate 3 times -> verify activation count. Create -> leave untouched for 30 days -> verify status is `fading`.
5. Core memory buffer: fill to 50 entries, add a higher-priority candidate, verify lowest-priority entry was evicted.
6. Retrieval engine: given 500 episodic memories with known properties, verify that a query about "Monday meetings" returns memories about meetings on Mondays ranked highest.
7. Consolidation: inject 5 episodic memories about the same pattern, run consolidation, verify a semantic fact was generated.
8. Memory store survives app restart without data loss.
9. CoreData background context operations: write 100 memories on a background context while the main context reads, verify no merge conflicts.
10. At least 40 unit tests + 10 integration tests pass.

### Independently Testable After This Phase

- Each memory repository (CRUD + decay + lifecycle).
- Retrieval engine accuracy (synthetic test set with known correct rankings).
- Core memory buffer management.
- Consolidation logic (synthetic episodic memories -> semantic facts).
- Vector search performance benchmarks.

---

## Phase 4: Reflection

**Goal:** Nightly Opus reflection cycle running, producing patterns, rules, and model updates. The system can "think." THIS IS THE INTELLIGENCE BOOTSTRAP MILESTONE.

### What Gets Built

| Component | Description | Complexity |
|-----------|-------------|------------|
| **Nightly reflection orchestrator** | `ReflectionOrchestrator` actor. Triggers at configurable time (default 2:00 AM local). Checks preconditions: minimum 10 new signals since last reflection, system not in low-power mode, API reachable. Runs the 6-stage pipeline sequentially. Handles failures per-stage (partial results saved). Writes `ReflectionCycle` record with metadata (start/end time, stage reached, signal count processed, model version produced). | L |
| **Stage 1: Episodic summarisation** | Retrieves today's episodic memories (last 24h). Groups by context (meeting cluster, email thread, focus session, app usage block). Summarises each group via Opus. Output: 10-30 day-level summaries with themes tagged. Estimated: 5,000-15,000 input tokens, 2,000-4,000 output tokens. | M |
| **Stage 2: First-order pattern extraction** | Takes Stage 1 summaries + recent episodic history (past 7 days). Uses Opus to extract observable first-order patterns: "Executive deferred Board memo for 4th consecutive day", "Average email response time increased 40% this week", "No 1:1 with CFO in 12 days." Output: list of `FirstOrderPattern` structs with evidence references. Estimated: 10,000-25,000 input tokens, 3,000-6,000 output tokens. | M |
| **Stage 3: Second-order insight synthesis** | Takes Stage 2 patterns + existing semantic model + existing pattern library. Uses Opus at maximum effort. Cross-references new patterns with historical model. Generates named insights: "Post-board fatigue correlates with 72h of reduced strategic output", "Avoidance of CFO 1:1 coincides with pending headcount decision." Output: `SecondOrderInsight` structs with confidence, evidence chains, model implications. Estimated: 10,000-25,000 Opus tokens. | L |
| **Stage 4: Rule generation** | Takes Stage 3 insights + existing procedural rules. Opus proposes new rules or updates existing ones. "When board meeting occurs, protect following 3 days from strategic decisions." "Before CFO 1:1, surface pending people decisions." Rules include: conditions, actions (observation-only!), confidence, source insight references. Contradiction detection: if new rule conflicts with existing rule, flag both -- do NOT silently override. Estimated: 5,000-10,000 Opus tokens. | M |
| **Stage 5: Model update** | Writes all outputs to Layer 2: new semantic facts (via `SemanticMemoryRepository`), updated procedural rules (via `ProceduralMemoryRepository`), new/updated patterns (via pattern store), core memory updates (via `CoreMemoryManager`). Creates model version snapshot: serialise current semantic model + procedural rules + pattern library to a versioned JSON blob. Stored in CoreData with version number and timestamp. | M |
| **Stage 6: Intelligence preparation** | Selects which insights, patterns, and alerts are worth surfacing in tomorrow's morning session. Priority ranking: new confirmed patterns > contradictions detected > pattern violations > routine observations. Compiles `MorningBrief` payload: opening insight (most significant new finding), named patterns to discuss, task plan recommendations, proactive alerts, and one targeted question for active preference elicitation. | M |
| **Prompt templates** | Stored as Swift string constants in `ReflectionPrompts.swift`. One template per stage. Each template has: system prompt (includes core memory, executive profile, and processing instructions), user prompt (stage-specific input data), output schema (structured JSON expected). Templates are versioned alongside the code. | M |
| **Reflection quality self-assessment** | After Stage 3, Opus rates its own reflection: `confidence: high/medium/low`, `signal_richness: sparse/adequate/rich`, `novel_findings: count`. Logged in `ReflectionCycle` record. Used to adjust future reflection depth (sparse signal days get shorter reflections). | S |
| **Pattern lifecycle manager** | `PatternLifecycleManager`. Patterns have states: `emerging` (seen 1-2 times) -> `confirmed` (seen 3+ times with consistent evidence) -> `fading` (no new evidence in 14 days) -> `archived` (no new evidence in 60 days). Confirmed patterns are eligible for rule generation. Fading patterns trigger a "is this still true?" check in the next reflection. | M |

### Dependencies

- **Phase 3 complete.** Memory repositories, retrieval engine, core memory manager, embedding service -- the reflection engine reads from and writes to Layer 2.
- **Phase 1:** `ClaudeClient` (Sonnet + Opus), privacy abstraction pipeline.

### Completion Criteria

1. Nightly orchestrator runs end-to-end with synthetic data (50 episodic memories simulating a day). All 6 stages complete without error.
2. Stage 1 produces at least 5 coherent day-level summaries from 50 episodic memories.
3. Stage 2 extracts at least 3 first-order patterns from the summaries.
4. Stage 3 produces at least 1 named second-order insight with an evidence chain of 2+ first-order patterns.
5. Stage 4 produces at least 1 new procedural rule from the insights.
6. Stage 5 writes all outputs to memory and produces a model version snapshot that is loadable and diff-able against the previous version.
7. Stage 6 produces a `MorningBrief` payload with at least: 1 opening insight, 1 named pattern, and 1 proactive alert.
8. Contradiction detection: inject two conflicting patterns, run Stage 4, verify both are flagged (not silently resolved).
9. Pattern lifecycle: inject a pattern, confirm it (3 evidence points), leave it for 14 days, verify status transitions to `fading`.
10. Partial failure: kill API mid-Stage 3, verify Stages 1-2 outputs are saved and the next run can resume from Stage 3.
11. Prompt templates produce valid JSON outputs that parse into Swift structs without error.
12. At least 25 unit tests + 10 integration tests pass. Integration tests use real Opus API calls against synthetic data.

### Independently Testable After This Phase

- Each reflection stage in isolation (mock inputs, verify outputs).
- Pattern lifecycle transitions.
- Contradiction detection logic.
- Model versioning and snapshot comparison.
- End-to-end reflection with synthetic data (the "does it actually produce insight?" test).
- Quality self-assessment calibration.

### THE INTELLIGENCE BOOTSTRAP

After Phase 4, run the system for 3 consecutive days with real data (developer's own Mac). At the end of 3 days:
- The system should have at least 5 named patterns about the developer's behaviour.
- At least 2 procedural rules should exist.
- The morning brief for Day 3 should reference observations from Days 1-2.
- **If this doesn't happen, the architecture has a fundamental problem. Stop and diagnose before Phase 5.**

---

## Phase 5: Intelligence Delivery

**Goal:** The executive sees and interacts with the intelligence. Morning session, menu bar, alerts, focus timer, query interface, day plan. The system can "speak."

### What Gets Built

| Component | Description | Complexity |
|-----------|-------------|------------|
| **Morning intelligence session** | Redesign existing morning session UI. Opens with the top named pattern from the `MorningBrief` payload, not a task list. Flow: (1) Named pattern + evidence presented, (2) Opus asks one targeted question via voice, (3) Executive responds (voice), (4) Opus synthesises response + plan, (5) Day plan displayed with reasoning. Uses Opus as morning director with full core memory in system prompt. | L |
| **Menu bar intelligence widget** | Redesign existing menu bar. Three sections: Now (current task + focus state), Next (upcoming commitment + prep needed), Insight (one rotating pattern-based observation). Clicking any section opens detail. Updated every 5 minutes from Layer 2 queries. | M |
| **Proactive alert system** | `ProactiveAlertManager`. Triggers on: confirmed pattern violation ("You usually do deep work at 9am but you've been in email for 40 minutes"), approaching deadline with insufficient progress, significant pattern change, energy curve anomaly. Maximum 3 alerts per day (interrupt budget). Priority queue: only the most important alert fires. Dismissal is a signal (fed back to Layer 1). | M |
| **Focus timer (Layer 4 integration)** | Existing focus timer bridged to Layer 4. On completion: writes focus session data to Layer 2 (actual duration, interruption count, outcome). Layer 4 shows "Your average focus session has been 32 minutes this week, down from 41 last week" type intelligence. | S |
| **Query interface** | Natural language query via command palette (Cmd+K). Examples: "Why did you rank this task first?", "What patterns do you see in my meetings?", "How has my email response time changed?". Routes to Sonnet with relevant memories in context (retrieved via `MemoryRetrievalEngine`). Response displayed inline. | M |
| **Day plan generation** | Replaces existing static day plan. Inputs: morning session voice response, today's calendar, task list with Thompson scores, procedural rules about scheduling, energy curve model, core memory. Opus generates plan with explanations ("I've placed the strategy review at 10am because your data shows that's your peak analytical window, and the board prep needs your best thinking"). | M |

### Dependencies

- **Phase 4 complete.** Reflection engine must be producing `MorningBrief` payloads, named patterns, and procedural rules.
- **Phase 3:** Memory retrieval engine (for query interface and context assembly).
- **Phase 2:** Signal agents (for real-time data feeding focus timer, alerts).

### Completion Criteria

1. Morning session launches with a named pattern (from real reflection output), asks a question, processes voice response, and generates a day plan with reasoning.
2. Menu bar shows Now/Next/Insight correctly, updates without user intervention.
3. Proactive alert fires when a confirmed pattern is violated (e.g., user is in email during their typical deep work window).
4. Alert budget: simulate 10 alert-worthy events in one day, verify only 3 fire.
5. Focus timer completion writes data to Layer 2 and Layer 4 displays a trend observation.
6. Query interface: ask "Why did you rank task X first?" and receive a response that references actual Thompson sampling scores and procedural rules.
7. Day plan includes time-slot assignments with natural-language reasoning.
8. All Layer 4 components degrade gracefully when Layer 3 has not yet produced output (e.g., first-ever morning session with no patterns yet).
9. At least 20 unit tests + 5 integration tests pass.

### Independently Testable After This Phase

- Morning session flow with mock `MorningBrief` payloads.
- Menu bar rendering with mock data.
- Alert trigger logic and budget enforcement.
- Query routing and response quality (subjective but assessable).
- Day plan generation with known inputs -> known reasonable outputs.

---

## Phase 6: Polish and Distribution

**Goal:** Cold start experience, onboarding, settings, model versioning UI, intelligence reports, distribution packaging. The system is ready for Yasser.

### What Gets Built

| Component | Description | Complexity |
|-----------|-------------|------------|
| **Cold start strategy** | First-launch experience when no data exists. Archetype picker: "What type of executive are you?" (Strategic / Operational / Hybrid / Creative). Pre-loads scoring weights based on archetype. Calendar history bootstrap: imports 90 days of Outlook calendar history via Graph to infer patterns on Day 1 (meeting density, recurring events, quiet periods). First morning session acknowledges it's learning: "I've been observing for [X days]. Here's what I see so far, and what I'm still uncertain about." | M |
| **Onboarding flow** | Install -> permissions request (Accessibility for app focus, microphone for voice) -> Microsoft sign-in (MSAL OAuth) -> archetype selection -> first signal ingestion -> "I'm watching. I'll have your first intelligence report in 24 hours." 5 screens max. No tutorial -- executives won't read it. | M |
| **Settings and preferences** | Configurable: polling intervals, alert frequency cap, Do Not Disturb schedule, voice capture toggle, app focus window title tracking (opt-in), reflection schedule time, which signal sources are active. Invariant (not configurable): observation-only constraint, privacy abstraction pipeline, memory retention policy. Corrections as signals: when the user changes a setting, it's a signal ("Executive disabled meeting alerts -- may indicate alert fatigue or preference for self-directed attention management"). | M |
| **Model versioning UI** | View model evolution over time. "Your model has 47 semantic facts, 12 procedural rules, and 8 confirmed patterns. This week: +3 facts, +1 rule, 1 pattern moved from emerging to confirmed." Compare any two model versions side-by-side. Rollback to a previous version (if a bad reflection corrupted the model). | M |
| **Month-over-month intelligence reports** | Monthly summary: patterns confirmed, rules generated, model growth, behaviour changes detected, accuracy of predictions (were morning session recommendations followed? were time estimates accurate?). Comparison to previous month. Trend charts. "Your deep work hours increased 23% this month. The system's time estimates improved from 34% to 18% average error." | L |
| **Sparkle auto-update** | Sparkle framework integrated. Appcast XML hosted (GitHub Pages or S3). Ed25519 signature verification. Check for updates on launch + daily. | S |
| **DMG packaging + notarisation** | Build script: archive -> create DMG -> notarise with `notarytool` -> staple. Code signing with Developer ID. Gatekeeper-friendly. | S |
| **CoreData migration strategy** | Lightweight migration for additive schema changes (new attributes, new entities). Heavyweight migration for destructive changes (renamed attributes, changed relationships). Migration tests: create a store with version N, migrate to version N+1, verify data integrity. | M |

### Dependencies

- **Phases 1-5 complete.** All layers operational.
- Cold start depends on: Calendar agent (Phase 2), Memory (Phase 3), Morning session (Phase 5).
- Distribution depends on: everything (you can only package what's built).

### Completion Criteria

1. Fresh install on a clean Mac: onboarding completes, first signal ingestion begins, "watching" confirmation displayed. Total time: under 3 minutes.
2. Cold start: archetype selected, 90-day calendar history imported, first morning session runs with calendar-inferred observations within 24 hours.
3. Settings: change alert frequency cap, verify alert behaviour changes immediately. Disable voice capture, verify no voice signals are generated.
4. Model versioning: run 3 nights of reflection, view model diff between Night 1 and Night 3, verify differences are displayed.
5. Rollback: corrupt the model (manually edit a semantic fact), rollback to previous version, verify corruption is gone.
6. Intelligence report: after 30 days of simulated data, generate monthly report with trend charts.
7. Sparkle: host a test appcast, verify the app detects and applies an update.
8. DMG: build DMG, install on a second Mac (or clean user account), verify app launches and completes onboarding.
9. CoreData migration: create a store with the Phase 1 schema, migrate through all schema versions to Phase 6, verify zero data loss.
10. At least 15 unit tests + 5 integration tests pass.

### Independently Testable After This Phase

- Onboarding flow (on a clean Mac or clean user account).
- Calendar history import (mock Graph responses with 90 days of data).
- Settings persistence and signal emission.
- Model versioning CRUD and diff.
- DMG installation on a clean system.

---

## Dependency Graph

```
Phase 1: Foundation
    |
    v
Phase 2: Signal Ingestion
    |
    v
Phase 3: Memory
    |
    v
Phase 4: Reflection  <-- INTELLIGENCE BOOTSTRAP MILESTONE
    |
    v
Phase 5: Intelligence Delivery
    |
    v
Phase 6: Polish + Distribution
```

**Critical path:** Phase 1 -> Phase 2 -> Phase 3 -> Phase 4. This is strictly sequential. Phase 4 cannot start without Phase 3 data; Phase 3 cannot start without Phase 2 signals; Phase 2 cannot start without Phase 1 infrastructure.

**Parallelisation opportunities:**
- Within Phase 1: CoreData model and layer protocols can be built in parallel with API clients and auth.
- Within Phase 2: Email agent and calendar agent share no code and can be built in parallel. App focus agent is independent. Voice agent is independent. Task agent depends on nothing.
- Within Phase 3: Episodic, semantic, and procedural repositories share no code and can be built in parallel. Retrieval engine depends on all three. Core memory depends on semantic memory.
- Within Phase 5: Menu bar, alerts, focus timer, and query interface share no code and can be built in parallel. Morning session depends on all of them (integration point).
- Phase 6 components are largely independent of each other.

**Leaf nodes (no Timed dependencies, can be built anytime):**
- Logging framework
- Error handling framework
- Directory structure
- DMG packaging scripts
- Sparkle integration

---

## Session Estimates

| Phase | Estimated Sessions | Notes |
|-------|-------------------|-------|
| Phase 1 | 4-6 | CoreData model is the largest task. Auth is the riskiest (MSAL can be finicky). |
| Phase 2 | 5-8 | Graph API integration is well-understood but has edge cases. App focus agent needs Accessibility API permissions which can be tricky. |
| Phase 3 | 5-7 | Retrieval engine is the most complex component. Vector search performance tuning may require iteration. |
| Phase 4 | 6-10 | Highest uncertainty. Prompt engineering for reflection quality is iterative. Opus API costs are real during testing. Budget $20-50 for Phase 4 API testing. |
| Phase 5 | 4-6 | UI work is well-suited to AI-pair-programming. Morning session voice integration has existing code to bridge. |
| Phase 6 | 3-5 | Distribution and migration are well-defined tasks. Intelligence reports are the most complex item. |
| **Total** | **27-42** | At 4-6 hours per session: **108-252 hours of development time.** |

---

## Risk Register

| Risk | Phase | Likelihood | Impact | Mitigation |
|------|-------|------------|--------|------------|
| MSAL OAuth token refresh fails silently | 1, 2 | Medium | High (no signals) | Token health check on every agent poll. Alert user on 3 consecutive failures. |
| Opus reflection produces low-quality patterns | 4 | Medium | Critical (product value) | Quality self-assessment, test with synthetic data first, iterate prompts before real data. |
| CoreData performance degrades at scale (>10K memories) | 3 | Medium | Medium | Benchmark at 10K, 50K, 100K records in Phase 3. Introduce indexes early. |
| App Nap kills background agents | 2 | High | High | `beginActivity(options: [.userInitiated, .idleSystemSleepDisabled])`. Test aggressively. |
| Privacy abstraction pipeline misses PII | 1 | Low | Critical (trust) | Regex + NER pipeline. Test with real executive-style data. Manual audit of first 100 API calls. |
| Voice transcription accuracy on executive jargon | 2 | Medium | Medium | Apple Speech handles general English well. Custom vocabulary not available. Accept and document limitation. |
| Vector search too slow at 50K+ embeddings | 3 | Medium | Medium | Accelerate framework for cosine similarity. Benchmark in Phase 3. USearch fallback in Phase 6. |
