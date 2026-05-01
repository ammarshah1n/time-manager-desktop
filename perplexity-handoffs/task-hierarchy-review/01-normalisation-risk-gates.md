# Proposed Plan + Risk Gates

## Proposed Plan

# TickTick-Style Task Hierarchy + Silent AI Learning

## Summary

Build a mapped task hierarchy: users can add sidebar sections/subsections and subtasks, while Timed keeps canonical planning buckets underneath so AI, voice, Dish Me Up, estimation, and backend learning stay coherent.

Default model:

- Sidebar hierarchy is user-facing: `Email > Reply / Read Today / Read This Week / CC/FYI`, plus `Action`, `Calls`, `Transit`, `Waiting`, and user-created sections.
- Each section maps to one canonical `TaskBucket`; custom subsections inherit the parent bucket unless changed in detail view.
- Subtasks are one level only and are stored as normal task rows with `parent_task_id`.
- Time/priority edits are captured silently as feedback events. The next review asks about only meaningful or repeated corrections.

## Coordination / Collision Controls

- Do not start implementation while current offline-sync work is active in `DataBridge.swift`, `OfflineSyncQueue.swift`, `TimedAppShell.swift`, or `DataBridgeTests.swift`; those overlap persistence.
- First implementation step must normalize Swift/DB bucket IDs before adding hierarchy: Swift currently writes human `TaskBucket.rawValue`, while Supabase expects snake_case values.
- Split work by ownership to avoid subagent clashes:
  - Schema/backend worker: migrations, Edge Functions, Trigger tasks.
  - Swift persistence worker: models, `SupabaseClient`, `DataBridge`.
  - UI worker: sidebar, task list, subtasks, completed section.
  - AI worker: voice/orb/Dish Me Up context and feedback learning.
- One commit per change, conventional format. After code changes, run `graphify update .`.

## Interface / Data Model Changes

- Add `task_sections` table:
  - `id`, `workspace_id`, `profile_id`, `parent_section_id`, `title`, `canonical_bucket_type`, `sort_order`, `color_key`, `is_system`, `is_archived`, timestamps.
  - Enforce one visible subsection level in Swift/service logic.
- Extend `tasks`:
  - `section_id`, `parent_task_id`, `sort_order`, `manual_importance`, `completed_at`, optional `notes`.
  - `manual_importance`: `blue = normal`, `orange = important`, `red = critical`; maps into existing planning `importance` but remains visibly user-authored.
- Extend `behaviour_events`:
  - Add `section_id`, `parent_task_id`, `event_metadata`.
  - Add event types: `section_created`, `section_renamed`, `task_section_changed`, `subtask_created`, `subtask_completed`, `manual_importance_changed`.
  - Keep using `estimate_override`, but require it from every edit surface, not just Today.
- Treat subtasks as first-class planning rows:
  - Incomplete subtasks can be ranked, estimated, completed, deferred, and learned from.
  - A parent with incomplete subtasks is a container unless it has no children or explicit standalone work.

## Implementation Plan

1. Data model:
   - Add Swift models for `TaskSection`, `ManualImportance`, and hierarchy helpers near the existing task model.
   - Extend `TimedTask`/`TaskDBRow` mapping with section, parent, ordering, completed timestamp, and manual importance.
   - Fix canonical bucket serialization before relying on remote hierarchy.

2. Service layer:
   - Add section load/save/upsert methods through `SupabaseClient` and `DataBridge`.
   - Extend offline replay to queue `task_sections.upsert` and feedback event inserts after the existing offline-sync changes are settled.
   - Centralize task mutations so `TasksPane`, `TaskDetailSheet`, Today, Capture, Triage, and Orb all log estimate/importance/section corrections consistently.

3. View model/state:
   - Add a hierarchy adapter that derives sidebar rows, active section tasks, parent/subtask rows, and completed rows from `[TaskSection] + [TimedTask]`.
   - Keep `TimedRootView` as owner initially, but move grouping/sorting logic out of views.
   - Sort incomplete rows by explicit `sort_order`, then existing planning score; completed rows go to a bottom collapsed group.

4. UI:
   - Replace fixed bucket-only sidebar rows with native macOS sidebar sections and disclosure groups.
   - Add plus actions for top-level sections, subsections, tasks within a section, and one-level subtasks.
   - Show AI recommended time on each task row, allow quick manual override, and mark overrides visually without noisy copy.
   - Add blue/orange/red importance control in row/detail surfaces.
   - Show completed tasks greyed out at the bottom in a collapsed "Completed" disclosure.

5. AI/backend:
   - Extend `ConversationTools`, `orb-conversation`, `ConversationModel` client state, and voice context to include sections, subtasks, manual importance, AI/manual estimates, and recent corrections.
   - Add safe tools for in-app-only changes: add section, add subtask, move task to section, update estimate, update manual importance.
   - Update `generate-dish-me-up` and daily planning to plan over sections/subtasks while preserving observation-only behavior.
   - Update morning review voice flow to read recent significant corrections and ask at most 1-3 follow-up questions.

6. Silent learning:
   - Log edits immediately without interrupting the user.
   - "Meaningful correction" threshold: estimate changed by at least 15 minutes or 33%, manual importance changed to orange/red, repeated same-section corrections, or repeated same bucket estimate drift.
   - Next review asks only when the correction is useful to explain. Otherwise the system silently updates future estimates/ranking.
   - Feed actual minutes through existing `estimation_history`; feed override patterns through `behaviour_events`, profile-card generation, and relevant synthesis jobs.

7. Docs/memory:
   - Update repo docs/PRD to define custom mapped sections, one-level subtasks, manual importance, completed-task behavior, and silent feedback learning as core product behavior.
   - Update Timed-Brain memory notes for PRD, behaviour events schema, email taxonomy, and executive morning-list examples after implementation lands.

## Test Plan

- Swift unit tests:
  - Bucket canonical ID round-trip.
  - `TaskSection`/`TimedTask` Codable round-trip.
  - One-level subtask validation.
  - Hierarchy grouping/sorting/completed-bottom behavior.
  - Estimate and importance edits emit correct `behaviour_events`.
- Backend tests/checks:
  - Migration applies cleanly.
  - RLS allows workspace/profile-owned sections and tasks only.
  - `estimate_override` and subtask events insert successfully.
  - Edge Functions type-check after schema updates.
- Integration/manual acceptance:
  - Create `Email > Read in 2 days`, add a task, add subtasks, set red/orange/blue importance.
  - Override AI estimate from 45m to 30m and verify it is logged silently.
  - Complete tasks/subtasks and verify completed rows collapse at bottom.
  - Ask Orb/voice about the section and confirm it can read and update the right task.
  - Next morning review references only meaningful correction patterns.
  - Run `swift build`, `swift test`, relevant `deno check`, then `graphify update .`.

## Assumptions

- Custom sections are display/organisation structure, not replacements for canonical planning buckets.
- Subtasks are one level only.
- AI may modify in-app task structure only when the user instructs it; it still never sends emails, books events, or acts outside Timed.
- Views do not call Supabase directly; persistence remains through `DataBridge`/`SupabaseClient`.

## Risk Gates

- Gate 1: bucket serialization normalized before hierarchy work.
- Gate 2: schema migration reviewed before Swift model changes.
- Gate 3: `DataBridge` offline queue changes landed before extending persistence.
- Gate 4: every task mutation path logs estimate/importance/section corrections consistently.
- Gate 5: Edge Function tool schemas match Swift tool schemas exactly.
- Gate 6: Dish Me Up, voice context, and estimation all understand subtasks.
- Gate 7: RLS and indexes verified for `task_sections`, `tasks.section_id`, and `tasks.parent_task_id`.
- Gate 8: full `swift build`, `swift test`, relevant `deno check`, and migration checks pass.

## Specific Areas Perplexity Should Stress-Test

- Whether `task_sections.parent_section_id` should be enforced at DB level or only in Swift.
- Whether `tasks.parent_task_id` should reference `tasks(id)` with `on delete cascade`, `set null`, or restricted deletion.
- Whether parent tasks should aggregate child estimates or be treated as non-executable containers.
- How to avoid duplicate learning signals when both a parent and subtask are completed.
- How to preserve old local JSON tasks that do not contain section or subtask fields.
- How to seed default sections for existing users without relying on brittle client-only bootstrap.
- How to keep Swift `ConversationTools.schemas()` and Edge `TOOL_SCHEMAS` in exact lockstep.
- How to make `estimate_override` payloads machine-readable enough for future estimator training.
- How to prevent `generate-dish-me-up` from double-counting parent and child tasks.
- How to avoid a partial rollout where the UI creates sections that voice, Dish Me Up, or estimation ignore.
