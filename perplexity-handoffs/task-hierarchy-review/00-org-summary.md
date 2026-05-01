# Timed Task Hierarchy Review - Repo Context

Generated for Perplexity Deep Research adversarial review.

## Current Repo State

- Repo: `/Users/integrale/time-manager-desktop`
- Branch: `unified`
- `git checkout unified && git pull`: already on `unified`, already up to date.
- Current observed dirty state at handoff creation:
  - `SESSION_LOG.md`
  - untracked `.agents/skills/...` skill files
- Collision-prone files from the task/persistence inspection:
  - `Sources/TimedKit/Core/Services/DataBridge.swift`
  - `Sources/TimedKit/Core/Services/OfflineSyncQueue.swift`
  - `Sources/TimedKit/AppEntry/TimedAppShell.swift`
  - `Tests/DataBridgeTests.swift`

These collision notes matter because the proposed task hierarchy touches task persistence, offline replay, Supabase row mapping, local JSON fallback, and the tests around that layer.

## Key Product Intent

The requested feature is a TickTick-like task hierarchy inside Timed:

- Users can add sidebar sections and subsections.
- Sections map to canonical planning buckets so AI/backend planning remains stable.
- Users can add tasks within every section.
- Users can add one-level subtasks under tasks.
- Users can rank task/subtask importance manually with blue, orange, and red markers.
- Done tasks should remain visible greyed out at the bottom in a collapsible section.
- AI-recommended time estimates must be visible in the task list.
- User edits to AI estimates or priority should be learned from silently.
- The next review should ask follow-up questions only for meaningful or repeated corrections.

## Subagent Findings

### Current task model is flat

- `TaskBucket` is a fixed enum in `Sources/TimedKit/Features/PreviewData.swift`.
- `TimedTask` has no `sectionId`, `parentTaskId`, row ordering, completed timestamp, persisted notes, or manual importance color.
- `TimedTask.bucket` is immutable, so changing buckets currently rebuilds a task.

### Current task UI is bucket-filtered

- `TasksPane` accepts one `TaskBucket`.
- It computes `bucketTasks` with `tasks.filter { $0.bucket == bucket }`.
- It has no section tree, subsection tree, inline add task per section, or subtask rendering.

### Swift/DB bucket IDs are mismatched

- Swift `TaskBucket.rawValue` uses human labels like `Action`, `Reply`, `Read Today`.
- Supabase `tasks.bucket_type` expects snake_case values such as `action`, `reply_email`, `read_today`.
- `DataBridge.makeTaskRow` currently writes `bucketType: task.bucket.rawValue`.
- `TimedTask.init(from:)` tries to decode `TaskBucket(rawValue: row.bucketType)`.

This is a blocker for reliable hierarchy migration. Bucket serialization should be normalized before hierarchy fields are added.

### Behaviour events exist but estimate feedback is incomplete

- `behaviour_events` supports `estimate_override`.
- `TodayPane` logs `estimate_override` when its time picker changes an estimate.
- `TasksPane`, `TaskDetailSheet`, and Orb `update_task` can change estimates without consistently logging an event.

### Orb and backend paths are flat today

- Orb tool schemas support `add_task`, `update_task`, `move_to_bucket`, `mark_done`, `snooze_task`, `request_dish_me_up_replan`, and `end_conversation`.
- Tool schemas use fixed buckets and have no `sectionId`, `parentTaskId`, or manual importance color.
- `voice-llm-proxy` reads flat tasks and does not mutate tasks in the morning check-in path.
- `generate-dish-me-up` reads flat pending tasks and normalizes one estimate per task.

## Quoted Repo Evidence

### `Sources/TimedKit/Features/PreviewData.swift`

```swift
enum TaskBucket: String, CaseIterable, Hashable, Codable {
    case reply        = "Reply"
    case action       = "Action"
    case calls        = "Calls"
    case readToday    = "Read Today"
    case readThisWeek = "Read This Week"
    case transit      = "Transit"
    case waiting      = "Waiting"
    case ccFyi        = "CC / FYI"
}
```

```swift
struct TimedTask: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let title: String
    let sender: String
    var estimatedMinutes: Int
    let bucket: TaskBucket
    let emailCount: Int
    let receivedAt: Date
    var priority: Int? = nil
    var replyMedium: ReplyMedium? = nil
    var dueToday: Bool      = false
    var isDoFirst: Bool     = false
    var isTransitSafe: Bool = false
    var waitingOn: String?  = nil
    var askedDate: Date?    = nil
    var expectedByDate: Date? = nil
    var isDone: Bool = false
    var estimateUncertainty: Int? = nil
    var planScore: Int? = nil
    var scheduledStartTime: Date? = nil
    var urgency: Int = 3
    var importance: Int = 3
    var energyRequired: String = "medium"
    var context: String = "anywhere"
    var skipCount: Int = 0
    var snoozedUntil: Date? = nil
}
```

Risk: no user-facing section hierarchy, no parent/subtask relation, no stable row order, no explicit manual importance color, and no persisted completed timestamp in the Swift task model.

### `Sources/TimedKit/Features/Tasks/TasksPane.swift`

```swift
struct TasksPane: View {
    let bucket: TaskBucket
    @Binding var tasks: [TimedTask]
    @Binding var blocks: [CalendarBlock]

    var bucketTasks: [TimedTask] {
        tasks.filter { $0.bucket == bucket }
    }
}
```

```swift
TaskRow(
    task: task,
    onUpdateTime: { newMins in
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].estimatedMinutes = newMins
        }
    }
)
```

Risk: per-bucket filtering is hard-coded, and time updates here do not log `estimate_override`.

### `Sources/TimedKit/Core/Clients/SupabaseClient.swift`

```swift
struct TaskDBRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let sourceType: String
    let bucketType: String
    let title: String
    let description: String?
    let status: String
    let priority: Int
    let dueAt: Date?
    let estimatedMinutesAi: Int?
    let estimatedMinutesManual: Int?
    let actualMinutes: Int?
    let estimateSource: String?
    let isDoFirst: Bool
    let isTransitSafe: Bool
    let isOverdue: Bool
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let urgency: Int
    let importance: Int
    let energyRequired: String
    let context: String
    let skipCount: Int
}
```

Risk: DB row type has no `section_id`, `parent_task_id`, `sort_order`, or `manual_importance`.

```swift
struct BehaviourEventInsert: Codable, Sendable {
    let workspaceId: UUID
    let profileId: UUID
    let eventType: String
    let taskId: UUID?
    let bucketType: String
    let hourOfDay: Int
    let dayOfWeek: Int
    let oldValue: String?
    let newValue: String?
}
```

Risk: behaviour events have no section/subtask identity and old/new values are strings in Swift even though Postgres stores JSONB.

### `Sources/TimedKit/Core/Services/DataBridge.swift`

```swift
private func makeTaskRow(_ task: TimedTask, workspaceId: UUID, profileId: UUID) -> TaskDBRow {
    TaskDBRow(
        id: task.id,
        workspaceId: workspaceId,
        profileId: profileId,
        sourceType: "manual",
        bucketType: task.bucket.rawValue,
        title: task.title,
        description: nil,
        status: task.isDone ? "done" : "pending",
        priority: task.isDoFirst ? 10 : 5,
        dueAt: task.dueToday ? Calendar.current.startOfDay(for: Date()) : nil,
        estimatedMinutesAi: nil,
        estimatedMinutesManual: task.estimatedMinutes,
        actualMinutes: nil,
        estimateSource: "manual",
        isDoFirst: task.isDoFirst,
        isTransitSafe: task.isTransitSafe,
        isOverdue: false,
        completedAt: task.isDone ? Date() : nil,
        createdAt: task.receivedAt,
        updatedAt: Date(),
        urgency: task.urgency,
        importance: task.importance,
        energyRequired: task.energyRequired,
        context: task.context,
```

Risk: writes human bucket labels into DB `bucket_type`, maps all saved tasks to `sourceType: "manual"`, drops description/notes, and sets completed timestamp at save-time rather than preserving an actual completion time.

### `Sources/TimedKit/Core/Tools/ConversationTools.swift`

```swift
[
    "name": "add_task",
    "description": "Add one task to Timed's in-app task list. This does not contact anyone or perform the work.",
    "input_schema": [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "bucket": ["type": "string", "enum": ["action", "reply", "calls", "readToday", "readThisWeek", "transit", "waiting", "ccFyi"]],
            "isDoFirst": ["type": "boolean"],
            "estimatedMinutes": ["type": "integer"],
            "urgency": ["type": "integer"],
            "importance": ["type": "integer"],
            "notes": ["type": "string"],
        ],
        "required": ["title", "bucket"],
    ],
]
```

Risk: Orb can mutate in-app tasks but has no section/subtask schema fields and still relies on the legacy bucket enum strings.

### `supabase/migrations/20260331000001_initial_schema.sql`

```sql
create table public.tasks (
  id                       uuid primary key default gen_random_uuid(),
  workspace_id             uuid not null references public.workspaces(id) on delete cascade,
  profile_id               uuid references public.profiles(id) on delete set null,
  source_type              text not null check (source_type in ('email','whatsapp','voice','manual')),
  source_email_id          uuid references public.email_messages(id) on delete set null,
  source_voice_capture_id  uuid,
  bucket_type              text not null check (bucket_type in (
    'action','reply_email','reply_wa','reply_other',
    'read_today','read_this_week','calls','transit','waiting','other'
  )),
  title                    text not null,
  description              text,
  status                   text not null default 'pending' check (status in (
    'pending','in_progress','done','cancelled','deferred'
  )),
  estimated_minutes_ai     integer,
  estimated_minutes_manual integer,
  actual_minutes           integer,
  estimate_source          text not null default 'ai' check (estimate_source in ('ai','manual','default')),
  completed_at             timestamptz,
  embedding                vector(1536),
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
```

Risk: flat task table. No section table, no parent task relation, no sort order, and no manual importance field.

```sql
create table public.behaviour_events (
  id             uuid not null default gen_random_uuid(),
  workspace_id   uuid not null references public.workspaces(id) on delete cascade,
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  event_type     text not null check (event_type in (
    'task_completed',
    'task_deferred',
    'task_deleted',
    'plan_order_override',
    'estimate_override',
    'session_started',
    'triage_correction'
  )),
  task_id        uuid references public.tasks(id) on delete set null,
  plan_id        uuid references public.daily_plans(id) on delete set null,
  bucket_type    text,
  hour_of_day    integer,
  day_of_week    integer,
  old_value      jsonb,
  new_value      jsonb,
  occurred_at    timestamptz not null default now(),
  primary key (id, occurred_at)
) partition by range (occurred_at);
```

Risk: event type check must be extended carefully across later migrations/partitions. No section/subtask identity.

### `supabase/functions/orb-conversation/index.ts`

```ts
const TOOL_SCHEMAS: ToolSchema[] = [
  { name: "add_task", description: "Add one task to Timed's in-app task list. This does not contact anyone or perform the work.",
    input_schema: { type: "object", properties: {
      title: { type: "string" },
      bucket: { type: "string", enum: ["action","reply","calls","readToday","readThisWeek","transit","waiting","ccFyi"] },
      isDoFirst: { type: "boolean" },
      estimatedMinutes: { type: "integer" },
      urgency: { type: "integer" },
      importance: { type: "integer" },
      notes: { type: "string" },
    }, required: ["title", "bucket"] } },
  { name: "update_task", description: "Update fields on an existing Timed task.",
    input_schema: { type: "object", properties: {
      taskId: { type: "string" }, title: { type: "string" }, bucket: { type: "string" },
      isDoFirst: { type: "boolean" }, estimatedMinutes: { type: "integer" },
      urgency: { type: "integer" }, importance: { type: "integer" }, notes: { type: "string" },
    }, required: ["taskId"] } },
]
```

Risk: Edge tool schemas must stay exactly aligned with Swift `ConversationTools.schemas()`. Both need hierarchy fields together.

### `supabase/functions/voice-llm-proxy/index.ts`

```ts
const [tasks, calendar, acb, rules, yesterdayCompletions, inbox, synthesis] = await Promise.all([
  supabase.from("tasks")
    .select("id,title,bucket_type,due_at,deferred_count,last_viewed_at,is_overdue")
    .or(`workspace_id.eq.${userId},profile_id.eq.${userId}`)
    .eq("status", "pending")
    .order("due_at", { ascending: true, nullsFirst: false })
    .limit(20),
```

Risk: morning voice has no section tree, parent/subtask context, estimates, manual importance, or correction context.

### `supabase/functions/generate-dish-me-up/index.ts`

```ts
const tasksQ = supabase.from("tasks")
  .select("id,title,bucket_type,source_type,estimated_minutes_ai,estimated_minutes_manual,due_at,deferred_count,last_viewed_at,is_overdue,is_do_first,created_at,workspace_id,profile_id")
  .or(`workspace_id.eq.${userId},profile_id.eq.${userId}`)
  .eq("status", "pending")
  .order("due_at", { ascending: true, nullsFirst: false })
  .order("created_at", { ascending: true })
  .limit(30);
```

```ts
const taskRows = (tasks.data ?? []).map(t => ({
  ...t,
  estimated_minutes: t.estimated_minutes_manual ?? t.estimated_minutes_ai ?? 15,
}));
```

Risk: planner sees flat pending tasks only. It does not know whether a task is a parent container, a subtask, or inside a user-created section.

## Main Review Questions for Perplexity

Please focus on backend correctness and implementation safety:

- How should the schema represent user display sections while preserving canonical planning buckets?
- Should `parent_task_id` live on `tasks`, and what constraint prevents nested subtasks deeper than one level?
- What indexes and RLS rules are required for `task_sections`, `tasks.section_id`, and `tasks.parent_task_id`?
- How should existing flat tasks migrate without data loss?
- How should local JSON decode older tasks safely after model changes?
- How should Swift and Edge tool schemas be kept aligned?
- How should `estimate_override` be made reliable across Today, Tasks, Detail, and Orb?
- Which Trigger/Edge jobs need awareness of sections/subtasks immediately, and which can safely ignore them in v1?
- What must be tested before implementation begins?
