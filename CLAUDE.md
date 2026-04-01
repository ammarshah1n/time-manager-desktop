# CLAUDE.md — Timed (Timed) v2

## Project
Executive time management app. Native Swift + SwiftUI macOS app with Supabase backend.

## MVP Features
1. Email triage (SaneBox-style, Outlook via Graph API)
2. Task extraction from email (Claude API)
3. Time estimation (AI + user override + learning)
4. Daily planning engine ("I have X hours, give me work")
5. Calendar read/write (Apple EventKit + Outlook Graph)
6. PA sharing (Karen — full access via Supabase Realtime)

## Stack
- **App:** Swift 6.1, SwiftUI, macOS 15+, Apple Liquid Glass
- **Backend:** Supabase (Postgres, Edge Functions, Auth, Realtime, Storage)
- **AI:** Claude Sonnet (classification), Claude Opus (extraction, planning)
- **Email:** Microsoft Graph API
- **Calendar:** EventKit + Graph API
- **Voice:** Apple Speech + Whisper API fallback

## FILE ORACLE — Living Map
> This section is updated every time a file is created.
> After creating ANY new file, immediately add it here with: path → exported function/type → one-line purpose
> After every /compact, re-read this section from disk.

### Files Created So Far
```
tools/taskflow/taskflow.sh        → CLI router, routes to commands/*.sh
tools/taskflow/config.json        → vault path, retry limits, TDD default
tools/taskflow/commands/parse.sh  → PRD decomposition via Claude CLI
tools/taskflow/commands/next.sh   → dependency-aware next task finder
tools/taskflow/commands/start.sh  → focused context output for Claude
tools/taskflow/commands/complete.sh → mark done + Obsidian + PLAN.md hooks
tools/taskflow/commands/fail.sh   → failure tracking + circuit breaker
tools/taskflow/commands/status.sh → per-FR progress dashboard
tools/taskflow/commands/autopilot.sh → autonomous loop orchestrator (Codex dispatch + circuit breaker)
tools/taskflow/commands/dispatch.sh  → Codex-first execution with Claude debug fallback on build failure
tools/taskflow/commands/worktree.sh  → git worktree per FR
tools/watchdog/watchdog.sh           → resurrects autopilot if dead, heartbeat to vault every 5 min
~/Library/LaunchAgents/com.timed.watchdog.plist → launchd: keeps watchdog alive for unattended runs
tools/taskflow/templates/walkthrough.md → auto-filled on complete
tools/taskflow/templates/error.md      → auto-filled on fail
Sources/Core/Models/EmailMessage.swift → EmailMessage struct — Codable email model
Sources/Core/Models/CalendarBlock.swift → CalendarBlock, BlockCategory — time block model
Sources/Core/Services/EmailClassifier.swift → EmailClassifying protocol + stub service
Sources/Core/Services/TimedScheduler.swift → TimedScheduling protocol + stub service
Tests/EmailMessageTests.swift          → EmailMessage Codable roundtrip test
Tests/EmailClassifierTests.swift       → EmailClassifier stub + category encoding tests
Tests/CalendarBlockTests.swift         → CalendarBlock Codable roundtrip test
Tests/TimedSchedulerTests.swift        → Scheduler empty/no-match input tests
Sources/Features/Onboarding/OnboardingFlow.swift → OnboardingFlow, OnboardingUserPrefs — 8-step first-launch wizard + static prefs accessor
docs/runbooks/env-setup.md             → all env var names, purpose, where to get values
docs/runbooks/deploy.md                → Supabase + macOS app deployment steps
docs/runbooks/graph-oauth-setup.md     → Azure App Registration step-by-step
docs/runbooks/db-reset.md              → local Supabase reset and migration commands
.claude/hooks/README.md                → documents all hooks, guards, and wiring instructions
.claude/hooks/permission-check.sh      → 3-tier PreToolUse safety guard (configured in settings.json)
.claude/hooks/post-write-check.sh      → swift build check after .swift writes (not wired yet)
.claude/hooks/write-obsidian-walkthrough.sh → Stop hook: writes walkthrough to Timed-Brain (not wired yet)
.claude/guards/file-write-guard.sh     → blocks writes outside allowed dirs (not wired yet)
.claude/guards/no-raw-sql.sh           → blocks direct SQL execution (not wired yet)

### Legacy v1 Sources (carried over — NOT part of v2 architecture, do not build on these)
Sources/AISummarySection.swift         → [v1] AI summary card UI
Sources/AutonomousSupport.swift        → [v1] autonomous agent support
Sources/CalendarExporter.swift         → [v1] calendar export to ICS
Sources/CodexBridge.swift              → [v1] Codex subprocess bridge pattern (reusable)
Sources/CodexMemoryInsights.swift      → [v1] Codex memory insights view
Sources/CodexMemorySchoolPack.swift    → [v1] school-specific memory pack
Sources/CodexMemorySync.swift          → [v1] Codex memory sync service
Sources/ConfettiView.swift             → [v1] confetti animation
Sources/ConfidenceCalibrationView.swift → [v1] confidence scoring UI
Sources/ContentView.swift              → [v1] root content view
Sources/ContextSearchService.swift     → [v1] context-aware search
Sources/DailyOverviewCard.swift        → [v1] daily overview card UI
Sources/DeadlineAlertService.swift     → [v1] deadline alert notifications
Sources/DeadlineCountdown.swift        → [v1] countdown timer UI
Sources/FeedbackViews.swift            → [v1] feedback collection views
Sources/FocusTimerModel.swift          → [v1] Pomodoro/focus timer model
Sources/FocusTimerWidget.swift         → [v1] focus timer widget UI
Sources/GlobalFocusHotkeyController.swift → [v1] global hotkey registration
Sources/ImportPipeline.swift           → [v1] data import orchestrator
Sources/KeyboardShortcutsHelpView.swift → [v1] keyboard shortcuts help UI
Sources/MenuBarController.swift        → [v1] menu bar controller
Sources/Models.swift                   → [v1] legacy model definitions
Sources/NLTaskParser.swift             → [v1] natural language task parser
Sources/ObsidianNoteSnippetCard.swift  → [v1] Obsidian note snippet UI
Sources/ObsidianVaultImporter.swift    → [v1] Obsidian vault import
Sources/ObsidianVaultSyncNotification.swift → [v1] vault sync notification
Sources/PDFExporter.swift              → [v1] PDF export (out of scope v2)
Sources/PlannerStore.swift             → [v1] planner state store
Sources/PlanningEngine.swift           → [v1] planning engine (superseded by FR-05)
Sources/Preferences.swift              → [v1] user preferences
Sources/QuizView.swift                 → [v1] quiz/study view
Sources/SchoolCalendarService.swift    → [v1] school calendar integration
Sources/SearchPanelView.swift          → [v1] search panel UI
Sources/SeqtaBackgroundSync.swift      → [v1] SEQTA background sync
Sources/SettingsView.swift             → [v1] settings view
Sources/SpacedRepetitionEngine.swift   → [v1] spaced repetition engine
Sources/StudyModeView.swift            → [v1] study mode view
Sources/TaskDetailView.swift           → [v1] task detail view
Sources/TimedAppDelegate.swift         → [v1] app delegate
Sources/TimedAppearance.swift          → [v1] appearance/theming
Sources/TimedCard.swift                → [v1] card UI component
Sources/TimedKeyboardCommands.swift    → [v1] keyboard command handlers
Sources/TimedLogoMark.swift            → [v1] logo mark view
Sources/TimedPaneComponents.swift      → [v1] pane layout components
Sources/TimeManagerDesktopApp.swift    → [v1] @main app entry point
Sources/VisualEffectView.swift         → [v1] NSVisualEffectView wrapper
Sources/WeeklyReviewView.swift         → [v1] weekly review view
Sources/Core/Services/EmailSyncService.swift → EmailSyncService actor — background Graph delta poll → Supabase upsert → classify-email Edge Function
Sources/Core/Services/CalendarSyncService.swift → CalendarSyncService actor — fetch Outlook events → CalendarBlock + FreeTimeSlot detection
Sources/Core/Services/TaskExtractionService.swift → TaskExtractionService actor — thread bundling by subject/sender → ExtractedTaskBundle
Sources/Core/Services/SharingService.swift → SharingService actor — invite link generation, PA member management, Realtime placeholder
Sources/Core/Services/TimedLogger.swift → Structured os.Logger (general, dataStore, graph, supabase, planning, voice, calendar, triage, sharing)
Sources/Core/Services/String+EmailSubject.swift → String.cleanedEmailSubject — strips Re:/Fwd: prefixes
Sources/Features/Tasks/TaskDetailSheet.swift → Full task edit sheet (bucket, time, flags, waiting, date, delete)
Sources/Features/Triage/TaskBundleSheet.swift → Smart Bundle sheet — grouped thread preview, accept per-row or all
Sources/Features/Sharing/SharingPane.swift → Settings tab: invite link + copy, PA members, sharing status
Tests/DataStoreTests.swift → Roundtrip encode/decode tests for all 5 model types
```

### Planned File Map (from specs)
```
Sources/Core/Models/
  Email.swift             → Email, Classification, TriageFolder types
  Task.swift              → Task, TaskBundle, TaskEstimate types
  Plan.swift              → Plan, PlanItem, Timed types
Sources/Core/Clients/
  GraphClient.swift       → ALL Microsoft Graph calls. Nowhere else.
  SupabaseClient.swift    → ALL Supabase calls. Never import Supabase directly.
Sources/Features/
  EmailTriage/            → FR-01 + FR-02: classifyEmail(), email polling
  TaskEngine/             → FR-03 + FR-04: emailToTask(), estimateTime()
  PlanningEngine/         → FR-05: generatePlan() — THE CORE
  PASharing/              → FR-07: share link + realtime sync
supabase/
  migrations/             → ONLY way schema changes happen
  functions/              → Edge Functions (email polling, classification)
```

## Task System — taskflow
This project uses `taskflow` (`tools/taskflow/taskflow.sh`) for task orchestration.
- **Parse PRD:** `taskflow parse PRD.md` → generates `tools/taskflow/tasks.json`
- **Get next task:** `taskflow next` → dependency-aware, returns highest-priority available task
- **Start task:** `taskflow start <id>` → sets in-progress, outputs focused context + acceptance criteria
- **Complete task:** `taskflow complete <id>` → writes Obsidian walkthrough, updates PLAN.md
- **Fail task:** `taskflow fail <id> --reason "..."` → circuit breaker at 3 failures → blocked
- **Dashboard:** `taskflow status` → per-FR progress bars
- **Overnight:** `taskflow autopilot [--tdd]` → autonomous loop with per-task circuit breaker
- **Parallel FRs:** `taskflow worktree FR-01` → isolated git worktree

When working on a task via taskflow:
- You will receive focused context with acceptance criteria
- When ALL acceptance criteria are met and code compiles/tests pass, output: `TASK_COMPLETE`
- If stuck after 3 attempts on the same error, output: `TASK_BLOCKED`
- Never work on tasks not assigned via `taskflow start`

## Architecture Rules
- Read `docs/rules/` before every task (mirrored from Obsidian vault).
- No business logic in route handlers or Edge Function entry points.
- One Edge Function per pipeline stage.
- All Graph API calls through `GraphClient.swift`. No exceptions.
- All Supabase access through `SupabaseClient.swift`. No direct imports.
- All AI calls log to `ai_pipeline_runs`.
- Sonnet for classification, Opus only where reasoning matters.
- Every table has `workspace_id` + RLS.
- Every mutation carries `created_by`.
- **After creating any new .swift file, update the FILE ORACLE section above.**

## AUTO-DOCUMENTATION PROTOCOL (MANDATORY)

### The 8 Files — Nothing Else

| File | Purpose | Writer |
|------|---------|--------|
| `PLAN.md` | Current state only, ≤50 lines | Claude (live) |
| `CHANGELOG.md` | What happened, reverse-chronological | Claude (live) + Codex (backfill) |
| `~/Timed-Brain/06 - Context/decision-log.md` | What Ammar decided — table rows | Claude (live) + Codex |
| `~/Timed-Brain/06 - Context/prompts-log.md` | Ammar's prompts — AIF gold | Codex ONLY (from transcripts) |
| `~/Timed-Brain/05 - Dev Log/sessions/*.md` | Readable session transcripts | post-session-export.sh (auto) |
| `docs/rules/corrections-log.md` | What Claude got wrong | Claude (immediate on correction) |
| claude-mem | 3 keys: timed-resume, timed-current, timed-corrections | Claude (at checkpoints + Stop) |
| `~/.claude/projects/*/.jsonl` | Raw transcripts | Claude Code (built-in, automatic) |

### Trigger Table

| Action | Write To | What |
|--------|---------|------|
| File created | CHANGELOG.md Added + File Oracle | Path, one-line purpose |
| File modified | CHANGELOG.md Changed | What changed and why |
| Task completed | CHANGELOG.md Added/Changed + PLAN.md LAST COMPLETED + claude-mem timed-current | What was built |
| Architecture decision | CHANGELOG.md Decided + decision-log.md new row | D-NNN row with AIF tag |
| Correction received | CHANGELOG.md Corrections + corrections-log.md + claude-mem timed-corrections + CLAUDE.md rule | Triple-write, immediate |
| Install (any tool) | CHANGELOG.md Added | Exact command, version, reason |
| Env var added | docs/runbooks/env-setup.md + CHANGELOG.md | Name, purpose, where to get |
| New dependency | stack-decisions.md + CHANGELOG.md | Package, version, why |
| Error hit | 04 - Errors/ if significant | Error template format |
| ~60% context | Update all 3 claude-mem keys + PLAN.md + CHANGELOG.md session section | Suggest /compact |

### What "Human Decision" Means
The AI output is NOT a human decision. These ARE:
- Problem identification — Ammar saw a gap before asking AI
- The prompt itself — framing, scope, constraints. Log the PROMPT to prompts-log.md.
- System synthesis — connecting tools into unified flows
- Quality judgement — "not good enough", "like the pros"
- Correction/redirection — every "no", "wrong", "don't do that"

### Token Economics (HARD)
| Job | Tool |
|-----|------|
| .jsonl indexing, decision extraction, deduplication | Codex (see tools/scripts/codex-index-prompt.md) |
| Live CHANGELOG, PLAN, claude-mem writes | Claude (has session context) |
| Never: Claude reads raw .jsonl files | Codex does this cheaper |

### Anti-Bloat
- ONE source of truth per fact. CHANGELOG = history. PLAN = current. decision-log = decisions.
- Max 1 sentence per File Oracle entry.
- Never duplicate info across files — link instead.
- PLAN.md: archive overflow to CHANGELOG.md immediately.

## Context Management

**Double-Esc time travel:** When Claude goes off-track, press Esc Esc for a rewind menu:
- Restore conversation only — keep code changes, reset the thread
- Restore code only — keep reasoning, undo the bad implementation
- Restore both — full nuclear rewind
- **"Summarize from here"** — use at 60-70% context instead of /compact, gives you control
  over exactly what gets compressed. Use this aggressively in long sessions.

**Context7 MCP (toggleable):** Fetches live docs for Supabase Swift SDK, TCA, and Graph API. Add "use context7" to any prompt when working with those SDKs. See installed-tools.md for install command.

## Anti-Patterns (NEVER repeat)
1. Over-engineering: start with 1 data source, not 4
2. No silent failures: every job must have progress tracking + timeout detection
3. Always smoke test Edge Functions against real payload shape before deploying
4. Use cheapest sufficient model. Wrong model = timeouts.
5. Never batch commits. Commit after every change.
6. Reverse-prompt before building: list every ambiguity first.

## SELF-IMPROVEMENT PROTOCOL
9.  After every session: run /wrap-up. No exceptions.
10. After every mistake caused by a skill: run /self-improve. Patch the skill, don't just fix the code.
11. After every user correction given 2+ times: this is CRITICAL — /self-improve must create a rule.
12. The goal: by session 20, CLAUDE.md and 00-Rules/ encode every mistake ever made. No mistake happens twice.

## Installed Tools
See Obsidian `06 - Context/installed-tools.md` for the full registry of all skills, MCPs, hooks, and their activation rules. Do not duplicate details here — reference the registry.

## Tool Dispatch
| Task | Tool |
|------|------|
| Architecture, planning, complex reasoning | Claude Opus (me) |
| Standard feature implementation | Claude Sonnet via Ralph loop |
| Boilerplate, CRUD, migrations, test stubs | Codex |
| Research | Perplexity Deep Research via Comet MCP |
| Browser automation | Comet MCP |

## File Structure
```
Sources/           ← all Swift source files
Tests/             ← all test files
supabase/          ← migrations, Edge Functions
docs/              ← PRD, specs
tools/taskflow/    ← task orchestration CLI (bash + jq)
.claude/           ← hooks, guards
scripts/           ← build, deploy, package scripts
```

## Obsidian Vault
`~/Timed-Brain/` — rules, walkthroughs, decisions, specs, errors, dev log.
Connected via obsidian-mcp. Read `00 - Rules/` at session start.

## Commit Convention
```
[COMPONENT]: Short description

Co-Authored-By: Claude <noreply@anthropic.com>
```
Components: `TRIAGE`, `TASKS`, `ESTIMATE`, `PLANNER`, `CALENDAR`, `SHARING`, `INFRA`, `UI`
