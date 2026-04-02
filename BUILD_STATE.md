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
The entire intelligence infrastructure is missing:
- No three-tier memory (episodic/semantic/procedural)
- No reflection engine (nightly Opus analysis)
- No observation pipeline (behavioural signal capture)
- No memory retrieval system (recency × importance × relevance scoring)
- No intelligence delivery (morning session opens with tasks, not patterns)
- No compounding — the system does not get smarter over time

This is the primary build target. Everything else is foundation.

## Next Phase
Phase 0 — Complete documentation architecture (docs/, skills, commands)
Then: Phase 1 — Data Layer (memory store schema, episodic/semantic/procedural)
