# Timed — BUILD_STATE.md

> Every component mapped to status, complexity, prerequisites, and build phase. Read this before every session.

**Last updated:** 2026-04-02

---

## Status Key

| Status | Meaning |
|--------|---------|
| DONE | Shipped, working, tested |
| IN PROGRESS | Partially built, not yet functional |
| NOT STARTED | Designed, not yet coded |
| BLOCKED | Cannot proceed until prerequisite is resolved |

| Complexity | Meaning |
|------------|---------|
| S | < 4 hours, single file, low risk |
| M | 4–16 hours, 2–5 files, moderate risk |
| L | 1–3 days, 5–15 files, cross-cutting |
| XL | 3–7 days, 15+ files, architectural significance |

---

## Layer 1: Signal Ingestion

| Component | Status | Complexity | Prerequisites | Phase | Notes |
|-----------|--------|-----------|---------------|-------|-------|
| **EmailSignalAgent** — Graph delta sync polling | DONE (partial) | M | Auth flow | 2 | `EmailSyncService.swift` exists with full delta sync logic. Not connected to UI — needs auth bridge. |
| **CalendarSignalAgent** — Graph calendar sync | DONE (partial) | M | Auth flow | 2 | `CalendarSyncService.swift` exists. Same auth gap as email. |
| **VoiceCaptureService** — Apple Speech transcription | DONE | M | — | 1 | Fully working. `VoiceCaptureService.swift` + `VoiceResponseParser.swift`. Real-time partial results. |
| **AppFocusSignalAgent** — NSWorkspace app tracking | NOT STARTED | M | — | 3 | Needs `NSWorkspace.didActivateApplicationNotification`. Bundle ID + optional window title. |
| **SignalWritePort** — Protocol definition | NOT STARTED | S | CoreData stack | 2 | Protocol exists in architecture spec. Needs Swift implementation. |
| **ImportanceClassifier** — Haiku-based signal scoring | NOT STARTED | M | Edge Function (`classify-email`) | 3 | Currently email classification only. Needs generalization to all signal types. |
| **AgentCoordinator** — Lifecycle management for all agents | NOT STARTED | M | All agents | 3 | Starts/stops agents, monitors health, reports status. |
| **TranscriptParser** — Voice → task extraction | DONE | M | — | 1 | `VoiceResponseParser.swift` — regex + heuristic parsing. Works for morning sessions. |
| **GraphClient** — Microsoft Graph API client | DONE | L | — | 1 | Full MSAL OAuth + all read methods. `GraphClient.swift`. |
| **EmailClassifier** — Email triage bucketing | DONE (local) | S | — | 1 | `EmailClassifier.swift` — local heuristic. Edge Function `classify-email` is the production version. |

---

## Layer 2: Memory Store

| Component | Status | Complexity | Prerequisites | Phase | Notes |
|-----------|--------|-----------|---------------|-------|-------|
| **CoreData Model** — `.xcdatamodeld` with all entities | NOT STARTED | L | — | 2 | 15+ entities defined in data-models.md spec. Needs Xcode model creation. |
| **TimedPersistenceController** — CoreData stack | NOT STARTED | M | CoreData model | 2 | `NSPersistentContainer`, multi-context setup, merge policy. |
| **EmbeddingVectorTransformer** — `[Float]` ↔ `Data` | NOT STARTED | S | — | 2 | ValueTransformer for 1024-dim vectors in CoreData. |
| **EpisodicMemoryStore** — CRUD + retrieval scoring | NOT STARTED | L | CoreData stack, Embedding service | 2 | Core of Layer 2. Retrieval-scored queries (recency × importance × relevance). |
| **SemanticMemoryStore** — CRUD + confidence management | NOT STARTED | M | CoreData stack | 3 | Upsert, reinforce, contradict, deactivate. |
| **ProceduralMemoryStore** — Rule CRUD + activation tracking | NOT STARTED | M | CoreData stack | 3 | Create rules, track activations, log exceptions. |
| **CoreMemoryManager** — Fixed-size buffer management | NOT STARTED | M | CoreData stack | 3 | 50-entry buffer, eviction to semantic, priority recalculation. |
| **MemoryConsolidator** — Tier promotion logic | NOT STARTED | L | All memory stores | 4 | Episodic → semantic, semantic → procedural, archival. |
| **JinaEmbeddingClient** — API client for Jina embeddings | NOT STARTED | S | — | 2 | HTTP client for jina-embeddings-v3. 1024-dim output. Batch support. |
| **DataStore** — JSON local persistence (current) | DONE | M | — | 1 | `DataStore.swift` — actor with JSON file I/O. Will be superseded by CoreData but kept as fallback during migration. |
| **SupabaseClient** — Remote persistence | DONE (partial) | L | Auth flow | 2 | `SupabaseClient.swift` — 12 operations implemented. Not called from UI due to auth gap. |

---

## Layer 3: Reflection Engine

| Component | Status | Complexity | Prerequisites | Phase | Notes |
|-----------|--------|-----------|---------------|-------|-------|
| **NightlyReflectionEngine** — Opus recursive reflection | NOT STARTED | XL | Episodic store, Semantic store, Procedural store, Core memory, AI Router | 4 | The heart of Timed. 4-pass Opus reflection. Highest architectural significance. |
| **ReflectionPromptBuilder** — System/user prompt construction | NOT STARTED | L | Core memory buffer, Pattern store | 4 | Builds the prompts for Opus with full context injection. |
| **WeeklyConsolidationEngine** — Prune, merge, archive | NOT STARTED | L | All memory stores, pgvector | 5 | Monthly archival to Supabase pgvector. Pattern lifecycle management. |
| **ReflectionScheduler** — NSBackgroundActivityScheduler | NOT STARTED | S | Nightly engine | 4 | Triggers nightly at 02:00, weekly on Sunday 03:00. |
| **TriggeredReflection** — Event-driven Opus calls | NOT STARTED | M | Nightly engine | 5 | For importance > 0.9 signals and user corrections. |
| **PatternAnalyzer** — Pattern lifecycle management | NOT STARTED | M | Pattern store | 4 | Status transitions: emerging → confirmed → fading → archived. |

---

## Layer 4: Intelligence Delivery

| Component | Status | Complexity | Prerequisites | Phase | Notes |
|-----------|--------|-----------|---------------|-------|-------|
| **MorningDirectorService** — Opus-powered morning briefing | NOT STARTED | XL | Core memory, Patterns, Profile, AI Router | 4 | Generates `MorningBriefing` with named patterns, avoidance warnings, energy guidance. |
| **Morning Interview UI** — Voice-first morning session | DONE | L | — | 1 | Full UI in `MorningInterview/`. Voice recording, transcript display, AI response. |
| **ProactiveAlertService** — Pattern-based alerts | NOT STARTED | L | Patterns, Profile, Calendar | 5 | Deadline risk, energy warnings, meeting overload, avoidance triggers. |
| **PlanningEngine** — Thompson sampling + knapsack | DONE | XL | — | 1 | `PlanningEngine.swift` — full scoring, Thompson sampling, behavioural rules, mood context. |
| **TimeSlotAllocator** — Calendar-aware scheduling | DONE | XL | — | 1 | `TimeSlotAllocator.swift` — energy-tier matching, meeting buffers, 75% utilization cap, incremental repair. |
| **Menu Bar Widget** — Glanceable intelligence | DONE | M | — | 1 | `MenuBar/` — Now/Next/Later display. Working. |
| **Command Palette** — Cmd+K quick actions | DONE | M | — | 1 | `CommandPalette/` — search, navigation, actions. Working. |
| **Today View** — Daily plan display | DONE | L | — | 1 | `Today/` — task list, plan score display, scheduled times. |
| **Focus Timer** — Pomodoro with ML feedback | DONE | M | — | 1 | `Focus/` — timer, pause/resume, completion tracking. |
| **Task Management** — CRUD + batch operations | DONE | L | — | 1 | `Tasks/` — create, edit, complete, defer, batch select. Task Detail Modal. |
| **Calendar View** — Read-only calendar display | DONE | M | — | 1 | `Calendar/` — week view with drag-to-create. |
| **Email Triage View** — Inbox classification display | DONE | M | — | 1 | `Triage/` — email list with classification badges. |
| **Voice Capture View** — Quick voice capture | DONE | M | — | 1 | `Capture/` — record, transcribe, extract tasks. |
| **Onboarding** — First-run experience | DONE (basic) | M | — | 1 | `Onboarding/` — exists but needs archetype picker for cold-start. |
| **AIModelRouter** — Model tier routing + fallback | NOT STARTED | M | — | 3 | Actor that routes requests to Haiku/Sonnet/Opus with rate limiting and fallback. |
| **UserProfileService** — Profile CRUD + energy curve | NOT STARTED | M | CoreData stack | 3 | Manages CDUserProfile singleton. Exposes `UserProfilePort`. |

---

## Infrastructure

| Component | Status | Complexity | Prerequisites | Phase | Notes |
|-----------|--------|-----------|---------------|-------|-------|
| **AuthService** — MSAL OAuth sign-in flow | DONE (code) | L | — | 2 | `AuthService.swift` — full implementation. Not connected to UI launch flow. |
| **Supabase Auth Bridge** — Sign in → workspace bootstrap | NOT STARTED | M | AuthService | 2 | Microsoft OAuth provider in Supabase → create workspace + profile on first sign-in. |
| **UI ↔ Supabase Bridge** — Dual-write DataStore + Supabase | NOT STARTED | L | Auth bridge | 2 | DataStore writes also push to Supabase. Reads prefer local, fall back to remote. |
| **EmailSyncService** — Background Graph delta sync | DONE (code) | L | Auth bridge | 2 | `EmailSyncService.swift` — fully implemented. Needs auth session to activate. |
| **CalendarSyncService** — Background Graph calendar sync | DONE (code) | M | Auth bridge | 2 | `CalendarSyncService.swift` — fully implemented. Same auth gap. |
| **TimedLogger** — os.Logger subsystems | DONE | S | — | 1 | `TimedLogger.swift` — subsystems for planning, memory, voice, dataStore, network. |
| **TimedScheduler** — Task scheduling coordinator | DONE | M | — | 1 | `TimedScheduler.swift` — coordinates timed operations. |
| **NetworkMonitor** — Connectivity tracking | DONE | S | — | 1 | `NetworkMonitor.swift` — NWPathMonitor wrapper. |
| **SharingService** — PA task sharing | DONE (code) | M | Auth bridge | 2 | `SharingService.swift` — share tasks with PA. Needs auth. |
| **Supabase Edge Functions** — 9 functions | DONE | L | — | 1 | All 9 deployed and active. See architecture.md for full list. |
| **Realtime Subscriptions** — Supabase Realtime | NOT STARTED | M | Auth bridge | 3 | Subscribe to email_messages, tasks tables for real-time updates. |
| **Sparkle Auto-Update** — Update framework | NOT STARTED | S | — | 5 | Integrate Sparkle framework for DMG auto-updates. |

---

## Cold-Start Intelligence

| Component | Status | Complexity | Prerequisites | Phase | Notes |
|-----------|--------|-----------|---------------|-------|-------|
| **Archetype Picker** — Onboarding role selection | NOT STARTED | M | Onboarding UI | 3 | Pre-loads scoring weights based on executive archetype (CEO, COO, CFO, etc.). |
| **Calendar History Bootstrap** — 90-day Outlook import | NOT STARTED | M | CalendarSyncService + Auth | 3 | Import 90 days of calendar history → infer meeting patterns, chronotype, key contacts. |
| **EMA Feedback Loop Closure** — Completion → estimate update | DONE (partial) | S | CompletionRecord model | 1 | `markTaskCompleted()` records actual duration. EMA update logic in DataStore. Needs CoreData migration. |
| **Active Preference Elicitation** — Voice session questions | NOT STARTED | M | Morning Director | 4 | One targeted question per voice session to actively learn preferences. |

---

## Dependency Graph

```
Phase 1 (DONE — shipped features):
  VoiceCaptureService ─────────────┐
  TranscriptParser ────────────────┤
  PlanningEngine ──────────────────┤
  TimeSlotAllocator ───────────────┤
  GraphClient ─────────────────────┤
  EmailClassifier ─────────────────┤
  DataStore (JSON) ────────────────┤
  TimedLogger ─────────────────────┤
  All 10 UI screens ───────────────┤
  Menu Bar ────────────────────────┤
  Command Palette ─────────────────┤
  Focus Timer ─────────────────────┤
  Edge Functions (9) ──────────────┘

Phase 2 (AUTH BRIDGE — the critical unlock):
  AuthService ──┐
                ├──► Supabase Auth Bridge ──┐
                │                           ├──► UI ↔ Supabase Bridge
                │                           ├──► EmailSyncService (activate)
                │                           └──► CalendarSyncService (activate)
                │
  CoreData Model ──► TimedPersistenceController ──┐
  EmbeddingVectorTransformer ─────────────────────┤
  JinaEmbeddingClient ───────────────────────────┘

Phase 3 (OBSERVATION AGENTS + MEMORY):
  EpisodicMemoryStore ──────────────────┐
  SignalWritePort ──────────────────────┤
  AppFocusSignalAgent ──────────────────┤
  AgentCoordinator ─────────────────────┤
  AIModelRouter ────────────────────────┤
  ImportanceClassifier (generalized) ───┤
  SemanticMemoryStore ──────────────────┤
  ProceduralMemoryStore ────────────────┤
  CoreMemoryManager ────────────────────┤
  UserProfileService ───────────────────┤
  Archetype Picker ─────────────────────┤
  Calendar History Bootstrap ───────────┤
  Realtime Subscriptions ───────────────┘

Phase 4 (INTELLIGENCE CORE — the differentiator):
  NightlyReflectionEngine ──────────────┐
  ReflectionPromptBuilder ──────────────┤
  ReflectionScheduler ──────────────────┤
  PatternAnalyzer ──────────────────────┤
  MemoryConsolidator ───────────────────┤
  MorningDirectorService ───────────────┤
  Active Preference Elicitation ────────┘

Phase 5 (POLISH + SCALE):
  WeeklyConsolidationEngine ────────────┐
  TriggeredReflection ──────────────────┤
  ProactiveAlertService ────────────────┤
  Sparkle Auto-Update ─────────────────┘
```

---

## Critical Path

The shortest path from current state to "intelligence that compounds" is:

```
1. Supabase Auth Bridge           [M, ~8h]
   └─ Unlocks ALL remote services (email sync, calendar sync, Supabase queries)

2. CoreData Stack + Model         [L, ~16h]
   └─ Unlocks persistent memory layer (currently JSON files)

3. Episodic Memory Store          [L, ~12h]
   └─ Unlocks signal → memory pipeline

4. Jina Embedding Client          [S, ~3h]
   └─ Unlocks vector storage and similarity search

5. Nightly Reflection Engine      [XL, ~24h]
   └─ THE differentiator. Opus recursive reflection.

6. Morning Director Service       [XL, ~20h]
   └─ Delivers nightly intelligence to the user

Total critical path: ~83 hours of focused development
```

Everything else (app focus tracking, proactive alerts, weekly consolidation, archetype picker) enhances the core but is not on the critical path.

---

## The Gap (Unchanged From Previous Session)

**UI uses local DataStore. SupabaseClient + GraphClient are fully implemented but not called from UI.**

Root cause: No sign-in flow connected. RLS policies require `auth.uid()`. Without a Supabase session, all remote queries fail.

**Fix:** Phase 2 — Supabase Auth Bridge. This is the single most important unlock.

---

## What's Shipped (Phase 1 Inventory)

These components are DONE, tested, and working in the app:

1. Voice-first morning planning (90s interview → AI day plan via Edge Function)
2. AI email triage (Graph → Edge Function → Do First / Action / Reply / Read / CC)
3. Thompson sampling task scoring (Beta posterior, Gaussian approximation, hour-range bucketing)
4. EMA time estimation (per-bucket exponential moving average, 30-day learning)
5. Calendar-aware time-slot allocator (gap extraction, energy-tier matching, 75% utilization cap)
6. Focus timer with Pomodoro persistence (feeds completion data back into EMA)
7. Menu bar presence (Now/Next/Later glanceable awareness)
8. Command palette (Cmd+K search, navigation, quick actions)
9. Global hotkey (Cmd+Shift+Space)
10. Premium design system (TimedMotion animations, TimedSounds, dark mode palette)
11. 10 UI screens (Today, Morning Interview, Focus, Tasks, Calendar, Triage, Capture, Waiting, Sharing, Settings stub)
12. Task Detail Modal with inline editing
13. Calendar drag-to-create blocks
14. Batch task operations (multi-select, bulk complete/defer)
15. 49 passing tests (swift-testing)
