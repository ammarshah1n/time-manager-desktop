# BUILD_STATE.md — Last updated: 2026-04-02 (initial audit)

## What Exists and Works

### Signal Ingestion ✅
- [x] GraphClient.swift — MSAL auth + delta email sync + calendar events + webhooks (489 lines)
- [x] EmailSyncService.swift — Actor, delta sync, folder-move detection, reply latency social graph (606 lines)
- [x] CalendarSyncService.swift — Actor, Outlook events → CalendarBlocks, free-time gap detection (201 lines)
- [x] VoiceCaptureService.swift — Apple Speech (SFSpeechRecognizer + AVAudioEngine), live transcript (368 lines)
- [x] VoiceResponseParser.swift — Parses spoken commands during morning interview (365 lines)
- [x] NetworkMonitor.swift — NWPathMonitor wrapper (21 lines)
- [x] EmailClassifier.swift — Protocol + stub, real classification via Edge Function (🔄 placeholder)

### Memory Store ✅ (partial — no intelligence memory)
- [x] DataStore.swift — Local JSON persistence actor, ~/Library/Application Support/Timed/ (113 lines)
- [x] SupabaseClient.swift — 11 row types, 20+ operations, full CRUD (764 lines)
- [x] Domain models — TimedTask, TaskBucket, TriageItem, WOOItem, CaptureItem, CalendarBlock, etc.
- [ ] ~~CoreData~~ — NOT USED. Persistence is JSON local + Supabase remote.
- [ ] Episodic memory tier — NOT STARTED
- [ ] Semantic memory tier — NOT STARTED
- [ ] Procedural memory tier — NOT STARTED

### Reflection Engine ✅ (scoring only — no intelligence engine)
- [x] PlanningEngine.swift — Composite scoring, Thompson sampling, behavioural rules, mood modifiers (501 lines)
- [x] TimeSlotAllocator.swift — Calendar-aware slot allocation, energy tiers, incremental repair (612 lines)
- [x] InsightsEngine.swift — Estimated vs actual time comparison (28 lines, minimal)
- [x] TaskExtractionService.swift — Thread grouping, bucket detection, time estimation (178 lines)
- [ ] Nightly Opus reflection engine — NOT STARTED
- [ ] Pattern extraction (first-order) — NOT STARTED
- [ ] Insight synthesis (second-order) — NOT STARTED
- [ ] Rule generation (procedural memory writes) — NOT STARTED
- [ ] Memory retrieval (recency × importance × relevance) — NOT STARTED

### Delivery ✅ (UI complete — intelligence delivery not started)
- [x] TimedRootView.swift — Root nav, all state management (489 lines, 🔄 god-view)
- [x] TodayPane.swift — Today dashboard
- [x] TriagePane.swift — Keyboard-driven email triage, undo stack, AI correction logging (620 lines)
- [x] TasksPane.swift — Per-bucket task list, bulk ops, context menu (546 lines)
- [x] PlanPane.swift — Full planning pane (634 lines, 🔄 duplicates DishMeUpSheet logic)
- [x] DishMeUpSheet.swift — "I have X minutes" planning (555 lines)
- [x] FocusPane.swift — Circular countdown timer, Pomodoro, session persistence (505 lines)
- [x] CalendarPane.swift — Weekly grid, drag-to-create, Outlook sync (656 lines)
- [x] CapturePane.swift — Voice/text quick capture (393 lines)
- [x] MorningInterviewPane.swift — 5-step voice morning interview (500+ lines)
- [x] CommandPalette.swift — Cmd+K, fuzzy search, action registry (264 lines)
- [x] MenuBarManager.swift — NSStatusItem, current task, next event (358 lines)
- [x] QuickCapturePanel.swift — Cmd+Shift+Space floating panel (141 lines)
- [x] OnboardingFlow.swift — 9-step first launch (655 lines)
- [x] PrefsPane.swift — Settings tabs (414 lines)
- [x] WaitingPane.swift — WOO tracker (456 lines)
- [x] SharingPane.swift — Workspace sharing (260 lines)
- [ ] Morning intelligence briefing (pattern headlines, cognitive state) — NOT STARTED
- [ ] Proactive intelligence alerts — NOT STARTED
- [ ] Named pattern delivery — NOT STARTED

### Infrastructure ✅
- [x] AuthService.swift — Supabase Auth, Microsoft OAuth, workspace bootstrap (310 lines, 🔄 violates DI)
- [x] TimedColors.swift — Dark-mode palette (55 lines)
- [x] TimedMotion.swift — Animation curves (16 lines)
- [x] TimedSounds.swift — System sounds, rate limiting (79 lines)
- [x] TimedLogger.swift — os.Logger categories (19 lines)
- [x] SharingService.swift — Actor, invite links, PA management (156 lines)
- [x] SpeechService.swift — AVSpeechSynthesizer TTS (98 lines)

### Tests
- [x] CalendarBlockTests — Codable roundtrip
- [x] DataStoreTests — Roundtrip for 5 model types
- [x] EmailClassifierTests — Stub classification
- [x] EmailMessageTests — Codable roundtrip
- [x] TimedPlanningEngineV2Tests — 22 tests (scoring, mood, rules, parser)
- [x] TimedSchedulerTests — Stub returns
- [ ] TimeSlotAllocator tests — NOT STARTED
- [ ] EmailSyncService tests — NOT STARTED
- [ ] VoiceResponseParser tests — NOT STARTED
- [ ] Memory store tests — NOT STARTED
- [ ] Reflection engine tests — NOT STARTED

### Backend (Supabase)
- [x] 15 SQL migrations deployed
- [x] 9 Edge Functions active (classify-email, detect-reply, estimate-time, generate-daily-plan, generate-profile-card, graph-webhook, parse-voice-capture, renew-graph-subscriptions)
- [x] Jina AI embeddings configured (1024-dim)
- [x] Microsoft OAuth app registration (Azure)

## Known Issues / Landmines
- PreviewData.swift contains ALL domain models (587 lines) — should split into Core/Models/
- AuthService creates its own SupabaseClient, violating DI pattern
- PlanPane and DishMeUpSheet duplicate plan generation logic
- TimedRootView is a 489-line god-view holding all @State arrays
- TCA dependency declared but only used for @Dependency injection, not state management
- No CoreData/SwiftData — persistence is JSON local + Supabase remote
- Legacy/ folder (41 files) excluded from build, kept as reference

## Architecture Gap: The Intelligence Core
> **Updated 2026-04-03** — research ingested, architecture synthesised. Full specs in `research/ARCHITECTURE-*.md`.

The entire intelligence infrastructure is designed but unbuilt:
- No 5-tier memory (Tier 0-3 + ACB) — schema designed in ARCHITECTURE-MEMORY.md §1,7
- No nightly 6-phase pipeline — designed in ARCHITECTURE-MEMORY.md §2
- No signal extraction beyond email/calendar — 30+ signals designed in ARCHITECTURE-SIGNALS.md §1
- No 5-dimension retrieval engine — designed in ARCHITECTURE-MEMORY.md §3
- No ONA/relationship graph — designed in ARCHITECTURE-SIGNALS.md §2
- No chronobiology/energy model — designed in ARCHITECTURE-SIGNALS.md §5
- No intelligence delivery (morning briefing) — designed in ARCHITECTURE-DELIVERY.md §1-3
- No privacy/trust architecture — designed in ARCHITECTURE-DELIVERY.md §5
- No cold start pipeline — designed in ARCHITECTURE-DELIVERY.md §6
- No behavioural prediction (avoidance, burnout, reversal) — designed in ARCHITECTURE-MEMORY.md §5
- No compounding evaluation (CCR metric) — designed in ARCHITECTURE-MEMORY.md §6

This is the primary build target. All architecture decisions are made. Ready to build.

## Build Phases (Intelligence Core)

| Phase | Focus | Key Deliverables | Depends On |
|-------|-------|-----------------|------------|
| 1 | Data Layer | Supabase schema (14 tables), Tier 0 write path, Voyage AI embeddings, HNSW indexes | — |
| 2 | Signal Expansion | Keystroke dynamics service, voice feature extraction, ONA graph builder, energy model | Phase 1 |
| 3 | Nightly Pipeline | 6-phase consolidation (Haiku→Sonnet→Opus), pattern validation, ACB generation | Phase 1 |
| 4 | Retrieval & Prediction | 5-dimension retrieval, avoidance detection, burnout forecasting, decision reversal | Phase 1, 3 |
| 5 | Intelligence Delivery | Morning briefing engine, alert system, voice delivery, coaching layer | Phase 3, 4 |
| 6 | Privacy & Cold Start | Trust-earning sequence, progressive permissions, default intelligence library, onboarding | Phase 1, 5 |

## Research Library
- **14 Deep Research reports:** `research/perplexity-outputs/v2/v2-01` through `v2-14`
- **14 decision extractions:** `research/extractions/extract-01` through `extract-14`
- **3 architecture syntheses:** `research/ARCHITECTURE-MEMORY.md`, `ARCHITECTURE-SIGNALS.md`, `ARCHITECTURE-DELIVERY.md`

Any future build session should read `CLAUDE.md` → `BUILD_STATE.md` → relevant `ARCHITECTURE-*.md` → build.
Last Session: 2026-04-11 15:38
