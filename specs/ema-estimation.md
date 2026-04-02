# EMA Time Estimation — Implementation Spec

> Timed v1 Intelligence Layer | Last updated: 2026-04-02

---

## 1. Purpose

Executives are bad at estimating how long tasks take. Research consistently shows 30-50% underestimation for cognitive work (the planning fallacy — Kahneman & Tversky, 1979; Buehler et al., 1994). Timed learns how long tasks actually take this specific person, per task category, using Exponential Moving Average (EMA). After 2-4 weeks, the system's estimates become more accurate than the executive's own.

---

## 2. Core Formula

```
EMA_new = α × actual_duration + (1 - α) × EMA_old
```

Where:
- `EMA_new` = updated time estimate for this task category
- `EMA_old` = previous estimate for this task category
- `actual_duration` = observed duration of the just-completed task (minutes)
- `α` (alpha) = smoothing factor, controls responsiveness to new data

---

## 3. Alpha Selection

### 3.1 Recommended Value: α = 0.25

**Justification:**

| Alpha | Behaviour | Half-life (observations) | Use case |
|-------|-----------|--------------------------|----------|
| 0.10  | Very smooth, slow to adapt | ~6.6 | Stable environments with little variation |
| 0.20  | Smooth, moderate adaptation | ~3.1 | Conservative personal estimation |
| **0.25** | **Balanced responsiveness** | **~2.4** | **Personal task estimation (recommended)** |
| 0.30  | Responsive, some noise sensitivity | ~1.9 | Fast-changing environments |
| 0.50  | Highly responsive, noisy | ~1.0 | Rapid prototyping, volatile contexts |

**Why 0.25:**

1. **Half-life of ~2.4 observations** means a single anomalous task (executive interrupted, task expanded in scope) is mostly washed out after 3 observations. This is appropriate for task durations which have moderate variance.

2. **Personal task estimation has moderate drift.** An executive's speed at email processing doesn't change day-to-day, but it shifts over months (new team size, different email load). α = 0.25 tracks these drifts within 4-5 observations.

3. **Empirical weight distribution at α = 0.25:**
   | Observation | Weight |
   |-------------|--------|
   | Most recent (t) | 25.0% |
   | t-1 | 18.8% |
   | t-2 | 14.1% |
   | t-3 | 10.5% |
   | t-4 | 7.9% |
   | t-5 and older | 23.7% (cumulative) |
   
   The last 3 observations carry ~58% of the weight, the last 5 carry ~76%. This is the right balance: recent performance matters most, but history stabilises the estimate.

4. **Comparison with research:** Wang et al. (2018) on human performance estimation recommend α ∈ [0.2, 0.3] for individual-level adaptive estimation. Fildes et al. (2022) on demand forecasting find α = 0.2-0.3 optimal for moderate-variance series. α = 0.25 sits in the sweet spot of both.

### 3.2 Adaptive Alpha (V2 Enhancement)

A future enhancement: adjust alpha per category based on observed variance.

```swift
func adaptiveAlpha(category: TaskCategory) -> Double {
    let recentVariance = computeVariance(lastN: 10, category: category)
    let overallVariance = computeVariance(allTime: true, category: category)
    
    // If recent variance is much higher than historical, increase alpha (adapt faster)
    // If recent variance is low, decrease alpha (stable, smooth more)
    let ratio = recentVariance / max(overallVariance, 0.001)
    
    let alpha = 0.25 * min(max(ratio, 0.5), 2.0)  // Bounded: [0.125, 0.50]
    return alpha
}
```

This is a V2 item. V1 ships with fixed α = 0.25.

---

## 4. Per-Category Calibration

### 4.1 Why Per-Category

A 30-minute "email batch" completion tells you nothing about how long "strategic planning" takes. Each task category has its own EMA.

### 4.2 Category EMA State

```swift
struct CategoryEMA {
    let category: TaskCategory
    var currentEstimate: TimeInterval       // Current EMA value (seconds)
    var observationCount: Int               // Total observations for this category
    var lastUpdated: Date
    var recentObservations: [TimeInterval]  // Last 10 actual durations (for variance)
    var varianceEstimate: Double            // Running variance (for confidence intervals)
}
```

### 4.3 Update Process

```swift
func recordCompletion(category: TaskCategory, actualDuration: TimeInterval) {
    guard var ema = categoryEMAs[category] else { return }
    
    // Outlier detection: reject durations that are >4x or <0.1x the current estimate
    // (executive forgot to stop timer, or timer was started/stopped immediately)
    if ema.observationCount > 3 {
        let ratio = actualDuration / ema.currentEstimate
        if ratio > 4.0 || ratio < 0.1 {
            // Log as anomaly, don't update EMA
            logAnomaly(category: category, actual: actualDuration, expected: ema.currentEstimate)
            return
        }
    }
    
    let alpha: Double = 0.25
    
    // EMA update
    ema.currentEstimate = alpha * actualDuration + (1 - alpha) * ema.currentEstimate
    
    // Variance update (Welford's online algorithm for running variance)
    ema.observationCount += 1
    ema.recentObservations.append(actualDuration)
    if ema.recentObservations.count > 10 {
        ema.recentObservations.removeFirst()
    }
    ema.varianceEstimate = computeVariance(ema.recentObservations)
    ema.lastUpdated = Date()
    
    categoryEMAs[category] = ema
}
```

---

## 5. Confidence Intervals

### 5.1 Why Confidence Intervals Matter

A point estimate of "45 minutes" is less useful than "40-55 minutes (80% confidence)". Confidence intervals enable:
- The scheduler to buffer appropriately (don't schedule a meeting 45 minutes after a task that might take 55)
- The morning briefing to communicate uncertainty ("This usually takes you about 45 minutes, but it's ranged from 35 to 65 recently")
- The system to know when its own estimates are unreliable

### 5.2 Confidence Interval Computation

Using the running variance of recent observations:

```swift
func confidenceInterval(category: TaskCategory, level: Double = 0.80) -> (lower: TimeInterval, upper: TimeInterval) {
    guard let ema = categoryEMAs[category], ema.observationCount >= 3 else {
        // Not enough data — return wide interval
        let estimate = ema?.currentEstimate ?? coldStartEstimate(category)
        return (estimate * 0.5, estimate * 2.0)
    }
    
    let stdDev = sqrt(ema.varianceEstimate)
    
    // z-score for desired confidence level
    // 80% → 1.28, 90% → 1.645, 95% → 1.96
    let z: Double
    switch level {
    case 0.80: z = 1.28
    case 0.90: z = 1.645
    case 0.95: z = 1.96
    default: z = 1.28
    }
    
    let margin = z * stdDev
    
    let lower = max(60, ema.currentEstimate - margin)  // Floor: 1 minute minimum
    let upper = ema.currentEstimate + margin
    
    return (lower, upper)
}
```

### 5.3 Confidence Narrowing Over Time

With more observations, the variance estimate becomes more accurate and (for consistent tasks) decreases:

| Observation count | Typical CI width (80%) | State |
|-------------------|----------------------|-------|
| 1-2 | ±100% of estimate | Unreliable — use cold start range |
| 3-5 | ±40-60% of estimate | Learning — wide intervals |
| 6-10 | ±25-35% of estimate | Calibrating — useful for rough scheduling |
| 11-20 | ±15-25% of estimate | Calibrated — reliable for scheduling |
| 20+ | ±10-20% of estimate | Precise — tight scheduling possible |

**Display logic:** The system only displays confidence intervals to the executive once they've narrowed below ±35%. Before that, it shows the point estimate with a "learning" indicator.

---

## 6. Focus Timer Integration

### 6.1 How Focus Timer Feeds EMA

The focus timer is the primary source of actual duration data:

```
1. Executive starts focus timer on a task (category assigned)
2. Executive works on the task
3. Focus timer completes (natural end or manual stop)
4. Actual duration = timer_end - timer_start - pauses
5. Feed actual_duration into EMA for that task's category
```

### 6.2 Timer Completion Types

| Completion type | Duration used | EMA update? |
|-----------------|---------------|-------------|
| Full session completed (timer ran to planned end) | Planned duration | Yes — but see Section 6.3 |
| Task finished early (exec stops timer) | Actual elapsed time | Yes |
| Timer abandoned (exec starts different task) | N/A | No — no reliable duration signal |
| Timer paused and resumed | Elapsed minus pause time | Yes |
| Timer ran but task not finished | Elapsed time | No — partial observation, not a completion (see Section 6.4) |

### 6.3 Censored Observations (Task Fit the Timer)

When the executive sets a 30-minute focus timer and works for exactly 30 minutes, we have a **censored observation**: we know the task took *at most* 30 minutes, but maybe the executive just stopped when the timer ended, even though they could have continued.

**Handling:** If the planned timer duration is within ±20% of the current EMA estimate, treat it as a valid observation. If the planned timer duration is significantly shorter than the EMA (executive set a deliberately short timer), don't update the EMA — the task probably wasn't finished, it was a partial work session.

```swift
func shouldUpdateEMA(plannedDuration: TimeInterval, actualDuration: TimeInterval, currentEMA: TimeInterval) -> Bool {
    // If the executive stopped early → actual < planned → task finished early → valid
    if actualDuration < plannedDuration * 0.9 { return true }
    
    // If timer ran to completion, check if it's close to our estimate
    let ratio = plannedDuration / currentEMA
    if ratio > 0.6 && ratio < 1.5 { return true }  // Close enough to be a real completion
    
    // Timer was much shorter than expected task → probably a partial work session
    return false
}
```

### 6.4 Multi-Session Tasks

Some tasks take multiple focus sessions to complete. The EMA should capture the TOTAL time, not per-session:

```swift
struct TaskDurationTracker {
    let taskId: UUID
    var sessions: [(start: Date, end: Date, duration: TimeInterval)]
    var totalDuration: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }
    
    /// Call when the task is marked complete
    func feedEMA() {
        guard let task = getTask(taskId) else { return }
        recordCompletion(category: task.category, actualDuration: totalDuration)
    }
}
```

The EMA is updated only when `markTaskCompleted()` is called, using the sum of all focus sessions for that task.

---

## 7. Handling Pattern Changes

### 7.1 The Problem

An executive might become faster at email processing (new inbox zero system) or slower at analysis (more complex projects). The EMA must adapt.

### 7.2 Natural Adaptation

EMA with α = 0.25 naturally adapts: after 5 observations at the new speed, ~76% of the estimate reflects the new behaviour. After 10 observations, ~94%. For categories that occur daily (emailBatch), adaptation takes 1-2 weeks. For weekly categories (strategicPlanning), 2-3 months.

### 7.3 Detecting Step Changes

A step change is an abrupt, persistent shift in task duration — not gradual drift.

**Detection (run weekly by the nightly engine):**

```swift
func detectStepChange(category: TaskCategory) -> Bool {
    guard let ema = categoryEMAs[category], 
          ema.recentObservations.count >= 5 else { return false }
    
    let recent5 = Array(ema.recentObservations.suffix(5))
    let recentMean = recent5.reduce(0, +) / Double(recent5.count)
    
    // If the last 5 observations are consistently >30% away from the current EMA
    let deviation = abs(recentMean - ema.currentEstimate) / ema.currentEstimate
    return deviation > 0.30
}
```

**When a step change is detected:**
1. Log it as an episodic memory: "Detected that {category} tasks are now taking significantly {longer/shorter} — {old_estimate}min → {new_mean}min"
2. **Reset the EMA** to the mean of the last 5 observations. This accelerates adaptation instead of waiting for EMA to catch up gradually.
3. Reset the observation count to 5 (to widen confidence intervals appropriately).

### 7.4 Role/Context Changes

When the executive changes roles, teams, or companies, all EMAs should be reset to archetype priors. This is triggered manually during a "reset" conversation with the system, not automatically detected.

---

## 8. Cold Start

### 8.1 Archetype-Based Initial Estimates

Before any observations exist, the system uses archetype-derived estimates:

**Operational CEO archetype (example):**

| Category | Initial estimate (minutes) | CI (80%) | Source |
|----------|---------------------------|----------|--------|
| strategicPlanning | 90 | 45-150 | Executive time studies |
| creativeWork | 60 | 30-120 | Varies wildly by person |
| analysis | 45 | 25-75 | Financial review benchmarks |
| technicalWork | 60 | 30-120 | CTO archetype borrowed |
| oneOnOne | 30 | 20-45 | Calendar analysis standard |
| teamMeeting | 45 | 30-60 | Default meeting length |
| externalMeeting | 60 | 30-90 | Includes prep and follow-up |
| peopleDecision | 30 | 15-60 | Often deferred, actual time is short |
| emailDeepResponse | 15 | 8-30 | Per-email, not batch |
| emailBatch | 25 | 15-45 | Batch processing session |
| phoneCall | 20 | 10-30 | Scheduled calls |
| presentation | 120 | 60-240 | Preparation + delivery |
| scheduling | 10 | 5-20 | Administrative |
| delegation | 15 | 5-30 | Brief + follow-up |
| review | 30 | 15-60 | Reviewing others' work |
| administrative | 15 | 5-30 | Routine tasks |
| learning | 30 | 15-60 | Reading, study |
| recovery | 15 | 5-30 | Intentional breaks |

### 8.2 Calendar History Bootstrap

From 90-day calendar history:
- Meeting durations provide direct observations for meeting-type categories.
- Back-to-back meeting gaps suggest email/admin task durations.
- These are injected as pseudo-observations (treated as real observations with α = 0.15 instead of 0.25 to reduce their weight relative to future real observations).

### 8.3 Minimum Observation Count Before Trust

The system's own estimates are marked with a trust level:

| Observation count | Trust level | Display behaviour |
|-------------------|-------------|-------------------|
| 0 | `archetype` | "Estimated ~{x}min (based on typical executives)" |
| 1-4 | `learning` | "~{x}min (still learning your pace — {n} observations)" |
| 5-9 | `calibrating` | "~{x}min (calibrating — {n} observations)" |
| 10+ | `calibrated` | "{x}min" (stated with confidence, no qualifier) |

The scheduler's buffer logic also varies:
- `archetype` trust: buffer = +50% of estimate (wide margin for unknown)
- `learning` trust: buffer = +35%
- `calibrating` trust: buffer = +20%
- `calibrated` trust: buffer = +10%

---

## 9. Data Model

### 9.1 CoreData

```swift
@Model
class TaskCategoryEMA {
    @Attribute(.unique) var category: String       // TaskCategory.rawValue
    var currentEstimate: Double                    // Seconds
    var observationCount: Int
    var lastUpdated: Date
    var recentObservations: [Double]               // Last 10 durations (seconds), stored as Transformable
    var varianceEstimate: Double
    var trustLevel: String                         // "archetype" | "learning" | "calibrating" | "calibrated"
    var stepChangeDetectedAt: Date?
}
```

### 9.2 Supabase

```sql
create table task_category_ema (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users not null,
    category text not null,
    current_estimate double precision not null,     -- seconds
    observation_count int not null default 0,
    last_updated timestamptz not null default now(),
    recent_observations double precision[] default '{}',
    variance_estimate double precision default 0,
    trust_level text not null default 'archetype',
    step_change_detected_at timestamptz,
    unique(user_id, category)
);

alter table task_category_ema enable row level security;
create policy "users_own_ema" on task_category_ema
    for all using (auth.uid() = user_id);
```

### 9.3 Observation Log

```sql
create table duration_observations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users not null,
    task_id uuid,
    category text not null,
    actual_duration double precision not null,       -- seconds
    planned_duration double precision,               -- what the exec set the timer to (if any)
    ema_before double precision not null,
    ema_after double precision not null,
    was_anomaly boolean default false,
    was_step_change boolean default false,
    completion_type text not null,                   -- 'focus_complete', 'manual_complete', 'early_stop'
    created_at timestamptz not null default now()
);
```

---

## 10. Integration Points

### 10.1 Morning Planning

The morning plan uses EMA estimates to:
- Calculate total work hours needed for all tasks
- Identify if the day is over-committed (total estimated > available hours)
- Place tasks into time slots with appropriate buffers

### 10.2 Calendar Slot Allocator

The slot allocator uses EMA estimate + buffer (based on trust level):

```swift
func slotDuration(task: Task) -> TimeInterval {
    let ema = categoryEMAs[task.category]!
    let bufferMultiplier: Double
    
    switch ema.trustLevel {
    case "archetype": bufferMultiplier = 1.50
    case "learning": bufferMultiplier = 1.35
    case "calibrating": bufferMultiplier = 1.20
    case "calibrated": bufferMultiplier = 1.10
    default: bufferMultiplier = 1.35
    }
    
    return ema.currentEstimate * bufferMultiplier
}
```

### 10.3 Deadline Risk Detection

EMA estimates feed the proactive alert system:

```swift
func checkDeadlineRisk(task: Task) -> DeadlineRisk {
    guard let deadline = task.deadline else { return .none }
    
    let (_, upper) = confidenceInterval(category: task.category, level: 0.90)
    let availableTime = deadline.timeIntervalSinceNow - scheduledMeetingTime(until: deadline)
    
    if upper > availableTime {
        return .atRisk(estimatedCompletion: upper, availableTime: availableTime)
    }
    return .onTrack
}
```

### 10.4 Thompson Sampling Score

The EMA feeds the deadline pressure component of the Thompson scoring formula (see thompson-sampling.md Section 4.3):

```swift
let estimatedHours = categoryEMAs[task.category]!.currentEstimate / 3600
```

---

## 11. Testing Strategy

- **EMA math:** Verify EMA converges to the true mean for a constant input sequence. After 20 observations of exactly 30 minutes, EMA should be within 1% of 30 minutes regardless of cold-start value.
- **Alpha sensitivity:** Run the same observation sequence with α = 0.15, 0.25, 0.35. Verify 0.25 balances responsiveness and stability (quantify via MSE against true values).
- **Outlier rejection:** Feed an anomalous 4x observation. Verify EMA is unchanged.
- **Confidence interval narrowing:** Verify CI width monotonically decreases with more observations for a constant-mean input.
- **Step change detection:** Feed 20 observations at 30 min, then 5 at 60 min. Verify step change is detected and EMA resets.
- **Multi-session tasks:** Complete a task across 3 focus sessions. Verify total duration (sum of sessions) is used for EMA, not individual session durations.
- **Censored observation handling:** Set a 15-minute timer when EMA is 45 minutes. Verify the observation is NOT used (partial session).
- **Cold start bootstrap:** Load calendar pseudo-observations. Verify they shift the estimate from archetype default but with reduced weight.
- **Trust level transitions:** Verify trust level transitions happen at exactly the right observation counts (0, 1, 5, 10).
- **Persistence round-trip:** Write EMA state to CoreData and Supabase, read it back, verify exact equality.
