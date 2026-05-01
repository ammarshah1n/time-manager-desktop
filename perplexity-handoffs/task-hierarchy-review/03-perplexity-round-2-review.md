---
source_url: https://www.perplexity.ai/search/ac0459bd-58a5-4e58-8bfe-e26a3bd00f4e
title: "Do not merely convert the uploaded files into a report. Treat them as starting..."
captured_at: 2026-05-01T11:25:21.629Z
length: 54829
---

Executive verdict: safe / unsafe / safe after changes.
- Top 10 implementation blockers, ordered by severity.
- Required schema changes with exact columns and constraints.
- Required Swift/API changes.
- Required Edge Function / Trigger changes.
- Collision prevention plan.
- Acceptance test matrix.
- Revised implementation plan.
- Any assumptions you had to make.
Show more
3 attachments
Completed 6 steps

I now have everything needed. Let me write the full implementation risk report.

Timed — TickTick Hierarchy + Silent AI Learning: Implementation Risk Report

Verdict: UNSAFE TO IMPLEMENT AS WRITTEN. Safe after the changes described below.

The plan identifies the right concepts but contains eight hard blockers that will cause data loss, silent corruption, or divergent state between Swift, Supabase, Orb, and the planner if work begins immediately. No single layer can be implemented safely while the others remain in their current state.

Executive Summary

The proposal introduces three structurally entangled changes simultaneously: (1) a task_sections display hierarchy over fixed canonical buckets, (2) one-level subtasks stored as peer task rows with a parent_task_id self-reference, and (3) a silent AI-learning loop fed by behaviour_events. Each change is individually achievable. Their collision risk is high because the current codebase has a pre-existing data integrity fault — Swift writes human-readable TaskBucket.rawValue strings ("Reply", "Read Today") into tasks.bucket_type, while the DB check constraint expects snake_case values (reply_email, read_today) — that must be treated as the true Gate 0 before any hierarchy work begins. Until that round-trip is idempotent, any migration that adds section_id or parent_task_id will produce rows with invalid bucket_type values that the DB constraint will silently accept (because the existing constraint was defined at table creation with the correct enum, but DataBridge bypasses it by writing wrong strings that the Swift row type does not validate before insert).
00-org-summary.md
+1

Beyond that structural fault, the planner (generate-dish-me-up), voice proxy, and Orb tool schemas are all flat and have no awareness of the proposed hierarchy, meaning a partial rollout where the Swift UI creates sections and subtasks will produce double-counted plan estimates and orphaned context in all AI surfaces.
00-org-summary.md

Identity of the Codebase (Subject Verification)

All evidence is drawn from the supplied repo context files and verified cross-references to the named Swift source paths, Supabase migration SQL, and Edge Function TypeScript. No external namesake ambiguity applies; this is a single private codebase.

Top 10 Implementation Blockers (Ordered by Severity)
Blocker 1 — Bucket Serialization Fault (CRITICAL / Data Corruption)

DataBridge.makeTaskRow writes task.bucket.rawValue ("Reply", "Read Today") into tasks.bucket_type. The Postgres check constraint requires snake_case values (reply_email, read_today, read_this_week, cc_fyi). Because the Supabase Swift client submits these as plain strings, they either silently insert with wrong values (bypassing check if old rows pre-date the constraint) or fail at insert. Any migration that adds section_id will JOIN against bucket_type values that are wrong. Every round-trip decode also fails because TimedTask.init(from:) tries TaskBucket(rawValue: row.bucketType) where row.bucketType is a DB snake_case string but the enum case expects the human label.
00-org-summary.md

Fix required before anything else: Add a static func dbValue: String computed property to TaskBucket that maps each case to its DB-safe snake_case string, update makeTaskRow to use it, update TimedTask.init(from:) to use a reverse mapping table, and run a one-time backfill migration to normalize existing rows.

Blocker 2 — behaviour_events Check Constraint on Partitioned Table (CRITICAL / Migration Risk)

The new event types (section_created, section_renamed, task_section_changed, subtask_created, subtask_completed, manual_importance_changed) must be added to the event_type check constraint on behaviour_events, which is a partitioned table. In Postgres, ALTER TABLE … ADD CONSTRAINT on a partitioned parent propagates to all existing child partitions only if they are attached partitions defined after the parent constraint. Adding or modifying a check constraint on an already-partitioned table requires running the ALTER on the parent (which Postgres ≥ 11 propagates automatically to all existing partitions) but then validating it with VALIDATE CONSTRAINT separately to avoid table-level locks. The migration file must handle this explicitly; simply changing the enum in the parent DDL in a new migration file is not sufficient if partition slabs already exist.
github
youtube
00-org-summary.md

Fix required: Write the migration to drop the old event_type check constraint by name, recreate it with all new values, then VALIDATE CONSTRAINT explicitly. Do not use NOT VALID unless you accept that old rows with unsupported types will not be checked.

Blocker 3 — tasks.parent_task_id Deletion Semantics Unspecified (HIGH / Data Loss Risk)

The plan proposes parent_task_id on tasks but does not define the ON DELETE behaviour. Three choices have materially different consequences:
01-normalisation-risk-gates.md
stackoverflow
+1

Option	Effect	Correct for Timed?
ON DELETE CASCADE	Deleting parent silently deletes all subtasks	No — user created subtasks independently and expects them to survive or be promoted
ON DELETE SET NULL	Deleting parent orphans subtasks (becomes parentless top-level tasks)	Yes, with caveat — subtasks become standalone in their section
ON DELETE RESTRICT	Prevents parent deletion while subtasks exist	Safer UX but requires explicit UI prompt

Recommended: ON DELETE SET NULL with a compound check (CHECK (parent_task_id != id)) to prevent self-referencing, plus a Postgres trigger or application-level guard that promotes orphaned subtasks to the parent's section rather than leaving them parentless. Add a DB-level depth constraint: a task with a non-null parent_task_id cannot itself be referenced as a parent by another row (one-level only). Enforce with a trigger, not just application code, because Orb and Edge Functions write directly.
reddit

Blocker 4 — generate-dish-me-up Double-Counts Parent + Child Tasks (HIGH / AI Planning Corruption)

The planner query selects all status = 'pending' rows with no filter on parent_task_id. Once subtasks are stored as peer rows, the planner will sum estimated_minutes for both a parent task and all its subtasks, inflating the daily plan time. For example, a parent task "Draft contract" (estimated 60 min) with three subtasks (20 min each) would yield 120 min of double-counted work.
00-org-summary.md

Fix required (v1 minimum): Extend the planner query with .is('parent_task_id', null) to plan only at the parent level, and separately sum child estimates onto the parent's row via a computed column or a DB view (task_with_subtask_duration) that returns effective planned minutes. Alternatively, treat subtasks as non-plannable and mark parent_task_id IS NOT NULL rows as is_planning_unit = false. The plan says subtasks are "first-class planning rows" but this conflicts directly with the double-counting risk — pick one model and enforce it at the DB layer before shipping.
01-normalisation-risk-gates.md

Blocker 5 — Swift/Edge Tool Schema Divergence (HIGH / Runtime Orb Failures)

ConversationTools.swift and orb-conversation/index.ts contain identical TOOL_SCHEMAS arrays that must stay in exact lockstep. Adding sectionId, parentTaskId, and manualImportance to one without updating the other means the Claude tool-call contract will be broken: Orb will either hallucinate field values, pass unrecognised fields, or fail to add subtasks/sections when instructed. There is currently no shared schema source of truth — both files are hand-maintained.
00-org-summary.md

Fix required: Generate both schemas from a single canonical JSON or TypeScript definition file (kept in supabase/shared/tool-schemas.ts, exported as a module for the Edge Function and rendered as a Swift file at build time via a code-gen script, or at minimum checked by a Deno test that diffs the two). Gate 5 from the plan is correct but the enforcement mechanism is not specified.
01-normalisation-risk-gates.md

Blocker 6 — estimate_override Logging Is Incomplete and Payload Is Opaque (HIGH / AI Learning Broken)

TodayPane logs estimate_override but TasksPane.onUpdateTime, TaskDetailSheet, and Orb's update_task path do not. The Swift BehaviourEventInsert struct passes oldValue and newValue as String? even though the Postgres column is jsonb. This means the learning signal is both incomplete (missing 3 of 4 edit surfaces) and machine-unreadable (string "45" vs. structured {"minutes": 45, "source": "task_pane"}). Future estimator training cannot be retrained from these events reliably.
00-org-summary.md

Fix required: (a) Create a single TaskMutationService that all edit surfaces call; it is the only place that constructs and inserts behaviour_events. (b) Change BehaviourEventInsert.oldValue and newValue to [String: AnyCodable] or a typed EventPayload struct that encodes to valid JSONB. Minimum payload for estimate events: {"minutes": Int, "source": String, "task_id": UUID, "section_id": UUID?, "is_subtask": Bool}.

Blocker 7 — Local JSON Cache Has No Migration Path for New Fields (MEDIUM / Crash on Upgrade)

TimedTask is Codable and persisted to local JSON. When sectionId, parentTaskId, sortOrder, manualImportance, completedAt, and notes are added as non-optional fields, existing cached JSON files that lack these keys will throw a DecodingError.keyNotFound at launch, making the app unlaunchable for any user with a local cache.
oneuptime
+1

Fix required: All new fields on TimedTask and TaskSection must have Optional type or be given @Default property-wrapper-backed defaults. Add a modelVersion: Int field to the local JSON root with a migration function that reads the old format and writes the new one on first launch after upgrade. New fields: var sectionId: UUID? = nil, var parentTaskId: UUID? = nil, var sortOrder: Int = 0, var manualImportance: ManualImportance = .blue, var completedAt: Date? = nil, var notes: String? = nil.
joro

Blocker 8 — task_sections Has No Seed Migration for Existing Users (MEDIUM / Blank UI on First Launch)

The plan adds a task_sections table but does not define how existing users get their default system sections created. On first launch after the migration, the sidebar will be empty (no sections exist in the new table). The proposal says "default sections are display/organisation structure" but does not specify whether they are seeded by the backend or the Swift client.
01-normalisation-risk-gates.md

Fix required: Write a Postgres migration or a Supabase Edge Function called on workspace creation (and back-filled for existing workspaces) that inserts the canonical system sections (is_system = true) mapped to each canonical_bucket_type. The Swift client should not bootstrap sections on first run; it should read from the DB and fall back to showing tasks in a flat view only if a network failure prevents loading. A supabase/seeds/default_sections.sql that can be re-run idempotently (using ON CONFLICT DO NOTHING) is the safest approach.

Blocker 9 — voice-llm-proxy Morning Context Is Blind to Hierarchy (MEDIUM / Broken Voice Experience)

The morning check-in query selects 7 columns from tasks with no join to task_sections and no parent_task_id awareness. After hierarchy lands, the voice model will read a flat list of tasks without knowing which are subtasks, which section they belong to, or what manual importance was set. It also lacks estimates, which the plan requires the morning flow to reference when asking about corrections.
00-org-summary.md

Fix required (v1): At minimum, add section_id, parent_task_id, manual_importance, estimated_minutes_ai, estimated_minutes_manual to the voice query. Exclude pure subtasks from the primary context list (WHERE parent_task_id IS NULL) and inject a brief subtask summary per parent. This is a small query change but must be coordinated with schema landing.

Blocker 10 — completedAt Is Fabricated at Save-Time (LOW-MEDIUM / Reporting Fault)

DataBridge.makeTaskRow writes completedAt: task.isDone ? Date() : nil — meaning the completion timestamp is the moment of the next save, not the moment the user ticked the task done. This corrupts estimation_history actuals and breaks any reporting on completion time vs. scheduled time.
00-org-summary.md

Fix required: Add var completedAt: Date? to TimedTask. Set it once when isDone transitions from false to true via TaskMutationService, preserve it on subsequent saves.

Required Schema Changes
sql
-- Migration: add task_sections table
create table public.task_sections (
  id                   uuid primary key default gen_random_uuid(),
  workspace_id         uuid not null references public.workspaces(id) on delete cascade,
  profile_id           uuid references public.profiles(id) on delete set null,
  parent_section_id    uuid references public.task_sections(id) on delete set null,
  title                text not null,
  canonical_bucket_type text not null references bucket_type_check,
  sort_order           integer not null default 0,
  color_key            text,
  is_system            boolean not null default false,
  is_archived          boolean not null default false,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  -- Enforce max one subsection level in DB: a section with a parent cannot itself be a parent
  -- (enforced via trigger; DB cannot express this with a simple check constraint)
  constraint task_sections_no_deep_nesting check (true) -- placeholder; see trigger below
);
create index idx_task_sections_workspace on public.task_sections(workspace_id);
create index idx_task_sections_parent on public.task_sections(parent_section_id) where parent_section_id is not null;

-- Migration: extend tasks table
alter table public.tasks
  add column section_id         uuid references public.task_sections(id) on delete set null,
  add column parent_task_id     uuid references public.tasks(id) on delete set null,
  add column sort_order         integer not null default 0,
  add column manual_importance  text not null default 'blue'
    check (manual_importance in ('blue', 'orange', 'red')),
  add column notes              text,
  -- completedAt already exists in schema; ensure it is set precisely
  add column is_planning_unit   boolean not null default true;

-- Prevent self-reference and deep nesting via trigger
create or replace function enforce_subtask_depth()
returns trigger language plpgsql as $$
begin
  if new.parent_task_id is not null then
    -- self-reference
    if new.parent_task_id = new.id then
      raise exception 'A task cannot be its own parent';
    end if;
    -- parent cannot itself be a subtask (one level only)
    if exists (select 1 from public.tasks where id = new.parent_task_id and parent_task_id is not null) then
      raise exception 'Subtasks cannot have subtasks (max depth: 1)';
    end if;
    -- a parent cannot be planning_unit=false while subtasks are being added to it
    -- mark parent as container
    update public.tasks set is_planning_unit = false where id = new.parent_task_id and is_planning_unit = true;
  end if;
  return new;
end;
$$;
create trigger trg_subtask_depth
before insert or update of parent_task_id on public.tasks
for each row execute function enforce_subtask_depth();

-- Indexes
create index idx_tasks_section_id on public.tasks(section_id) where section_id is not null;
create index idx_tasks_parent_task_id on public.tasks(parent_task_id) where parent_task_id is not null;
create index idx_tasks_workspace_status_planning on public.tasks(workspace_id, status, is_planning_unit)
  where status = 'pending';

-- Extend behaviour_events check constraint (partitioned table — must be done carefully)
alter table public.behaviour_events drop constraint if exists behaviour_events_event_type_check;
alter table public.behaviour_events add constraint behaviour_events_event_type_check
  check (event_type in (
    'task_completed','task_deferred','task_deleted','plan_order_override',
    'estimate_override','session_started','triage_correction',
    'section_created','section_renamed','task_section_changed',
    'subtask_created','subtask_completed','manual_importance_changed'
  ));
-- After adding, validate without locking:
alter table public.behaviour_events validate constraint behaviour_events_event_type_check;

-- Extend behaviour_events columns
alter table public.behaviour_events
  add column section_id      uuid references public.task_sections(id) on delete set null,
  add column parent_task_id  uuid references public.tasks(id) on delete set null,
  add column event_metadata  jsonb;

-- Backfill bucket_type normalization (one-time)
update public.tasks set bucket_type = case bucket_type
  when 'Reply'          then 'reply_email'
  when 'Action'         then 'action'
  when 'Calls'          then 'calls'
  when 'Read Today'     then 'read_today'
  when 'Read This Week' then 'read_this_week'
  when 'Transit'        then 'transit'
  when 'Waiting'        then 'waiting'
  when 'CC / FYI'       then 'cc_fyi'
  else bucket_type
end
where bucket_type not in ('action','reply_email','reply_wa','reply_other','read_today',
  'read_this_week','calls','transit','waiting','other');
Required RLS Policies
sql
-- task_sections: workspace-scoped, no cross-tenant access
alter table public.task_sections enable row level security;

create policy "task_sections_select" on public.task_sections
  for select to authenticated
  using (workspace_id in (
    select id from public.workspaces where profile_id = auth.uid()
    union
    select workspace_id from public.workspace_members where profile_id = auth.uid()
  ));

create policy "task_sections_insert" on public.task_sections
  for insert to authenticated
  with check (workspace_id in (
    select id from public.workspaces where profile_id = auth.uid()
    union
    select workspace_id from public.workspace_members where profile_id = auth.uid()
  ));

create policy "task_sections_update" on public.task_sections
  for update to authenticated
  using (workspace_id in (
    select id from public.workspaces where profile_id = auth.uid()
  ));

-- System sections cannot be renamed or archived by the user (enforce in application layer)
-- tasks: existing RLS must be extended to cover new columns — no change to policy syntax needed
-- as the workspace_id check already covers the new rows

Note: the existing tasks RLS should use workspace_id consistently. The current voice-llm-proxy query uses or(workspace_id.eq.${userId},profile_id.eq.${userId}), which conflates workspace and profile IDs — this should be normalised when the hierarchy work lands.
supabase
+2
00-org-summary.md

Required Swift / API Changes

TimedTask model additions (all optional or defaulted for backward compatibility):

swift
var sectionId: UUID?       = nil
var parentTaskId: UUID?    = nil
var sortOrder: Int         = 0
var manualImportance: ManualImportance = .blue
var completedAt: Date?     = nil
var notes: String?         = nil
// computed
var isSubtask: Bool { parentTaskId != nil }
var isPlanningUnit: Bool   = true

TaskBucket serialization fix:

swift
extension TaskBucket {
  var dbValue: String {
    switch self {
    case .reply:        return "reply_email"
    case .action:       return "action"
    case .calls:        return "calls"
    case .readToday:    return "read_today"
    case .readThisWeek: return "read_this_week"
    case .transit:      return "transit"
    case .waiting:      return "waiting"
    case .ccFyi:        return "cc_fyi"
    }
  }
  static func from(dbValue: String) -> TaskBucket? {
    TaskBucket.allCases.first { $0.dbValue == dbValue }
  }
}

TaskDBRow additions:

swift
let sectionId: UUID?
let parentTaskId: UUID?
let sortOrder: Int
let manualImportance: String
let notes: String?
let isPlanningUnit: Bool

New TaskSection Swift model:

swift
struct TaskSection: Identifiable, Codable, Sendable {
  let id: UUID
  let workspaceId: UUID
  var title: String
  let parentSectionId: UUID?
  let canonicalBucketType: String
  var sortOrder: Int
  var colorKey: String?
  let isSystem: Bool
  var isArchived: Bool
}

TaskMutationService (new, centralised):
All task mutations (estimate change, importance change, done toggle, section move, subtask creation) must flow through a single service that: (a) applies the change to the in-memory model, (b) constructs and inserts a BehaviourEventInsert with structured JSONB payload, (c) calls DataBridge to persist. This replaces scattered tasks[idx].estimatedMinutes = newMins calls in TasksPane, TaskDetailSheet, TodayPane, and Orb tool handlers.
00-org-summary.md

BehaviourEventInsert payload change:

swift
struct BehaviourEventInsert: Codable, Sendable {
  // ... existing fields ...
  let sectionId: UUID?
  let parentTaskId: UUID?
  let eventMetadata: [String: AnyJSON]  // encodes to jsonb
}
Required Edge Function / Trigger Changes

orb-conversation/index.ts — add to both add_task and update_task schemas:

typescript
sectionId:        { type: "string", format: "uuid", description: "Target section ID" },
parentTaskId:     { type: "string", format: "uuid", description: "Parent task ID (subtasks only)" },
manualImportance: { type: "string", enum: ["blue", "orange", "red"] },

This must be done atomically with the Swift ConversationTools.swift change in a single PR.
01-normalisation-risk-gates.md

voice-llm-proxy/index.ts — extend task query:

typescript
supabase.from("tasks")
  .select("id,title,bucket_type,section_id,parent_task_id,manual_importance,
           estimated_minutes_ai,estimated_minutes_manual,due_at,is_overdue,is_planning_unit")
  .eq("status", "pending")
  .is("parent_task_id", null)   // top-level only for morning context
  .limit(20)

generate-dish-me-up/index.ts — prevent double-counting:

typescript
.eq("is_planning_unit", true)  // excludes parent containers once they have subtasks

Separately, sum child estimates onto the parent in a DB view for display purposes.

New estimate-learning Trigger job (or Supabase scheduled function):

text
Runs nightly or on demand.
Reads behaviour_events WHERE event_type = 'estimate_override'
  AND occurred_at > last_run_at
  AND ABS(CAST(new_value->>'minutes' AS int) - CAST(old_value->>'minutes' AS int)) >= 15
     OR ABS(CAST(new_value->>'minutes' AS int) - CAST(old_value->>'minutes' AS int))::float
        / NULLIF(CAST(old_value->>'minutes' AS int), 0) >= 0.33
Groups by (workspace_id, bucket_type, section_id) to detect drift patterns.
Writes corrected priors back to a new table: estimate_priors(workspace_id, bucket_type, section_id, prior_minutes, confidence, updated_at).
generate-dish-me-up reads estimate_priors for future plan estimates.

This keeps AI learning entirely server-side and silent. No direct AI API call from Swift.
01-normalisation-risk-gates.md

Collision Prevention Plan

The four files identified as collision-prone (DataBridge.swift, OfflineSyncQueue.swift, TimedAppShell.swift, DataBridgeTests.swift) all touch the same persistence pipeline that the hierarchy work will extend. The plan's worker-split approach is correct, but the sequencing must be strictly serial:
01-normalisation-risk-gates.md
+1

No hierarchy work begins until the offline-sync branch for those four files is merged and main/unified is clean.

Schema worker owns: migration files, RLS, indexes, trigger function, seed SQL — no Swift changes.

Swift persistence worker owns: TimedTask, TaskSection, TaskDBRow, BehaviourEventInsert, DataBridge, SupabaseClient, OfflineSyncQueue extensions — no UI changes.

UI worker begins only after Swift persistence worker's PR is merged and swift build passes.

AI/backend worker owns: ConversationTools, orb-conversation, voice-llm-proxy, generate-dish-me-up — begins after schema worker PR is merged and deno check passes on Edge Functions.

Workers 3 and 5 must coordinate on the single atomic PR that updates both ConversationTools.swift and orb-conversation TOOL_SCHEMAS simultaneously.

Subtask Coherence Model

The plan says subtasks are "first-class planning rows" but the double-counting risk (Blocker 4) requires a clear ruling. Recommended model:

A task with parent_task_id IS NOT NULL is a subtask. It has its own estimated_minutes, manual_importance, sort_order, and behaviour_events. It can be completed independently.

A task that has subtasks (is_planning_unit = false) is a container. generate-dish-me-up does not plan it directly; it plans its subtasks. Its effective estimate is the sum of incomplete subtask estimates (maintained by the trigger on subtask update).

A task with no children and parent_task_id IS NULL is a standalone task. is_planning_unit = true. Planned normally.

Completion rule: Completing the last incomplete subtask does NOT auto-complete the parent. The parent requires an explicit done-tick. Rationale: the parent may have non-subtask work (its own title/notes represent context). Completing a subtask logs subtask_completed; completing the parent logs task_completed. Avoid double learning signals by only feeding estimation_history actuals from the parent's completedAt - scheduledStartTime delta, not from each subtask independently.
01-normalisation-risk-gates.md

Silent Learning Coherence

The plan's 15-minute / 33% threshold for "meaningful correction" is sound. Additional rules needed:
01-normalisation-risk-gates.md

Deduplication gate: If the same task's estimate is changed more than once in a 30-minute window, log only the first and last event; discard intermediate. Prevents rapid slider-dragging from polluting the prior.

Subtask override attribution: When a subtask estimate is changed, tag the behaviour_event with both task_id = subtask.id and parent_task_id = subtask.parentTaskId so the learning signal can be aggregated at the parent-bucket level.

Morning review gate: The voice-llm-proxy morning summary should include at most the 3 most-recent meaningful corrections (above threshold, deduplicated) rather than all corrections since last session. "Meaningful" is evaluated server-side by the estimate-learning job, not the Swift client.

Acceptance Test Matrix
#	Test	Layer	Pass Criterion
T1	TaskBucket DB round-trip	Swift unit	TaskBucket.from(dbValue: bucket.dbValue) == bucket for all cases
T2	TimedTask Codable with missing new fields	Swift unit	Old JSON without sectionId/parentTaskId decodes without throw; new fields nil/default
T3	Subtask depth enforcement	DB trigger	Insert of task with parent_task_id pointing to a subtask raises exception
T4	Self-reference prevention	DB trigger	UPDATE tasks SET parent_task_id = id WHERE id = X raises exception
T5	Parent deletion promotes subtask	DB + integration	DELETE FROM tasks WHERE id = parent sets child parent_task_id = NULL, child still exists
T6	estimate_override emitted from all surfaces	Integration	Changing estimate in TasksPane, TaskDetailSheet, TodayPane, and Orb each produce 1 behaviour_events row with valid JSONB payload
T7	Tool schema parity	Deno test	orb-conversation TOOL_SCHEMAS and ConversationTools.schemas() output diff is empty
T8	Planner excludes subtasks and containers	Backend	generate-dish-me-up result for a parent-with-subtasks includes only subtasks in plan, parent excluded
T9	RLS cross-workspace isolation	Backend	User A cannot read task_sections owned by workspace B
T10	Default sections seeded on existing workspaces	Migration	After migration, each existing workspace has 8+ task_sections rows with is_system = true
T11	Local JSON migration on upgrade	Swift integration	App launched with pre-hierarchy JSON cache loads cleanly, all tasks visible with default field values
T12	Completed tasks appear at bottom	UI	Done task renders greyed, sorted below all pending tasks in its section, in collapsed group
T13	Orb can add subtask via voice	End-to-end	"Add a subtask to Draft contract called Attach exhibits" → new row with parent_task_id set, logged in behaviour_events
T14	Morning review references corrections	End-to-end	After 45→30 min override, next morning voice session mentions the correction pattern
T15	swift build + swift test + deno check	CI	Zero errors across all three
Revised Implementation Sequence

Phase 0 — Prerequisites (before any feature branch is opened)

Merge outstanding offline-sync work in DataBridge.swift, OfflineSyncQueue.swift, TimedAppShell.swift, DataBridgeTests.swift
01-normalisation-risk-gates.md

Fix TaskBucket serialization (Gate 1) — single PR, includes backfill migration

Confirm swift build + swift test clean

Phase 1 — Schema (schema-worker owns)

Migration: task_sections table + RLS + indexes

Migration: extend tasks with new columns + trigger function

Migration: fix behaviour_events check constraint for new event types + extend columns

Seed migration for default system sections

deno check on all Edge Functions after migration type generation

Phase 2 — Swift Persistence (swift-worker owns)

Add TaskSection model, ManualImportance enum

Extend TimedTask and TaskDBRow with new optional fields

Implement TaskMutationService with consistent behaviour_events emission

Extend DataBridge and OfflineSyncQueue for section upsert + subtask rows

Update SupabaseClient codegen types

swift build + swift test — T1, T2, T6 must pass

Phase 3 — AI/Backend (ai-worker owns, concurrent with Phase 2 after Phase 1 lands)

Update ConversationTools.swift and orb-conversation TOOL_SCHEMAS in atomic commit — T7 must pass

Update voice-llm-proxy query

Update generate-dish-me-up with is_planning_unit filter — T8 must pass

Implement estimate-learning nightly job

deno check + integration tests T6, T8, T9

Phase 4 — UI (ui-worker owns, after Phase 2 lands)

Sidebar disclosure groups replacing fixed bucket rows

Subtask inline add, importance colour controls

Completed tasks collapsed group

AI estimate badge + override UI

T12 manual acceptance

Phase 5 — End-to-end acceptance

Full matrix T1–T15

graphify update .

PRD and memory updates
01-normalisation-risk-gates.md

Assumptions Made

The Supabase project uses Postgres ≥ 14 (partitioned table constraint propagation behaviour assumed as described).
github

workspace_members table exists or workspace ownership is determined by workspaces.profile_id; the exact join for RLS must be confirmed against the actual schema.

estimation_history table referenced in the plan exists in the DB; it was not shown in the supplied migration snippet.

Orb/Claude tool calls return task mutations as JSON to the Swift ConversationModel, which applies them through TaskMutationService, not directly — this is the correct architecture per the hard constraint "no direct AI API calls from Swift".
01-normalisation-risk-gates.md

is_planning_unit is initialised true for all existing tasks in the backfill migration and set to false by the subtask trigger only on new parent assignment.

cc_fyi is the correct DB snake_case for TaskBucket.ccFyi; the DB check constraint currently allows other but not cc_fyi — the bucket normalisation migration must add cc_fyi or map it to other.

Unresolved Gaps

estimation_history table structure not provided — cannot confirm whether the silent learning job can write corrected priors to it or needs a new estimate_priors table.

WorkspaceMembers RLS join path — RLS policies above assume a members table; must be verified against full schema.

Supabase supabase-js Swift SDK version — the codegen types for TaskDBRow need to be regenerated after schema changes; the generation command is not documented in the supplied files.

Offline queue serialisation format — OfflineSyncQueue operation type not shown; must confirm it can serialise task_sections.upsert operations alongside existing task operations.

cc_fyi bucket DB value — the existing check constraint does not list cc_fyi; either the bucket must map to other or the constraint must be extended.

Prepared by Deep Research
33 sources
Please review this revised plan after your first report. Do not be contrarian for its own sake. Only flag material blockers that could cause data loss, backend drift, migration failure, AI/tool mismatch, security/RLS leakage, or broken user-facing behavior. If it is implementable, say so clearly and put non-blocking improvements in a separate section.

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

- `canonical_bucket_type` must use the same canonical values as `tasks.bucket_type`.
- Add indexes on `(workspace_id, profile_id, is_archived, sort_order)` and `parent_section_id`.
- Enforce one visible subsection level with a DB trigger: a section with a parent cannot itself become a parent.
- Seed default system sections server-side for every existing workspace with an idempotent migration or seed script. The Swift client must not be the source of truth for system section creation.

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
- `parent_task_id uuid references public.tasks(id) on delete set null`
- `sort_order integer not null default 0`
- `manual_importance text not null default 'blue' check (manual_importance in ('blue','orange','red'))`
- `notes text`
- `is_planning_unit boolean not null default true`

Required constraints and triggers:

- Prevent self-parenting: `parent_task_id != id`.
- Enforce one-level subtasks at DB level: a task whose `parent_task_id` is not null cannot be used as another task's parent.
- When a subtask is added to a parent, set the parent `is_planning_unit = false`.
- Before deleting a parent task, promote children by setting `parent_task_id = null` and preserving or copying the parent's `section_id`.
- A parent container may still be completed manually, but parent completion does not produce an estimate-learning signal unless it has its own explicit actual minutes and no incomplete subtasks.

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
- Gate 4: `DataBridge` offline queue changes landed before extending persistence.
- Gate 5: every mutation path logs structured behaviour events through `TaskMutationService`.
- Gate 6: Edge Function tool schemas match Swift tool schemas by shared source or automated parity test.
- Gate 7: Dish Me Up, voice context, estimate-time, and silent learning all understand planning units.
- Gate 8: RLS and indexes verified for `task_sections`, `tasks.section_id`, and `tasks.parent_task_id`.
- Gate 9: old local JSON decodes and upgrades.
- Gate 10: `swift build`, `swift test`, relevant `deno check`, migration checks, and `graphify update .` pass.

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

## Perplexity Round 2 Validation Request

Validate this revised plan for implementability. Do not be contrarian for its own sake. Only flag material blockers that could cause data loss, backend drift, migration failure, AI/tool mismatch, security/RLS leakage, or broken user-facing behavior.

If this plan is now implementable, say so clearly and list only non-blocking improvements separately.
Show more
Completed 4 steps

This is a targeted second-pass review. Here is the verdict and findings.

Timed Revised Plan — Round 2 Implementation Risk Review
Verdict: SAFE TO IMPLEMENT with two material fixes and one sequencing note

The revised plan is substantially correct. It has absorbed all the structural issues from Round 1. The subtask planning model is internally consistent, the gate ordering is sound, and the schema additions are well-specified. Only two items remain that could cause real-world failure, plus one sequencing note that is not strictly a blocker but will cause pain if ignored.

Material Blockers (Must Fix Before Implementation)
Blocker 1 — Parent-Deletion Trigger Conflicts with FK ON DELETE SET NULL (DATA INTEGRITY RISK)

The plan says: "Before deleting a parent task, promote children by setting parent_task_id = null and preserving or copying the parent's section_id." This is the right user-facing behaviour, but the implementation has a collision trap.

The FK is defined as parent_task_id … ON DELETE SET NULL. Postgres's built-in FK cascade action (SET NULL) fires after constraint enforcement but the plan also calls for a BEFORE DELETE trigger to copy the parent's section_id onto orphaned children. The problem: BEFORE DELETE on the parent fires before the FK cascade sets children's parent_task_id to null — so at the point the trigger runs, the children still reference the parent row that hasn't been deleted yet, which is fine for reading. However, if you also intend to update section_id on children inside that trigger, the section_id copy will race with the FK SET NULL — Postgres will run your trigger's UPDATE children SET section_id = OLD.section_id, then the FK cascade will run and set parent_task_id = NULL on the same rows in the same transaction. This is safe in Postgres (both happen in the same transaction, FK cascade fires after the BEFORE trigger), but the order means your trigger correctly reads OLD.section_id before it is gone.
postgresql
+1

The actual risk is simpler: the FK ON DELETE SET NULL on parent_task_id already handles nullification automatically. If you additionally write a BEFORE DELETE trigger to do the same thing (or to copy section_id), and the trigger also does an UPDATE tasks SET parent_task_id = NULL ..., you create a double-write. Worse, if an Edge Function or Orb tool issues a hard delete on a parent task directly (bypassing Swift), only the FK fires, not the Swift-side promotion logic — and if section_id was supposed to be copied, it will not be.

Fix: Do not rely on the FK ON DELETE SET NULL for parent-task deletion. Remove the cascade FK action. Instead, write a single BEFORE DELETE trigger on tasks that: (a) copies section_id from the parent onto children, (b) sets parent_task_id = NULL on children, and (c) sets is_planning_unit = TRUE on children, all within the trigger body before the parent row is actually deleted. Set the FK to ON DELETE RESTRICT so that the trigger runs first and Postgres never actually uses the cascade. This gives you guaranteed promotion logic that works regardless of whether the delete comes from Swift, Orb, or a raw SQL admin operation:
postgresql

sql
-- FK definition
parent_task_id uuid references public.tasks(id) on delete restrict,

-- Promotion trigger
create or replace function promote_orphaned_subtasks()
returns trigger language plpgsql as $$
begin
  update public.tasks
  set parent_task_id    = null,
      section_id        = coalesce(section_id, OLD.section_id),
      is_planning_unit  = true
  where parent_task_id = OLD.id;
  return OLD;
end;
$$;

create trigger trg_promote_orphans
before delete on public.tasks
for each row execute function promote_orphaned_subtasks();

This pattern is well-supported in Postgres BEFORE DELETE triggers on self-referential tables.
neon
+1

Blocker 2 — RLS on task_sections Uses a Join-Based Subquery That Will Be Slow at Scale (SECURITY + PERFORMANCE RISK)

The plan's RLS approach (implied from Round 1 output) queries workspaces or workspace_members inline inside each policy. For task_sections this means every SELECT on the sidebar runs a join subquery per row evaluation. Supabase's own documentation and production patterns explicitly warn that inline join subqueries in RLS policies cause significant performance degradation when the child table has more than a few hundred rows, and that the correct pattern is a SECURITY DEFINER helper function that is evaluated once per query rather than per row.
supabase
+3

More critically: if workspace_members itself has RLS enabled (as it should for isolation), the inline subquery in task_sections RLS will also invoke workspace_members RLS, creating a policy-within-policy evaluation cycle that Supabase warns can cause silent permission failures or extremely slow queries.
reddit
+1

Fix: Define a SECURITY DEFINER function in a private schema before writing any task_sections or tasks RLS policies:

sql
create schema if not exists private;

create or replace function private.user_workspace_ids()
returns uuid[]
language sql
security definer
stable
as $$
  select array_agg(id)
  from public.workspaces
  where profile_id = (select auth.uid())
  union
  select array_agg(workspace_id)
  from public.workspace_members
  where profile_id = (select auth.uid());
$$;

-- Then all policies use:
create policy "task_sections_select" on public.task_sections
  for select to authenticated
  using (workspace_id = any(private.user_workspace_ids()));

This evaluates the membership check once per query, not once per row, and avoids RLS-on-RLS cycles.
supabase
+2

Sequencing Note (Not a Hard Blocker, But Will Cause Pain)
canonical_bucket_type on task_sections Has No FK Enforcement

The plan requires canonical_bucket_type on task_sections to use the same values as tasks.bucket_type. The current schema enforces tasks.bucket_type with a check constraint. task_sections.canonical_bucket_type has no check constraint and no FK in the plan as written. This means it is possible to seed a section with canonical_bucket_type = 'reply' (old human value) while tasks correctly use reply_email. The system will silently tolerate the mismatch and any join or filter on the two columns will produce empty results.

Fix (not hard but do it in the schema PR): Either reuse the same check constraint values, or create a Postgres DOMAIN for the canonical bucket type and apply it to both columns. A domain is the cleanest option:
reddit

sql
create domain public.canonical_bucket as text
  check (value in ('action','reply_email','reply_wa','reply_other',
                   'read_today','read_this_week','calls','transit',
                   'waiting','cc_fyi','other'));

-- Then both columns use the domain:
bucket_type          public.canonical_bucket not null,  -- on tasks
canonical_bucket_type public.canonical_bucket not null, -- on task_sections

This eliminates the class of "bucket value drifts between sections and tasks" silently.
reddit

Non-Blocking Improvements

These will not cause failures if omitted in v1 but should be tracked:

estimate_priors table is referenced but not defined. The plan mentions a server-side learning job that writes to estimate_priors(workspace_id, bucket_type, section_id, prior_minutes, confidence, updated_at). This table does not appear in the schema additions. It needs to be created and indexed before the learning job runs; otherwise the job will fail silently if it tries to upsert to a non-existent table. Add it to the schema PR alongside task_sections.

is_planning_unit transition trigger fires on every subtask add, but does not fire when the last subtask is deleted. If all subtasks of a parent are deleted, is_planning_unit on the parent remains false permanently unless a trigger also fires on subtask deletion to recheck whether any children remain and restore is_planning_unit = true. Add a companion trigger:

sql
create or replace function restore_planning_unit_on_last_child_delete()
returns trigger language plpgsql as $$
begin
  if OLD.parent_task_id is not null then
    if not exists (select 1 from public.tasks where parent_task_id = OLD.parent_task_id) then
      update public.tasks set is_planning_unit = true where id = OLD.parent_task_id;
    end if;
  end if;
  return OLD;
end;
$$;
create trigger trg_restore_planning_unit
after delete on public.tasks
for each row execute function restore_planning_unit_on_last_child_delete();

behaviour_events partition constraint migration should include a lock_timeout. Dropping and recreating a check constraint on a partitioned parent table requires an ACCESS EXCLUSIVE lock. In production, add SET lock_timeout = '5s' before the migration to avoid hanging behind long-running queries.
supabase

voice-llm-proxy RLS bypass. The existing query uses or(workspace_id.eq.${userId},profile_id.eq.${userId}) which conflates the workspace UUID with the user profile UUID. This is a latent bug independent of the hierarchy work. It will not cause data leakage (a user cannot guess another user's UUID), but it means voice queries may return zero results for any workspace where workspace_id ≠ profile_id. Worth fixing in the AI/backend PR.

Shared schema source for tool parity. The plan correctly requires an automated parity test (Gate 6). The simplest concrete implementation: a supabase/shared/tool-schemas.json file, imported by orb-conversation/index.ts and by a code-generation script that produces the Swift ConversationTools.schemas() output at build time. A Deno test that JSON.stringify-diffs both sides will catch any drift. This is implementable as a single file in the schema PR.

Acceptance Tests: Additions Only

The existing 14-test matrix is complete. Add:

#	Test	Criterion
T16	Parent deletion promotes children	After DELETE FROM tasks WHERE id = parent_id, former children have parent_task_id IS NULL, is_planning_unit = TRUE, and section_id matches former parent's section_id
T17	Deleting last subtask restores parent planning unit	After deleting the final child, parent row has is_planning_unit = TRUE
T18	task_sections RLS does not evaluate per-row join	EXPLAIN ANALYZE on SELECT * FROM task_sections shows private.user_workspace_ids() called once, not once per row
T19	canonical_bucket_type domain rejects invalid value	INSERT INTO task_sections (canonical_bucket_type, …) VALUES ('Reply', …) raises constraint violation

The two fixes above (parent deletion trigger and RLS security definer) are the only items standing between this plan and a green light. Both are small, localised changes to the schema PR. Once they are in, the implementation sequence and gate structure as written is safe to execute.

Prepared by Deep Research
30 sources
Ask a follow-up
Deep research
