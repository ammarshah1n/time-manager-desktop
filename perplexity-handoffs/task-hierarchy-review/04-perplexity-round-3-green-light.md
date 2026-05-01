---
source_url: https://www.perplexity.ai/search/ac0459bd-58a5-4e58-8bfe-e26a3bd00f4e
title: "Do not merely convert the uploaded files into a report. Treat them as starting..."
captured_at: 2026-05-01T11:28:07.534Z
length: 18993
---

Round 3 validation. The plan below incorporates your two material fixes from Round 2: parent deletion is owned by DB triggers with ON DELETE RESTRICT, RLS uses a private SECURITY DEFINER workspace helper, canonical buckets use a domain, estimate_priors is defined, and extra tests were added. Do not be contrarian for its own sake. Only flag material blockers that would make implementation unsafe. If there are no material blockers, explicitly say: GREEN LIGHT: implementable. Put non-blocking suggestions separately.

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
Show more
Reviewing the revised plan for implementation risks and safe blockers

GREEN LIGHT: implementable.

No material blockers remain. The two fixes from Round 2 are correctly incorporated. The trigger model, RLS pattern, domain approach, and planning-unit model are all sound. The gate ordering and acceptance test matrix are complete.

Confirmation of Round 2 Fixes

Parent deletion trigger correctly uses ON DELETE RESTRICT + a BEFORE DELETE trigger owning promotion semantics. The FK cascade conflict described in Round 2 cannot occur under this design.
01-normalisation-risk-gates.md

RLS is correctly delegated to private.user_workspace_ids() as a SECURITY DEFINER stable function, avoiding per-row join evaluation and RLS-on-RLS cycles.
supabase
+1

canonical_bucket domain applied to both tasks.bucket_type and task_sections.canonical_bucket_type closes the silent mismatch gap.
reddit

estimate_priors table is defined with correct composite unique key and domain-typed bucket_type before the learning job ships.
01-normalisation-risk-gates.md

voice-llm-proxy workspace/profile conflation is explicitly called out for fix in the AI/backend PR.

One Narrow Issue Worth Noting (Not a Blocker, But Address in the Schema PR)
estimate_priors.section_id is ON DELETE CASCADE — verify intent

The plan defines section_id uuid references public.task_sections(id) on delete cascade on estimate_priors. This means deleting a custom section silently deletes all learned priors for that section. For system sections (is_system = true) this never fires, so learned priors for canonical buckets are safe. For user-created custom sections it means the prior disappears when the user archives or deletes the section, which is probably acceptable — but if the intent is to retain priors even after section deletion (for post-hoc analysis or retraining), ON DELETE SET NULL with a nullable section_id on estimate_priors would be safer. Neither is wrong; just make it deliberate. Given that (workspace_id, profile_id, bucket_type, section_id) is the unique key, SET NULL would collapse multiple section-level priors onto the same (workspace_id, profile_id, bucket_type, NULL) key on conflict — so if you use SET NULL you need ON CONFLICT DO UPDATE logic in the learning job. CASCADE is simpler and likely fine for v1.

Non-Blocking Improvements

These will not cause implementation failure. Carry them as backlog items.

task_sections nesting trigger should also fire on UPDATE of parent_section_id, not only INSERT. A user renaming or re-parenting a section via Orb or a future API call that issues an UPDATE rather than an INSERT could bypass the depth check if the trigger is BEFORE INSERT only. Make it BEFORE INSERT OR UPDATE OF parent_section_id.

restore_planning_unit_on_last_child_delete needs to handle soft-delete if you ever add a status = 'cancelled' path for subtasks. Currently the trigger checks NOT EXISTS (SELECT 1 FROM tasks WHERE parent_task_id = OLD.parent_task_id). If cancelled/done subtasks remain as rows, the parent will never have is_planning_unit restored because child rows still exist. Consider filtering: WHERE parent_task_id = OLD.parent_task_id AND status NOT IN ('done','cancelled'), matching the planner's own status = 'pending' filter.

promote_orphaned_subtasks trigger should log a task_section_changed behaviour event for any child whose section_id changed during promotion (i.e. where the child had no section_id of its own and inherited from the parent). Without this, the silent learning signal misses the reclassification. This is a low-priority nicety for v1 but will matter when the estimator tries to attribute priors to sections.

estimate_priors.confidence is typed numeric with no precision. Postgres numeric without precision/scale is unconstrained, which is fine, but adding check (confidence between 0 and 1) makes the semantics explicit and prevents the learning job from accidentally writing raw event counts instead of a normalised score.

Shared tool-schema source is required by Gate 7 but the concrete artefact (a supabase/shared/tool-schemas.json and a Deno parity test) is not defined in the plan. Adding this to the schema PR scope (even as a stub with a failing test) ensures Gate 7 is testable before the AI/backend PR opens.

voice-llm-proxy workspace fix is called out in the AI/backend PR but the fix is one line and very low risk. Consider moving it to the Schema PR or Gate 0 PR as a standalone commit so it does not block hierarchy-related voice testing in Phase 3.

Prepared by Deep Research
4 sources
Ask a follow-up
Deep research
