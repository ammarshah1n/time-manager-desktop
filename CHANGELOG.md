# Changelog
All notable changes to Timed are documented here.
Newest on top. Format follows [Keep a Changelog](https://keepachangelog.com/).

---

## [Session 2026-03-31 evening] — Production hardening + backend wiring + 5 missing FRs

### Added
- `Sources/Core/Services/EmailSyncService.swift` — actor: background Graph delta poll → Supabase upsert → classify-email Edge Function
- `Sources/Core/Services/CalendarSyncService.swift` — actor: fetch Outlook events → CalendarBlock + free-time gap detection (FreeTimeSlot)
- `Sources/Core/Services/TaskExtractionService.swift` — actor: thread bundling by subject/sender, ExtractedTaskBundle
- `Sources/Core/Services/SharingService.swift` — actor: invite link generation, PA member management, Realtime placeholder
- `Sources/Core/Services/TimedLogger.swift` — structured os.Logger (general, dataStore, graph, supabase, planning, voice, calendar, triage, sharing)
- `Sources/Core/Services/String+EmailSubject.swift` — cleanedEmailSubject stripping Re:/Fwd: prefixes
- `Sources/Features/Tasks/TaskDetailSheet.swift` — full edit sheet: bucket, time, flags, waiting on, expected date, delete
- `Sources/Features/Triage/TaskBundleSheet.swift` — Smart Bundle UI: grouped threads, editable title/bucket/time, accept per-row or all
- `Sources/Features/Sharing/SharingPane.swift` — Settings tab: invite link + copy, active PA members, sharing status indicator
- `Tests/DataStoreTests.swift` — roundtrip encode/decode for all 5 model types

### Changed
- `Sources/Features/TimedRootView.swift` — empty defaults (not .samples), loadData falls back to samples only on first launch, overdue WOO badge on sidebar, commented EmailSyncService call site
- `Sources/Features/TimeManagerDesktopApp.swift` — reads `prefs.appearance.theme` from AppStorage, applies `.preferredColorScheme`
- `Sources/Features/Today/TodayPane.swift` — task detail sheet on row tap, stale items amber banner with snooze (FR-08)
- `Sources/Features/Tasks/TasksPane.swift` — task detail sheet, batch ops (multi-select, bulk move/done/delete), stale badges
- `Sources/Features/Calendar/CalendarPane.swift` — drag-to-create (15min snap, preview, NewBlockEditor), Sync Calendar button, free-time slot rendering
- `Sources/Features/Triage/TriagePane.swift` — Smart Bundle button calling TaskExtractionService
- `Sources/Features/Waiting/WaitingPane.swift` — overdue-by-X-days indicators
- `Sources/Features/Prefs/PrefsPane.swift` — added Sharing tab
- `Sources/Features/Onboarding/OnboardingFlow.swift` — accounts step (Outlook/Supabase detection, local-mode banner)
- `Sources/Features/MorningInterview/MorningInterviewPane.swift` — real blocks binding (not .samples), expanded travel keywords, .transit category
- `Sources/Core/Clients/GraphClient.swift` — safe MSAL init (try? not try!), os.Logger
- `Sources/Core/Clients/SupabaseClient.swift` — safe init (no fatalError), os.Logger, added upsertEmailMessage
- `Sources/Core/Services/DataStore.swift` — safe init (guard let), os.Logger on load/save
- `Sources/Core/Services/PlanningEngine.swift` — os.Logger on plan generation
- `Sources/Core/Services/VoiceCaptureService.swift` — failable init (not fatalError), os.Logger
- `Sources/Features/PreviewData.swift` — TaskBucket.staleAfterDays, TimedTask.isStale, .transit on BlockCategory, categoryColor for transit
- `Sources/Core/Models/CalendarBlock.swift` — added .transit to BlockCategory
- `Package.swift` — added swift-testing dependency
- Deleted 14 legacy v1 test files, fixed 4 v2 test assertions

### Documentation fixed
- `PLAN.md` — rewrote to reflect actual state: backend LIVE, UI ↔ backend bridge is the gap
- `~/Timed-Brain/06 - Context/human-checklist.md` — marked Azure, Supabase, Edge Functions, API keys as DONE
- `~/Timed-Brain/05 - Dev Log/Week-14-2026.md` — full session dev log with post-mortem on doc drift
- Memory: `project_timed_yasser.md` updated, `feedback_docs_verification.md` created

### State as of end of session
- `swift build` → `Build complete!` (zero errors)
- `swift test` → 49/49 pass
- Backend: Supabase project live, 8 edge functions ACTIVE, all secrets configured
- Blocker: Supabase Auth (Microsoft provider) not yet enabled in dashboard — needs Azure client secret rotation

---

## [Session 2026-03-31] — Full persistence + UX polish (4 parallel tracks)

### Added
- `Sources/Core/Services/DataStore.swift` — actor for JSON persistence to `~/Library/Application Support/Timed/`
- Quick-add task bar in `TodayPane` — inline field + bucket picker, submits on Return
- `computeReason()` in `PlanningEngine` — human-readable rank reasons for every Dish Me Up task

### Changed
- `Sources/Features/PreviewData.swift` — all models now `Codable + Sendable + Equatable`; `TriageItem.avatarColor` converted to computed hash property (was stored `Color`); `CaptureItem` + `TriageItem` + `TimedTask` + `WOOItem` all persist-ready
- `Sources/Features/TimedRootView.swift` — root state lifted for `wooItems` + `captureItems`; `loadData()` + `persistenceObserver` wired; morning interview once-per-day guard via `@AppStorage`
- `Sources/Features/Today/TodayPane.swift` — `completedIds` ↔ `task.isDone` sync on appear + on change; quick-add bar added
- `Sources/Features/Waiting/WaitingPane.swift` — converted to `@Binding` (was `@State` with samples); "FROM TASKS" section added; Copy to Clipboard + Send via Email now functional
- `Sources/Features/Capture/CapturePane.swift` — `@State private var items` → `@Binding var items`
- `Sources/Features/Prefs/PrefsPane.swift` — `SyncTab`, `BlocksTab`, `NotificationsTab`, `AppearanceTab` all use `@AppStorage`
- `Sources/Features/Focus/FocusPane.swift` — skip/forward button now calls `onComplete()`
- `Sources/Features/Calendar/CalendarPane.swift` — Remove button deletes block; Start Focus opens real `FocusPane` sheet via local state
- `Sources/Features/MorningInterview/MorningInterviewPane.swift` — speak buttons toggle "Listening…" state with red mic
- `Sources/Core/Services/PlanningEngine.swift` — added `replyBump=350`, `callsBump=250`, `transitBump=150` score constants; `computeReason()` fills `rankReason` (was always nil)
- `Sources/Features/DishMeUp/DishMeUpSheet.swift` — `toPlanTask()` has 10-level priority, real `isOverdue`, granular `deferredCount`; `taskReasons` dict preserves engine rank reasons; `bucketTypeStr()` returns distinct types for reply/calls/transit
- `Sources/Features/Plan/PlanPane.swift` — same `toPlanTask()` improvements as DishMeUpSheet

### State as of end of session
- `swift build` → `Build complete!` (zero errors)
- All task/triage/WOO/calendar/capture data persists across app restarts
- Dish Me Up produces intelligently ranked stacks with visible reasons
- 8 previously-broken buttons now functional

---

## [Session 2026-03-29] — Documentation spine + jigsaw architecture

### Added
- `CHANGELOG.md` — this file, single source of change history
- `~/Timed-Brain/06 - Context/decision-log.md` — Ammar's decisions in table format
- `~/Timed-Brain/06 - Context/prompts-log.md` — Ammar's prompts as AIF evidence artifacts
- `~/Timed-Brain/05 - Dev Log/sessions/` — folder for auto-exported session transcripts
- `.claude/hooks/post-session-export.sh` — SessionEnd hook: .jsonl → readable .md
- `tools/scripts/codex-index-prompt.md` — Codex batch job: indexes sessions, extracts decisions
- `tools/scripts/index-sessions.sh` — bash runner for session indexing
- `docs/runbooks/db-reset.md` — local Supabase reset commands
- `.claude/hooks/README.md` — hook documentation and wiring instructions

### Changed
- `~/.claude/settings.json` — obsidian MCP path fixed: `~/TimeBlock Vault` → `~/Timed-Brain`
- `~/.claude/settings.json` — SessionEnd hook extended with post-session-export.sh
- `CLAUDE.md` — Documentation Protocol replaced with Auto-Documentation Protocol; "Human Decision" redefined
- `PLAN.md` — trimmed to ≤50 lines; sprint history archived here
- `~/Timed-Brain/06 - Context/installed-tools.md` — hooks corrected, MCPs updated

### Decided
- [D-042] We will name the app "Timed" not "TimeBlock" — shorter, cleaner. (High confidence) — E1
- [D-041] We will use a 26-component documentation jigsaw, not ad-hoc notes — context was dying between sessions (High) — PA1, A1
- [D-040] We will index transcripts via Codex, not Claude — token economics (High) — PA1

### Corrections Received
- Prompts ARE the human AIF evidence, not just AI-chosen outcomes. Log the prompt itself.
- "claude-mem" is already installed (thedotmack plugin) — no install needed, just use it
- Obsidian MCP was pointing at wrong vault — fixed

---

## [Session 2026-03-28] — Project setup, architecture, vault population

### Added
- Repo initialised at `~/time-manager-desktop`
- `CLAUDE.md` with File Oracle, architecture rules, skill activation
- `AGENTS.md` with autonomous agent rules and circuit breaker
- `PLAN.md` sprint tracking
- 7 FR specs (`docs/specs/FR-01` through `FR-07`)
- 3 ADRs (`docs/decisions/001-003`): Graph API, Supabase, Edge Functions + pgmq
- `tools/taskflow/` CLI: parse, next, start, complete, fail, status, autopilot, worktree
- `~/Timed-Brain/` Obsidian vault: 00 - Rules (7 files), 01 - Walkthroughs, 02 - Decisions (3 ADRs), 03 - Specs (7 symlinks), 04 - Errors, 05 - Dev Log, 06 - Context (7 files), 07 - Templates (4 files), HOME.md
- Custom skills: wrap-up, self-improve, tca-patterns, graph-api, timed-arch
- Hooks: file-write-guard.sh, no-raw-sql.sh, post-write-check.sh, write-obsidian-walkthrough.sh, permission-check.sh
- Core models: `Sources/Core/Models/EmailMessage.swift`, `CalendarBlock.swift`
- Core services: `Sources/Core/Services/EmailClassifier.swift`, `TimedScheduler.swift`
- Tests: EmailMessage, EmailClassifier, CalendarBlock, TimedScheduler Codable roundtrip tests
- Runbooks: env-setup.md, deploy.md, graph-oauth-setup.md
- `.env.example` with 6 env vars

### Decided
- [D-039] We will use Supabase as backend — relational, realtime, known stack. (High) — ADR-002
- [D-038] We will use Microsoft Graph API not IMAP — delta queries, webhooks, OAuth. (High) — ADR-001
- [D-037] We will use Edge Functions + pgmq + pg_cron not Inngest — zero extra infra. (High) — ADR-003
- [D-036] We will use TCA for all SwiftUI — testable state management. (High) — swift-rules
- [D-035] We will use Sources/Core/ as canonical structure — flat Sources/ contradicted CLAUDE.md. (High)
- [D-034] We will route classification to Sonnet, extraction/planning to Opus — cost vs quality. (High)
- [D-033] We will use swift-testing not XCTest — modern API, async, parameterised. (Medium)

### Fixed
- File Oracle contradiction: planned Sources/TimedCore/ vs actual Sources/Core/ — standardised on Sources/Core/
- Vault duplicate folders merged: 01-Walkthroughs + 01 - Walkthroughs → 01 - Walkthroughs
- Vault duplicate folders merged: 04-Errors + 04 - Errors → 04 - Errors
- Obsidian vault renamed: TimeBlock-Brain → Timed-Brain

### Corrections Received
- App is "Timed" not "TimeBlock" — all references updated
- Do not suggest Codex when Claude has 5 hours of session context — context is expensive
