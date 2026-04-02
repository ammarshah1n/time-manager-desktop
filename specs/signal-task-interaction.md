# Signal Spec: Task Interaction Signals

> Layer: Signal Ingestion
> Status: Implementation-ready
> Dependencies: DataStore, PlanningEngine, SupabaseClient, Memory (episodic tier)
> Swift target: 5.9+ / macOS 14+

---

## 1. Purpose

Task interaction signals are the primary behavioural exhaust from the user's daily work in Timed. Every task lifecycle event — creation, deferral, completion, deletion, priority change — reveals how the executive actually operates versus how they think they operate. This spec defines what gets captured, how it is structured, how it feeds downstream ML, and how it flows into episodic memory.

---

## 2. Signal Catalogue

### 2.1 Task Opened / Viewed

**Trigger:** User opens `TaskDetailSheet` or selects a task in `TasksPane`/`TodayPane`.

| Field | Type | Description |
|-------|------|-------------|
| `taskId` | `UUID` | Target task |
| `viewDurationMs` | `Int?` | Time spent in detail view (recorded on dismiss). Nil if < 500ms (noise). |
| `viewContext` | `String` | Where opened from: `today_pane`, `tasks_pane`, `triage_pane`, `command_palette`, `menu_bar` |

**ML signal:** Repeated views without action → hesitation signal. Views from `command_palette` → task was actively sought (high salience).

### 2.2 Task Created

**Trigger:** New `TimedTask` persisted via DataStore or SupabaseClient.

| Field | Type | Description |
|-------|------|-------------|
| `taskId` | `UUID` | New task ID |
| `sourceType` | `TaskSource` | `email_triage`, `voice_capture`, `manual`, `calendar_extraction`, `morning_interview` |
| `bucket` | `TaskBucket` | Assigned bucket |
| `estimatedMinutes` | `Int` | Initial estimate |
| `estimateSource` | `EstimateSource` | `ai`, `manual`, `ema_prior` |
| `priority` | `Int` | Initial priority (1-5) |
| `dueAt` | `Date?` | Initial due date if set |
| `isDoFirst` | `Bool` | Flagged as do-first |

**ML signal:** Creation source distribution → how the executive prefers to generate work. Manual creation rate declining over time → trust signal (user trusting AI triage more).

### 2.3 Task Deferred

**Trigger:** User moves a task's `dueAt` to a later date, or moves a task from Today to a future date.

| Field | Type | Description |
|-------|------|-------------|
| `taskId` | `UUID` | Deferred task |
| `previousDueAt` | `Date?` | Old due date (nil if none set) |
| `newDueAt` | `Date` | New due date |
| `deferCount` | `Int` | Cumulative deferrals for this task (post-increment) |
| `deferReason` | `DeferReason?` | Optional: `too_busy`, `not_ready`, `waiting_on_input`, `low_priority`, `no_reason` |
| `deferContext` | `String` | UI context: `today_pane_swipe`, `task_detail`, `morning_interview`, `batch_reschedule` |

**ML signal:** This is the highest-value behavioural signal in the system.
- `deferCount >= 3` → chronic avoidance. Feed to reflection engine for avoidance pattern detection.
- Defer from `morning_interview` → user consciously deprioritised during planning (intentional).
- Defer from `today_pane_swipe` → user saw the task and reflexively pushed it (avoidance).
- `previousDueAt` to `newDueAt` delta → how far the user pushes things (1 day = mild, 7+ days = strong avoidance).
- Defer reason `waiting_on_input` → not avoidance, external blocker. Different category entirely.

### 2.4 Task Rescheduled

**Trigger:** User changes the scheduled time slot for a task (via drag in CalendarPane or manual edit) without changing the due date.

| Field | Type | Description |
|-------|------|-------------|
| `taskId` | `UUID` | Rescheduled task |
| `previousSlotStart` | `Date?` | Old slot (nil if unscheduled) |
| `newSlotStart` | `Date` | New slot |
| `rescheduledBy` | `RescheduleSource` | `user_drag`, `user_edit`, `ai_replan`, `conflict_resolution` |

**ML signal:** User overriding AI-placed slots → Thompson sampling correction input. Track which time-of-day the user moves tasks TO — reveals actual energy preferences vs stated preferences.

### 2.5 Task Completed

**Trigger:** `isDone` set to `true`. Timer stopped or manual completion.

| Field | Type | Description |
|-------|------|-------------|
| `taskId` | `UUID` | Completed task |
| `actualMinutes` | `Int?` | From focus timer if used. Nil if completed without timer. |
| `estimatedMinutes` | `Int` | What was estimated at completion time |
| `completionMethod` | `CompletionMethod` | `focus_timer`, `manual_check`, `batch_complete`, `morning_review_done` |
| `completedAt` | `Date` | Timestamp |
| `deferCount` | `Int` | Total deferrals before completion |
| `wasOverdue` | `Bool` | Was the task past its due date at completion |
| `dayOfWeek` | `Int` | 1-7, for weekly pattern extraction |
| `hourOfDay` | `Int` | 0-23, for circadian pattern extraction |

**ML signal:**
- `actualMinutes` vs `estimatedMinutes` → EMA update for `BucketEstimate`. The core learning loop for time estimation accuracy.
- `completionMethod == .focus_timer` → high-confidence actual duration.
- `completionMethod == .manual_check` → actual duration unknown; do not update EMA.
- `deferCount > 0` on completion → the task was hard to start but got done. Correlate with task properties to learn avoidance-then-completion patterns.
- `hourOfDay` clustered → reveals when the user actually does work (vs when they plan to).

### 2.6 Task Deleted

**Trigger:** Task permanently removed (not archived, not completed).

| Field | Type | Description |
|-------|------|-------------|
| `taskId` | `UUID` | Deleted task |
| `taskAge` | `TimeInterval` | Seconds since creation |
| `deferCount` | `Int` | Deferrals at deletion time |
| `bucket` | `TaskBucket` | Bucket at deletion |
| `deletionContext` | `String` | `user_explicit`, `stale_sweep`, `duplicate_merge` |

**ML signal:** High defer count + deletion → confirmed avoidance that resolved by abandonment. `taskAge < 300` (deleted within 5 min of creation) → regret/noise, not avoidance. Track bucket-level deletion rates → some task types consistently abandoned.

### 2.7 Priority Changed

**Trigger:** User manually changes `priority` field on an existing task.

| Field | Type | Description |
|-------|------|-------------|
| `taskId` | `UUID` | Changed task |
| `previousPriority` | `Int` | Old value (1-5) |
| `newPriority` | `Int` | New value (1-5) |
| `changeContext` | `String` | `task_detail`, `today_pane`, `morning_interview`, `batch_edit` |

**ML signal:** Priority overrides → Thompson sampling correction. When the user consistently promotes a bucket/category, the scoring model should learn to score that category higher. Direction matters: promotion (3→5) signals urgency perception; demotion (5→2) signals the AI overestimated importance.

### 2.8 Task Edited

**Trigger:** User modifies any field other than priority, due date, or completion status (those have their own signals).

| Field | Type | Description |
|-------|------|-------------|
| `taskId` | `UUID` | Edited task |
| `fieldsChanged` | `[String]` | Array of field names: `title`, `estimatedMinutes`, `bucket`, `replyMedium`, `isDoFirst`, `isTransitSafe`, `waitingOn` |
| `editContext` | `String` | `task_detail`, `batch_edit`, `morning_interview` |

**ML signal:** `estimatedMinutes` changed manually → user disagrees with AI estimate. Track direction (up/down) per bucket. `bucket` changed → AI triage miscategorisation. Feed to classifier correction loop. `isDoFirst` toggled → explicit priority signal stronger than numeric priority.

---

## 3. Signal Envelope Format

Every signal is wrapped in a standard envelope before persistence and routing.

```swift
struct TaskSignal: Codable, Sendable, Identifiable {
    let id: UUID                    // unique signal ID
    let workspaceId: UUID           // multi-tenant key
    let profileId: UUID             // user key
    let signalType: TaskSignalType  // enum matching section 2 categories
    let taskId: UUID                // target task
    let timestamp: Date             // ISO8601, UTC
    let payload: Data               // JSON-encoded type-specific struct from section 2
    let sessionId: UUID?            // morning interview session, if applicable
    let clientVersion: String       // app version for schema migration tracking
}

enum TaskSignalType: String, Codable, Sendable {
    case taskViewed
    case taskCreated
    case taskDeferred
    case taskRescheduled
    case taskCompleted
    case taskDeleted
    case priorityChanged
    case taskEdited
}
```

### Payload decoding

Each `signalType` maps to exactly one payload struct. The consumer decodes `payload` based on `signalType`:

| `signalType` | Payload struct |
|--------------|---------------|
| `taskViewed` | `TaskViewedPayload` |
| `taskCreated` | `TaskCreatedPayload` |
| `taskDeferred` | `TaskDeferredPayload` |
| `taskRescheduled` | `TaskRescheduledPayload` |
| `taskCompleted` | `TaskCompletedPayload` |
| `taskDeleted` | `TaskDeletedPayload` |
| `priorityChanged` | `PriorityChangedPayload` |
| `taskEdited` | `TaskEditedPayload` |

---

## 4. Deduplication

### 4.1 Client-side deduplication

- `taskViewed`: Debounce 2-second window per `taskId`. If the same task is selected, deselected, and reselected within 2s, emit one signal with combined `viewDurationMs`.
- `taskEdited`: Coalesce rapid edits to the same task within a 5-second window. Merge `fieldsChanged` arrays.
- All other signals: No coalescing. Each is a discrete lifecycle event.

### 4.2 Server-side deduplication

- Supabase table uses `UNIQUE(id)` — the `TaskSignal.id` is generated client-side (UUID v4).
- Idempotent writes: if a signal with the same `id` already exists, the insert is silently dropped (`ON CONFLICT DO NOTHING`).
- Replay safety: the client may re-send signals after a network failure. The unique ID ensures no duplicates.

### 4.3 Ordering

- Signals are ordered by `timestamp` (client clock, UTC).
- Client clock skew: the server records `server_received_at` alongside the client `timestamp`. If `abs(server_received_at - timestamp) > 60s`, flag the signal for clock-skew correction.
- Within a single session (same `sessionId`), signals are processed in `timestamp` order. Cross-session ordering uses server receive time as tiebreaker.

---

## 5. ML Feed Specifications

### 5.1 Avoidance Detection (Deferral Signals)

**Input:** All `taskDeferred` signals for a given `profileId`, joined with task metadata (bucket, title keywords, sender).

**Algorithm:**
1. Group deferrals by `taskId`. Tasks with `deferCount >= 3` are avoidance candidates.
2. Extract features from avoidance candidates: bucket, sender domain, title keyword clusters, time-of-day when deferred, day-of-week.
3. Build per-user avoidance profile: which categories of work does this executive chronically avoid?
4. Feed avoidance profile into semantic memory as a `work_style.avoidance` fact.

**Update cadence:** Nightly reflection engine. Not real-time.

**Output:** Avoidance facts for semantic memory, e.g.:
```json
{
  "factType": "work_style",
  "category": "avoidance",
  "content": "Chronically defers HR-related action items (avg 4.2 deferrals before completion). Defers most often on Monday mornings.",
  "confidence": 0.82,
  "evidenceCount": 17,
  "sourceSignalIds": ["uuid1", "uuid2", "..."]
}
```

### 5.2 Time Estimation EMA Update (Completion Signals)

**Input:** `taskCompleted` signals where `completionMethod == .focus_timer` (high-confidence actuals only).

**Algorithm (existing in InsightsEngine, extended here):**
1. On each qualifying completion, update `BucketEstimate` for the task's bucket:
   ```
   newEMA = alpha * actualMinutes + (1 - alpha) * previousEMA
   ```
   where `alpha = 0.3` (responsive to recent data, smoothed over ~7 completions).
2. Update `estimateUncertainty` using running standard deviation of `(actual - estimated)` residuals.
3. If `abs(actual - estimated) / estimated > 0.5` for 3+ consecutive completions in a bucket, emit an `estimate_drift` alert to the morning briefing queue.

**Update cadence:** Immediate on completion. EMA is a streaming update.

**Output:** Updated `BucketEstimate` persisted to DataStore and synced to Supabase `bucket_estimates` table.

### 5.3 Thompson Sampling Correction (Priority + Reschedule Signals)

**Input:** `priorityChanged` and `taskRescheduled` signals where `rescheduledBy == .user_drag` or `rescheduledBy == .user_edit`.

**Algorithm:**
1. Each user override is a reward/penalty signal for the PlanningEngine's scoring model.
2. Priority promotion (user increases priority) → increase the Thompson sampling beta distribution's alpha for that task's feature cluster.
3. Priority demotion → increase beta.
4. Time slot override → the user disagrees with the AI's time placement. Record the user's preferred slot and update the per-bucket time-of-day preference distribution.
5. After `N >= 10` overrides in a feature cluster, the PlanningEngine should converge toward the user's revealed preferences.

**Update cadence:** Batch at end of day. Thompson parameters are updated in the nightly cycle, not per-event, to avoid overfitting to single interactions.

**Output:** Updated `BehaviourRule` entries with `ruleType = "category_pref"` or `ruleType = "timing"`, fed back into `PlanRequest.behaviouralRules`.

---

## 6. Persistence

### 6.1 Local (DataStore)

Signals are buffered in a local JSON file (`task_signals.json`) via the DataStore actor. Buffer is flushed to Supabase on a 30-second interval or when buffer exceeds 50 signals.

```swift
// DataStore additions
func appendSignal(_ signal: TaskSignal) throws
func loadPendingSignals() throws -> [TaskSignal]
func clearFlushedSignals(ids: Set<UUID>) throws
```

### 6.2 Remote (Supabase)

**Table:** `task_signals`

```sql
CREATE TABLE task_signals (
    id              UUID PRIMARY KEY,
    workspace_id    UUID NOT NULL REFERENCES workspaces(id),
    profile_id      UUID NOT NULL REFERENCES profiles(id),
    signal_type     TEXT NOT NULL,
    task_id         UUID NOT NULL,
    timestamp       TIMESTAMPTZ NOT NULL,
    payload         JSONB NOT NULL,
    session_id      UUID,
    client_version  TEXT NOT NULL,
    server_received_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(id)
);

CREATE INDEX idx_task_signals_profile_type ON task_signals(profile_id, signal_type);
CREATE INDEX idx_task_signals_task ON task_signals(task_id);
CREATE INDEX idx_task_signals_timestamp ON task_signals(timestamp);
```

**RLS:** `profile_id = auth.uid()` for all operations. Insert only from authenticated client. Select for the reflection engine service role.

### 6.3 Episodic Memory Bridge

Every `TaskSignal` is also written to the episodic memory store (see `episodic-memory.md`) as a raw event. The signal envelope maps to episodic memory fields:

| TaskSignal field | Episodic field |
|------------------|---------------|
| `id` | `event_id` |
| `timestamp` | `occurred_at` |
| `signalType` | `event_type` (prefixed: `task.`) |
| `payload` | `raw_data` |
| `taskId` | `entity_id` |

The episodic store handles importance scoring at write time. Task signals receive base importance scores:

| Signal type | Base importance |
|-------------|----------------|
| `taskCreated` | 0.3 |
| `taskViewed` | 0.1 |
| `taskDeferred` | 0.5 + (0.1 * min(deferCount, 5)) |
| `taskRescheduled` | 0.3 |
| `taskCompleted` | 0.4 |
| `taskDeleted` | 0.3 |
| `priorityChanged` | 0.4 |
| `taskEdited` | 0.2 |

---

## 7. Supporting Types

```swift
enum TaskSource: String, Codable, Sendable {
    case emailTriage = "email_triage"
    case voiceCapture = "voice_capture"
    case manual
    case calendarExtraction = "calendar_extraction"
    case morningInterview = "morning_interview"
}

enum EstimateSource: String, Codable, Sendable {
    case ai
    case manual
    case emaPrior = "ema_prior"
}

enum DeferReason: String, Codable, Sendable {
    case tooBusy = "too_busy"
    case notReady = "not_ready"
    case waitingOnInput = "waiting_on_input"
    case lowPriority = "low_priority"
    case noReason = "no_reason"
}

enum RescheduleSource: String, Codable, Sendable {
    case userDrag = "user_drag"
    case userEdit = "user_edit"
    case aiReplan = "ai_replan"
    case conflictResolution = "conflict_resolution"
}

enum CompletionMethod: String, Codable, Sendable {
    case focusTimer = "focus_timer"
    case manualCheck = "manual_check"
    case batchComplete = "batch_complete"
    case morningReviewDone = "morning_review_done"
}
```

---

## 8. Implementation Notes

### 8.1 Signal Emission Points

Signals are emitted from the DataStore layer, not from views. Every mutation method on DataStore that modifies a task emits the corresponding signal as a side effect. Views do not construct signals directly.

Exception: `taskViewed` is emitted from the view layer (onAppear/onDisappear of `TaskDetailSheet`) because DataStore has no concept of "viewing."

### 8.2 Offline Resilience

All signals are persisted locally before any network call. If Supabase is unreachable, the local buffer grows. On reconnection (detected via `NetworkMonitor`), the buffer flushes in chronological order. No signals are lost.

### 8.3 Signal Volume Estimate

For a typical executive day:
- ~50-80 task views
- ~5-15 task creations
- ~5-10 deferrals
- ~10-20 completions
- ~2-5 deletions
- ~5-10 priority changes
- ~10-15 edits

**Total: ~90-155 signals/day.** Well within Supabase free-tier write limits. Local buffer of 50 signals before flush is sufficient.

---

## 9. Acceptance Criteria

1. **Every task lifecycle event defined in Section 2 produces exactly one signal** (after deduplication) with all specified fields populated.
2. **Signal envelope validates** — `signalType` matches payload struct. Invalid payloads are logged via `TimedLogger.signal` and dropped, never persisted.
3. **Offline buffering works** — Disconnect network, perform 20 task operations, reconnect. All 20 signals appear in Supabase within 60 seconds of reconnection, in correct chronological order.
4. **Deduplication holds** — Rapid-fire the same task view 10 times in 2 seconds. Exactly 1 `taskViewed` signal is emitted.
5. **EMA updates on completion** — Complete a task with focus timer. `BucketEstimate` for that bucket updates within 1 second. New estimate reflects the actual duration.
6. **Avoidance detection fires** — Defer a task 3 times. The nightly reflection engine identifies it as an avoidance candidate. Semantic memory receives an avoidance fact.
7. **Thompson correction converges** — Override priority for the same bucket type 10 times (consistently promoting). PlanningEngine's next plan scores that bucket type higher.
8. **Episodic bridge writes** — Every signal in `task_signals` has a corresponding entry in the episodic memory store with correct field mapping and importance score.
9. **No write scopes used** — Signal emission never triggers any Microsoft Graph write operation. All Graph interaction remains read-only.
10. **Performance** — Signal emission adds < 5ms to any user interaction. Local persistence is async and non-blocking to the UI thread.
