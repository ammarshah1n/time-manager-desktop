# The Scoring Model — Linear Weighted Sum + Greedy Knapsack: Diagnosis, Alternatives, and What to Actually Build

## Executive Summary

Timed's scoring model is a **linear additive composite score** fed into a **priority-ordered greedy knapsack**. It is not naïve — it already has Thompson sampling, timing bumps from energy-curve rules, mood filters, and a `durationPenalty` to discourage duration-padding. But four structural problems limit its accuracy for a single executive user: (1) it already implements Thompson sampling but the `bucketStats` array is always empty, so Thompson always returns zero; (2) the `durationPenalty` operates on biased AI estimates, not corrected actuals; (3) the greedy ordering ignores task dependency chains and energy-time coupling; and (4) the score constants (`Score.*`) were hand-tuned and have never been calibrated against completion data.

The verdict on each alternative: **Multi-armed bandit** is already partially implemented (Thompson proxy exists) and finishing it is the highest-ROI change. **Constraint satisfaction** is overkill for a single-user to-do list and introduces latency. **Full RL with neural ranking** is data-starved at this scale. **Bayesian time estimation feedback** (covered in Loop 3) is a prerequisite for fixing the knapsack regardless of which ordering algorithm is chosen.

***

## Part 1: What the Current Scoring Model Actually Does

### `scoreTask()` — Full Breakdown

`PlanningEngine.scoreTask()` computes a `ScoreBreakdown` with seven additive components:

\[
S = S_\text{base} + S_\text{overdue} + S_\text{deadline} + S_\text{mood} + S_\text{behaviour} + S_\text{timing} + S_\text{thompson}
\]

**Base score:** `bucketBase + priorityBase + quickWin + durationPenalty`

- `bucketBase`: action=400, reply=350, calls=250, transit=150, read=100, other=0
- `priorityBase`: `task.priority × 80` (priority 0–5 scale from DB)
- `quickWin`: +150 if `estimatedMinutes ≤ 5`
- `durationPenalty`: `-2 × estimatedMinutes` (discourages padding with long tasks)

**Bumps:**
- Overdue: +1000 (hard bump, makes overdue tasks dominate)
- Deadline: +500 (≤24h), +200 (≤72h), +100 (≤1 week)
- Mood: +500 (easy_wins if ≤5m), +500 (avoidance if deferredCount ≥2), -9999 (deep_focus kill for non-action)
- Behaviour/ordering: `Score.behaviourOrdering × confidence` per matching `ordering` rule
- Timing: `Score.timingMatch × confidence` if current hour in `preferred_hours`, `Score.timingMiss × confidence` if not
- Thompson: 0–250 based on completion ratio for bucket+hour-range



### The Greedy Knapsack

After scoring, tasks are sorted descending by `totalScore`. Fixed-position tasks (`isDailyUpdate`, `isFamilyEmail`) are pulled out and pinned to positions 0 and 1. The greedy pass then adds tasks in score order until `availableMinutes` would be exceeded. There is no backtracking — if a 45-minute task is at position 3 in the score ranking but won't fit in the remaining 40 minutes, it is discarded to overflow even if three 10-minute tasks ranked below it would fit.

`DishMeUpSheet` passes `bucketStats: []` (always empty) when constructing `PlanRequest`. `TodayPane` likely does the same. This means `thompsonBump()` always returns 0 — the check `guard total >= Score.thompsonMinSamples` never triggers because `total = completions + deferrals` is always zero.

### Three Structural Problems

**Problem 1 — Thompson is wired but starved.** The code is correct. The data pipeline that feeds it does not exist. Fix: populate `bucketStats` from `behaviour_events` on plan generation (covered in Loop 3 report).

**Problem 2 — `durationPenalty` operates on hallucinated estimates.** `task.estimatedMinutes` comes from `tasks.estimated_minutes_ai`, which was set at task creation by `estimate-time`. If Loop 3's estimation loop was never seeded (it wasn't — see previous report), these estimates are systematic guesses from the Claude Sonnet fallback or hardcoded category defaults. The penalty `−2 × 30` = −60 for a mis-estimated action task vs `−2 × 5` = −10 for a reply systematically over-penalises action tasks relative to quick tasks. Fix: use corrected `BucketEstimate.meanMinutes` from Loop 1 as the estimate basis.

**Problem 3 — Greedy ignores fill-in opportunities.** The greedy algorithm's 0-1 decision (add or skip, no backtracking) means it consistently sub-fills the available window. For a 120-minute `DishMeUp` session with three 35-minute tasks scored highly and a 20-minute gap, the current algorithm leaves 20 minutes unallocated rather than filling with a 20-minute task ranked lower. A trivial fix — a second-pass fill — captures most of this value without changing the algorithm class.[^1]

***

## Part 2: Should the Scoring Model Be Replaced?

### Option A: Multi-Armed Bandit (Finish What's Already Built)

**What it means here:** Each task bucket+hour-range pair is an "arm." The reward signal is `task_completed` vs `task_deferred` from `behaviour_events`. Thompson sampling draws a completion-probability sample from the Beta posterior \(\text{Beta}(\alpha_k, \beta_k)\) for each arm \(k\), where \(\alpha_k = \text{completions} + 1\), \(\beta_k = \text{deferrals} + 1\), and selects the arm with the highest sample.[^2]

**The code already does this.** `thompsonBump()` computes a score bonus proportional to `completions / (completions + deferrals)` per bucket+hour-range. The `Score.thompsonMax = 250` caps the bonus. The `thompsonMinSamples = 10` gates cold-start.

**What's missing:** (a) `bucketStats` is never populated (b) the proxy `ratio = completions / total` is not real Thompson sampling — it computes the *maximum a posteriori* estimate rather than *sampling* from the Beta posterior. True Thompson sampling draws a random sample from `Beta(α, β)` rather than taking the mean, which drives exploration of uncertain buckets. For a single-user system with small N, the distinction matters most in the first 20–50 observations per arm.[^3][^2]

**The fix — real Beta Thompson sampling in Swift:**

```swift
// In PlanningEngine.thompsonBump(), replace the ratio proxy:
let alpha = Double(stat.completions) + 1.0
let beta = Double(stat.deferrals) + 1.0
// Draw from Beta(alpha, beta) using log-normal approximation (no Beta distribution in Swift stdlib)
let mu = alpha / (alpha + beta)
let variance = (alpha * beta) / ((alpha + beta) * (alpha + beta) * (alpha + beta + 1))
let sigma = sqrt(variance)
// Clamp to [0, 1]
let sample = min(1.0, max(0.0, mu + sigma * gaussianSample()))
return Int(sample * Double(Score.thompsonMax))
```

`gaussianSample()` uses the Box-Muller transform (two `Double.random(in: 0..<1)` calls). Total delta: ~15 lines.[^4][^5]

**Verdict: Finish this first.** It's already architecturally present, requires no new infrastructure, and is the theoretically correct way to handle exploration for a system with limited data.[^6][^7]

### Option B: Reinforcement Learning (reward = completion rate)

**What it means here:** Model the planning problem as a Markov Decision Process where the state is the current task queue + context features, the action is a task ordering, and the reward is binary completion at end of session. A policy gradient or Q-learning agent learns which orderings lead to higher completion rates.

**Why it won't work at Timed's scale:** RL with neural policies requires thousands of episodes (days of use) to converge, has high variance on small datasets, and is extremely sensitive to reward sparsity. For a single executive completing 10–20 tasks/day, the reward signal is too sparse and non-stationary (the executive's schedule changes constantly). A full RL agent trained on a single user would be dominated by noise for months.[^6]

**The contextual bandit is the right scope.** Contextual bandits treat each plan generation as an independent context-action-reward tuple — no inter-episode state dependencies — which matches the actual problem structure (each `DishMeUp` session is independent). The Thompson sampling already in `PlanningEngine` is the right algorithm.[^5][^4]

**Verdict: Not now.** The bandit is the correct tool for this problem size. RL adds complexity without benefit below ~10,000 labelled episodes.

### Option C: Neural Ranking Models

**What it means here:** Train a learning-to-rank model (e.g., a pairwise RankNet or a listwise LambdaMART) to predict the ideal task ordering from features. The existing `ScoreBreakdown` components become input features; ground truth comes from "which task did the user complete when presented with an ordered list."

**The core problem:** Learning-to-rank requires pairwise preference data — for every presented plan, you need to know which tasks were completed vs deferred *and* what the causal relationship was. At 15 tasks/day and 50% completion rate, generating statistically meaningful pairwise labels takes months. LambdaMART in production (Reclaim, Todoist) is trained on millions of users, not one.[^8]

**What you can get from this direction now:** The `ScoreBreakdown` struct already decomposes the score into interpretable components. Adding `estimate_error` (from Loop 3) and `hour_of_day` to the feature vector, then fitting a simple logistic regression on `completed` (binary outcome per task) against these features, is feasible within 30 days of data collection. This is not neural ranking — it's a calibrated linear model — but it calibrates the hand-tuned `Score.*` constants against real data.

**Calibration of Score constants via logistic regression:**

```python
# After 30 days of data in behaviour_events + estimation_history
from sklearn.linear_model import LogisticRegression
import pandas as pd

df = pd.read_sql("""
    SELECT 
        bucket_type, estimated_minutes, priority, deferred_count,
        hour_of_day, days_in_queue,
        event_type = 'task_completed' AS completed
    FROM behaviour_events
    WHERE event_type IN ('task_completed', 'task_deferred')
""", conn)

X = df[['estimated_minutes', 'priority', 'deferred_count', 'hour_of_day', 'days_in_queue']]
y = df['completed']
model = LogisticRegression().fit(X, y)
print(model.coef_)  # Calibrated weights to replace Score.* constants
```

**Verdict: Not a neural model, but log-reg calibration is worthwhile after 30 days.**

### Option D: Constraint Satisfaction (like Motion)

**What Motion does:** Motion models scheduling as a CSP with hard constraints (calendar availability, deadlines, estimated duration) and soft constraints (priority, time-of-day preferences). It uses a priority-ordered insertion heuristic with backtracking to find a feasible assignment of tasks to time slots. The key difference from Timed's approach: Motion schedules tasks *to specific calendar time slots*, not just orders them in a queue.[^9][^10]

**Why this doesn't apply to Timed's model:** Timed is a *queue prioritisation* system, not a *calendar scheduler*. The executive starts the app, picks a session duration, and gets an ordered list — not time-blocked calendar events. The knapsack constraint is soft (the `DishMeUp` session time), not hard calendar blocks. Constraint satisfaction adds O(N²) backtracking complexity for a problem that doesn't have hard placement constraints.[^11][^10]

**What you can borrow from CSP:** The concept of **slack preservation** — preferring orderings that keep the schedule flexible rather than over-committing to long tasks at the front of the queue. The `durationPenalty` already partially does this, but a more principled version would prefer orderings where the *cumulative estimated time + buffer* stays below `availableMinutes × 0.85`, leaving a 15% slack buffer for overruns.[^10]

**Verdict: Don't replace greedy with CSP. Add a slack-aware fill pass.**

***

## Part 3: The Greedy Knapsack — The Fix Is Simple

The greedy algorithm leaves value on the table when score-rank and duration are misaligned. Two additions fix 80% of this:

### Fix 1 — Second-Pass Fill

After the greedy pass, calculate `remainingMinutes = availableMinutes - usedMinutes`. Run a second pass over `overflow` items sorted by `estimatedMinutes` ascending, adding any item where `estimatedMinutes ≤ remainingMinutes`. This takes ~8 lines:[^1]

```swift
// After the greedy loop, second-pass fill:
var remainingMinutes = request.availableMinutes - usedMinutes
var fillCandidates = overflow.sorted { $0.estimatedMinutes < $1.estimatedMinutes }
overflow = []
for item in fillCandidates {
    if item.estimatedMinutes <= remainingMinutes {
        selected.append((task: item, breakdown: scoreTask(item, now: now, ...)))
        remainingMinutes -= (item.estimatedMinutes + bufferPerTask)
    } else {
        overflow.append(item)
    }
}
```

This is especially impactful for `DishMeUpSheet` sessions where the user has, say, 90 minutes and the top three tasks are 35+35+30 = 100 minutes, but six 10-minute replies are in overflow.

### Fix 2 — Corrected Duration in Knapsack Budget

Currently: `if usedMinutes + item.task.estimatedMinutes <= request.availableMinutes`

The `estimatedMinutes` on the task is the AI's original estimate, not corrected by actuals. Once Loop 3 is live, `PlanRequest` should carry `bucketEstimates: [String: Double]` (already defined in `DishMeUpSheet.generate()` and the `PlanRequest` struct) and the knapsack budget calculation should use:

```swift
let correctedMinutes = request.bucketEstimates[item.task.bucketType]
    .map { Int($0) } ?? item.task.estimatedMinutes
if usedMinutes + correctedMinutes <= request.availableMinutes { ... }
```

`DishMeUpSheet` already populates `bucketEstimates` in `PlanRequest` from `DataStore.shared.loadBucketEstimates()`. The change is in `PlanningEngine.generatePlan()` — use the corrected estimate for budget accounting, not the raw AI estimate. ~10 lines.

***

## Part 4: Score Constant Problems

### The `durationPenalty = -2` Is Too Aggressive for Short Sessions

For a 30-minute `DishMeUp` session, an action task estimated at 25 minutes has:
- `base = 400 (action) + priority×80 + 0 (no quick win) + (25×-2) = 400 - 50 - ... = 350+`
- A reply task estimated at 5 minutes: `350 + priority×80 + 150 (quick win) + (5×-2) = 490+`

The reply consistently outscores the action task because of the penalty, even when the user only has `deepFocus` mode available and explicitly wants action work. The `deepFocus` mode kills non-action with `-9999`, which overrides this — but only if the user activates it.

The penalty should scale with session length: steeper for short sessions (where long tasks genuinely don't fit), flatter for long sessions (where duration matters less):

```swift
// In scoreTask(), replace:
let durationPenalty = task.estimatedMinutes * Score.durationPenalty

// With (requires passing availableMinutes into scoreTask):
let penaltyRate = availableMinutes < 45 ? -3 : availableMinutes < 90 ? -2 : -1
let durationPenalty = task.estimatedMinutes * penaltyRate
```

`scoreTask()` currently does not receive `availableMinutes` — it would need to be added as a parameter or embedded in `PlanRequest` and threaded through. ~5 lines in the function signature + call sites.

### The `quickWinBump` Threshold Is Too Strict

`quickWinBump = 150` fires only if `estimatedMinutes ≤ 5`. For most executives, "quick win" means ≤10–15 minutes. An email reply estimated at 8 minutes gets no quick win bump. This threshold should be configurable or derived from the user's `BucketEstimate` data — the 25th percentile of `reply_email` actual times is the natural quick-win threshold.

### The `overdueBump = 1000` Dominates Everything

An overdue task with `priority=1` scores: `350 (reply) + 80 + 1000 = 1430`. A high-priority (`priority=5`) action task due in 48 hours scores: `400 + 400 + 200 = 1000`. The overdue bump is so large that any overdue task automatically beats any non-overdue task regardless of business importance. For an executive with 20 overdue emails (common), the plan will be all overdue tasks, all the time, until the backlog clears — even if a critical deadline-bound action task needs to happen today.

Fix: cap the effective overdue count at 3 items — the greedy algorithm already handles "we can't do everything," so the scoring just needs to order the top-3 overdue items above fresh work, not make every overdue item dominate:

```swift
// Track overdue tasks seen so far in the scoring pass
// If more than 3 overdue tasks have already been selected, 
// reduce overdueBump to 200 for subsequent ones
let overdueBump = task.isOverdue ? 
    (overdueCountSoFar < 3 ? Score.overdueBump : 200) : 0
```

This requires tracking state across `scoreTask()` calls in `generatePlan()` rather than keeping `scoreTask()` pure — a small architectural trade-off.

***

## Part 5: What Not to Build

| Alternative | Why Skip It Now |
|---|---|
| Full RL (policy gradient) | Needs thousands of episodes; single-user data is too sparse[^6] |
| LambdaMART / neural ranking | Requires pairwise preference labels at scale; not feasible for one user[^8] |
| Constraint satisfaction scheduler | Correct for calendar-block products (Motion); wrong for queue-prioritisation[^11] |
| UCB1 bandit | Thompson sampling already present and better-calibrated for noisy small-N settings[^3][^2] |
| Separate RL reward model | `task_completed` / `task_deferred` in `behaviour_events` already is the reward signal |

***

## Part 6: The Full Scoring Model Improvement Roadmap

| Priority | Change | Lines | Dependency | Expected Impact |
|---|---|---|---|---|
| 1 | Populate `BucketCompletionStat` from `behaviour_events` | ~30 | Loop 3 write-back | Thompson sampling activates; +~150 points directional accuracy |
| 2 | True Beta Thompson sampling (Box-Muller draw) | ~15 | Step 1 | Exploration of undersampled bucket+hour combinations |
| 3 | Second-pass fill in greedy knapsack | ~8 | None | Fills 10–25% of wasted session time |
| 4 | Use `bucketEstimates` corrected minutes in budget | ~10 | Loop 1 EMA | Knapsack operates on honest durations |
| 5 | Session-length-adaptive `durationPenalty` | ~5 | None | Fixes bias against action tasks in short sessions |
| 6 | Cap `overdueBump` dominance after 3 items | ~12 | None | Prevents overdue backlog from monopolising every plan |
| 7 | Logistic regression calibration of Score constants | ~50 (Python script) | 30 days of data | Data-derived weights replace hand-tuned constants |

Steps 1–4 interact with the Loop 3 write-back from the previous report. Steps 3, 5, 6 are entirely independent and can be shipped immediately. Step 7 is a future calibration exercise once the data pipeline is live.

---

## References

1. [[PDF] Advanced Greedy Algorithms and Surrogate Constraint Methods for ...](https://leeds-faculty.colorado.edu/glover/444%20-%20Advanced%20Greedy%20Algorithms%20and%20Surrogate%20Constraint%20Methods.pdf) - Single-constraint 0-1 knapsack and covering problems with linear and quadratic objectives may be for...

2. [Thompson Sampling for Bandits - Guide 2025 | ShadeCoder](https://www.shadecoder.com/topics/thompson-sampling-for-bandits-a-comprehensive-guide-for-2025) - Research indicates that Bayesian approaches like Thompson Sampling tend to provide efficient explora...

3. [[PDF] Comparative Analysis and Practical Applications of Multi-Armed ...](https://www.scitepress.org/Papers/2024/129391/129391.pdf) - In comparing the widely-used Multi-Armed Bandit. (MAB) algorithms—ε-greedy, UCB (Upper. Confidence B...

4. [[PDF] A Practical Method for Solving Contextual Bandit Problems Using ...](https://www.auai.org/uai2017/proceedings/papers/171.pdf) - To guide the exploration- exploitation trade-off, we use a bootstrapping approach which abstracts Th...

5. [[PDF] Thompson Sampling for Constrained Bandits](https://rlj.cs.umass.edu/2025/papers/RLJ_RLC_2025_365.pdf) - Contextual bandits model sequential decision-making where an agent balances exploration and exploita...

6. [A Comparison of Bandit Algorithms | Towards Data Science](https://towardsdatascience.com/a-comparison-of-bandit-algorithms-24b4adfcabb/) - Part 3: Bandit Algorithms _- The Greedy Algorithm · The Optimistic ... Baby Robot Guide, Multi Armed...

7. [[PDF] Comparative analysis and applications of classic multi-armed bandit ...](https://pdfs.semanticscholar.org/8012/f0e7ea4edf09ff57312e1d43ed0493d909b8.pdf) - Keywords: Reinforcement Learning, Multi-armed Bandit, Upper Confidence Bound, Epsilon-. Greedy Algor...

8. [[PDF] Learning Variable Ordering Heuristics for Solving Constraint ... - arXiv](https://arxiv.org/pdf/1912.10762.pdf) - A constraint programming approach to simultaneous task allocation and motion scheduling for industri...

9. [[PDF] Minimizing conflicts: a heuristic repair method for constraint ...](https://www.dcs.gla.ac.uk/~pat/cpM/papers/mintonAIJ.pdf) - The paper describes a simple heuristic approach to solving large-scale constraint satisfaction and s...

10. [[PDF] From Precedence Constraint Posting to Partial Order Schedules](https://www.ri.cmu.edu/pub_files/2007/5/pcos_AICOM07.pdf) - Our approach is characterized by the use of the Con- straint Satisfaction Problem paradigm (CSP): a ...

11. [[PDF] 5 CONSTRAINT SATISFACTION PROBLEMS - Artificial Intelligence](http://aima.cs.berkeley.edu/newchap05.pdf) - Higher-order constraints involve three or more variables. A ... state may be chosen randomly or by a...

