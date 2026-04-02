# Timed — Full System Implementation Plan

> Sequenced task list for the complete Timed system.
> Every component from all 50 spec docs mapped to a concrete task.
> No time estimates. No dates. Just sequence and dependencies.
> Generated: 2026-04-02

---

## Phase 1: Foundation

Everything mounts on this. CoreData schema, layer protocols, signal queue, auth bridge, API clients, error/logging infrastructure. Nothing else can begin until this is unbreakable.

---

### 1.01 — Directory structure scaffold

Create the full `Sources/` and `Tests/` directory tree matching the architecture spec.

- **Files to create:**
  - `Sources/Core/Models/`, `Sources/Core/Models/DTOs/`
  - `Sources/Core/Ports/`
  - `Sources/Core/Clients/`
  - `Sources/Core/Services/Agents/`, `Services/Memory/`, `Services/Reflection/`, `Services/Intelligence/`
  - `Sources/Core/Persistence/`
  - `Sources/Core/Infrastructure/`
  - `Sources/Core/Design/`
  - `Sources/Features/` (subdirs per screen)
  - `Sources/Legacy/`
  - `Tests/TimedTests/Layer1/`, `Layer2/`, `Layer3/`, `Layer4/`, `Infrastructure/`
- **Depends on:** Nothing
- **Acceptance criterion:** `swift build` succeeds; every directory exists and is importable

---

### 1.02 — Shared enums and value types

Define all canonical enums referenced across layers: `SignalSource`, `ModalityTag`, `MemoryTier`, `AIModelTier`, `AIRequestType`, `PatternStatus`, `FactType`, `FactCategory`, `FactStatus`, `RuleStatus`, `TaskCategory` (20 categories), `TaskBucket`, `AlertType`, `AlertUrgency`, `ArchitectureLayer`, `SnapshotTrigger`, `ReflectionTrigger`, `ProceduralRuleType`, `TriggerField`, `TriggerOperator`, `QueryType`, `RuleAction` (5 cases), `PromotionStatus`.

- **Files to create:** `Sources/Core/Models/Enums.swift`
- **Depends on:** 1.01
- **Acceptance criterion:** All enums compile, are `Sendable`, `Codable`, `CaseIterable` where specified in data-models.md; no `@Model` (SwiftData) macros anywhere

---

### 1.03 — Error handling framework

Implement `TimedError` protocol and typed error enums per layer: `SignalError`, `MemoryError`, `ReflectionError`, `DeliveryError`, `APIError`, `AuthError`. Each error carries `layer`, `isRecoverable`, `userMessage`, `logMessage`.

- **Files to create:** `Sources/Core/Infrastructure/TimedError.swift`
- **Depends on:** 1.02 (needs `ArchitectureLayer` enum)
- **Acceptance criterion:** All error enums conform to `TimedError`; force-unwrap search across codebase returns zero hits outside tests

---

### 1.04 — Logging framework

Extend existing `TimedLogger.swift` with subsystems for all four layers: `.layer1`, `.layer2`, `.layer3`, `.layer4`, `.auth`, `.api`, `.coredata`. OSLog subsystem `com.timed.app`.

- **Files to modify:** `Sources/Core/Infrastructure/TimedLogger.swift`
- **Depends on:** 1.01
- **Acceptance criterion:** Each subsystem emits to Console.app filterable by subsystem; `print()` and `NSLog()` grep across codebase returns zero hits

---

### 1.05 — CoreData model file (full schema)

Create `.xcdatamodeld` with all entities from data-models.md: `CDSignal`, `CDEmailSignal`, `CDCalendarEvent`, `CDVoiceSession`, `CDAppFocusSession`, `CDEpisodicMemory`, `CDSemanticMemory`, `CDProceduralMemory`, `CDCoreMemoryEntry`, `CDPattern`, `CDRule`, `CDTask`, `CDFocusSession`, `CDCompletionRecord`, `CDUserProfile`, `CDMLModelState`, `CDReflectionRun`, plus join entities `CDEpisodicSemanticLink`, `CDPatternEpisodicLink`, `CDSemanticProceduralLink`. All relationships, constraints, indexes.

- **Files to create:** `Sources/Core/Persistence/TimedModel.xcdatamodeld/`
- **Depends on:** 1.02 (enum raw values used in entity attributes)
- **Acceptance criterion:** Model loads in a test harness; all entities instantiate; relationships set without crash; all indexed attributes have CoreData indexes defined

---

### 1.06 — CoreData NSManagedObject subclasses

Generate or hand-write `@objc(CD...)` subclasses for every entity in the model. Each subclass includes `@NSManaged` properties matching the schema. No `@Model` (SwiftData) macros.

- **Files to create:**
  - `Sources/Core/Models/CDSignal.swift`
  - `Sources/Core/Models/CDEmailSignal.swift`
  - `Sources/Core/Models/CDCalendarEvent.swift`
  - `Sources/Core/Models/CDVoiceSession.swift`
  - `Sources/Core/Models/CDAppFocusSession.swift`
  - `Sources/Core/Models/CDEpisodicMemory.swift`
  - `Sources/Core/Models/CDSemanticMemory.swift`
  - `Sources/Core/Models/CDProceduralMemory.swift`
  - `Sources/Core/Models/CDCoreMemoryEntry.swift`
  - `Sources/Core/Models/CDPattern.swift`
  - `Sources/Core/Models/CDRule.swift`
  - `Sources/Core/Models/CDTask.swift`
  - `Sources/Core/Models/CDFocusSession.swift`
  - `Sources/Core/Models/CDCompletionRecord.swift`
  - `Sources/Core/Models/CDUserProfile.swift`
  - `Sources/Core/Models/CDMLModelState.swift`
  - `Sources/Core/Models/CDReflectionRun.swift`
  - `Sources/Core/Models/CDEpisodicSemanticLink.swift`
  - `Sources/Core/Models/CDPatternEpisodicLink.swift`
  - `Sources/Core/Models/CDSemanticProceduralLink.swift`
- **Depends on:** 1.05
- **Acceptance criterion:** Every entity from the `.xcdatamodeld` has a corresponding Swift class; `swift build` succeeds; zero `@Model` annotations

---

### 1.07 — EmbeddingVectorTransformer

Custom `ValueTransformer` subclass for storing 1024-dim `[Float]` vectors as `Data` in CoreData `Transformable` attributes.

- **Files to create:** `Sources/Core/Persistence/EmbeddingVectorTransformer.swift`
- **Depends on:** 1.05
- **Acceptance criterion:** Round-trip test: `[Float]` -> `Data` -> `[Float]` with zero precision loss for 1024-dim vectors

---

### 1.08 — TimedPersistenceController

CoreData stack: `NSPersistentContainer`, multi-context setup (viewContext for UI reads, newBackgroundContext for writes), merge policy `NSMergeByPropertyObjectTrumpMergePolicy`, automatic change merging. Registers `EmbeddingVectorTransformer` before loading stores.

- **Files to create:** `Sources/Core/Persistence/TimedPersistenceController.swift`
- **Depends on:** 1.05, 1.06, 1.07
- **Acceptance criterion:** Container loads persistent store; viewContext and backgroundContext both instantiate entities; background saves merge into viewContext within 1 second

---

### 1.09 — DTO definitions

Plain `Sendable` structs for all cross-layer communication: `EpisodicMemoryDTO`, `SemanticMemoryDTO`, `ProceduralRuleDTO`, `CoreMemoryEntryDTO`, `PatternDTO`, `PatternSummary`, `UserProfileDTO`, `CalendarEventDTO`, `TaskDTO`, `SignalInput`, `EmailSignalDTO`, `ScoredMemory`, `MorningBriefing`, `ProactiveAlert`, `AIRequest`, `AIResponse`, `ReflectionRunResult`, `ConsolidationResult`, `ModelSnapshot`, `ConfidenceDistribution`, `PlanItem`, `RemoteUpdate`, `RateLimitInfo`. Plus `.toDTO()` extensions on all NSManagedObject subclasses.

- **Files to create:**
  - `Sources/Core/Models/DTOs/EpisodicMemoryDTO.swift`
  - `Sources/Core/Models/DTOs/SemanticMemoryDTO.swift`
  - `Sources/Core/Models/DTOs/ProceduralRuleDTO.swift`
  - `Sources/Core/Models/DTOs/CoreMemoryEntryDTO.swift`
  - `Sources/Core/Models/DTOs/PatternDTO.swift`
  - `Sources/Core/Models/DTOs/UserProfileDTO.swift`
  - `Sources/Core/Models/DTOs/CalendarEventDTO.swift`
  - `Sources/Core/Models/DTOs/TaskDTO.swift`
  - `Sources/Core/Models/DTOs/SignalInput.swift`
  - `Sources/Core/Models/DTOs/EmailSignalDTO.swift`
  - `Sources/Core/Models/DTOs/ScoredMemory.swift`
  - `Sources/Core/Models/DTOs/MorningBriefing.swift`
  - `Sources/Core/Models/DTOs/ProactiveAlert.swift`
  - `Sources/Core/Models/DTOs/AIRequest.swift`
  - `Sources/Core/Models/DTOs/AIResponse.swift`
  - `Sources/Core/Models/DTOs/ReflectionRunResult.swift`
  - `Sources/Core/Models/DTOs/ModelSnapshot.swift`
  - `Sources/Core/Models/DTOs/PlanItem.swift`
- **Files to modify:** All CD*.swift files (add `.toDTO()` extension)
- **Depends on:** 1.06
- **Acceptance criterion:** Every DTO is `Sendable` and `Codable`; every NSManagedObject subclass has a `.toDTO()` method; no NSManagedObject reference leaks into a DTO

---

### 1.10 — Layer boundary protocols

Define all port protocols exactly as specified in architecture.md: `SignalWritePort`, `SignalAgent`, `ImportanceClassifier`, `EpisodicMemoryReadPort`, `MemoryWritePort`, `EmbeddingPort`, `PatternQueryPort`, `UserProfilePort`, `ReflectionEngine`, `MorningDirector`, `AlertEngine`, `AIRouter`, `SyncPort`.

- **Files to create:**
  - `Sources/Core/Ports/SignalWritePort.swift`
  - `Sources/Core/Ports/SignalAgent.swift`
  - `Sources/Core/Ports/ImportanceClassifier.swift`
  - `Sources/Core/Ports/EpisodicMemoryReadPort.swift`
  - `Sources/Core/Ports/MemoryWritePort.swift`
  - `Sources/Core/Ports/EmbeddingPort.swift`
  - `Sources/Core/Ports/PatternQueryPort.swift`
  - `Sources/Core/Ports/UserProfilePort.swift`
  - `Sources/Core/Ports/ReflectionEngineProtocol.swift`
  - `Sources/Core/Ports/MorningDirectorProtocol.swift`
  - `Sources/Core/Ports/AlertEngineProtocol.swift`
  - `Sources/Core/Ports/AIRouterProtocol.swift`
  - `Sources/Core/Ports/SyncPort.swift`
- **Depends on:** 1.09 (protocols reference DTOs)
- **Acceptance criterion:** All protocols compile; each protocol has at least one mock conformer in `Tests/`; no layer imports another layer's internal types

---

### 1.11 — SignalBus actor

`SignalBus` actor receives `SignalInput` values from any Layer 1 agent, persists `CDSignal` + `CDEpisodicMemory` to CoreData via background context, and notifies Layer 2 subscribers via `AsyncStream`. Back-pressure: if Layer 2 is slow, queue buffers to CoreData (disk), not memory.

- **Files to create:** `Sources/Core/Services/Agents/SignalBus.swift`
- **Depends on:** 1.08, 1.10 (needs `SignalWritePort`, persistence controller)
- **Acceptance criterion:** Unit test: SignalBus accepts 1,000 signals and persists all to CoreData within 2 seconds; subscribers receive all signals via `AsyncStream`

---

### 1.12 — Microsoft OAuth (MSAL) auth bridge

Connect existing `AuthService.swift` MSAL flow to Supabase auth. On first sign-in: create workspace + profile in Supabase. Store tokens in Keychain. Token refresh on 401. Scopes: `Mail.Read`, `Calendars.Read`, `offline_access`, `User.Read` only. Remove any existing write scopes (`Mail.ReadWrite`, `Mail.Send`, `Calendars.ReadWrite`).

- **Files to modify:**
  - `Sources/Core/Services/AuthService.swift` (remove write scopes, add Supabase session bootstrap)
- **Files to create:**
  - `Sources/Core/Services/SupabaseAuthBridge.swift`
- **Depends on:** 1.03 (needs `AuthError`)
- **Acceptance criterion:** OAuth flow completes end-to-end on a real Mac; token stored in Keychain; Supabase session active; `auth.uid()` available for RLS; zero write scopes in MSAL config

---

### 1.13 — Anthropic API client (ClaudeClient)

`ClaudeClient` actor with three entry points: `.classify(model: .haiku)`, `.analyse(model: .sonnet)`, `.reflect(model: .opus)`. Routes through Supabase Edge Functions (keeps API keys off-device). Retry with exponential backoff. Rate-limit awareness per model tier.

- **Files to create:** `Sources/Core/Clients/ClaudeClient.swift`
- **Depends on:** 1.03, 1.04 (needs errors, logging)
- **Acceptance criterion:** `.classify(model: .haiku, prompt: "test")` returns a response; retries on 429 with backoff; rate limit state is queryable

---

### 1.14 — AI Model Router

`AIModelRouter` actor implementing `AIRouter` protocol. Routes `AIRequest` to the appropriate model tier (Haiku/Sonnet/Opus). Manages cross-model rate limiting. Injects core memory buffer into system prompts when `includesCoreMemory: true`. Handles fallback (Haiku -> heuristic, Sonnet -> cached, Opus -> retry 3x then fail).

- **Files to create:** `Sources/Core/Infrastructure/AIModelRouter.swift`
- **Depends on:** 1.10, 1.13 (needs `AIRouter` protocol, `ClaudeClient`)
- **Acceptance criterion:** Router dispatches classification to Haiku, reflection to Opus; fallback fires when primary model is unavailable; rate limit state tracks per-model usage

---

### 1.15 — Privacy abstraction pipeline (PrivacyAbstractor)

`PrivacyAbstractor` service that runs before every LLM API call. Strips PII markers (email addresses, phone numbers, physical addresses) via regex. Replaces proper names with consistent tokens (`[PERSON_1]`, `[PERSON_2]`). Restores tokens in responses. Configurable via `PrivacySettings`.

- **Files to create:** `Sources/Core/Infrastructure/PrivacyAbstractor.swift`
- **Files to modify:** `Sources/Core/Infrastructure/AIModelRouter.swift` (integrate sanitisation pre-call)
- **Depends on:** 1.14
- **Acceptance criterion:** Unit test: input with "John Smith john@example.com" outputs "[PERSON_1] [EMAIL_1]"; round-trip restoration succeeds; sanitiser is called on every `AIRouter.route()` invocation

---

### 1.16 — LLM input sanitiser

`LLMInputSanitiser` with per-source truncation rules: email body max 200 chars with signature/forward stripping, voice transcript structured extraction only, nightly reflection uses `content` field (not raw payloads). Implements the three-tier data classification from privacy-spec.md. `DeviceOnlyData` marker protocol enforced at compile time.

- **Files to create:** `Sources/Core/Infrastructure/LLMInputSanitiser.swift`
- **Depends on:** 1.15
- **Acceptance criterion:** Email body with signature + forwarded content truncates to 200 chars clean; `DeviceOnlyData` types fail to compile if passed to `SyncableRecord` APIs

---

### 1.17 — Jina embedding client

`EmbeddingService` actor implementing `EmbeddingPort`. Calls Jina AI `jina-embeddings-v3` via HTTPS. Returns `[Float]` (1024-dim). Batch endpoint for up to 128 texts per call. Local cache keyed on content hash to avoid re-embedding identical text. Cosine similarity via Accelerate `vDSP`.

- **Files to create:** `Sources/Core/Clients/JinaEmbeddingClient.swift`
- **Depends on:** 1.10 (needs `EmbeddingPort` protocol), 1.03
- **Acceptance criterion:** `.embed("test text")` returns a 1024-dim vector; batch embed of 50 texts returns 50 vectors; cache hit returns identical vector without network call; `cosineSimilarity` of a vector with itself returns 1.0

---

### 1.18 — DataStore dual-write bridge

Bridge existing `DataStore.swift` (JSON persistence) with CoreData. Writes go to both stores during migration period. Reads prefer CoreData, fall back to DataStore. Toggle via `UserDefaults` flag.

- **Files to modify:** `Sources/Core/Services/DataStore.swift`
- **Files to create:** `Sources/Core/Persistence/DualWriteBridge.swift`
- **Depends on:** 1.08
- **Acceptance criterion:** Write a task via bridge; read from CoreData succeeds; read from DataStore succeeds; toggle to CoreData-only mode works without data loss

---

### 1.19 — Foundation test suite

Unit tests covering: CoreData CRUD for every entity, SignalBus throughput, auth flow mocks, API client mocks, embedding round-trip, error hierarchy, DTO serialisation.

- **Files to create:**
  - `Tests/TimedTests/Infrastructure/CoreDataModelTests.swift`
  - `Tests/TimedTests/Infrastructure/SignalBusTests.swift`
  - `Tests/TimedTests/Infrastructure/ClaudeClientTests.swift`
  - `Tests/TimedTests/Infrastructure/EmbeddingServiceTests.swift`
  - `Tests/TimedTests/Infrastructure/PrivacyAbstractorTests.swift`
  - `Tests/TimedTests/Infrastructure/DTOSerializationTests.swift`
- **Depends on:** 1.01 through 1.18
- **Acceptance criterion:** At least 20 unit tests pass; `swift test` succeeds with zero failures

---

## Phase 2: Signal Ingestion

All five signal agents running, observing real data, writing to the signal queue via `SignalWritePort`. The system can "see."

---

### 2.01 — Email signal agent

`EmailSignalAgent` actor implementing `SignalAgent`. Microsoft Graph `Mail.Read` via delta queries. Polls every 60s (configurable). Extracts: sender, subject, timestamp, thread ID, is-reply, importance flag, read/unread, response latency (computed from thread). Classifies email category via Haiku (Do First / Action / Reply / Read / Ignore). Computes derived fields: `responseLatency`, `threadDepth`, `senderFrequency`. Deduplication via `conversationId` + `internetMessageId`. Writes `CDEmailSignal` + `CDSignal` to CoreData.

- **Files to create:** `Sources/Core/Services/Agents/EmailSignalAgent.swift`
- **Files to modify:** `Sources/Core/Services/EmailSyncService.swift` (bridge to new agent architecture)
- **Depends on:** 1.11, 1.12, 1.13, 1.14 (SignalBus, auth, ClaudeClient for Haiku classification, AIRouter)
- **Acceptance criterion:** Agent retrieves real emails from test Outlook account; classifies them into triage buckets; writes `CDEmailSignal` records to CoreData; delta token persists across restarts

---

### 2.02 — Calendar signal agent

`CalendarSignalAgent` actor implementing `SignalAgent`. Microsoft Graph `Calendars.Read` via delta queries. Polls every 120s. Extracts: event metadata, attendees, duration, is-recurring, acceptance status, cancellation. Classifies meeting type via Haiku (Strategic / Operational / 1:1 / External / Admin). Computes: `meetingDensity`, `backToBackDetection`, `gapExtraction`, `overrunFrequency`. Writes `CDCalendarEvent` + `CDSignal`.

- **Files to create:** `Sources/Core/Services/Agents/CalendarSignalAgent.swift`
- **Files to modify:** `Sources/Core/Services/CalendarSyncService.swift` (bridge to new agent architecture)
- **Depends on:** 1.11, 1.12, 1.14
- **Acceptance criterion:** Agent retrieves real calendar events; classifies meeting types; computes gap extraction and density; writes `CDCalendarEvent` records

---

### 2.03 — App focus agent

`AppFocusSignalAgent` actor implementing `SignalAgent`. Observes `NSWorkspace.didActivateApplicationNotification` and `didDeactivateApplicationNotification`. Records: bundle ID, localised app name, timestamp, duration (computed on next switch). Classifies activity type locally (no API call): deep work / shallow work / communication / break / unknown via bundle ID mapping. Minimum session threshold: 2 seconds. Window title capture opt-in, off by default. Writes `CDAppFocusSession` + `CDSignal`.

- **Files to create:** `Sources/Core/Services/Agents/AppFocusSignalAgent.swift`
- **Depends on:** 1.11
- **Acceptance criterion:** Agent records 50+ app switches in a 1-hour test period with correct durations; background-only apps (`.accessory` activation policy) are filtered out; sessions under 2s are discarded

---

### 2.04 — Voice capture agent

Bridges existing `VoiceCaptureService.swift` to `SignalAgent` protocol. Apple Speech (`SFSpeechRecognizer`) on-device only. Captures during: morning session, ad-hoc voice notes (hotkey triggered). Extracts: transcript, word count, speaking pace (WPM), session duration, detected topic keywords. Raw audio is NEVER stored. Writes `CDVoiceSession` + `CDSignal`.

- **Files to create:** `Sources/Core/Services/Agents/VoiceSignalAgent.swift`
- **Files to modify:** `Sources/Core/Services/VoiceCaptureService.swift` (adapt to write via SignalBus)
- **Depends on:** 1.11
- **Acceptance criterion:** Agent captures a 60-second voice session; produces a transcript; writes a `CDVoiceSession` record; no audio data persisted on disk or in memory after signal write

---

### 2.05 — Task signal agent

`TaskSignalAgent` observes internal task system events: task created, completed, deferred, re-prioritised, deleted, viewed, duration recorded. Captures: taskId, sourceType, bucket, estimatedMinutes, actualMinutes, deferralCount, viewDurationMs, viewContext. Feeds Thompson sampling alpha/beta updates and EMA actuals. Writes `CDSignal` with task metadata.

- **Files to create:** `Sources/Core/Services/Agents/TaskSignalAgent.swift`
- **Depends on:** 1.11
- **Acceptance criterion:** Agent captures a task completion event; writes a `CDSignal` record with correct task metadata; Thompson sampling parameters update on completion

---

### 2.06 — Importance classifier (generalised)

`HaikuImportanceClassifier` implementing `ImportanceClassifier` protocol. Classifies signal importance (0.0-1.0) for all signal types, not just email. Prompt template with calibration anchors (1-10 scale normalised to 0-1). Routes through `AIModelRouter` with Haiku tier. Heuristic fallback when Haiku unavailable (keyword + sender matching for email, priority flag for tasks, attendee count for calendar).

- **Files to create:** `Sources/Core/Services/Agents/HaikuImportanceClassifier.swift`
- **Depends on:** 1.14, 1.10
- **Acceptance criterion:** Classifier scores a "Board meeting cancelled" signal > 0.7; scores a "Routine weekly sync" signal < 0.4; heuristic fallback produces reasonable scores without API call

---

### 2.07 — Agent coordinator and health monitor

`AgentCoordinator` actor. Starts/stops all signal agents. Health monitoring: each agent reports heartbeat every 60s. Stalled agents (3 missed heartbeats) get restarted. Status queryable for menu bar display. Resource budget enforcement: if an agent exceeds 5% CPU sustained for 30s, pause for 5 minutes (circuit breaker).

- **Files to create:** `Sources/Core/Services/Agents/AgentCoordinator.swift`
- **Depends on:** 2.01, 2.02, 2.03, 2.04, 2.05
- **Acceptance criterion:** Coordinator starts all 5 agents; health monitor shows all healthy; simulated stalled agent (stop sending heartbeats) triggers restart after 3 missed beats

---

### 2.08 — Background execution infrastructure

Login Item registration via `SMAppService`. App Nap mitigation via `NSProcessInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled])`. Process info activity for each agent polling cycle.

- **Files to create:** `Sources/Core/Infrastructure/BackgroundExecutionManager.swift`
- **Depends on:** 2.07
- **Acceptance criterion:** App registered as login item; background activity token active during agent polling; App Nap does not pause agents during idle periods

---

### 2.09 — Sleep/wake reconciliation

On `NSWorkspace.willSleepNotification`: persist agent state, flush signal queue. On `didWakeNotification`: trigger catch-up delta queries for email + calendar (fetch changes since last sync timestamp). Throttle catch-up: max 50 items per batch, 500ms delay between batches.

- **Files to create:** `Sources/Core/Infrastructure/SleepWakeReconciler.swift`
- **Depends on:** 2.01, 2.02, 2.07
- **Acceptance criterion:** Put Mac to sleep for 5 minutes; wake; email/calendar agents catch up without data loss; no CPU spike above 15% during catch-up

---

### 2.10 — Signal ingestion test suite

Tests for: email signal parsing (recorded Graph JSON), calendar signal parsing, delta sync token handling, computed field derivation (responseLatency, threadDepth, meetingDensity, backToBack), privacy filtering (no attachment binaries, body truncation), malformed response handling, app focus session tracking, voice transcript extraction, task signal capture, agent health monitoring, sleep/wake reconciliation.

- **Files to create:**
  - `Tests/TimedTests/Layer1/EmailSignalAgentTests.swift`
  - `Tests/TimedTests/Layer1/CalendarSignalAgentTests.swift`
  - `Tests/TimedTests/Layer1/AppFocusAgentTests.swift`
  - `Tests/TimedTests/Layer1/VoiceSignalAgentTests.swift`
  - `Tests/TimedTests/Layer1/TaskSignalAgentTests.swift`
  - `Tests/TimedTests/Layer1/AgentCoordinatorTests.swift`
  - `Tests/TimedTests/Layer1/ImportanceClassifierTests.swift`
- **Depends on:** 2.01 through 2.09
- **Acceptance criterion:** At least 30 unit tests + 5 integration tests pass; 90% line coverage on Layer 1

---

## Phase 3: Memory

Three memory tiers operational with embedding-based retrieval. The system can "remember."

---

### 3.01 — Episodic memory store

`EpisodicMemoryStore` actor implementing `EpisodicMemoryReadPort` + relevant `MemoryWritePort` methods. Create from any `Signal`. Read with filtering (time range, source modality, importance threshold). Update access count + `lastAccessedAt` on every retrieval. Embed content at write time via `EmbeddingService`. Mark consolidated without deleting. Retention: keep all for 90 days, then archive (move embedding to archival tier, keep metadata).

- **Files to create:** `Sources/Core/Services/Memory/EpisodicMemoryStore.swift`
- **Depends on:** 1.08, 1.17, 1.10
- **Acceptance criterion:** Write 100 episodic memories from test signals; retrieve top-10 by time range; `lastAccessedAt` updates on retrieval; consolidation flag persists; store survives app restart

---

### 3.02 — Semantic memory store

`SemanticMemoryStore` actor implementing relevant `MemoryWritePort` methods. Create from reflection engine output. Key-value structure with confidence score (0.0-1.0). Categories: `work_style`, `preferences`, `relationships`, `avoidance_patterns`, `energy`, `decision_making`. Reinforce: increment count + update confidence + update `lastReinforcedAt`. Contradict: flag conflict for reflection engine resolution. Decay: confidence -= 0.01 per week without reinforcement (floor: 0.1). Deactivation threshold: confidence < 0.3 after contradictionCount >= 3.

- **Files to create:** `Sources/Core/Services/Memory/SemanticMemoryStore.swift`
- **Depends on:** 1.08, 1.17, 1.10
- **Acceptance criterion:** Create a fact; reinforce 5 times; verify confidence increases; advance clock 4 weeks; verify confidence decreased by ~0.04; contradict a fact; verify contradictionCount increments

---

### 3.03 — Procedural memory store

`ProceduralMemoryStore` actor implementing relevant `MemoryWritePort` methods. Create from reflection engine output. Fields: rule text, confidence, activation count, success/failure counts, trigger conditions (`TriggerCondition` array), action (`RuleAction`), exceptions. Activate: log activation, increment count. Deactivate: status -> `fading` after 30 days without activation. Archive: status -> `archived` after 90 days. Source attribution: links to reflection cycle + pattern IDs. Contradiction detection: flag conflicting rules, never silently override.

- **Files to create:** `Sources/Core/Services/Memory/ProceduralMemoryStore.swift`
- **Depends on:** 1.08, 1.10
- **Acceptance criterion:** Create a rule; activate 3 times; verify activation count; leave untouched 30 simulated days; verify status is `fading`; inject two conflicting rules; both flagged

---

### 3.04 — Core memory manager

`CoreMemoryManager` actor. MemGPT-style fixed-size buffer (50 entries max, ~4,000 tokens). Each entry: content string (max 500 chars), priority rank, `lastUpdated`, source memory ID. Promotion: semantic fact with confidence > 0.8 and reinforcement count > 5 is a candidate. Demotion: lowest-priority entry evicted when buffer is full and a higher-priority candidate arrives. Serialisation: produces XML-like `<core_memory>` document for injection into every Opus/Sonnet system prompt. Sections: identity, priorities, relationships, patterns, rules, self-model.

- **Files to create:** `Sources/Core/Services/Memory/CoreMemoryManager.swift`
- **Depends on:** 1.08, 3.02 (reads semantic memory for promotion candidates)
- **Acceptance criterion:** Fill to 50 entries; add a higher-priority candidate; verify lowest-priority entry evicted; serialised output is under 4,000 tokens; round-trip: serialise -> deserialise preserves all entries

---

### 3.05 — Memory retrieval engine

`MemoryRetrievalEngine` actor. Three-axis scoring: `recency(m) = 0.995 ^ hours_since_access(m)`, `importance(m) = m.importanceScore`, `relevance(m, q) = cosine_similarity(embed(m), embed(q))`. Composite: `score = w_recency * recency + w_importance * importance + w_relevance * relevance`. Default weights: `(0.2, 0.3, 0.5)`. Returns top-K results (default K=20) with scores. Supports per-query weight overrides. Searches across all three memory tiers.

- **Files to create:** `Sources/Core/Services/Memory/MemoryRetrievalEngine.swift`
- **Depends on:** 3.01, 3.02, 3.03, 1.17
- **Acceptance criterion:** Given 500 episodic memories with known properties, a query about "Monday meetings" returns Monday meeting memories ranked highest; top-10 retrieval under 200ms for 10,000 memories; per-query weight overrides change result ordering

---

### 3.06 — Vector search (Accelerate framework)

On-device vector search using Accelerate framework `vDSP` for cosine similarity. Embeddings stored as `Data` (binary) on CoreData entities via `EmbeddingVectorTransformer`. At query time: load candidate embeddings, compute cosine similarity, return top-K. Performance target: <200ms for 10,000 memories.

- **Files to create:** `Sources/Core/Services/Memory/VectorSearchEngine.swift`
- **Depends on:** 1.07, 1.17
- **Acceptance criterion:** Benchmark: 10,000 embeddings, top-20 query in <200ms; cosine similarity of identical vectors returns 1.0; orthogonal vectors return 0.0

---

### 3.07 — User profile service

`UserProfileService` implementing `UserProfilePort`. Manages `CDUserProfile` singleton. Exposes: current profile, energy curve (24 hourly weights), chronotype, archetype, core memory buffer access. Energy curve initialized from archetype defaults, refined by chronotype model.

- **Files to create:** `Sources/Core/Services/Intelligence/UserProfileService.swift`
- **Depends on:** 1.08, 1.10
- **Acceptance criterion:** Profile singleton creates on first access; energy curve returns 24 Float values; profile persists across app restart

---

### 3.08 — Chronotype inference model

Infers executive's cognitive performance curve from observed behaviour. Tracks per-task-type performance by time-of-day. Inputs: app focus sessions (productive vs shallow), task completion velocity by hour, email response quality/speed by hour, focus session durations. Outputs: 24-hour performance curve per task type (analytical, creative, interpersonal, administrative). Bayesian update from daily observations. Updates semantic memory with chronotype facts.

- **Files to create:** `Sources/Core/Services/Intelligence/ChronotypeModel.swift`
- **Depends on:** 3.01, 3.02, 3.07
- **Acceptance criterion:** After 14 simulated days of data, model produces a non-uniform energy curve; peak hours differ between analytical and creative task types; curve persists as semantic memory

---

### 3.09 — Cognitive load proxy model

Real-time cognitive load estimation from digital signals. Inputs: email response latency vs baseline, app-switch rate, meeting density (cumulative), calendar gap availability, focus session interruption rate. Output: cognitive load score (0.0-1.0) with trend direction. Used to gate task recommendations and detect overload.

- **Files to create:** `Sources/Core/Services/Intelligence/CognitiveLoadModel.swift`
- **Depends on:** 3.01, 2.01, 2.02, 2.03
- **Acceptance criterion:** Load score increases after 3 consecutive meetings; decreases after 30-minute gap with no context switches; score is queryable in real-time

---

### 3.10 — Relationship health scorer

Per-contact model of every professional relationship. Continuous health score per contact. Inputs per contact: response latency trend, email frequency, email length/formality changes, meeting frequency, calendar co-attendance, pronoun usage shifts. Output: relationship health score (0-100), trend (improving/stable/deteriorating), last contact date, recommended action cadence. Surfaces relationship intelligence as semantic memories.

- **Files to create:** `Sources/Core/Services/Intelligence/RelationshipScorer.swift`
- **Depends on:** 3.01, 3.02, 2.01, 2.02
- **Acceptance criterion:** Given 30 days of simulated email + calendar data for 10 contacts, scorer produces distinct health scores; a contact with declining response times shows "deteriorating" trend

---

### 3.11 — Thompson sampling integration (Layer 2 bridge)

Bridge existing `PlanningEngine.swift` Thompson sampling to CoreData. Persist `TaskCategoryPrior` (alpha/beta per category) as CoreData entities (using `@objc(CD...)`, not `@Model`). Map 20-category taxonomy to cold-start 6-category archetypes with translation functions. Update alpha/beta from task signal agent completions.

- **Files to create:** `Sources/Core/Models/CDTaskCategoryPrior.swift`
- **Files to modify:** `Sources/Core/Services/PlanningEngine.swift` (read/write priors from CoreData)
- **Depends on:** 1.08, 2.05
- **Acceptance criterion:** Priors persist across app restart; completion of a `strategicPlanning` task updates the correct prior; cold-start archetype maps to all 20 categories

---

### 3.12 — EMA estimation integration (Layer 2 bridge)

Bridge existing EMA time estimation to CoreData. Persist per-category EMA values as CoreData entities. Alpha = 0.3 (reconciled operational value with cold-start schedule: 0.5 day 1 -> 0.4 days 2-7 -> 0.35 days 8-14 -> 0.3 day 15+). Confidence band: `[EMA * 0.7, EMA * 1.4]`.

- **Files to create:** `Sources/Core/Models/CDEMAEstimate.swift`
- **Files to modify:** `Sources/Core/Services/DataStore.swift` (EMA read/write via CoreData)
- **Depends on:** 1.08, 2.05
- **Acceptance criterion:** EMA values persist; completion of a task updates the correct category EMA; confidence band computed correctly; cold-start alpha schedule transitions correctly

---

### 3.13 — Supabase real-time subscriptions

Subscribe to `email_messages` and `tasks` Supabase tables for real-time updates from Edge Functions. On change: update local CoreData, emit signal if new data detected.

- **Files to modify:** `Sources/Core/Clients/SupabaseClient.swift`
- **Depends on:** 1.12
- **Acceptance criterion:** Real-time subscription connected; Edge Function email classification update reflected in local CoreData within 5 seconds

---

### 3.14 — Memory store test suite

Tests for: episodic CRUD + retrieval scoring, semantic reinforcement + decay + contradiction, procedural lifecycle (create -> activate -> fading -> archived), core memory buffer management (eviction, serialisation), retrieval engine accuracy (synthetic test set with known correct rankings), vector search benchmarks, consolidation logic, chronotype model convergence, cognitive load scoring, relationship scorer trend detection.

- **Files to create:**
  - `Tests/TimedTests/Layer2/EpisodicMemoryStoreTests.swift`
  - `Tests/TimedTests/Layer2/SemanticMemoryStoreTests.swift`
  - `Tests/TimedTests/Layer2/ProceduralMemoryStoreTests.swift`
  - `Tests/TimedTests/Layer2/CoreMemoryManagerTests.swift`
  - `Tests/TimedTests/Layer2/MemoryRetrievalEngineTests.swift`
  - `Tests/TimedTests/Layer2/VectorSearchBenchmarkTests.swift`
  - `Tests/TimedTests/Layer2/ChronotypeModelTests.swift`
  - `Tests/TimedTests/Layer2/CognitiveLoadModelTests.swift`
  - `Tests/TimedTests/Layer2/RelationshipScorerTests.swift`
- **Depends on:** 3.01 through 3.13
- **Acceptance criterion:** At least 40 unit tests + 10 integration tests pass; 85% line coverage on Layer 2

---

## Phase 4: Reflection

Nightly Opus reflection cycle running, producing patterns, rules, and model updates. The system can "think." This is the intelligence bootstrap milestone.

---

### 4.01 — Reflection scheduler

`ReflectionScheduler` using `NSBackgroundActivityScheduler`. Triggers nightly at 02:00 local time (configurable). Weekly consolidation Sunday 03:00. Manual trigger via command palette. Checks preconditions: minimum 10 new signals since last reflection, system not in low-power mode, API reachable.

- **Files to create:** `Sources/Core/Services/Reflection/ReflectionScheduler.swift`
- **Depends on:** 1.08, 1.14
- **Acceptance criterion:** Scheduler fires at configured time; skips if fewer than 10 signals; manual trigger from command palette works; precondition failure logs reason

---

### 4.02 — Reflection prompt templates

All 6 stage prompt templates stored as Swift string constants in `ReflectionPrompts.swift`. Each template: system prompt (core memory + executive profile + processing instructions), user prompt (stage-specific input data), output JSON schema (structured expected output), few-shot examples. Versioned alongside code. Stages: episodic_summarisation, first_order_extraction, second_order_synthesis, rule_generation, model_update, morning_session_script.

- **Files to create:** `Sources/Core/Services/Reflection/ReflectionPrompts.swift`
- **Depends on:** 3.04 (core memory serialisation format)
- **Acceptance criterion:** All 6 templates compile; JSON output schemas parse into Swift structs; system prompts include core memory injection point

---

### 4.03 — Reflection prompt builder

`ReflectionPromptBuilder` assembles prompts for each stage. Injects: core memory buffer, executive profile, episodic memories (for Stage 1), pattern library (for Stages 2-3), existing rules (for Stage 4), semantic model (for Stage 3). Respects context window limits -- selects top-K memories by retrieval score if full set exceeds budget.

- **Files to create:** `Sources/Core/Services/Reflection/ReflectionPromptBuilder.swift`
- **Depends on:** 4.02, 3.04, 3.05, 3.07
- **Acceptance criterion:** Builder produces prompts for all 6 stages; total input tokens for Stage 3 (largest) stay under 40K; core memory is present in every prompt's system message

---

### 4.04 — Stage 1: Episodic summarisation

Retrieves today's episodic memories (last 24h). Groups by context (meeting cluster, email thread, focus session, app usage block). Summarises each group via Opus. Output: 10-30 day-level summaries with themes tagged. Estimated: 5K-15K input tokens, 2K-4K output tokens.

- **Files to create:** `Sources/Core/Services/Reflection/Stages/EpisodicSummariser.swift`
- **Depends on:** 4.03, 3.01, 1.14
- **Acceptance criterion:** Given 50 synthetic episodic memories, produces at least 5 coherent summaries; output parses into `[EpisodicSummary]` struct array; themes are tagged

---

### 4.05 — Stage 2: First-order pattern extraction

Takes Stage 1 summaries + recent episodic history (past 7 days). Opus extracts observable first-order patterns using the 28-archetype pattern library from named-patterns.md as vocabulary. Pattern taxonomy: temporal (5 subtypes), behavioural (4 subtypes), relational (4 subtypes), cognitive (4 subtypes), avoidance (7 archetypes). Each pattern: evidence references, evidence count, confidence, classification. Output: `[FirstOrderPattern]`.

- **Files to create:** `Sources/Core/Services/Reflection/Stages/FirstOrderExtractor.swift`
- **Depends on:** 4.03, 4.04
- **Acceptance criterion:** Given Stage 1 output from 50 memories, extracts at least 3 patterns; each pattern has 2+ evidence references; patterns are classified into the taxonomy

---

### 4.06 — Stage 3: Second-order insight synthesis

Takes Stage 2 patterns + existing semantic model + existing pattern library. Opus at maximum effort. Cross-references new patterns with historical model via correlation matrix (Calendar x Email x Task x Focus x Voice x Behaviour). Generates named insights with evidence chains and confidence scores. Detects model corrections (previously stored facts that are wrong). Output: `[SecondOrderInsight]` + candidate rules + semantic memory updates + model corrections.

- **Files to create:** `Sources/Core/Services/Reflection/Stages/SecondOrderSynthesiser.swift`
- **Depends on:** 4.03, 4.05, 3.02
- **Acceptance criterion:** Given Stage 2 patterns, produces at least 1 named insight with evidence chain of 2+ first-order patterns; confidence score is present; model corrections flag contradictions

---

### 4.07 — Stage 4: Rule generation

Takes Stage 3 insights + existing procedural rules. Opus proposes new IF-THEN rules or updates existing ones. Rule schema: trigger conditions, context conditions, recommendation, confidence, evidence summary. Contradiction detection: new rule conflicting with existing rule flags both. Rules are observation/recommendation only -- never actions.

- **Files to create:** `Sources/Core/Services/Reflection/Stages/RuleGenerator.swift`
- **Depends on:** 4.03, 4.06, 3.03
- **Acceptance criterion:** Given Stage 3 insights, produces at least 1 new procedural rule; rule parses into `ProceduralRule` schema; contradiction detection flags conflicting rules

---

### 4.08 — Stage 5: Model update (deterministic)

Writes all reflection outputs to Layer 2. No LLM call -- this stage is deterministic. Creates: new semantic facts via `SemanticMemoryStore`, updated procedural rules via `ProceduralMemoryStore`, new/updated patterns, core memory buffer adjustments via `CoreMemoryManager`. Creates model version snapshot: serialise current semantic model + procedural rules + pattern library to a versioned JSON blob stored in CoreData.

- **Files to create:** `Sources/Core/Services/Reflection/Stages/ModelUpdater.swift`
- **Depends on:** 4.07, 3.01, 3.02, 3.03, 3.04
- **Acceptance criterion:** All Stage 4 outputs written to memory stores; model version snapshot is loadable and diff-able against previous version; core memory buffer reflects new facts

---

### 4.09 — Stage 6: Intelligence preparation

Selects insights, patterns, and alerts worth surfacing in tomorrow's morning session. Priority ranking: new confirmed patterns > contradictions detected > pattern violations > routine observations. Compiles `MorningBrief` payload: opening insight, named patterns, task plan recommendations, proactive alerts, one targeted question for active preference elicitation.

- **Files to create:** `Sources/Core/Services/Reflection/Stages/IntelligencePreparator.swift`
- **Depends on:** 4.08
- **Acceptance criterion:** Produces `MorningBrief` with at least: 1 opening insight, 1 named pattern, 1 proactive alert, 1 question; cached as local JSON for morning session

---

### 4.10 — Nightly reflection orchestrator

`NightlyReflectionOrchestrator` actor implementing `ReflectionEngine` protocol. Runs the 6-stage pipeline sequentially. Handles per-stage failures (partial results saved -- if Stage 3 fails, Stages 1-2 outputs are saved and next run can resume). Writes `CDReflectionRun` record with metadata: start/end time, stage reached, signal count processed, token counts, model version produced, cost estimate.

- **Files to create:** `Sources/Core/Services/Reflection/NightlyReflectionOrchestrator.swift`
- **Depends on:** 4.01 through 4.09
- **Acceptance criterion:** Orchestrator runs end-to-end with synthetic data (50 episodic memories); all 6 stages complete; `CDReflectionRun` record saved with accurate metadata; partial failure: kill API mid-Stage 3, verify Stages 1-2 saved

---

### 4.11 — Reflection quality self-assessment

After Stage 3, Opus rates its own reflection: `confidence: high/medium/low`, `signal_richness: sparse/adequate/rich`, `novel_findings: count`. Logged in `CDReflectionRun`. Used to adjust future reflection depth (sparse signal days get shorter reflections -- skip Stage 3 deep synthesis if fewer than 20 episodic memories).

- **Files to modify:** `Sources/Core/Services/Reflection/Stages/SecondOrderSynthesiser.swift`
- **Files to modify:** `Sources/Core/Services/Reflection/NightlyReflectionOrchestrator.swift`
- **Depends on:** 4.06, 4.10
- **Acceptance criterion:** Quality assessment is present in every reflection run; sparse days (< 20 memories) produce shorter reflections; assessment logged in `CDReflectionRun`

---

### 4.12 — Pattern lifecycle manager

`PatternLifecycleManager`. Patterns have states: `emerging` (seen 1-2 times) -> `confirmed` (seen 3+ times with consistent evidence) -> `fading` (no new evidence in 14 days) -> `archived` (no new evidence in 60 days). Confirmed patterns eligible for rule generation. Fading patterns trigger "is this still true?" check in next reflection. Status transitions logged.

- **Files to create:** `Sources/Core/Services/Intelligence/PatternLifecycleManager.swift`
- **Depends on:** 1.08, 3.01
- **Acceptance criterion:** Inject a pattern; confirm it (3 evidence points); leave it 14 simulated days; verify status transitions to `fading`; leave it 60 days; verify `archived`

---

### 4.13 — Avoidance pattern detector

Detects avoidance vs rational deprioritisation. Signals: repeated deferral without context change, engagement without completion (viewing but not acting), category affinity (people decisions, confrontational emails, ambiguous strategic choices), substitution behaviour (low-value tasks performed instead of deferred high-value ones). Outputs: avoidance patterns as `FirstOrderPattern` with avoidance-specific archetype classification (7 archetypes from named-patterns.md: task avoidance, conversation avoidance, decision avoidance, feedback avoidance, delegation avoidance, confrontation avoidance, ambiguity avoidance).

- **Files to create:** `Sources/Core/Services/Intelligence/AvoidanceDetector.swift`
- **Depends on:** 3.01, 3.02, 2.05
- **Acceptance criterion:** Given a task deferred 4 times over 10 days with no blocking dependencies and lower-priority tasks being completed, detector flags avoidance; rational single deferral with context change is NOT flagged

---

### 4.14 — Memory consolidation engine

`MemoryConsolidationEngine` actor. Runs after every nightly reflection. Episodic -> semantic promotion: 3+ episodic memories with cosine similarity > 0.75 within 30 days generate a semantic fact (Condition A). Reflection engine explicit extraction (Condition B). High-confidence single event with importance >= 0.8 (Condition C). Semantic -> procedural: fact confirmed by 5+ observations becomes rule candidate. Duplicate detection: new fact checked against existing facts (cosine similarity > 0.85). Episodic memories get `consolidated = true` but are NOT deleted.

- **Files to create:** `Sources/Core/Services/Memory/MemoryConsolidationEngine.swift`
- **Depends on:** 3.01, 3.02, 3.03, 3.05
- **Acceptance criterion:** Inject 5 episodic memories about the same pattern; run consolidation; verify a semantic fact was generated; original episodic memories still exist with `consolidated = true`; duplicate fact with cosine similarity > 0.85 merges rather than duplicates

---

### 4.15 — Triggered reflection

`TriggeredReflectionService`. Fires for: importance > 0.9 signals, user corrections (explicit "that's wrong" feedback), pattern contradictions. Runs a lightweight reflection (Stages 2-4 only, scoped to the triggering event + recent context). Opus at max effort. Defers to nightly if Opus unavailable.

- **Files to create:** `Sources/Core/Services/Reflection/TriggeredReflectionService.swift`
- **Depends on:** 4.10, 3.05
- **Acceptance criterion:** High-importance signal (0.95) triggers reflection within 60 seconds; user correction creates an episodic memory + triggers reflection; output updates relevant semantic/procedural memories

---

### 4.16 — Reflection test suite

Tests for: each reflection stage in isolation (mock inputs -> verify outputs), pattern lifecycle transitions, contradiction detection, model versioning and snapshot comparison, prompt template JSON schema validation, partial failure recovery, quality self-assessment, avoidance detection, consolidation logic. Integration tests use real Opus API calls against synthetic data.

- **Files to create:**
  - `Tests/TimedTests/Layer3/EpisodicSummariserTests.swift`
  - `Tests/TimedTests/Layer3/FirstOrderExtractorTests.swift`
  - `Tests/TimedTests/Layer3/SecondOrderSynthesiserTests.swift`
  - `Tests/TimedTests/Layer3/RuleGeneratorTests.swift`
  - `Tests/TimedTests/Layer3/ModelUpdaterTests.swift`
  - `Tests/TimedTests/Layer3/ReflectionOrchestratorTests.swift`
  - `Tests/TimedTests/Layer3/PatternLifecycleTests.swift`
  - `Tests/TimedTests/Layer3/AvoidanceDetectorTests.swift`
  - `Tests/TimedTests/Layer3/ConsolidationEngineTests.swift`
- **Depends on:** 4.01 through 4.15
- **Acceptance criterion:** At least 25 unit tests + 10 integration tests pass; 60% line coverage on Layer 3

---

### 4.17 — Intelligence bootstrap validation (3-day live test)

Run the system for 3 consecutive days with real data (developer's own Mac). Validate:
- At least 5 named patterns about the developer's behaviour
- At least 2 procedural rules exist
- Morning brief for Day 3 references observations from Days 1-2
- Model version diff between Day 1 and Day 3 shows growth

This is a gate. If this fails, the architecture has a fundamental problem. Stop and diagnose before Phase 5.

- **Files to create:** None (manual validation)
- **Depends on:** 4.01 through 4.16
- **Acceptance criterion:** All four validation points met after 3 days of real use

---

## Phase 5: Intelligence Delivery

The executive sees and interacts with the intelligence. Morning session, menu bar, alerts, focus timer, query interface, day plan. The system can "speak."

---

### 5.01 — Morning director service

`MorningDirectorService` implementing `MorningDirector` protocol. Opus-powered morning briefing. Reads: `MorningBrief` from overnight reflection, core memory buffer, recent patterns, today's calendar, pending tasks + Thompson scores, executive profile. Generates `MorningBriefing` struct: opening insight (most significant named pattern), today plan with reasoning, avoidance warning, energy guidance, proactive alerts, one targeted question for preference elicitation.

- **Files to create:** `Sources/Core/Services/Intelligence/MorningDirectorService.swift`
- **Depends on:** 4.09, 3.04, 3.07, 1.14
- **Acceptance criterion:** Given a `MorningBrief` payload, produces a `MorningBriefing` with all required fields; opening insight references a named pattern; plan items include natural-language reasoning

---

### 5.02 — Morning intelligence session UI redesign

Redesign existing morning session UI in `Features/MorningInterview/`. Opens with the top named pattern, not a task list. Flow: (1) Named pattern + evidence presented visually, (2) Opus asks one targeted question via voice, (3) Executive responds (voice captured by `VoiceSignalAgent`), (4) Opus synthesises response + plan, (5) Day plan displayed with per-slot reasoning. First-ever session (no patterns yet) degrades gracefully to calendar-based observations.

- **Files to modify:** `Sources/Features/MorningInterview/` (all files)
- **Depends on:** 5.01, 2.04
- **Acceptance criterion:** Morning session launches with a named pattern; voice question plays; voice response captured; day plan rendered with reasoning per slot; first-use graceful degradation works

---

### 5.03 — Morning session voice interaction

Implement the chief-of-staff voice personality from morning-voice.md. Declarative sentences, specific citations (numbers, dates, names), no filler phrases, warmth without performance, adaptive length. Pre-generated session cached as local JSON from Stage 6. Voice synthesis via `AVSpeechSynthesizer` with `en-AU` locale. Name parameterised from user profile, not hardcoded.

- **Files to create:** `Sources/Core/Services/Intelligence/MorningVoiceEngine.swift`
- **Files to modify:** `Sources/Features/MorningInterview/` (voice playback integration)
- **Depends on:** 5.02, 3.07
- **Acceptance criterion:** Voice plays with en-AU locale; executive's name read from profile not hardcoded; session cached from overnight reflection; voice adapts: shorter when executive is curt

---

### 5.04 — Day plan generation

Replaces existing static day plan. Inputs: morning session voice response, today's calendar, task list with Thompson scores, procedural rules about scheduling, energy curve model, core memory, EMA duration estimates. Opus generates time-slotted plan with per-task explanations ("Board deck at 10am because your analytical peak data supports it"). Uses upper confidence bound of EMA for slot allocation to prevent optimistic packing. 75% utilisation cap. Meeting buffer rules.

- **Files to create:** `Sources/Core/Services/Intelligence/DayPlanGenerator.swift`
- **Files to modify:** `Sources/Core/Services/PlanningEngine.swift`, `Sources/Core/Services/TimeSlotAllocator.swift`
- **Depends on:** 5.01, 3.08, 3.11, 3.12
- **Acceptance criterion:** Plan assigns tasks to time slots with natural-language reasoning; strategic work placed in measured peak analytical window; 75% utilisation cap respected; upper EMA bound used for duration

---

### 5.05 — Menu bar intelligence widget redesign

Redesign existing menu bar in `Features/MenuBar/`. Three sections at Check level: Now (current task + focus state + cognitive load indicator), Next (upcoming commitment + prep needed from procedural rules), Insight (one rotating pattern-based observation from confirmed patterns). Three zoom levels: Glance (1-3 words), Check (10-second summary), Dive (full detail on patterns/tasks/alerts). Updated every 5 minutes from Layer 2 queries. Badge for unread alerts.

- **Files to modify:** `Sources/Features/MenuBar/` (all files)
- **Depends on:** 3.09, 4.12, 3.05
- **Acceptance criterion:** Menu bar shows Now/Next/Insight correctly; updates without user intervention; click expands to popover with three sections; badge appears for unread alerts; Insight rotates between confirmed patterns

---

### 5.06 — Proactive alert system

`ProactiveAlertManager` implementing `AlertEngine` protocol. Triggers on: confirmed pattern violation, approaching deadline with insufficient progress, significant pattern change, energy curve anomaly, relationship health deterioration. Interrupt-value equation: `AlertValue = (Severity x TimeSensitivity x Confidence) / UserCost`. Delivery threshold: > 0.6. Budget: maximum 3 alerts per day. Priority queue: only highest-value alerts fire. Context-aware cost: focus timer active = 5x cost, meeting = 3x, idle = 0.5x. Dismissal is a signal fed back to Layer 1. Seven alert types from architecture.md.

- **Files to create:** `Sources/Core/Services/Intelligence/ProactiveAlertManager.swift`
- **Depends on:** 4.12, 3.09, 3.10, 2.02
- **Acceptance criterion:** Alert fires on confirmed pattern violation; budget enforced: simulate 10 alert-worthy events, verify only 3 fire; dismissal creates a signal in Layer 1; focus timer active suppresses low-value alerts

---

### 5.07 — Focus timer Layer 4 integration

Bridge existing focus timer in `Features/Focus/` to Layer 4. On completion: writes focus session data to Layer 2 (actual duration, interruption count, app-switch log, session quality score, completion status). Layer 4 intelligence overlay: shows trend observation ("Average focus session 32min this week, down from 41 last week"). Feeds EMA model, energy curve model, chronotype inference.

- **Files to modify:** `Sources/Features/Focus/` (completion handler, intelligence overlay)
- **Depends on:** 3.01, 3.08, 3.12
- **Acceptance criterion:** Focus timer completion writes `CDFocusSession` + `CDCompletionRecord` to CoreData; EMA updates on completion; intelligence overlay shows trend when 5+ sessions recorded

---

### 5.08 — Query interface

Natural language query via command palette (`Cmd+K`). Classification by Haiku into query types: factual, pattern, comparison, relationship, temporal, procedural, hypothetical, meta. Routes to Sonnet with relevant memories retrieved via `MemoryRetrievalEngine` (top-20 by relevance). Response displayed inline in command palette. Supports follow-up questions within session. Query is an episodic memory (logged to Layer 1). Minimum 3 words, maximum 500 characters.

- **Files to create:** `Sources/Core/Services/Intelligence/QueryEngine.swift`
- **Files to modify:** `Sources/Features/CommandPalette/` (add query mode)
- **Depends on:** 3.05, 1.14
- **Acceptance criterion:** "Why did you rank task X first?" returns a response referencing Thompson sampling scores and procedural rules; response under 3 seconds; query logged as episodic memory

---

### 5.09 — Active preference elicitation

One targeted question per morning session to actively learn preferences during cold-start period (days 1-14) and ongoing (1 question per session maximum). Question selection based on information value: asks about areas with lowest model confidence. Response parsed and stored as high-confidence semantic fact (importance >= 0.8, explicit declaration).

- **Files to create:** `Sources/Core/Services/Intelligence/PreferenceElicitor.swift`
- **Depends on:** 5.01, 3.02
- **Acceptance criterion:** First morning session includes a preference question; response creates a semantic fact with `contains_explicit_declaration: true`; question selection avoids re-asking about high-confidence areas

---

### 5.10 — Supabase nightly sync

Push local memory state to Supabase after nightly reflection: episodic (metadata + embeddings, NOT raw content for Tier 1 data), semantic, procedural, patterns, profile. Pull: pending Edge Function results (email classifications). Archive: episodic memories older than 90 days with 0 access -> Supabase pgvector (keep embedding, drop CoreData record).

- **Files to create:** `Sources/Core/Services/SyncService.swift`
- **Depends on:** 1.12, 3.01, 3.02, 3.03, 4.10
- **Acceptance criterion:** Nightly sync pushes all memory tiers; Tier 1 data (raw email bodies, voice transcripts) never transmitted; pgvector archival works; pull retrieves pending classifications

---

### 5.11 — Intelligence delivery test suite

Tests for: morning session flow with mock `MorningBrief`, menu bar rendering with mock data, alert trigger logic and budget enforcement, query routing and response quality, day plan generation with known inputs, preference elicitation question selection, focus timer completion data flow.

- **Files to create:**
  - `Tests/TimedTests/Layer4/MorningDirectorTests.swift`
  - `Tests/TimedTests/Layer4/ProactiveAlertTests.swift`
  - `Tests/TimedTests/Layer4/QueryEngineTests.swift`
  - `Tests/TimedTests/Layer4/DayPlanGeneratorTests.swift`
  - `Tests/TimedTests/Layer4/PreferenceElicitorTests.swift`
- **Depends on:** 5.01 through 5.10
- **Acceptance criterion:** At least 20 unit tests + 5 integration tests pass; 70% line coverage on Layer 4

---

## Phase 6: Polish

Cold start, onboarding, settings, model versioning, intelligence reports, distribution. The system is ready for Yasser.

---

### 6.01 — Cold start strategy implementation

`ColdStartService`. Archetype picker at onboarding pre-loads scoring weights for all 20 Thompson categories, chronotype default curve, and EMA priors. Five archetypes: CEO, COO, CFO, CTO, Creative Director. Calendar history bootstrap: import 90 days of Outlook calendar history via Graph to infer meeting patterns, key contacts, chronotype indicators, recurring commitments on Day 1. EMA alpha schedule: 0.5 (day 1) -> 0.4 (days 2-7) -> 0.35 (days 8-14) -> 0.3 (day 15+). First morning session acknowledges learning state with confidence qualifiers.

- **Files to create:** `Sources/Core/Services/Intelligence/ColdStartService.swift`
- **Depends on:** 2.02, 3.07, 3.08, 3.11, 3.12, 5.01
- **Acceptance criterion:** Archetype selected at onboarding; 90-day calendar imported; first morning session runs with calendar-inferred observations within 24 hours; Thompson priors reflect archetype

---

### 6.02 — Onboarding flow redesign

Redesign existing `Features/Onboarding/` for intelligence layer. 8 steps under 5 minutes: (1) Welcome + privacy explanation, (2) Privacy detail (three-tier classification), (3) Microsoft sign-in (MSAL OAuth), (4) Permission requests (Accessibility for app focus, Microphone for voice), (5) Archetype selection (30 seconds), (6) Calendar import progress, (7) First signal ingestion confirmation, (8) "I'm watching. First intelligence report in 24 hours." No tutorial. No feature tour. Progressive disclosure only.

- **Files to modify:** `Sources/Features/Onboarding/` (all files)
- **Depends on:** 1.12, 6.01
- **Acceptance criterion:** Fresh install: onboarding completes in under 3 minutes; permissions granted; auth completed; archetype selected; calendar import initiated; "watching" confirmation displayed

---

### 6.03 — Settings and preferences panel

Redesign existing `Features/Prefs/`. Configurable: morning session time (5-10 AM, 15-min increments), polling intervals, alert frequency cap (0-5 per day), Do Not Disturb schedule, voice capture toggle, window title tracking (opt-in, off by default), reflection schedule time, active signal sources. "About My Model" panel: semantic fact count + confidence distribution, procedural rule count, confirmed pattern count, model age, next reflection time. Corrections as signals: setting changes emit `CDSignal` records. Invariant (not configurable): observation-only constraint, privacy abstraction, memory retention policy.

- **Files to modify:** `Sources/Features/Prefs/` (all files)
- **Depends on:** 3.02, 3.03, 4.12, 2.07
- **Acceptance criterion:** Change alert frequency cap; verify alert behaviour changes immediately; disable voice capture; verify no voice signals generated; "About My Model" shows accurate counts

---

### 6.04 — Model versioning service

`ModelVersioningService`. Snapshot captured: weekly (Sunday 03:00), pre-reflection (before every nightly run), manual trigger, milestones (day 30, 60, 90, 180). Snapshot contents: all semantic facts, active rules, confirmed/emerging patterns, core memory buffer, model metrics. Diff computation: added/removed/changed facts, rules, patterns between any two snapshots. Drift detection: distinguish genuine person change from model corruption. Rollback: restore a previous snapshot's semantic + procedural state.

- **Files to create:** `Sources/Core/Services/Intelligence/ModelVersioningService.swift`
- **Depends on:** 3.02, 3.03, 4.12, 4.08
- **Acceptance criterion:** Run 3 nights of reflection; view diff between Night 1 and Night 3; differences displayed accurately; rollback to Night 1 version restores Night 1's semantic model

---

### 6.05 — Model versioning UI

View model evolution over time in a dedicated Intelligence tab. Metrics: "47 semantic facts, 12 procedural rules, 8 confirmed patterns. This week: +3 facts, +1 rule." Side-by-side comparison of any two model versions. Rollback button with confirmation. Trend charts for model growth, confidence distribution, rule effectiveness rate.

- **Files to create:** `Sources/Features/Intelligence/ModelVersionView.swift`
- **Depends on:** 6.04
- **Acceptance criterion:** Intelligence tab shows current model metrics; side-by-side diff between two versions renders correctly; rollback with confirmation works

---

### 6.06 — Month-over-month intelligence reports

`IntelligenceReportGenerator`. Monthly summary generated by Opus at 03:00 on 1st of month. Sections: executive summary (3-5 sentences), model specificity metrics (fact count, confidence distribution, pattern inventory), prediction accuracy (day plan adherence, time estimate accuracy), behaviour change detection, relationship health summary, intelligence quality self-assessment. Stored in CoreData. Presented in Intelligence tab. Milestone reports at day 30, 60, 90, 180.

- **Files to create:** `Sources/Core/Services/Intelligence/IntelligenceReportGenerator.swift`
- **Files to create:** `Sources/Features/Intelligence/IntelligenceReportView.swift`
- **Depends on:** 6.04, 3.02, 3.03, 4.12, 5.04
- **Acceptance criterion:** After 30 days of simulated data, report generates with all sections; executive summary written by Opus; trend charts rendered; prediction accuracy calculated

---

### 6.07 — Weekly consolidation engine

`WeeklyConsolidationEngine` implementing weekly `ReflectionEngine` path. Runs Sunday 03:00. Scans: semantic memories with contradictions, patterns in `fading` status, episodic memories older than 90 days with 0 access. Opus review call: "What should be archived?" Archive: old episodic -> Supabase pgvector. Merge: overlapping semantic memories. Retire: rules with high exception rates. Recalculate: core memory priority ranks.

- **Files to create:** `Sources/Core/Services/Reflection/WeeklyConsolidationEngine.swift`
- **Depends on:** 4.10, 5.10, 3.01, 3.02, 3.03, 3.04
- **Acceptance criterion:** Weekly consolidation archives episodic memories older than 90 days; fading patterns reviewed; overlapping semantic facts merged; core memory recalculated

---

### 6.08 — CoreData migration strategy

Lightweight migration for additive schema changes (new attributes, new entities). Heavyweight migration with mapping models for destructive changes (renamed attributes, changed relationships). Migration version tracking: `TimedModel_1.0` -> `1.1` -> `2.0`. Migration tests: create a store with version N, migrate to N+1, verify data integrity.

- **Files to create:** `Sources/Core/Persistence/MigrationManager.swift`
- **Files to modify:** `Sources/Core/Persistence/TimedModel.xcdatamodeld/` (versioned models)
- **Depends on:** 1.05, 1.08
- **Acceptance criterion:** Create a store with Phase 1 schema; migrate through all schema versions; zero data loss; lightweight migration for optional attribute additions; heavyweight migration for type changes

---

### 6.09 — Sparkle auto-update integration

Sparkle framework. Appcast XML hosted on GitHub Pages or S3. Ed25519 signature verification. Check for updates on launch + daily. User-initiated check from Settings.

- **Files to create:** `Sources/Core/Infrastructure/SparkleUpdater.swift`
- **Files to modify:** `Sources/Features/Prefs/` (add update check button)
- **Depends on:** 6.03
- **Acceptance criterion:** Test appcast hosted; app detects available update; update downloads and applies correctly; signature verification prevents tampered updates

---

### 6.10 — DMG packaging + notarisation

Build script: Xcode archive -> create DMG -> notarise with `notarytool` -> staple. Code signing with Developer ID certificate. Gatekeeper-friendly. Automated via CI or local script.

- **Files to create:** `Scripts/build-dmg.sh`, `Scripts/notarise.sh`
- **Depends on:** 6.09
- **Acceptance criterion:** DMG installs on a clean Mac (or clean user account); app launches; Gatekeeper does not block; notarisation verified

---

### 6.11 — Drift detector agent

`DriftDetectorAgent` (from background-agents.md). Runs every 2 hours. Uses Haiku for lightweight anomaly detection against the current model. Detects: sudden behaviour changes that may indicate genuine person change (new role, crisis) vs model drift (stale patterns, overfitting). Flags anomalies for next nightly reflection.

- **Files to create:** `Sources/Core/Services/Agents/DriftDetectorAgent.swift`
- **Depends on:** 3.02, 2.07, 1.14
- **Acceptance criterion:** Simulated sudden behaviour shift (all email response times double) triggers anomaly flag within 4 hours; stable behaviour does not trigger false positives

---

### 6.12 — USearch vector index (performance upgrade)

Replace brute-force Accelerate `vDSP` cosine similarity with HNSW index from `usearch` Swift package for in-process vector search. <1ms query at 100K vectors. <5MB memory overhead. Incremental index updates (no full rebuild on new memory).

- **Files to modify:** `Sources/Core/Services/Memory/VectorSearchEngine.swift`
- **Depends on:** 3.06
- **Acceptance criterion:** 100K embeddings, top-20 query in <5ms; memory overhead under 10MB; incremental insert without full rebuild; results match brute-force within 95% recall

---

### 6.13 — Privacy settings UI + data deletion

Settings panel for all privacy controls from privacy-spec.md: `captureWindowTitles`, `captureEmailBodies`, `syncToCloud`, `retentionDaysEpisodic`, `retentionDaysSemantic`, `excludedAppBundleIds`, `excludedEmailDomains`, `allowVoiceProsodyAnalysis`. "Delete All My Data" button: wipes CoreData store, Keychain tokens, Supabase remote data, resets to fresh install. Data export: generate JSON dump of full model for user inspection.

- **Files to modify:** `Sources/Features/Prefs/` (privacy section)
- **Files to create:** `Sources/Core/Services/DataDeletionService.swift`
- **Depends on:** 6.03, 1.12
- **Acceptance criterion:** Delete All wipes local + remote data; export produces valid JSON of full model; privacy toggles immediately stop corresponding data collection

---

### 6.14 — Edge Function: run-nightly-reflection

Supabase Edge Function for server-side nightly reflection (backup path when local reflection fails or for cross-device sync). Triggers at 02:00 via Supabase cron. Reads episodic/semantic/procedural state from Supabase. Runs 6-stage Opus pipeline. Writes results back to Supabase. Local client pulls results on next sync.

- **Files to create:** `supabase/functions/run-nightly-reflection/index.ts`
- **Depends on:** 4.02, 5.10
- **Acceptance criterion:** Edge Function executes 6-stage pipeline; results written to Supabase; local client pulls and merges; function handles partial failure gracefully

---

### 6.15 — Prompt template versioning and storage

Prompt templates stored as versioned JSON documents in Supabase `prompt_templates` table. Version format: `{stage_name}-v{major}.{minor}.{patch}`. Active version tracked per stage. Rollback to previous version. A/B testing support: two versions active simultaneously with traffic split.

- **Files to create:** `Sources/Core/Services/Reflection/PromptVersionManager.swift`
- **Depends on:** 4.02, 5.10
- **Acceptance criterion:** Template versioned and stored in Supabase; update a template; new version active; rollback to previous version works

---

### 6.16 — Polish test suite

Tests for: onboarding flow completion, cold-start archetype loading, calendar history import, settings persistence and signal emission, model versioning CRUD and diff, DMG installation verification, CoreData migration chain, data deletion completeness, privacy toggle enforcement.

- **Files to create:**
  - `Tests/TimedTests/Layer4/ColdStartServiceTests.swift`
  - `Tests/TimedTests/Layer4/ModelVersioningTests.swift`
  - `Tests/TimedTests/Layer4/IntelligenceReportTests.swift`
  - `Tests/TimedTests/Infrastructure/CoreDataMigrationTests.swift`
  - `Tests/TimedTests/Infrastructure/DataDeletionTests.swift`
- **Depends on:** 6.01 through 6.15
- **Acceptance criterion:** At least 15 unit tests + 5 integration tests pass; CoreData migration chain verified end-to-end

---

## Dependency Summary

```
Phase 1: Foundation
    1.01 ─────────────────────────────────────────────────
     │
    1.02 (enums)
     │
    1.03 (errors) ──── 1.04 (logging)
     │
    1.05 (CoreData model)
     │
    1.06 (CD subclasses) ── 1.07 (transformer)
     │                        │
    1.08 (persistence ctrl) ──┘
     │
    1.09 (DTOs) ── 1.10 (protocols)
     │               │
    1.11 (SignalBus) ┘
     │
    1.12 (auth) ── 1.13 (ClaudeClient)
     │               │
    1.14 (AIRouter) ─┘
     │
    1.15 (privacy) ── 1.16 (sanitiser)
     │
    1.17 (Jina) ── 1.18 (dual-write bridge)
     │
    1.19 (tests)

Phase 2: Signal Ingestion
    2.01 (email) ─┐
    2.02 (calendar)│── 2.07 (coordinator) ── 2.08 (background) ── 2.09 (sleep/wake)
    2.03 (app focus)│
    2.04 (voice)  ─┤
    2.05 (task)   ─┤
    2.06 (classifier)┘
     │
    2.10 (tests)

Phase 3: Memory
    3.01 (episodic) ─┐
    3.02 (semantic) ──┤── 3.04 (core memory) ── 3.05 (retrieval) ── 3.06 (vector search)
    3.03 (procedural)─┘
    3.07 (profile) ── 3.08 (chronotype) ── 3.09 (cog load) ── 3.10 (relationships)
    3.11 (thompson) ── 3.12 (EMA) ── 3.13 (realtime)
     │
    3.14 (tests)

Phase 4: Reflection
    4.01 (scheduler)
    4.02 (prompts) ── 4.03 (builder) ── 4.04 (stage 1) ── 4.05 (stage 2)
     │                                                        │
    4.06 (stage 3) ── 4.07 (stage 4) ── 4.08 (stage 5) ── 4.09 (stage 6)
     │
    4.10 (orchestrator) ── 4.11 (self-assess) ── 4.12 (pattern lifecycle)
     │
    4.13 (avoidance) ── 4.14 (consolidation) ── 4.15 (triggered reflection)
     │
    4.16 (tests) ── 4.17 (3-day live gate)

Phase 5: Intelligence Delivery
    5.01 (morning director) ── 5.02 (morning UI) ── 5.03 (voice)
     │
    5.04 (day plan) ── 5.05 (menu bar) ── 5.06 (alerts)
     │
    5.07 (focus timer) ── 5.08 (query) ── 5.09 (elicitation) ── 5.10 (sync)
     │
    5.11 (tests)

Phase 6: Polish
    6.01 (cold start) ── 6.02 (onboarding) ── 6.03 (settings)
     │
    6.04 (versioning svc) ── 6.05 (versioning UI) ── 6.06 (reports)
     │
    6.07 (weekly consolidation) ── 6.08 (migration) ── 6.09 (sparkle)
     │
    6.10 (DMG) ── 6.11 (drift detector) ── 6.12 (USearch) ── 6.13 (privacy UI)
     │
    6.14 (edge fn reflection) ── 6.15 (prompt versioning) ── 6.16 (tests)
```

---

## Parallelisation Opportunities Within Each Phase

**Phase 1:** CoreData model (1.05-1.08) parallel with API clients (1.13, 1.17) and auth (1.12). Privacy pipeline (1.15-1.16) parallel with logging/errors (1.03-1.04).

**Phase 2:** Email agent (2.01) and calendar agent (2.02) share no code -- build in parallel. App focus (2.03), voice (2.04), and task (2.05) agents are all independent. Importance classifier (2.06) is independent.

**Phase 3:** Episodic (3.01), semantic (3.02), and procedural (3.03) repositories share no code -- build in parallel. Profile service (3.07) is independent. Chronotype (3.08), cognitive load (3.09), and relationship scorer (3.10) depend on 3.01/3.02 but are independent of each other.

**Phase 4:** Stages 1-4 (4.04-4.07) are strictly sequential. Pattern lifecycle (4.12) and avoidance detector (4.13) can be built in parallel with the reflection stages.

**Phase 5:** Menu bar (5.05), alerts (5.06), focus timer (5.07), and query (5.08) share no code -- build in parallel. Morning session (5.02-5.03) depends on the morning director (5.01).

**Phase 6:** Nearly all components are independent: cold start (6.01), model versioning (6.04), reports (6.06), Sparkle (6.09), DMG (6.10), USearch (6.12), drift detector (6.11) can all proceed in parallel.

---

## Audit Reconciliation Notes

This plan incorporates the resolutions from CHANGES.md:

- **Protocol naming:** Uses `SignalWritePort` (architecture.md canonical), not `SignalEmitting`
- **Reflection pipeline:** 6 stages, all Opus (no Sonnet for Stages 1-2)
- **Core memory buffer:** 50 entries, ~4,000 tokens
- **Nightly reflection time:** 02:00 (not 22:00)
- **Retrieval scoring:** `recency = 0.995^hours`, additive weighted `(0.2, 0.3, 0.5)`
- **EMA alpha:** 0.3 operational (with cold-start schedule ending at 0.3)
- **Nightly cost:** $1.50-$5.00 per run
- **CoreData only:** No `@Model` (SwiftData) annotations
- **Source enum:** Canonical `SignalSource` from data-models.md everywhere

Open items from AUDIT.md resolved by this plan:

- **G-01:** PrivacyAbstractor fully specified in task 1.15
- **G-02:** CDPattern entity specified in task 1.05/1.06
- **G-03:** SignalBus specified in task 1.11
- **G-04:** AIModelRouter specified in task 1.14
- **G-05:** CDUserProfile specified in task 1.05/1.06, service in task 3.07
- **G-06:** CoreData is canonical for v1 (task 1.05); JSON files via DataStore are legacy (task 1.18 bridges)
- **C-07:** Task category taxonomy mapping specified in task 3.11
- **C-09:** Protocol names reconciled per CHANGES.md
- **V-05:** Stages 4-6 prompts written during task 4.02
- **V-06:** Archetype-to-20-category mapping specified in task 3.11
