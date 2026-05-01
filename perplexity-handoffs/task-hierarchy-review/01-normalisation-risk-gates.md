# Revised Plan + Risk Gates

This revision incorporates Perplexity's first review from `02-perplexity-review.md`.

## Executive Ruling

The original plan is not safe to implement until the task persistence contract is fixed. The revised plan adds a Gate 0 and chooses one coherent subtask planning model:

- Gate 0: normalize `TaskBucket` Swift/DB serialization before any hierarchy work.
- Subtasks are executable planning units.
- Parent tasks with subtasks become containers and are excluded from planning.
- Standalone top-level tasks remain executable planning units.
- Only executable planning units produce time-estimation learning signals.

## Gate 0: Bucket Serialization Fix

Before adding sections or subtasks:

- Add `TaskBucket.dbValue` and `TaskBucket.from(dbValue:)`.
- Update `DataBridge.makeTaskRow` to write DB-safe values, not `TaskBucket.rawValue`.
- Update `TimedTask.init(from:)` to decode DB values.
- Add a migration/backfill that maps existing human labels to canonical DB values.
- Resolve `ccFyi`: either add `cc_fyi` to the DB check constraint or deliberately map it to `other`; preferred is adding `cc_fyi` because `CC / FYI` is a first-class bucket in Swift.
- Add a Swift test: `TaskBucket.from(dbValue: bucket.dbValue) == bucket` for every case.

## Data Model

### `task_sections`

Add `public.task_sections`:

- `id uuid primary key default gen_random_uuid()`
- `workspace_id uuid not null references public.workspaces(id) on delete cascade`
- `profile_id uuid references public.profiles(id) on delete set null`
- `parent_section_id uuid references public.task_sections(id) on delete set null`
- `title text not null`
- `canonical_bucket_type text not null`
- `sort_order integer not null default 0`
- `color_key text`
- `is_system boolean not null default false`
- `is_archived boolean not null default false`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Required constraints and indexes:

- Create a `public.canonical_bucket` domain and use it for both `tasks.bucket_type` and `task_sections.canonical_bucket_type`.
- The domain includes `action`, `reply_email`, `reply_wa`, `reply_other`, `read_today`, `read_this_week`, `calls`, `transit`, `waiting`, `cc_fyi`, and `other`.
- Add indexes on `(workspace_id, profile_id, is_archived, sort_order)` and `parent_section_id`.
- Enforce one visible subsection level with a DB trigger: a section with a parent cannot itself become a parent.
- Seed default system sections server-side for every existing workspace with an idempotent migration or seed script. The Swift client must not be the source of truth for system section creation.
- RLS must use a `private.user_workspace_ids()` `SECURITY DEFINER stable` helper, not inline joins against `workspaces` or `workspace_members`.

Default section tree:

- `Email`
  - `Reply`
  - `Read Today`
  - `Read This Week`
  - `CC / FYI`
- `Action`
- `Calls`
- `Transit`
- `Waiting`

### `tasks`

Extend `public.tasks`:

- `section_id uuid references public.task_sections(id) on delete set null`
- `parent_task_id uuid references public.tasks(id) on delete restrict`
- `sort_order integer not null default 0`
- `manual_importance text not null default 'blue' check (manual_importance in ('blue','orange','red'))`
- `notes text`
- `is_planning_unit boolean not null default true`

Required constraints and triggers:

- Prevent self-parenting: `parent_task_id != id`.
- Enforce one-level subtasks at DB level: a task whose `parent_task_id` is not null cannot be used as another task's parent.
- When a subtask is added to a parent, set the parent `is_planning_unit = false`.
- Before deleting a parent task, a single `BEFORE DELETE` DB trigger promotes children by setting `parent_task_id = null`, copying `section_id = coalesce(child.section_id, old_parent.section_id)`, and setting `is_planning_unit = true`.
- Do not rely on FK `ON DELETE SET NULL` for parent deletion; the FK stays `ON DELETE RESTRICT` so the trigger owns promotion semantics.
- Add an `AFTER DELETE` trigger for child deletion: if the deleted row was the last child, restore the former parent `is_planning_unit = true`.
- A parent container may still be completed manually, but parent completion does not produce an estimate-learning signal unless it has its own explicit actual minutes and no incomplete subtasks.

Trigger requirements:

- `promote_orphaned_subtasks()` runs `BEFORE DELETE ON public.tasks`.
- `restore_planning_unit_on_last_child_delete()` runs `AFTER DELETE ON public.tasks`.
- Both triggers must be covered by migration tests.

### Subtask Planning Model

Use exactly this model:

- Standalone top-level task: `parent_task_id is null`, no children, `is_planning_unit = true`; planned normally.
- Parent container: has at least one child, `is_planning_unit = false`; displayed in UI but excluded from `generate-dish-me-up`.
- Subtask: `parent_task_id is not null`, `is_planning_unit = true`; planned, ranked, estimated, completed, and learned from independently.
- Parent effective estimate for display is the sum of incomplete child estimates; this is display-only and must not be added to planning totals.
- Completing the final subtask does not auto-complete the parent. The parent can remain as context or be manually completed.

This avoids double-counting while preserving the user's requirement that subtasks can be ranked and estimated.

## Behaviour Events + Silent Learning

Extend `behaviour_events`:

- `section_id uuid references public.task_sections(id) on delete set null`
- `parent_task_id uuid references public.tasks(id) on delete set null`
- `event_metadata jsonb`
- Add event types:
  - `section_created`
  - `section_renamed`
  - `task_section_changed`
  - `subtask_created`
  - `subtask_completed`
  - `manual_importance_changed`

Migration rule:

- Because `behaviour_events` is partitioned, the migration must drop/recreate the `event_type` check constraint on the parent table and validate the new constraint. Do not just edit the original migration or update Swift strings.
- Set a short `lock_timeout` before altering the partitioned parent table so the migration fails fast instead of hanging behind long-running queries.

Payload rule:

- Replace string `oldValue` / `newValue` handling in Swift with typed JSON payloads that encode to JSONB.
- Minimum `estimate_override` payload:
  - `minutes`
  - `source`
  - `task_id`
  - `section_id`
  - `parent_task_id`
  - `is_subtask`
  - `estimate_source`

Silent learning:

- All estimate, section, completion, and importance mutations go through a new `TaskMutationService`.
- Deduplicate rapid estimate edits: within a 30-minute window for the same task, keep first and final values only.
- A correction is meaningful if it changes by at least 15 minutes or at least 33%, changes manual importance to orange/red, or repeats in the same bucket/section.
- Meaningful corrections are processed server-side into `estimate_priors` keyed by `(workspace_id, bucket_type, section_id)`.
- Morning review reads at most the three most relevant correction patterns and asks only when a follow-up would improve future recommendations.

Add `public.estimate_priors` before shipping the learning job:

- `workspace_id uuid not null references public.workspaces(id) on delete cascade`
- `profile_id uuid references public.profiles(id) on delete set null`
- `bucket_type public.canonical_bucket not null`
- `section_id uuid references public.task_sections(id) on delete cascade`
- `prior_minutes integer not null`
- `confidence numeric not null default 0`
- `sample_size integer not null default 0`
- `updated_at timestamptz not null default now()`
- Unique key on `(workspace_id, profile_id, bucket_type, section_id)`.

## Swift Changes

Add defaulted fields to `TimedTask` so old local JSON can decode:

- `sectionId: UUID? = nil`
- `parentTaskId: UUID? = nil`
- `sortOrder: Int = 0`
- `manualImportance: ManualImportance = .blue`
- `completedAt: Date? = nil`
- `notes: String? = nil`
- `isPlanningUnit: Bool = true`

Add:

- `TaskSection`
- `ManualImportance`
- `TaskHierarchyState` or equivalent pure grouping adapter
- `TaskMutationService`
- typed `BehaviourEventInsert` JSON payload support

Persistence rules:

- `DataBridge` and `SupabaseClient` load/save sections and tasks.
- `completedAt` is set only when a task transitions from incomplete to complete, then preserved.
- Local JSON migration must tolerate missing new fields and write the upgraded format on the next save.
- No Swift view writes directly to Supabase.

## Tool / AI Contract

`ConversationTools.swift` and `supabase/functions/orb-conversation/index.ts` must be updated atomically.

Required tool fields:

- `sectionId`
- `parentTaskId`
- `manualImportance`
- canonical bucket DB value

Contract enforcement:

- Add a shared schema source or an automated parity test that fails if Swift and Edge tool schemas diverge.
- Do not ship a UI that can create sections/subtasks before Orb, voice context, and Dish Me Up can read them.

Backend updates:

- `generate-dish-me-up` filters to `is_planning_unit = true` so it plans standalone tasks and subtasks, not parent containers.
- `voice-llm-proxy` reads `section_id`, `parent_task_id`, `manual_importance`, AI/manual estimates, and recent meaningful corrections.
- `voice-llm-proxy` must stop conflating workspace UUID and profile UUID in `.or(workspace_id.eq.${userId},profile_id.eq.${userId})`; resolve workspace/profile context explicitly before querying hierarchy-aware tasks.
- Morning voice context shows top-level tasks with a compact subtask summary, plus only the top correction prompts.
- `estimate-time` can estimate any planning unit; parent containers use child estimate sums for display only.

## UI Plan

- Sidebar uses native macOS disclosure sections.
- Users can add top-level sections and one-level subsections.
- Every section has an inline task add affordance.
- Every task row can add one-level subtasks.
- Blue/orange/red manual importance is shown as a compact control, not full-row color.
- AI estimate is visible; manual override is visible without noisy explanatory text.
- Completed tasks sit at the bottom of each section in a collapsed greyed-out group.
- Parent containers show child progress and effective child-estimate total.

## Implementation Sequence

1. Merge or isolate current offline-sync work before touching task persistence.
2. Gate 0 PR: bucket serialization + backfill + tests.
3. Schema PR: `task_sections`, task hierarchy columns, constraints, triggers, RLS, default section seed, `behaviour_events` migration.
4. Swift persistence PR: `TaskSection`, `ManualImportance`, `TimedTask` defaults, `TaskDBRow`, `SupabaseClient`, `DataBridge`, local JSON migration.
5. Mutation PR: `TaskMutationService`, typed behaviour event payloads, complete/estimate/importance/section mutation paths.
6. AI/backend PR: Orb schema parity, voice context, Dish Me Up planning-unit filter, estimate-priors learning job.
7. UI PR: sidebar hierarchy, inline task/subtask add, importance controls, completed group, parent container display.
8. Docs/memory PR: PRD, data model docs, behaviour-events docs, Timed-Brain updates.

## Risk Gates

- Gate 0: bucket serialization normalized and backfilled.
- Gate 1: schema migration reviewed before Swift model changes.
- Gate 2: default sections seeded for existing workspaces.
- Gate 3: one-level subtasks enforced at DB level.
- Gate 4: parent deletion and last-subtask deletion triggers pass migration tests.
- Gate 5: `DataBridge` offline queue changes landed before extending persistence.
- Gate 6: every mutation path logs structured behaviour events through `TaskMutationService`.
- Gate 7: Edge Function tool schemas match Swift tool schemas by shared source or automated parity test.
- Gate 8: Dish Me Up, voice context, estimate-time, and silent learning all understand planning units.
- Gate 9: RLS uses `private.user_workspace_ids()` and indexes are verified for `task_sections`, `tasks.section_id`, and `tasks.parent_task_id`.
- Gate 10: old local JSON decodes and upgrades.
- Gate 11: `swift build`, `swift test`, relevant `deno check`, migration checks, and `graphify update .` pass.

## Acceptance Tests

- `TaskBucket` DB round-trip for every case.
- Existing local `TimedTask` JSON without new fields decodes without crashing.
- Every existing workspace gets system sections after migration.
- Cross-workspace users cannot read or mutate another workspace's sections.
- Inserting a subtask under a subtask fails.
- A task cannot parent itself.
- Deleting a parent preserves children as standalone tasks in the expected section.
- Changing an estimate from Today, Tasks, Detail, and Orb each logs one structured `estimate_override`.
- Rapid estimate edits dedupe to first/final values.
- `generate-dish-me-up` never double-counts parent containers and subtasks.
- Voice context includes section/subtask/estimate data.
- Orb can add a subtask with `parent_task_id`.
- Completed tasks render collapsed and greyed at the bottom.
- Morning review mentions only meaningful correction patterns.
- Parent deletion promotes children: former children have `parent_task_id = null`, `is_planning_unit = true`, and the expected `section_id`.
- Deleting the final subtask restores the parent `is_planning_unit = true`.
- `task_sections` RLS uses `private.user_workspace_ids()` and does not evaluate a join per row.
- `task_sections.canonical_bucket_type` rejects human labels like `Reply`.

## Perplexity Round 3 Validation Request

Validate this second revision for implementability. Do not be contrarian for its own sake. Only flag material blockers that could cause data loss, backend drift, migration failure, AI/tool mismatch, security/RLS leakage, or broken user-facing behavior.

If this plan is now implementable, say so clearly and list only non-blocking improvements separately.
