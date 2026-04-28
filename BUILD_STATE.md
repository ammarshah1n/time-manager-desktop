# BUILD_STATE.md — Last updated: 2026-04-28 14:00 (Beta-readiness sprint shipped on `unified` — auth cascade live, alerts wired, briefing reachable, EmailClassifier live, iOS orb wired; ops backlog held for tonight)

> **Beta sprint SHIPPED 2026-04-28 PM** — commits `bcee82b` + `ec3a7fd` on `origin/unified`. 9 fixes from Beta-Ready Execution Plan + 3 Perplexity Deep Research audits: email/password auth, MainActor crash fix, smooth login transitions, Microsoft 4-square logo, "Set up later" plumbing, auth cascade (`bootstrapExecutive` → `signInWithGraph` → email + calendar sync), `v1BetaMode` defaulted false, `MorningBriefingPane` reachable, AlertEngine wired via new `AlertsPresenter`, `EmailClassifier.classifyLive` via anthropic-relay, iOS orb sheet → `ConversationView`, DishMeUp bucket dotColors + `sessionFraming` semibold, voice path guard test. Build green; `/Applications/Timed.app` is the new build.

> **Held for tonight (onsite, ~30 min):** (1) `supabase secrets set ELEVENLABS_API_KEY` + deploy `anthropic-proxy` and `elevenlabs-tts-proxy`, (2) `cd trigger && pnpm install && pnpm run deploy` to fire the nightly pipeline, (3) Graphiti backfill one-shot on Fedora. After all three: orb actually has data. TickTick task: "Tonight onsite: deploy voice proxies + Trigger.dev + Graphiti backfill" in Timed project.

> **Single source of truth: `unified` branch.** As of 2026-04-27 the four divergent branches (`ui/apple-v1-restore`, `ui/apple-v1-local-monochrome`, `ui/apple-v1-wired`, `ios/port-bootstrap`) have been merged into one trunk. See **`docs/UNIFIED-BRANCH.md`** for the permanent architecture reference and **`docs/SINCE-2026-04-24.md`** for the narrative of how we got here.
>
> **Build matrix from `unified` (verified):** `swift build` ✅ · `xcodebuild TimedMac` ✅ (arm64 only) · `xcodebuild TimediOS sim` ✅. **DMG produced:** `dist.noindex/Timed.dmg` (31 MB, ad-hoc signed).
>
> **Daily Mac use (Ammar, today, no cert needed):** `bash scripts/package_app.sh && bash scripts/install_app.sh` → `/Applications/Timed.app`. First launch: right-click → Open. Re-run after code changes. Active dev: `bash scripts/watch-and-build.sh`. See HANDOFF.md Chain A.1.
>
> **Apple Developer enrollment PARKED 2026-04-27** — Ammar attempted enrollment, redirected to free-tier `/account` (paid Program upgrade not yet started). Resume when there's a clear window. While parked: iOS unreachable (Track B = Xcode Personal Team, 7-day expiry); DMG remains ad-hoc signed (works with `xattr -cr /Applications/Timed.app` workaround). See HANDOFF.md Chain C.

## Voice Architecture (current)
| Layer | Tech | Where |
|---|---|---|
| ASR (orb conversation) | ElevenLabs Scribe v2 Turbo | inside the Conversational Agent |
| LLM (orb conversation) | Claude **Opus 4.7** | `supabase/functions/voice-llm-proxy/index.ts` |
| TTS (orb conversation) | ElevenLabs voice (agent-baked) | inside the Conversational Agent |
| LLM (Capture / Onboarding / Interview) | Claude Opus 4.7 via proxy | `supabase/functions/anthropic-proxy/index.ts` |
| TTS (one-shot, Capture / Dish Me Up) | ElevenLabs Lily via proxy | `supabase/functions/elevenlabs-tts-proxy/index.ts` |
| Batch ASR (parked, non-conversational) | Deepgram Nova-3 via proxy | `supabase/functions/deepgram-transcribe/index.ts` |

**Zero per-machine setup**: Agent ID, Supabase URL, anon JWT, Graph client/tenant IDs are all baked-in constants. All third-party API keys live server-side (Anthropic, ElevenLabs, Deepgram, Gemini) — the binary holds none.

**Why no Deepgram in the orb**: ElevenLabs Conversational AI locks ASR to their own models — Deepgram isn't a selectable provider. Deepgram subscription preserved for batch / non-conversational paths.

## What Exists and Works

### Signal Ingestion ✅
- [x] GraphClient.swift — MSAL auth + delta email sync + calendar events + webhooks (489 lines)
- [x] EmailSyncService.swift — Actor, delta sync, folder-move detection, reply latency social graph (606 lines)
- [x] CalendarSyncService.swift — Actor, Outlook events → CalendarBlocks, free-time gap detection (201 lines)
- [x] VoiceCaptureService.swift — Apple Speech (SFSpeechRecognizer + AVAudioEngine), live transcript (368 lines)
- [x] VoiceResponseParser.swift — Parses spoken commands during morning interview (365 lines)
- [x] NetworkMonitor.swift — NWPathMonitor wrapper (21 lines)
- [x] EmailClassifier.swift — Protocol + stub, real classification via Edge Function (🔄 placeholder)

### Memory Store ✅ (5-tier intelligence memory COMPLETE)
- [x] DataStore.swift — Local JSON persistence actor, ~/Library/Application Support/Timed/ (113 lines)
- [x] SupabaseClient.swift — 11 row types, 20+ operations, full CRUD (764 lines)
- [x] Domain models — TimedTask, TaskBucket, TriageItem, WOOItem, CaptureItem, CalendarBlock, etc.
- [x] Tier 0 — tier0_observations table + Tier0Writer actor + Tier0Observation DTO
- [x] Tier 1 — tier1_daily_summaries table + nightly Opus generation
- [x] Tier 2 — tier2_behavioural_signatures table + weekly pattern detection + 4-gate validation
- [x] Tier 3 — tier3_personality_traits table + monthly Opus synthesis
- [x] ACB — active_context_buffer (dual: ACB-FULL 10-12K + ACB-LIGHT 500-800 tokens)
- [x] MemoryStore protocol + 5-dimension retrieval engine (RetrievalEngine.swift)
- [x] LocalVectorStore (USearch HNSW) + EmbeddingService (dual-provider: Voyage + OpenAI)
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
- [x] CaptureAIClient.swift — Claude Opus 4.6 tool use for intelligent task parsing (145 lines)
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
- [ ] TimeSlotAllocator tests — NOT STARTED
- [ ] EmailSyncService tests — NOT STARTED
- [ ] VoiceResponseParser tests — NOT STARTED
- [ ] Memory store tests — NOT STARTED
- [ ] Reflection engine tests — NOT STARTED

### Backend (Supabase)
- [x] 48 SQL migrations deployed (all pushed 2026-04-14, including Dish Me Up task fields)
- [x] 29 Edge Functions deployed (all deployed 2026-04-14)
- [x] Anthropic API key set in Supabase secrets
- [x] Dual-provider embeddings: Voyage (Tier 0, 1024-dim) + OpenAI (Tier 1-3, 3072-dim)
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

## Architecture Status: Orb is now Microsoft + Graphiti aware (2026-04-28)
> **Updated 2026-04-28** — `voice-llm-proxy` upgraded: pulls 24h inbox snapshot into context, exposes 3 server-side tools to Opus (`search_emails`, `summarise_thread` via Haiku, `search_graphiti` via Cloudflare-tunnelled Fedora FastAPI). Postgres triggers bridge `email_messages` + `calendar_observations` → `tier0_observations` so the nightly engine and 9am/1pm/5pm ACB refresh see Graph data. Linux intelligence stack reachable from Edge Functions via persistent `timed-cf-tunnel.service` systemd user unit on Fedora. **Lights up the moment auth's `signInWithGraph()` populates `graphAccessToken`.**

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
Last Session: 2026-04-28 23:05

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
