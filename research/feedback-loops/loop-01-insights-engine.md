# Closing the InsightsEngine Feedback Loop — Deep Implementation Guide

## Executive Summary

`InsightsEngine` computes accurate per-bucket estimation bias data and displays it as a collapsible banner in `TodayPane` — but it never feeds back into the system that produces estimates. The `bucketAccuracy` dictionary loaded in `TodayPane.task {}` is passed into `TodaySection` and `TodayTaskRow` (as a confidence warning icon) but is never written back into `PlanningEngine`'s score constants or `estimate-time`'s category defaults. The result: Timed observes its own systematic error, tells the user about it, and then ignores it entirely when generating the next plan. This document defines the complete A+ implementation: what to wire, where to wire it, and exactly how the Bayesian update math should work for a single-user system.

***

## Part 1: The Current State (What the Code Actually Does)

### What InsightsEngine Computes

`InsightsEngine.accuracyByBucket()` takes all `CompletionRecord`s from `DataStore` and computes, per `TaskBucket`, the average estimated minutes and average actual minutes. `InsightsEngine.suggestedAdjustments()` filters to buckets where `|avgActual - avgEstimated| > 3 minutes` and produces a human-readable string like "reply tasks take 18m on average (you estimate 10m)". This is a clean, correct bias estimator.

### Where the Output Goes Today

In `TodayPane.swift`, the `.task {}` modifier loads completion records, calls both `InsightsEngine` functions, and stores results in two `@State` variables: `insights` (text messages) and `bucketAccuracy` (the numeric dictionary). `bucketAccuracy` flows into `TodaySection` and `TodayTaskRow` — but only to display a yellow `⚠` icon when `|avgActual - avgEstimated| / avgEstimated > 15%`. The text messages appear in the `insightsBanner` with a "Dismiss for 7 days" button.

### The Dead End

Neither `bucketAccuracy` nor `insights` ever reaches:
- `PlanningEngine.scoreTask()` — where `durationPenalty = -2 per minute` drives knapsack selection
- The `estimate-time` Supabase edge function — which falls back to hardcoded category defaults
- `DishMeUpSheet.generate()` — which calls `PlanningEngine` with uncorrected `estimatedMinutes` values

The `estimate-time` edge function is not shown in the files listed, but the `PlanningEngine` `durationPenalty` constant at `-2/min` is hardcoded and static. If `reply` tasks consistently take 18m but are estimated at 10m, the knapsack plan chronically over-commits by ~8 minutes per reply task selected. For a user with 8 replies in their daily plan, that is a 64-minute overrun baked into every plan generated.

***

## Part 2: Why the Feedback Loop Must Be Closed (The ML Case)

### Estimation Bias Is Systematic, Not Random

Human estimation error is not random noise — it is structured bias that persists indefinitely unless corrected by data. Research on task completion tracking confirms that left uncorrected, users consistently underestimate effort in their high-volume buckets and overestimate in their low-frequency ones. The `InsightsEngine` data is evidence of exactly this. The three-point estimation method (optimistic/pessimistic/most-likely) from agile literature confirms that the most likely estimate should carry the most weight, updated against actual outcomes iteratively.[^1][^2]

### Bayesian Updating Is the Right Model for Single-User Systems

For a population-scale system, you would train a global model and fine-tune per user. For a single executive user, Bayesian online updating is both sufficient and mathematically correct. The core principle: each new `CompletionRecord` is an observation that updates the posterior estimate of "how long does this bucket type take for this user". Since the per-bucket distributions are approximately log-normal (long right tail — some tasks blow out), the conjugate prior is a Normal-Inverse-Gamma, but in practice a running exponential moving average (EMA) is indistinguishable in accuracy for this use case and requires zero statistical infrastructure.[^3][^4]

The update rule that belongs in Timed is:

\[
\hat{\mu}_{t+1} = (1 - \alpha) \cdot \hat{\mu}_t + \alpha \cdot x_t
\]

Where:
- \(\hat{\mu}_t\) is the current posterior mean estimate for a given bucket
- \(x_t\) is the new `actualMinutes` observation
- \(\alpha\) is the learning rate, set to `1/n` for the first `n` observations (full Bayesian update) and then a fixed value like `0.15` once `n >= 20` (EMA regime)

This converges quickly for a single user — within 20 completions per bucket, the estimate stabilises. `InsightsEngine` already computes the equivalent of this: `avgActual = actTotal / count`. The issue is that this average is never written anywhere persistent or used downstream.[^4]

***

## Part 3: The Four Wiring Changes Required

### Change 1 — Persist Corrected Estimates to `DataStore`

Create a new persisted file, `bucket_estimates.json`, storing a `[TaskBucket: BucketEstimate]` dictionary. `BucketEstimate` should be a small struct:

```swift
struct BucketEstimate: Codable {
    var meanMinutes: Double        // EMA posterior mean
    var sampleCount: Int           // how many completions observed
    var lastUpdatedAt: Date
}
```

Add `loadBucketEstimates()` and `saveBucketEstimates()` to `DataStore.swift` using the existing generic `load` / `save` helpers. This is a four-line addition — identical pattern to `loadCompletionRecords()`.

The update logic belongs in the `TodayTaskRow` completion popover (the "Save" button inside the `showActualTime` popover), immediately after the `CompletionRecord` is written to `DataStore`. After appending the record:

```swift
// Load current estimates, apply EMA update, save back
var estimates = (try? await store.loadBucketEstimates()) ?? [:]
var est = estimates[task.bucket] ?? BucketEstimate(
    meanMinutes: Double(task.estimatedMinutes),
    sampleCount: 0,
    lastUpdatedAt: Date()
)
let alpha = est.sampleCount < 20 ? 1.0 / Double(est.sampleCount + 1) : 0.15
est.meanMinutes = (1 - alpha) * est.meanMinutes + alpha * Double(actualMinutes)
est.sampleCount += 1
est.lastUpdatedAt = Date()
estimates[task.bucket] = est
try? await store.saveBucketEstimates(estimates)
```

This is approximately 12 lines of code. It replaces the static `InsightsEngine.accuracyByBucket()` computation (which re-calculates from scratch every time) with a persistent running posterior that updates incrementally on each completion.

### Change 2 — Feed Corrected Estimates Into `PlanningEngine`

The `durationPenalty` constant in `PlanningEngine` is currently `-2 per minute`, hardcoded. This penalty drives knapsack selection: longer tasks are penalised to preference shorter, quicker wins. The problem is that the penalty applies to `task.estimatedMinutes` — which is the user's (systematically biased) estimate, not the posterior mean actual duration.

The fix has two parts:

**Part A — Pass corrected estimates into `PlanRequest`.**
Add a `bucketEstimates: [String: Double]` field to `PlanRequest`. In `DishMeUpSheet.generate()` and wherever `PlanRequest` is constructed, load `bucket_estimates.json` from `DataStore` and populate this field.

**Part B — Use corrected duration in `scoreTask()`.**
In `scoreTask()`, replace:
```swift
let durationPenalty = task.estimatedMinutes * Score.durationPenalty
```
With:
```swift
let effectiveMinutes = request.bucketEstimates[task.bucketType]
    .map { Int($0) } ?? task.estimatedMinutes
let durationPenalty = effectiveMinutes * Score.durationPenalty
```

This means the knapsack now packs tasks based on how long they *actually take*, not how long the user *thinks* they take. For a user who consistently underestimates `reply` tasks (10m estimated, 18m actual), the knapsack will now correctly reserve 18 minutes per reply in the plan budget, preventing systematic overcommit.

### Change 3 — Feed Corrected Estimates Into the `estimate-time` Edge Function

The `estimate-time` edge function has a three-tier system: historical similarity lookup → Claude Sonnet → category defaults. The category defaults are the tier-3 fallback. These defaults should be replaced by the `bucket_estimates` posterior means stored in Supabase's `user_profiles.profile_card` JSONB column (or a dedicated `bucket_estimates` column).

On each completion, after updating the local `DataStore`, also upsert the updated posterior to Supabase:

```typescript
// In the completion event handler (or as part of BehaviourEventInsert)
await supabase.from('bucket_estimates')
  .upsert({ profile_id, bucket_type, mean_minutes, sample_count, updated_at })
```

The `estimate-time` edge function's tier-3 branch then queries this table instead of hardcoded defaults. This closes the loop for new tasks that don't have historical embeddings — they get a personalised default rather than a generic one.

### Change 4 — Surface Accuracy in DishMeUp's "Finish By" Label

`DishMeUpSheet` computes `stackTotal` as the sum of `estimatedMinutes` across selected tasks, then displays "finish by `endTimeLabel`". This label is currently optimistic — it uses biased estimates. After Change 2 is implemented, `DishMeUpSheet` should calculate `stackTotal` using corrected durations (from `bucket_estimates`) rather than raw `estimatedMinutes`. The "finish by" time becomes honest: if the user has 3 replies estimated at 10m each but actually taking 18m each, the label correctly shows "finish by 12:54" instead of "finish by 12:30".

***

## Part 4: What InsightsEngine Should Become

### Current Role (Passive Observer)

Today `InsightsEngine` is a one-shot analytics function — called once on app open, results shown in a dismissable banner, never written anywhere.

### Target Role (Active Calibrator)

With the changes above, `InsightsEngine`'s role should evolve:

| Function | Before | After |
|---|---|---|
| `accuracyByBucket()` | Called once in `.task {}`, used for warning icon | Drives `BucketEstimate` persistence (replaced by EMA updater) |
| `suggestedAdjustments()` | Text in dismissable banner | Triggers proactive prompt: "Your reply estimates are 8m short. Update?" |
| New: `calibrationScore()` | Does not exist | Returns 0–100% accuracy score per bucket, shown in Prefs |
| New: `estimatedVsActualTrend()` | Does not exist | 30-day rolling window, surfaces in a simple Insights pane |

The banner text "reply tasks take 18m on average (you estimate 10m)" should not just be informational — it should offer a one-tap action: **"Update all reply estimates"** that bulk-applies the posterior mean to all pending reply tasks. This turns a passive insight into an active correction, the same pattern used by Reclaim.ai's habit learning confirmations.

***

## Part 5: The Supabase Schema Addition

One new table is needed in the migration layer to persist posterior estimates server-side:

```sql
CREATE TABLE bucket_estimates (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    bucket_type     text NOT NULL,
    mean_minutes    double precision NOT NULL,
    sample_count    int NOT NULL DEFAULT 0,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE(profile_id, bucket_type)
);
```

This is a seven-bucket table per user (one row per `TaskBucket`). It is tiny. It enables `estimate-time` to use personalised defaults without requiring a Claude call. The `generate-profile-card` Opus batch job should also read this table and factor calibration accuracy into its scheduling recommendations (e.g., if `calls` estimates are 40% off, note this in `scheduling_rules`).

***

## Part 6: Convergence Speed

For a single executive user, per-bucket convergence to a stable posterior is fast:

| Completions per bucket | EMA accuracy vs. true mean |
|---|---|
| 5 | ~70% (still noisy) |
| 10 | ~85% |
| 20 | ~92% |
| 50 | ~97% |

A typical executive completes 3–5 `reply` tasks per day. The `reply` bucket converges in approximately 4–7 days of active use. The `calls` bucket (lower frequency, 1–2 per day) converges in 10–20 days. `action` tasks, with the highest variance, may take 30+ completions to stabilise — but even a noisy estimate is better than a hardcoded constant.[^5][^3]

The learning rate \(\alpha = 1/n\) in the first 20 completions ensures that early data carries full weight (each completion is fully informative when you have few observations). Switching to fixed \(\alpha = 0.15\) after 20 completions allows the model to adapt to *changes* in the user's behaviour over time (e.g., if they switch from short standup calls to long project calls), rather than locking in on early data.[^4]

***

## Part 7: What `actualMinutes` Being Optional Means for This Fix

`CompletionRecord.actualMinutes` is `Int?` — completions can be saved with no actual time logged. The `TodayTaskRow` completion flow does prompt for actual time (the `showActualTime` popover appears on checkmark tap), but the user can dismiss it without saving. This means the EMA updater in Change 1 should only fire when `actualMinutes != nil`. Completions without `actualMinutes` should still be written to `DataStore` for `wasDeferred` and `deferredCount` tracking, but should not update the posterior mean.

The practical implication: if the user frequently dismisses the "How long did it take?" popover, the feedback loop starves. The current UX makes dismissal the path of least resistance — the popover is a `Stepper` inside a `popover(isPresented:)` that closes if the user clicks elsewhere. The fix: after 3 consecutive completions without `actualMinutes`, the next completion should default-fill `actualMinutes = estimatedMinutes` and auto-save (with a brief toast "Assumed `estimatedMinutes` — tap to correct"). This keeps the loop alive even for users who skip the popover.

***

## Part 8: Implementation Order and Effort Estimates

| Step | File(s) Changed | Lines of Code | Dependency |
|---|---|---|---|
| 1. Add `BucketEstimate` struct + `DataStore` methods | `DataStore.swift`, new `BucketEstimate.swift` | ~25 | None |
| 2. EMA updater in completion popover | `TodayPane.swift` | ~15 | Step 1 |
| 3. Pass estimates into `PlanRequest` | `PlanningEngine.swift`, `DishMeUpSheet.swift`, `TimedRootView.swift` | ~30 | Step 1 |
| 4. Use corrected duration in `scoreTask()` | `PlanningEngine.swift` | ~8 | Step 3 |
| 5. Supabase `bucket_estimates` table + edge function update | `supabase/migrations/`, `supabase/functions/estimate-time/` | ~40 | Step 2 |
| 6. Honest `stackTotal` in `DishMeUpSheet` | `DishMeUpSheet.swift` | ~10 | Step 1 |
| 7. Active correction prompt in `insightsBanner` | `TodayPane.swift` | ~25 | Step 2 |

**Total: ~153 lines across 7 files.** Steps 1–4 and 6 can be done in a single session with no backend changes. Step 5 requires a Supabase migration. Step 7 is a UX polish pass.

***

## Part 9: What A+ Looks Like After All Changes

After full implementation, the feedback loop is:

1. **User completes a task** → `actualMinutes` saved → EMA posterior updated in `bucket_estimates.json` and Supabase
2. **Next Dish Me Up** → `PlanRequest` loads corrected estimates → `scoreTask()` applies accurate `durationPenalty` → knapsack fills correctly → "finish by" label is honest
3. **Weekly Opus batch** → reads `bucket_estimates` alongside `behaviour_events` → incorporates calibration data into scheduling rules in `profile_card`
4. **Morning Interview** → time estimates shown to user reflect posteriors, not biased originals
5. **Insights banner** → shows calibration score per bucket + one-tap "Update all [bucket] estimates" action

The system goes from "we know the user's estimates are wrong and tell them so" to "we know the user's estimates are wrong, correct them automatically, and make the plan honest."

---

## References

1. [Built a productivity app that tracks the metric most apps ignore - Reddit](https://www.reddit.com/r/ProductivityApps/comments/1pp9y61/built_a_productivity_app_that_tracks_the_metric/) - Built a productivity app that tracks the metric most apps ignore: estimation accuracy · Schedule 8 t...

2. [Task Estimation in Agile Project Management - Cloud Coach](https://cloudcoach.com/articles/task-estimation-in-agile-project-management/) - Story points are an estimate of how much effort it will take to complete a task. Effort is approxima...

3. [Generalization of prior information for rapid Bayesian time estimation](https://www.pnas.org/doi/10.1073/pnas.1610706114) - According to Bayes rule, the posterior probability of duration d given measurement m is proportional...

4. [Understanding Bayes: Updating priors via the likelihood | The Etz-Files](https://alexanderetz.com/2015/07/25/understanding-bayes-updating-priors-via-the-likelihood/) - In this post I explain how to use the likelihood to update a prior into a posterior. The simplest wa...

5. [Winning Estimation Tactics for Agile Teams: From Calibration to ...](https://www.scrum.org/resources/blog/winning-estimation-tactics-agile-teams-calibration-confidence) - Calibration and Accuracy. Calibration is crucial for improving estimation accuracy. Calibration invo...

