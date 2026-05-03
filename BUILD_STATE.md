# BUILD_STATE.md — Last updated: 2026-05-03 (AI estimation remote gate)

> **AI estimation remote gate 2026-05-03** — Repaired the Wave 2 estimation path after the remote gate failed. `bucket_completion_stats` / `bucket_estimates` now exist before bucket normalization runs, task estimate writeback checks PostgREST errors and clears stale manual estimates, Swift task saves preserve AI provenance, reload prefers AI estimates when `estimate_source` says AI/default, reason chips attach to the inserted override event id, authenticated behaviour-event insert/update policies are live, and public RLS helper execution is granted for authenticated users.

> **Verified 2026-05-03 AI estimation remote gate** — `swift build` ✅; `swift test` ✅ (95 tests); `deno check supabase/functions/estimate-time/index.ts supabase/functions/generate-morning-briefing/index.ts` ✅; `supabase db push --include-all --linked --yes` ✅ through `20260503202000_grant_public_rls_helper_execution.sql`; `estimate-time` and `generate-morning-briefing` redeployed ✅; authenticated remote smoke ✅: schema columns visible, bootstrap succeeds, task insert succeeds, `estimate-time` writes `estimated_minutes_ai`, clears `estimated_minutes_manual`, sets `estimate_source`/`estimate_uncertainty`, and authenticated `behaviour_events` insert/update stores the reason metadata. Test rows were deleted after smoke. `graphify update .` ✅.

> **Known after AI estimation remote gate** — `supabase db lint --linked` still reports pre-existing broken legacy SQL functions (`match_tier0_observations`, `compute_baselines`, `compute_degree_centrality`, `compute_relationship_health`, `check_validation_gates`, `compute_weekly_ccr`) against missing/renamed tables or vector operator casts. This is separate from the estimation/task remote gate, which passed.

> **Briefing empty-state copy 2026-05-03** — Removed the consumer-visible Trigger.dev dashboard instruction from the Morning Briefing empty state. The post-onboarding fallback now explains that Timed needs enough recent activity before it can create a useful briefing.

> **Verified 2026-05-03 briefing copy fix** — `swift build` ✅; `swift test` ✅ (94 tests); `bash scripts/package_app.sh` ✅; `bash scripts/install_app.sh` ✅; `/Applications/Timed.app` `codesign --verify --deep --strict --verbose=2` ✅; installed binary matches `dist.noindex/Timed.app` at SHA-256 `8bb426f0fb4e72840f4ed68b020c4fa6bffa4972c7b88cc91fd59716ae9c0592`; `graphify update .` ✅.

> **Calendar header spacing 2026-05-03** — Fixed the weekly Calendar header row so the empty time-column spacer cannot stretch the header vertically. The week title, day labels, and hour grid now stay pinned together at the top instead of leaving the days halfway down the screen.

> **Verified 2026-05-03 calendar fix** — `swift build` ✅; `swift test` ✅ (94 tests); `bash scripts/package_app.sh` ✅; `bash scripts/install_app.sh` ✅; `/Applications/Timed.app` `codesign --verify --deep --strict --verbose=2` ✅; installed binary matches `dist.noindex/Timed.app` at SHA-256 `2b2e2e630154218d7090ffb82237f4b02f26b8933fb46e22a28da086af9562b7`; `graphify update .` ✅.

> **Morning interview spacing 2026-05-03** — Rebalanced the morning interview card after the energy-step screenshot review. The modal is taller, header/footer padding is roomier, the energy step has more top/bottom breathing room, and each energy option row has larger horizontal/vertical padding.

> **Verified 2026-05-03 spacing fix** — `swift build` ✅; `swift test` ✅ (94 tests); `bash scripts/package_app.sh` ✅; `bash scripts/install_app.sh` ✅; `/Applications/Timed.app` `codesign --verify --deep --strict --verbose=2` ✅; installed binary matches `dist.noindex/Timed.app` at SHA-256 `3c56ce3d5727b0d8973402001954a37e4501cc4c8df0eb81d3b667c59bf728f9`.

> **Installed app refresh 2026-05-03** — Rebuilt the macOS app from `unified` through `a6fdc4e` plus the existing local Swift worktree edits, installed it to `/Applications/Timed.app`, and relaunched the Dock-pinned app from that path. Fixed `scripts/package_app.sh` so ad-hoc signing no longer fails on macOS Bash when the codesign options list is empty.

> **Verified 2026-05-03 app refresh** — `bash scripts/package_app.sh` ✅; `bash scripts/install_app.sh` ✅; `/Applications/Timed.app` `codesign --verify --deep --strict --verbose=2` ✅; `/Applications/Timed.app/Contents/MacOS/timed` matches `dist.noindex/Timed.app/Contents/MacOS/timed` at SHA-256 `9c934118c83c1e201131c994349176db54cceb3fd10ddd3162e02b42673011bd`; `swift test` ✅ (94 tests); `graphify update .` ✅.

> **Next after app refresh** — Use the Dock-pinned Timed app; it points at `/Applications/Timed.app`. The local worktree still has uncommitted Swift edits in `DataBridge.swift`, `PreviewData.swift`, `TasksPane.swift`, and `TimedRootView.swift`.

> **Task correction logging 2026-05-01** — Implemented Gate 3 silent-learning event wiring. `BehaviourEventInsert` now carries `section_id`, `parent_task_id`, and event metadata; `DataBridge` centralizes task completion, bucket/section, estimate override, subtask-created, and manual-importance correction events; ConversationTools, Today, Tasks, Task Detail, and Morning Review estimate changes now route estimate corrections through that shared event writer.

> **Verified 2026-05-01 task correction logging** — `swift build` ✅; `swift test --filter DataBridgeTests` ✅ (19 tests); `swift test` ✅ (94 tests). Supabase local lint/reset remains blocked by unavailable local Postgres/OrbStack as recorded below.

> **Next after task correction logging** — Gate 4: expose task sections/subtasks/manual importance in the task UI and keep Edge Function tool schemas aligned with the new Swift mutation surface.

> **Task hierarchy Swift persistence 2026-05-01** — Implemented Gate 2 model/persistence wiring. `TimedTask` now carries optional `sectionId`, `parentTaskId`, `sortOrder`, manual blue/orange/red importance, notes, and planning-unit state; `TaskSection` / `TaskSectionDBRow` model the sidebar hierarchy; `SupabaseClient` can fetch/upsert `task_sections`; `DataBridge` can load/save task sections, queue offline section upserts, replay them, remote-overlay task loads, and persist hierarchy fields on task upserts while marking parents with active subtasks as non-planning units. Existing task rebuild paths preserve the new fields.

> **Verified 2026-05-01 task hierarchy Swift persistence** — `swift build` ✅; `swift test --filter DataBridgeTests` ✅ (17 tests); `swift test` ✅ (92 tests). Supabase local lint/reset still blocked by unavailable local Postgres/OrbStack as recorded below.

> **Next after Swift persistence** — Gate 3: add the mutation/logging service so estimate, section, subtask, and manual-importance corrections write consistent `behaviour_events` payloads for silent learning before UI controls are exposed.

> **Task hierarchy schema 2026-05-01** — Implemented Gate 1 of the TickTick-style hierarchy plan. Added migration `20260501211829_task_hierarchy_schema.sql` with `canonical_bucket`, `task_sections` and system section seeding, task `section_id` / `parent_task_id` / `sort_order` / `manual_importance` / planning-unit fields, one-level hierarchy triggers, subtask parent planning sync, parent-delete promotion, hierarchy-aware behaviour events, `estimate_priors`, private-helper RLS, and future behaviour-event partitions through 2026-12. Swift model/UI persistence expansion is still intentionally not landed.

> **Verified 2026-05-01 task hierarchy schema** — `swift build` ✅; `swift test --filter ProductionReadinessGuardTests` ✅ (7 tests); `swift test` ✅ (89 tests). `supabase db lint` could not run because local Postgres refused `127.0.0.1:54322`; `supabase start` could not start it because the OrbStack Docker socket was unavailable.

> **Next after task hierarchy schema** — Gate 2: extend Swift task/section DTOs and `DataBridge` persistence against the new schema, then wire mutation logging so section, estimate, subtask, and importance corrections feed silent learning consistently.

> **Task bucket normalization 2026-05-01** — Implemented Gate 0 of the task hierarchy plan. `TaskBucket` now has DB-safe `dbValue` / `from(dbValue:)` mapping, `DataBridge` task upserts and Today behaviour/estimate writes use snake_case bucket values, and migration `20260501211002_normalize_task_bucket_values.sql` backfills existing bucket-bearing tables while adding `cc_fyi` support and preserving `other`.

> **Verified 2026-05-01 bucket normalization** — `swift build` ✅; `swift test --filter DataBridgeTests` ✅ (14 tests); `swift test` ✅ (87 tests). `supabase db lint` could not run because local Postgres was not running; `supabase start` could not start it because the Docker/OrbStack daemon was unavailable.

> **Next after bucket normalization** — Gate 1: review and land the `task_sections` / task hierarchy schema migration before extending Swift task models.

> **Readiness cleanup 2026-05-01** — Narrowed production claims without wiring new surfaces. iOS remains simulator-build/scaffold only: TimediOS tabs are placeholders; BGTask workers, APNs token sink, and silent-push sync are not installed; the Share extension writes `share-queue.jsonl` without a main-app drain; widget snapshot writes and the Live Activity coordinator are not wired. `deepgram-transcribe` is local-only batch ASR; live `ConversationView` speech ingress uses `deepgram-token` + Deepgram WSS. `generate-embedding` is disabled and returns dimension `0`; app MemoryStore embedding calls are not production-ready until that function is re-enabled or replaced.

> **Installed app fix 2026-05-01** — Shipped and installed the Timed.app fixes for repeated launch login prompts and Capture voice permission failures. `AuthService.bootstrapExecutive()` no longer auto-opens Outlook/MSAL on launch; Capture voice now surfaces speech/microphone authorization failures with an Open Settings action; `scripts/package_app.sh` now carries Google OAuth plist config; the voice audio tap is isolated from `@MainActor` state. `/Applications/Timed.app` was rebuilt, installed, verified, and matches `dist.noindex/Timed.app` at binary SHA-256 `e5838964834b4e2668357313d0c8930fe65271dd4b8726b739963c2366108664`.

> **Verified 2026-05-01 app fix** — `swift build` ✅; `swift test` ✅ (71 tests); `bash scripts/package_app.sh` ✅; `/Applications/Timed.app` `codesign --verify --deep --strict --verbose=2` ✅; Dock item verified as `Timed` under persistent apps.

> **Next after app fix** — Launch Timed from the Dock. Outlook should not prompt during normal app bootstrap. If Capture reports blocked voice permissions, click Open Settings and enable Timed under macOS Privacy for Microphone/Speech Recognition.

> **Review remediation 2026-05-01** — Implemented the first review-plan fix batch on `unified`: removed/parameterized local secret surfaces, authenticated paid-provider and privileged Edge Functions, protected Graphiti core routes, added tenant ownership checks and Graph webhook `clientState` validation, repaired email/Gmail classify-email contracts and cursor advancement, added Tier 0 idempotency, and aligned macOS package/notarization/CI artifact paths.

> **Verified 2026-05-01** — `swift build` ✅; `swift test` ✅ (71 tests); `deno check` ✅ for the changed Edge Functions; `python3 -m py_compile services/graphiti/app/main.py` ✅; `pnpm typecheck` ✅ in `services/graphiti-mcp`; `bash -n scripts/package_app.sh scripts/notarize_app.sh` ✅. `gitleaks` and `actionlint` were not installed locally.

> **Remaining after this pass** — rotate exposed credentials out-of-band, deploy the Supabase function and migration changes, then continue with the larger open items: identity/bootstrap model alignment, durable offline queue replay, server-side Graph account schema drift, Xcode target CI coverage, and release signing with a real Developer ID certificate.

> **Current state 2026-04-30** — `unified` remains the single active trunk. Microsoft email/calendar was verified end-to-end on 2026-04-29. Gmail + Google Calendar were added as a parallel path in commit `4e5cf9e`, with no Microsoft-path rewrites. Gmail backend migration + `voice-llm-proxy` OR-gate are now live remotely. Trigger.dev Wave 2 Opus aliases route to 4.7; older Supabase Edge Functions still contain direct 4.6 IDs. Graphiti one-shot backfill completed in Prod run `run_cmol21ysj5ohl0unbrlg495f2`. `HANDOFF.md` is the live narrative; this file is the build-state ledger.

> **Verified via CLI 2026-04-30** — Supabase remote has **39 ACTIVE Edge Functions**. Local tree has **40 function dirs + `_shared`**; `deepgram-transcribe` is local-only. `supabase migration list --linked` showed **64 remote migrations applied**, including `20260430120000_gmail_provider.sql`.

> **Pending ops** — (1) launch Timed and connect Gmail with `5066sim@gmail.com`, (2) resume Apple Developer enrollment for notarised Mac/iOS delivery, (3) decide whether to deploy optional local-only `deepgram-transcribe`, (4) wire iOS/share/widget/Live Activity/background paths before making production iOS claims.

> **Beta sprint SHIPPED 2026-04-28 PM** — commits `bcee82b` + `ec3a7fd` on `origin/unified`. 9 fixes from Beta-Ready Execution Plan + 3 Perplexity Deep Research audits: email/password auth, MainActor crash fix, smooth login transitions, Microsoft 4-square logo, "Set up later" plumbing, auth cascade (`bootstrapExecutive` → `signInWithGraph` → email + calendar sync), `v1BetaMode` defaulted false, `MorningBriefingPane` reachable, AlertEngine wired via new `AlertsPresenter`, `EmailClassifier.classifyLive` via anthropic-relay, iOS orb sheet → `ConversationView` with empty task/calendar state, DishMeUp bucket dotColors + `sessionFraming` semibold, voice path guard test. Build green; `/Applications/Timed.app` was rebuilt. iOS remains scaffold/simulator-build only.

> **Single source of truth: `unified` branch.** As of 2026-04-27 the four divergent branches (`ui/apple-v1-restore`, `ui/apple-v1-local-monochrome`, `ui/apple-v1-wired`, `ios/port-bootstrap`) have been merged into one trunk. See **`docs/UNIFIED-BRANCH.md`** for the permanent architecture reference and **`docs/SINCE-2026-04-24.md`** for the narrative of how we got here.
>
> **Build matrix from `unified` (verified):** `swift build` ✅ · `xcodebuild TimedMac` ✅ (arm64 only) · `xcodebuild TimediOS sim` ✅ compile-only. **DMG produced:** `dist.noindex/Timed.dmg` (31 MB, ad-hoc signed).
>
> **Daily Mac use (Ammar, today, no cert needed):** `bash scripts/package_app.sh && bash scripts/install_app.sh` → `/Applications/Timed.app`. First launch: right-click → Open. Re-run after code changes. Active dev: `bash scripts/watch-and-build.sh`. See HANDOFF.md Chain A.1.
>
> **Apple Developer enrollment PARKED 2026-04-27** — Ammar attempted enrollment, redirected to free-tier `/account` (paid Program upgrade not yet started). Resume when there's a clear window. While parked: iOS unreachable (Track B = Xcode Personal Team, 7-day expiry); DMG remains ad-hoc signed (works with `xattr -cr /Applications/Timed.app` workaround). See HANDOFF.md Chain C.

> **Tree cleanup 2026-04-29** — repo went 9.4G → 285M. Wiped (gitignored, regeneratable): `.build/` (8.5G), `dist.noindex/` (122M, including the v0.1.0–0.1.3 zips and `Timed.dmg` — re-run `bash scripts/package_app.sh && bash scripts/create_dmg.sh` to rebuild), root `node_modules/` + `pnpm-lock.yaml` (520M, "stray" per .gitignore — real lockfile is under `trigger/`). Archived to `~/Archive/2026-04-29/timed/`: stale `specs/{BUILD_STATE,build-state,SESSION_LOG}.md` (Apr 2 copies superseded by root files); `logs/` watchdog logs (6.6M). DerivedData (8.3G across two Timed-* dirs, both <30 days old) left in place. Sibling dirs `Timed-Brain` (2.1G), `time-manager-desktop-isolated-git` (3.9G) untouched. Older `HANDOFF-wave2.md` remains historical only.

## Voice Architecture (current)
| Layer | Tech | Where |
|---|---|---|
| ASR (`ConversationView` orb) | Deepgram Nova-3 WSS via short-lived token | `DeepgramSTTService.swift` + `deepgram-token` |
| LLM (`ConversationView` orb) | Claude via streaming Edge Function | `supabase/functions/orb-conversation/index.ts` |
| TTS (`ConversationView` orb) | `orb-tts`; fallback to `elevenlabs-tts-proxy` one-shot | `StreamingTTSService.swift` / `SpeechService.swift` |
| Voice onboarding / morning check-in | ElevenLabs Conversational Agent | `MorningCheckInManager.swift` |
| LLM (Capture / Onboarding / Interview) | Claude Opus 4.7 via proxy | `supabase/functions/anthropic-proxy/index.ts` |
| TTS (one-shot, Capture / Dish Me Up) | ElevenLabs Lily via proxy | `supabase/functions/elevenlabs-tts-proxy/index.ts` |
| Batch ASR (parked, non-conversational) | Deepgram Nova-3 via local-only proxy | `supabase/functions/deepgram-transcribe/index.ts` (not deployed remotely) |

**Zero per-machine setup**: Agent ID, Supabase URL, anon JWT, Graph client/tenant IDs are all baked-in constants. All third-party API keys live server-side (Anthropic, ElevenLabs, Deepgram, Gemini) — the binary holds none.

**Deepgram function split**: `deepgram-token` is the live token issuer for `ConversationView`'s direct Deepgram WSS path. `deepgram-transcribe` is a parked batch-transcription proxy and is not deployed remotely.

## What Exists and Works

### Signal Ingestion ✅
- [x] GraphClient.swift — MSAL auth + delta email sync + calendar events + webhooks (489 lines)
- [x] EmailSyncService.swift — Actor, delta sync, folder-move detection, reply latency social graph (606 lines)
- [x] CalendarSyncService.swift — Actor, Outlook events → CalendarBlocks, free-time gap detection (201 lines)
- [x] VoiceCaptureService.swift — Apple Speech (SFSpeechRecognizer + AVAudioEngine), live transcript (368 lines)
- [x] VoiceResponseParser.swift — Parses spoken commands during morning interview (365 lines)
- [x] NetworkMonitor.swift — NWPathMonitor wrapper (21 lines)
- [x] EmailClassifier.swift — Protocol + stub, real classification via Edge Function (🔄 placeholder)

### Memory Store ⚠️ (schema + actors exist; app embeddings disabled)
- [x] DataStore.swift — Local JSON persistence actor, ~/Library/Application Support/Timed/ (113 lines)
- [x] SupabaseClient.swift — 11 row types, 20+ operations, full CRUD (764 lines)
- [x] Domain models — TimedTask, TaskBucket, TriageItem, WOOItem, CaptureItem, CalendarBlock, etc.
- [x] Tier 0 — tier0_observations table + Tier0Writer actor + Tier0Observation DTO
- [x] Tier 1 — tier1_daily_summaries table + nightly Opus generation
- [x] Tier 2 — tier2_behavioural_signatures table + weekly pattern detection + 4-gate validation
- [x] Tier 3 — tier3_personality_traits table + monthly Opus synthesis
- [x] ACB — active_context_buffer (dual: ACB-FULL 10-12K + ACB-LIGHT 500-800 tokens)
- [x] MemoryStore protocol + 5-dimension retrieval engine (RetrievalEngine.swift)
- [ ] App MemoryStore embeddings — `EmbeddingService` exists, but `generate-embedding` is a disabled stub that returns dimension `0`
- [x] DataBridge actor + GRDB offline queue (OfflineSyncQueue.swift)

### Reflection Engine ✅ (COMPLETE — 4-cron nightly pipeline)
- [x] PlanningEngine.swift — Composite scoring, Thompson sampling, behavioural rules, mood modifiers (501 lines)
- [x] TimeSlotAllocator.swift — Calendar-aware slot allocation, energy tiers, incremental repair (612 lines)
- [x] InsightsEngine.swift — Estimated vs actual time comparison (28 lines, minimal)
- [x] TaskExtractionService.swift — Thread grouping, bucket detection, time estimation (178 lines)
- [x] Nightly consolidation (2 AM) — importance scoring (Haiku+Sonnet), conflict detection, Opus daily summary, ACB gen, self-improvement loop
- [x] Morning refresh (5:15 AM) — overnight importance audit, summary addendum, ACB refresh
- [x] Morning briefing (5:30 AM) — Opus two-pass with adversarial review, engagement self-correction
- [x] Weekly pruning (Sunday 3 AM) — Tier 0 archival/tombstone, Tier 2 fading
- [x] Weekly pattern detection — Opus cross-domain analysis, Tier 2 candidate generation
- [x] Monthly trait synthesis — Opus Stage A (traits) + Stage B (predictions)
- [x] BOCPD change detection — student-t predictive, CDI computation
- [x] 5-dimension retrieval — recency × importance × relevance × temporal × tier_boost

### Delivery ✅ (UI complete — intelligence delivery not started)
- [x] TimedRootView.swift — Root nav, all state management (489 lines, 🔄 god-view)
- [x] TodayPane.swift — Today dashboard
- [x] TriagePane.swift — Keyboard-driven email triage, undo stack, AI correction logging (620 lines)
- [x] TasksPane.swift — Per-bucket task list, bulk ops, context menu (546 lines)
- [x] PlanPane.swift — Full planning pane (634 lines, 🔄 duplicates DishMeUpSheet logic)
- [x] DishMeUpSheet.swift — "I have X minutes" planning (555 lines)
- [x] FocusPane.swift — Circular countdown timer, Pomodoro, session persistence (505 lines)
- [x] CalendarPane.swift — Weekly grid, drag-to-create, Outlook sync (656 lines)
- [x] CapturePane.swift — Voice/text quick capture with Opus AI extraction (530 lines)
- [x] CaptureAIClient.swift — Claude Opus 4.7 tool use for intelligent task parsing (145 lines)
- [x] InterviewAIClient.swift — Opus-powered morning interview with ACB context (359 lines)
- [x] SpeechService.swift — ElevenLabs TTS (Lily default) + AVSpeechSynthesizer fallback (192 lines)
- [x] OnboardingFlow.swift — 10-step wizard with ElevenLabs voice narration + hero screen (580 lines)
- [x] MorningInterviewPane.swift — 5-step voice morning interview (500+ lines)
- [x] CommandPalette.swift — Cmd+K, fuzzy search, action registry (264 lines)
- [x] MenuBarManager.swift — NSStatusItem, current task, next event (358 lines)
- [x] QuickCapturePanel.swift — Cmd+Shift+Space floating panel (141 lines)
- [x] OnboardingFlow.swift — 9-step first launch (655 lines)
- [x] PrefsPane.swift — Settings tabs (414 lines)
- [x] WaitingPane.swift — WOO tracker (456 lines)
- [x] SharingPane.swift — Workspace sharing (260 lines)
- [x] MorningBriefingPane.swift — 7-section CIA PDB format, confidence badges, engagement tracking
- [x] AlertDeliveryView.swift — Menu bar alerts, 5-dim scoring, feedback loop
- [x] AlertEngine.swift — Multiplicative scoring, 3/day cap, adaptive threshold
- [x] CoachingTrustCalibrator — 4-stage trust progression, rupture protocol

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
- [x] Voice/readiness guard tests — static guards for voice path, classify-email contract, email upsert conflict target, and honest iOS readiness claims
- [ ] TimeSlotAllocator tests — NOT STARTED
- [ ] EmailSyncService tests — NOT STARTED
- [ ] VoiceResponseParser tests — NOT STARTED
- [ ] Memory store tests — NOT STARTED
- [ ] Reflection engine tests — NOT STARTED

### Backend (Supabase)
- [x] 64 SQL migrations applied remotely (verified with `supabase migration list --linked` 2026-04-30)
- [x] `20260430120000_gmail_provider.sql` applied remotely 2026-04-30
- [x] 39 Edge Functions active remotely (verified with `supabase functions list --project-ref fpmjuufefhtlwbfinxlx` 2026-04-30; `voice-llm-proxy` + 16 hardened functions redeployed)
- [ ] `deepgram-transcribe` exists locally but is not deployed remotely
- [x] Anthropic API key set in Supabase secrets
- [ ] `generate-embedding` is disabled locally and returns empty embeddings with dimension `0`; Voyage remains used by Graphiti/skill-library paths, but app MemoryStore embedding calls are not production-ready
- [x] Microsoft OAuth app registration (Azure) — client secret expires 2028-04-11
- [x] Azure provider enabled in Supabase Auth dashboard, redirect URLs configured
- [x] Shared Anthropic API helper (_shared/anthropic.ts) with Batch API + effort parameter routing

## Known Issues / Landmines
- PreviewData.swift contains ALL domain models (587 lines) — should split into Core/Models/
- AuthService creates its own SupabaseClient, violating DI pattern
- PlanPane and DishMeUpSheet duplicate plan generation logic
- TimedRootView is a 489-line god-view holding all @State arrays
- TCA dependency declared but only used for @Dependency injection, not state management
- No CoreData/SwiftData — persistence is JSON local + Supabase remote
- Legacy/ folder (41 files) excluded from build, kept as reference

## Architecture Status: Orb is now Microsoft + Gmail + Graphiti aware (2026-04-30)
> **Updated 2026-04-30** — `voice-llm-proxy` pulls a 24h inbox snapshot into context and gates inbox confidence on `(outlook_linked OR gmail_linked)` in live remote code. The Microsoft path is live after `signInWithGraph()`; the Gmail path now needs the app sign-in step with `5066sim@gmail.com`. Graphiti search is wired as a server-side tool, and the one-shot historical backfill completed in Trigger.dev Prod run `run_cmol21ysj5ohl0unbrlg495f2` with 2 Tier 0 observations emitted.

## Architecture Status: Intelligence Engine + Auth Bridge COMPLETE
> **Updated 2026-04-14** — Intelligence Maximisation Plan (12 steps) implemented. Auth bridge wired. App ready for first sign-in.

### Intelligence Engine (complete)
- [x] 5-tier memory (Tier 0-3 + ACB) — deployed, Swift actors, continuous ACB refresh (3x daily)
- [x] 4-cron nightly pipeline + effort parameter routing (replaces fixed thinking budgets)
- [x] 9 signal agents + real-time dual-scoring (Haiku RT at ingestion + Sonnet batch nightly)
- [x] ONA relationship graph + relationship intelligence cards (15-field, 3-layer disclosure)
- [x] Prediction layer — avoidance (3-stream), burnout, decision reversal, executive bias detection (6 biases)
- [x] Alert system — dual-scoring thresholds (0.90/0.80/0.75), deadline modifier, never-retract rule
- [x] Adversarial CCR briefing review — 10-check template, cross-context architecture
- [x] Weekly strategic synthesis (Opus max effort, Sunday 3 AM)
- [x] Privacy — consent state machine, KEK/DEK encryption, data export + deletion

### Auth & Sync Bridge (complete)
- [x] Supabase anon key hardcoded (was "" → client null)
- [x] OnboardingFlow shows Sign In buttons (was checking env vars with no fallback)
- [x] DataBridge dual-write: local first, fire-and-forget Supabase sync
- [x] URL scheme `timed://auth/callback` registered in dist/ Info.plist
- [x] Azure AD app registration fully configured (Supabase callback + MSAL redirect)

### Remaining
- Verification tasks (blocked on live data + first sign-in)
- URL scheme needs .app bundle (`swift build` creates bare executable)
- Whisper.cpp (research gap)
- Phase 13 (Month 11+ — requires accumulated data)

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
Last Session: 2026-05-03 16:18

### Intro + Brand System (new)
- [x] IntroFeature.swift — TCA 1.15+ @Reducer, phase machine (reveal → tagline → holding → exiting → finished)
- [x] IntroView.swift — circular mask reveal, MeshGradient hue drift, staggered word tagline, Reduce Motion collapse
- [x] BrandTokens.swift — BrandColor/Motion/Type/Version + BrandAsset.logoImage loader via Bundle.module
- [x] TimeManagerDesktopApp.swift — .windowStyle(.hiddenTitleBar), @AppStorage(BrandVersion.introSeenKey) gate
- [x] Sources/Resources/BrandLogo.png — copied from white-clock AppIcon (placeholder, pending real logo)

### Dish Me Up + Voice Onboarding ✅ (2026-04-24)
- [x] `generate-dish-me-up` Edge Function — 7-parallel DB read, Opus 4.6 + extended thinking (budget 10k / max 14k), cache_control ephemeral, knapsack 5-min-buffer, last_viewed_at stamping. Deployed, smoke-tested, Signal 7 verified live.
- [x] `voice-llm-proxy` — OpenAI SSE wrapper. Branches on `executives.onboarded_at`: null → Haiku (no thinking, ≤1s first token); set → Opus + thinking 4000. Filters thinking deltas so they never reach TTS.
- [x] `extract-voice-learnings` + `extract-onboarding-profile` — Haiku structured extraction. Onboarding extractor flips `onboarded_at = NOW()`.
- [x] `DishMeUpHomeView.swift` — eyebrow + headline hero (matches app scale), minute selector, primary button, collapsible voice check-in entry.
- [x] `MorningCheckIn/{Manager, View, MicActivityBar, OrbView}.swift` — ElevenLabs Conversation observer, orb + synthetic mic activity bar + collapsible transcript.
- [x] `VoiceOnboardingView.swift` — full-screen orb setup replacing the old 10-step form. Detects `[[ONBOARDING_COMPLETE]]` tag, posts transcript to extractor, flips hasCompletedOnboarding.
- [x] Package.swift — ElevenLabs Swift SDK 2.0.16 (pulls LiveKit + async-algs). `scripts/package_app.sh` now embeds LiveKitWebRTC.framework. `scripts/render_app_icons.sh` short-circuits when iconset exists.
- [x] Migrations 20260424000001 (voice_session_learnings, calendar_events view, tasks.last_viewed_at) + 20260424000002 (unschedule 4 no-consumer crons). Both pushed.
- [x] ElevenLabs agent `agent_3501kpyz0cnrfj8tgbb2bmg5arfk` — voice = Charlotte, speed 0.8, stability 0.55, first_message cleared.
- [x] Prompt hardening: "Timed never acts on the world" absolute boundary on all 3 prompts (onboarding, morning check-in, Dish Me Up). 3-field setup checklist (work hours / email cadence / transit). Single-turn rule (no hammering).
- [x] Cut dead code: adversarial ACB critique removed from acb-refresh, importance_scoring stage commented out in nightly-phase1, generate-embedding stubbed (no OpenAI).
- [x] Packaged `dist/Timed.app`, codesigned, launches cleanly with LiveKitWebRTC + MSAL embedded.

### Remaining (as of 2026-04-24 wrap)
- Yasser to complete a real onboarding conversation in the packaged app (not confirmed working end-to-end by user yet as of wrap).
- Wire non-display-name profile fields (work_hours, transit_modes, email_cadence_pref) into a persistence target — currently extracted but not written.
- Delete old OnboardingFlow.swift (unreachable from TimedRootView now).
- Pre-existing `swift test` failure on `PlanTask` constructor mismatch (not Dish-Me-Up related).
- ANTHROPIC_API_KEY was pasted in chat history; user declined rotation. Worth revisiting.
