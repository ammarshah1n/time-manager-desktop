# PLAN.md — Timed
<!-- New session: read this → CHANGELOG.md first entry → `swift build && swift test` → working in 30 seconds -->
<!-- Do NOT explore Obsidian/transcripts/specs. Trust this file. Verify infra with CLI if unsure. -->

## CURRENT STATE (2026-05-01)

- **UI complete** — 10 screens + task detail modal + calendar drag-to-create + batch ops + voice morning interview
- **Backend LIVE** — Supabase `fpmjuufefhtlwbfinxlx`, 28 edge functions ACTIVE, all secrets set
- **Azure LIVE** — MSAL OAuth in `GraphClient.swift` (silent + interactive), client secret expires 2028-04-11
- **Auth flow built** — `AuthService.swift`: Microsoft OAuth sign-in, session restore, workspace/profile/email_account bootstrap
- **All 3 ML loops CLOSED** — estimation write-back, email correction write-back, behaviour event logging
- **7-rank ML upgrade shipped** — embeddings, Bayesian estimation, energy curve, social graph, Thompson sampling, active learning
- **Scoring model upgraded** — real Beta Thompson, second-pass knapsack fill, adaptive penalty, overdue cap
- **5-tier intelligence memory COMPLETE** — Tier 0→3 + ACB, dual-provider embeddings (Voyage 1024-dim + OpenAI 3072-dim)
- **4-cron nightly pipeline COMPLETE** — Haiku→Sonnet→Opus chain, adversarial briefing review, self-improvement loop
- **36 SQL migrations deployed** (15 original + 15 intelligence + 6 intelligence maximisation)
- **Tests pass** — 49/49, `swift build` clean (as of 2026-04-14)

## ⚠️ ACTIVE BLOCKER — DB Migration Failure

> **Do not run `supabase db push` until this is resolved.**

- **What failed:** Migration `20260411030000_tier1_daily_summaries.sql` — HNSW index on `VECTOR(3072)` column
- **Error:** `column cannot have more than 2000 dimensions for hnsw index (SQLSTATE 54000)`
- **Root cause:** pgvector HNSW index cap is 2000 dimensions; OpenAI `text-embedding-3-large` outputs 3072-dim vectors which exceeds this limit
- **Pending migrations** (blocked): `20260411030000` through `20260411030004` (5 files)

**Fix options (pick one before retrying deploy):**

| Option | Change | Trade-off |
|--------|--------|-----------|
| A — Reduce dimensions | Truncate OpenAI embeddings to 1536-dim via `dimensions` API param | Minor accuracy loss (~1-2%), fixes blocker immediately |
| B — IVFFlat instead of HNSW | Replace `USING hnsw` with `USING ivfflat (lists = 100)` for 3072-dim columns | Slower recall, no dimension cap, works today |
| C — Swap to Voyage for all tiers | Switch Tier 1-3 to Voyage v3 (1024-dim) for cross-tier consistency | Best for cross-tier retrieval, requires re-embedding on first run |

**Recommended:** Option A (fastest to unblock). Change `text-embedding-3-large` calls to include `dimensions: 1536` in `EmbeddingService.swift` and rebuild affected migrations to use 1536-dim HNSW.

## WHAT WORKS END-TO-END

- Email sync pipeline: `GraphClient.fetchDeltaMessages` → `EmailSyncService` → Supabase → `classify-email` (Haiku + semantic few-shot)
- Time estimation: 4-tier (embedding similarity → historical → Bayesian Sonnet → personalised defaults from `bucket_estimates`)
- Planning: `PlanningEngine` with Thompson sampling, timing bumps, mood filtering, behaviour rules, corrected durations
- Voice: `SpeechService` (premium voices) + `VoiceCaptureService` + conversation state machine in `MorningInterview`
- Learning: `CompletionRecord` → EMA posterior → `estimation_history` → weekly Opus profile card → behaviour rules → `PlanningEngine`
- Calendar: auto-sync on auth, free-time detection, free-time banner in `TodayPane`
- Sharing: `SharingService` + `SharingPane` with real Supabase invite links + PA member management
- Insights: accuracy per bucket, confidence indicators on time pills, Learning tab in Settings
- 5-tier memory: Tier 0 observations → Tier 1 daily summaries → Tier 2 behavioural signatures → Tier 3 personality traits → ACB (dual: FULL 10-12K + LIGHT 500-800 tokens)
- Morning briefing: 7-section CIA PDB format, adversarial Opus review, engagement tracking, confidence badges

## WHAT NEEDS TESTING / MANUAL STEPS

1. **Fix HNSW blocker** (see above) — edit migrations, then run `supabase db push`
2. `supabase functions deploy` — redeploy `classify-email`, `estimate-time`, `generate-profile-card` after migration lands
3. `supabase secrets set ANTHROPIC_API_KEY=sk-ant-...` — unblocks the entire intelligence pipeline
4. Azure provider in Supabase Auth dashboard — confirm client secret is active (expires 2028-04-11)
5. First MSAL sign-in test — launch app, go through onboarding, click "Sign In" on Outlook

## NEXT FEATURE: TickTick-Style Task Hierarchy + Silent AI Learning

> **Status: NOT STARTED** — do not begin until offline-sync work in `DataBridge.swift`, `OfflineSyncQueue.swift`, `TimedAppShell.swift`, and `DataBridgeTests.swift` is merged and clean.

### What We're Building
A user-facing sidebar hierarchy (sections → subsections → tasks → subtasks) that maps onto canonical `TaskBucket` planning logic underneath. AI, voice, Dish Me Up, estimation, and backend learning all stay coherent. Users can customise the visual structure without breaking the planning engine.

**Default model:**
- Sidebar hierarchy: `Email > Reply / Read Today / Read This Week / CC/FYI`, plus `Action`, `Calls`, `Transit`, `Waiting`, and user-created sections
- Each section maps to one canonical `TaskBucket`; custom subsections inherit the parent bucket unless overridden in detail view
- Subtasks are one level only — stored as normal task rows with `parent_task_id`
- Time/priority edits are captured silently as feedback events; the next morning review asks about only meaningful or repeated corrections

### Pre-condition: Fix Bucket Serialisation
Swift currently writes human `TaskBucket.rawValue` strings; Supabase expects `snake_case`. This **must** be normalised before adding hierarchy. Doing it after creates a data migration nightmare.

### Schema Changes

**New table: `task_sections`**
```
id                  uuid PK
workspace_id        uuid FK
profile_id          uuid FK
parent_section_id   uuid FK nullable  -- null = top-level section
title               text
canonical_bucket_type text            -- maps to TaskBucket snake_case value
sort_order          integer
color_key           text nullable
is_system           boolean default false
is_archived         boolean default false
created_at, updated_at
```
Enforce one visible subsection level in Swift/service logic, not schema.

**Extend `tasks`:**
- `section_id uuid FK`
- `parent_task_id uuid FK nullable`
- `sort_order integer`
- `manual_importance text` — `blue` (normal) | `orange` (important) | `red` (critical)
- `completed_at timestamptz nullable`
- `notes text nullable`

**Extend `behaviour_events`:**
- Add columns: `section_id`, `parent_task_id`, `event_metadata jsonb`
- New event types: `section_created`, `section_renamed`, `task_section_changed`, `subtask_created`, `subtask_completed`, `manual_importance_changed`
- Require `estimate_override` from **every** edit surface, not just Today

**Subtask behaviour:** Incomplete subtasks are first-class planning rows — they can be ranked, estimated, completed, deferred, and learned from. A parent with incomplete subtasks is treated as a container.

### Implementation Order

**Step 1 — Data Model (Swift)**
- [ ] Add `TaskSection` model with `Codable`, `Hashable`
- [ ] Add `ManualImportance` enum (`blue`, `orange`, `red`)
- [ ] Extend `TimedTask` / `TaskDBRow` with `sectionId`, `parentTaskId`, `sortOrder`, `completedAt`, `manualImportance`
- [ ] Fix `TaskBucket` canonical serialisation (`rawValue` → `snake_case` with round-trip test)

**Step 2 — Service Layer**
- [ ] Add section load/save/upsert methods in `SupabaseClient` and `DataBridge`
- [ ] Extend offline replay to queue `task_sections.upsert` and feedback event inserts (after offline-sync PR lands)
- [ ] Centralise task mutations so `TasksPane`, `TaskDetailSheet`, Today, Capture, Triage, and Orb all log estimate/importance/section corrections consistently

**Step 3 — View Model / State**
- [ ] Add `HierarchyAdapter` that derives sidebar rows, active section tasks, parent/subtask rows, and completed rows from `[TaskSection] + [TimedTask]`
- [ ] Keep `TimedRootView` as owner initially; move grouping/sorting logic out of views into adapter
- [ ] Sort incomplete rows by explicit `sort_order`, then existing planning score; completed rows go to a collapsed bottom group

**Step 4 — UI**
- [ ] Replace fixed bucket-only sidebar rows with native macOS `List` sections and `DisclosureGroup`
- [ ] Add `+` actions for top-level sections, subsections, tasks within a section, and one-level subtasks
- [ ] Show AI-recommended time on each task row; allow quick manual override; mark overrides visually (no noisy copy)
- [ ] Add blue/orange/red importance control in row and detail surfaces
- [ ] Show completed tasks greyed out at the bottom in a collapsed "Completed" disclosure

**Step 5 — AI / Backend**
- [ ] Extend `ConversationTools`, `orb-conversation`, `ConversationModel` client state, and voice context to include sections, subtasks, `manual_importance`, AI/manual estimates, and recent corrections
- [ ] Add safe in-app-only tools: `add_section`, `add_subtask`, `move_task_to_section`, `update_estimate`, `update_manual_importance`
- [ ] Update `generate-dish-me-up` and daily planning to plan over sections/subtasks (preserve observation-only behaviour)
- [ ] Update morning review voice flow: read recent significant corrections, ask at most 1-3 follow-up questions

**Step 6 — Silent Learning**
- [ ] Log edits immediately, never interrupt the user
- [ ] Meaningful correction threshold: estimate changed ≥ 15 min or ≥ 33%, importance changed to orange/red, repeated same-section corrections, repeated same-bucket estimate drift
- [ ] Next morning review asks only when correction is worth explaining; otherwise silently updates future estimates/ranking
- [ ] Feed actual minutes through existing `estimation_history`; feed override patterns through `behaviour_events`, profile-card generation, and synthesis jobs

**Step 7 — Docs / Memory**
- [ ] Update repo `docs/` and PRD: custom mapped sections, one-level subtasks, `manual_importance`, completed-task behaviour, silent feedback learning as core product behaviour
- [ ] Update Timed-Brain memory notes for PRD, `behaviour_events` schema, email taxonomy, and executive morning-list examples

### Worker Ownership (avoid subagent collisions)

| Worker | Owns |
|--------|------|
| Schema/backend | migrations, Edge Functions, Trigger tasks |
| Swift persistence | models, `SupabaseClient`, `DataBridge` |
| UI | sidebar, task list, subtasks, completed section |
| AI | voice/orb/Dish Me Up context and feedback learning |

One commit per logical change, conventional format (`feat:`, `fix:`, `refactor:`). Run `graphify update .` after any code change.

### Test Plan

**Swift unit tests:**
- [ ] Bucket canonical ID round-trip (snake_case ↔ Swift enum)
- [ ] `TaskSection` / `TimedTask` `Codable` round-trip
- [ ] One-level subtask validation (reject depth > 1)
- [ ] `HierarchyAdapter` grouping/sorting/completed-bottom behaviour
- [ ] Estimate and importance edits emit correct `behaviour_events`

**Backend tests:**
- [ ] Migration applies cleanly after HNSW fix
- [ ] RLS allows only workspace/profile-owned sections and tasks
- [ ] `estimate_override` and subtask events insert successfully
- [ ] Edge Functions type-check after schema updates (`deno check`)

**Integration / manual acceptance:**
- [ ] Create `Email > Read in 2 days`, add a task, add subtasks, set red/orange/blue importance
- [ ] Override AI estimate from 45m → 30m, verify it is logged silently (no modal)
- [ ] Complete tasks/subtasks, verify completed rows collapse at bottom
- [ ] Ask Orb/voice about the section, confirm it can read and update the right task
- [ ] Next morning review references only meaningful correction patterns
- [ ] Run `swift build`, `swift test`, `deno check`, then `graphify update .`

### Assumptions
- Custom sections are display/organisation structure — not replacements for canonical planning buckets
- Subtasks are one level only; enforce in service logic, not schema
- AI may modify in-app task structure only when the user instructs it; it still never sends emails, books events, or acts outside Timed
- Views do not call Supabase directly; persistence remains through `DataBridge` / `SupabaseClient`

## REMAINING WORK (priority order)

1. **Fix HNSW migration blocker** — update `EmbeddingService.swift` to truncate OpenAI embeddings to 1536-dim, rebuild affected migrations, then `supabase db push`
2. **E2E auth → email sync → triage flow** — first real Outlook account sign-in; triggers 3-year backfill
3. **Set `ANTHROPIC_API_KEY`** — unblocks the entire intelligence pipeline (nightly crons, briefing, profile card)
4. **Task hierarchy feature** (above) — begin only after offline-sync PR is merged
5. **EventKit calendar context** — read macOS calendar for meeting fatigue signal (no OAuth needed)
6. **Thread velocity** — compute messages-per-hour per conversation, pass to `classify-email`
7. **Waiting items unblock** — detect reply in Graph delta sync, auto-unblock `waiting_items`
8. **Session interruption tracking** — detect app backgrounding mid-task
9. **Logistic regression calibration** of `Score.*` constants after 30 days of data

## KNOWN ISSUES / LANDMINES

- `PreviewData.swift` contains ALL domain models (587 lines) — should split into `Core/Models/`
- `AuthService.swift` creates its own `SupabaseClient`, violating DI pattern
- `PlanPane` and `DishMeUpSheet` duplicate plan generation logic
- `TimedRootView.swift` is a 489-line god-view holding all `@State` arrays
- TCA dependency declared but only used for `@Dependency` injection, not state management
- No CoreData/SwiftData — persistence is JSON local + Supabase remote
- `Legacy/` folder (41 files) excluded from build, kept as reference
- `TimeSlotAllocatorTests`, `EmailSyncServiceTests`, `VoiceResponseParserTests`, memory store tests, and reflection engine tests — **NOT STARTED**

## FILE QUICK REF

| Area | File |
|------|------|
| Root state | `Sources/Features/TimedRootView.swift` |
| Auth | `Sources/Core/Services/AuthService.swift` |
| Email sync | `Sources/Core/Services/EmailSyncService.swift` |
| Planning | `Sources/Core/Services/PlanningEngine.swift` |
| Voice | `Sources/Core/Services/SpeechService.swift`, `VoiceCaptureService.swift`, `VoiceResponseParser.swift` |
| Models | `Sources/Features/PreviewData.swift` |
| Supabase client | `Sources/Core/Clients/SupabaseClient.swift` |
| Graph (email) | `Sources/Core/Clients/GraphClient.swift` |
| Data bridge | `Sources/Core/Services/DataBridge.swift` |
| Edge functions | `supabase/functions/` (28 deployed) |
| Migrations | `supabase/migrations/` (36 deployed + 5 pending) |
| Architecture docs | `research/ARCHITECTURE-MEMORY.md`, `ARCHITECTURE-SIGNALS.md`, `ARCHITECTURE-DELIVERY.md` |
| Deep research | `research/perplexity-outputs/v2/v2-01` through `v2-14` |
