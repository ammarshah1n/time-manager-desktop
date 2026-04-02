# Timed: Cold-Start ML Acceleration — Codebase-Grounded Research Report

## What the Codebase Actually Has (and What It Doesn't)

Before recommending solutions, the gap must be understood precisely. The [time-manager-desktop](https://github.com/ammarshah1n/time-manager-desktop) repository is a Swift/SwiftUI macOS app with a deterministic scoring engine in `PlanningEngine.swift`, not a trained ML model. The current "ML" is a weighted formula:

```
score = importanceWeight(18×) + dueDatePressure + confidenceGap(12×) + effortWeight + sourceWeight + subjectPressure + recencyBoost + promptBoost
```

The weights are **hardcoded constants**. `TaskItem` stores `estimateMinutes`, `confidence`, `importance`, `completedAt`, and `isCompleted` — the completion history exists, but nothing reads it back to update future scores or estimates. The `PlannerStore` persists state via JSON snapshot to disk but there is no feedback loop: completing a task marks `isCompleted = true` and stores `completedAt`, but neither field is consumed by `PlanningEngine.rank()`.

**In plain terms: the product description says "ML time estimation that learns over 2–4 weeks" — but the learning loop doesn't exist yet.** The completion timestamps are collected but never used. This is actually good news: the data pipeline is already there, and the gap is a feedback consumer, not a data producer.

***

## The Cold-Start Problem, Precisely Stated

The cold-start problem for Timed has two distinct layers:

1. **Estimation cold-start** — `estimateMinutes` is user-provided at task creation (defaulting to 30 or 45 minutes in `ImportPipeline`). The EMA-based time learning described in the product spec doesn't yet exist. Until it does, every task estimate is a user guess, and the schedule quality depends entirely on how honest users are about their own time.

2. **Scoring cold-start** — `importance`, `confidence`, and `energy` are all static integers set at import. The `ImportPipeline` defaults `confidence = 3`, `importance = 3`, `energy = .medium` for all imported tasks — meaning every task starts with an identical mid-point score, and ranking is almost entirely deadline-pressure-driven until the user manually adjusts these values.

A trial user who imports their tasks, never adjusts the defaults, and runs a 14-day trial will see a schedule driven almost entirely by `dueDate`, because `importanceWeight × 18` and `confidenceGap × 12` cancel out when everything is `3/5`. The product's intelligence appears shallow because the behavioral signal hasn't been collected yet. Research confirms this pattern: cold-start is the dominant reason personalization systems underperform in early user sessions, with the challenge being to infer a high-dimensional preference vector from "strictly limited direct evidence".[^1]

***

## Strategy 1: Bootstrap from Outlook Calendar History on Day 1

This is the highest-leverage change available, and it requires no new ML infrastructure.

### What to Extract

The Outlook calendar (via Microsoft Graph) gives 90–180 days of event history on first connection. From this data, several behavioral signals can be inferred without the user doing anything:

| Signal | What to Extract | How to Use It |
|---|---|---|
| **Meeting density per day-of-week** | Count events by weekday | Adjust `windowMinutes` in `buildSchedule()` per day |
| **Meeting duration patterns** | Average duration by category (1:1s, standups, reviews) | Infer cognitive load before/after meeting blocks |
| **Focus block patterns** | Gaps ≥ 45 minutes in calendar | Learn when the user protects deep work time |
| **Day start / end time** | First and last calendar events per day | Infer active hours for the schedule window |
| **Recurring task patterns** | Weekly recurring events suggest routine tasks | Bootstrap `energy` assignment (morning = `.high`, post-lunch = `.low`) |
| **Meeting frequency with same people** | Frequent 1:1 clusters → management-heavy context | Adjust `sourceWeight` toward email-derived action items |

The key insight is that calendar history is **behavioral ground truth that already exists** — the user has been living their actual schedule for months. Capturing and parsing this at onboarding transforms the first day experience from "system knows nothing" to "system already has a model of your week".[^2]

Contextual bootstrapping — using metadata and contextual signals to infer preferences before behavioral data accrues — is established best practice for cold-start personalization. The calendar is the richest possible source of this metadata for an executive user.[^1]

### Implementation in Swift

The existing `CalendarExporter.swift` already has the EventKit plumbing. The onboarding bootstrap would:

```swift
// At first launch, after calendar permission is granted:
func bootstrapFromCalendarHistory(days: Int = 90) async -> UserBehaviourPrior {
    let events = await fetchPastEvents(days: days)
    
    let meetingLoadByDay = computeMeetingDensity(events)        // [Mon: 4.2, Tue: 6.1, ...]
    let activeHoursRange = inferActiveHours(events)              // e.g., 8am–6pm
    let focusSlotPattern = detectFocusBlocks(events)             // avg 2.3 × 45min blocks
    let energyCurve = inferEnergyPattern(events)                 // morning = high, post-lunch = low
    
    return UserBehaviourPrior(
        meetingLoad: meetingLoadByDay,
        activeHours: activeHoursRange,
        focusPattern: focusSlotPattern,
        energyCurve: energyCurve
    )
}
```

This prior then gets injected into `PlanningEngine.rank()` and `buildSchedule()` as initial weight adjustments. On Day 1, the schedule is already aware that Tuesday is a meeting-heavy day and Monday mornings are focus time — without the user ever configuring anything.

***

## Strategy 2: Active Preference Elicitation in the Voice Interview

The 90-second morning voice interview is currently described as generating a day plan. It should also be the **fastest preference signal collection mechanism** available.

### The Problem with Static Defaults

Every task imported via `ImportPipeline` receives `importance = 3`, `confidence = 3`, `energy = .medium`. The user is then expected to manually edit these values — which no one does. The voice interview is the natural place to surface the 3–5 highest-ambiguity tasks and ask the user to resolve them through conversation rather than form fields.

### Active Preference Elicitation via LLM

Research on cold-start preference elicitation shows that a two-phase protocol — static burn-in questions followed by adaptive targeted questions — is highly effective at inferring latent user preferences with minimal interactions. The key finding from recent research (Pep framework) is that the bottleneck in cold-start is not model capacity but whether the method exploits the **factored structure of preference data**. For Timed, this means: ask about one task to infer signals about a whole *class* of similar tasks.[^3][^1]

The morning voice session should do the following:

**Phase 1 (Week 1 only — burn-in):** Ask 2–3 high-information questions that resolve scoring ambiguity for the most common task types:
- *"You have a board prep task and a client email to handle. Which type of thing do you usually want off your plate first in the morning?"* → resolves the `importance` prior for admin vs. strategic work
- *"How long does a typical email response actually take you — the 5 minutes it looks like, or closer to 20?"* → seeds the EMA for email task estimates
- *"Do you prefer to tackle hard things first and coast into the afternoon, or warm up on easier tasks?"* → sets the `energy` scheduling preference

**Phase 2 (Ongoing):** For tasks in the day plan where `confidence` or `importance` is still at the default `3/5`, the AI surfaces the single most ambiguous task and asks one calibrating question:
- *"You've got 'Prepare for the budget review' on the plan. Is that a 30-minute scan or a 2-hour build?"*

This is exactly how voice onboarding has been shown to reduce interaction length and increase personalization quality: one study found pre-loading user context reduced onboarding duration from over 3 minutes to 1 minute 32 seconds, with 60% fewer questions asked. The mechanism is identical — start the conversation already knowing something, so questions focus on resolving genuinely unknown dimensions.[^4]

### Feedback as Implicit Signal

Every interaction the user takes after the morning plan is generated is an implicit preference signal that should update the scoring model:

| User Action | Signal | Model Update |
|---|---|---|
| Reorders tasks manually | Revealed preference for task A > task B | Adjust `importanceWeight` for that task type |
| Marks a task complete earlier than estimated | Task took less time than `estimateMinutes` | EMA update: reduce estimate for similar tasks |
| Skips a scheduled block | Task was over-scheduled or wrong time of day | Adjust `energy` assignment or time-of-day scoring |
| Ignores a "Do now" task all day | Score model overconfident | Reduce `dueDatePressure` weight for that source type |
| Completes a task significantly late | Underestimated complexity | Increase estimate baseline for that category |

None of these require a trained model — they are rule-based updates to the scoring constants in `PlanningEngine.swift`, triggered by observed behaviour in `PlannerStore`.

***

## Strategy 3: EMA Time Estimation — Building the Learning Loop

The product spec describes EMA-based time estimation that improves over 2–4 weeks. Here is the concrete implementation path using what's already in the data model.

### The Math

EMA for task duration estimation:

\[ \text{EMA}_t = \alpha \cdot \text{actual}_t + (1 - \alpha) \cdot \text{EMA}_{t-1} \]

Where `α` is the decay rate (typically 0.3–0.4 for fast adaptation, 0.1–0.15 for stable convergence). For task estimation, a value of `α = 0.3` means the most recent actual duration contributes 30% to the new estimate while 70% comes from history — fast enough to learn within 5–7 completions, stable enough not to overfit to one outlier session.[^5]

### What Needs to Change in the Code

**Step 1: Add `actualMinutes` to `TaskItem`** (in `Models.swift`):
```swift
struct TaskItem: ... {
    // existing fields ...
    var actualMinutes: Int?          // recorded when task is marked complete
    var estimateHistory: [Int]       // rolling window of last 10 actuals for same task category
}
```

**Step 2: Record actual duration in `PlannerStore.markTaskCompleted()`**:
```swift
func markTaskCompleted(_ task: TaskItem, now: Date = .now) {
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    
    // Calculate actual time from focus timer or session start
    let actualMinutes = focusTimerStore.elapsedMinutesFor(taskID: task.id) ?? task.estimateMinutes
    tasks[index].actualMinutes = actualMinutes
    tasks[index].isCompleted = true
    tasks[index].completedAt = now
    
    // Update EMA for this task category
    updateEstimateEMA(category: task.source, subject: task.subject, actual: actualMinutes)
    dismissedScheduleTaskIDs.insert(task.id)
    rebuildPlan(now: now)
}
```

**Step 3: Maintain per-category EMA priors in `PlannerStore`**:
```swift
// Keyed by (source, subject) tuple — e.g., ("email", "client") → 18 minutes
var estimatePriors: [String: Double] = [:]

func updateEstimateEMA(category: TaskSource, subject: String, actual: Int) {
    let key = "\(category.rawValue)-\(subject)"
    let alpha = 0.3
    let prior = estimatePriors[key] ?? Double(actual) // first observation seeds the EMA
    estimatePriors[key] = alpha * Double(actual) + (1 - alpha) * prior
}
```

**Step 4: Apply the learned prior at task creation time** in `ImportPipeline.swift` — instead of defaulting `estimateMinutes: 45` for all Seqta tasks, look up the EMA prior for that subject/source pair and use that as the initial estimate.

This closes the loop: tasks enter with a prior estimate, actual durations are recorded, the EMA updates the prior, and future tasks of the same type are pre-estimated from learned history rather than the hardcoded 30/45-minute defaults.

### Bootstrapping the EMA Before Day 1

The cold-start problem for the EMA specifically is: the first task has no prior. The bootstrap solution is a **category-level prior** drawn from empirical research and injected as initial values:

| Task Type | Empirical Prior | Source |
|---|---|---|
| Email response (short) | 12–18 minutes | Knowledge worker research |
| Email response (complex) | 25–35 minutes | Knowledge worker research |
| Meeting prep | 20–30 minutes | Calendar pattern inference |
| Deep work / document | 45–90 minutes | Pomodoro/focus timer research |
| Quick admin / approval | 5–10 minutes | Calendar gap analysis |

Research on task duration estimation consistently shows that people overestimate task duration by a median of ~45% — meaning the user's self-reported `estimateMinutes` will systematically run high. The EMA will naturally correct for this downward over 5–10 completions, but seeding the priors with empirically-grounded values (rather than user-reported values) will make the schedule more accurate from day one.[^6]

***

## Strategy 4: Thompson Sampling Warm-Start with Informative Priors

The product spec mentions Thompson sampling for task ordering. Thompson sampling requires a prior distribution over each action (task). The cold-start version of Thompson sampling operates with a **uniform prior** (Beta(1,1) for binary outcomes, or uniform Normal for continuous rewards) — meaning it has no preference between tasks until it observes outcomes.

The fix is an **informative prior** that encodes the calendar and preference signals collected above. Instead of Beta(1,1) (pure uncertainty), seed each task's prior based on:

- **Deadline proximity** → shift the prior toward higher reward for urgent tasks (already in `dueDatePressure`)
- **Time of day** → encode the energy curve from calendar bootstrap into the prior variance (high-energy tasks get a higher prior mean in morning slots)
- **Source archetype** → Seqta tasks historically have higher completion rates than chat-sourced tasks (`sourceWeight` exists but is static — this makes it dynamic)

In practice, for a personal productivity tool at this scale, Thompson sampling can be implemented without a full Bayesian engine. The existing scoring model *is* effectively a deterministic prior — the upgrade is to add observation-weighted posterior updates after each completed session, which is exactly what the EMA loop above provides. The Stanford Thompson sampling tutorial confirms that Beta distribution parameters `(α, β)` can be initialized from historical data rather than uniform priors, which is the warm-start approach.[^7]

***

## Strategy 5: Archetype-Based Onboarding (The Fast Track)

The highest-ROI change for MVP conversion is none of the above — it is **pre-loaded behavioural archetypes** that give the model an educated prior on day one, before any data is collected.

The concept: during onboarding, ask the user to select their closest archetype from 4–5 options (shown visually, not as a form). Each archetype pre-loads a different set of scoring weights into `PlanningEngine`:

| Archetype | Morning Energy | Meeting Load | Deep Work Preference | Default `importance` Skew |
|---|---|---|---|---|
| **The Operator** | High morning | 5–7/day | Short, frequent blocks | Operations/admin tasks higher |
| **The Builder** | Slow start | 2–3/day | Long uninterrupted blocks | Project/creation tasks higher |
| **The Executive** | Variable | 6–8/day | Pre/post meeting focus windows | Strategic tasks higher |
| **The Closer** | High all day | 4–5/day | Deadline-burst patterns | Deadline pressure amplified |

The user picks one in 15 seconds. The model immediately behaves like it knows them — not because it does, but because the archetype prior is a reasonable approximation that the EMA will refine over the following weeks.

This technique is well-supported: profile-based initialization — mapping user attributes to latent embedding spaces — is one of the core cold-start personalization strategies. The key is that it *feels* personal immediately (users see a schedule that matches their working style) even before any real learning has occurred.[^1]

***

## Voice Interview: Specific Prompt Architecture

The 90-second voice interview is the product's signature moment. It needs to do three things simultaneously:

1. **Generate the day plan** (current intended purpose)
2. **Collect preference signals** (missing today)
3. **Surface the model's visible intelligence** (so the user feels the product is already learning)

The voice interview prompt sent to Claude should be restructured. Instead of a generic planning prompt, it should follow this architecture:

**System context injected before the conversation:**
- Current ranked task list with scores and score reasons (already exists in `buildPlanningPrompt()`)
- Calendar events for today (already exists)
- **NEW:** Yesterday's completion history — which tasks were done, which were skipped, any timing deltas
- **NEW:** The user's archetype prior or any existing EMA estimates
- **NEW:** Top 2–3 tasks where `importance == 3 && confidence == 3` (default values = unknown preferences)

**Voice interview structure (90 seconds):**
- **0–15s:** AI opens with a specific observation about today: *"You've got a board presentation and 6 meetings today — that's your heaviest Tuesday in 3 weeks. Your one real focus window is 8–9:30am."*
- **15–50s:** User describes tasks, mood, and priorities in natural speech
- **50–75s:** AI asks ONE targeted clarifying question about the most ambiguous task: *"The board deck — is that final polish or still being built?"*
- **75–90s:** AI delivers the plan and *names the model's reasoning explicitly*: *"I'm ranking the deck first because it's your highest-stakes deliverable and your energy tends to peak before your first call."*

This last element — narrating the model's reasoning — is crucial for perceived intelligence and trial conversion. It makes the algorithm legible to the user without requiring them to inspect scores. Research on AI-assisted work shows adherence to AI recommendations increases over time when users understand the reasoning, with durable productivity gains even when AI is unavailable.[^8]

***

## What to Build First: Prioritised Implementation Order

Given the current codebase state, this is the recommended build sequence to maximise conversion improvement per engineering hour:

| Priority | Change | Time to Build | Conversion Impact |
|---|---|---|---|
| **1** | Archetype picker at onboarding → pre-load scoring weights | 1–2 days | High — immediate "wow" moment on day 1 |
| **2** | Calendar history bootstrap (day-of-week patterns, active hours) | 2–3 days | High — schedule feels accurate from day 1 |
| **3** | Voice interview narrates score reasoning explicitly | 1 day | Medium-high — builds trust in the model |
| **4** | `markTaskCompleted()` records `actualMinutes` from focus timer | 1 day | Medium — enables EMA but needs data accumulation |
| **5** | Per-category EMA prior in `PlannerStore` | 1–2 days | Medium — payoff accelerates after week 1 |
| **6** | Morning interview collects implicit preference signals | 2–3 days | Medium — compounding benefit over time |
| **7** | Thompson sampling posterior updates | 3–5 days | Lower (MVP) — EMA is sufficient for MVP |

The first two items alone transform the trial experience: a user who selects "The Executive" archetype and connects their Outlook calendar will see a schedule on day 1 that reflects their actual meeting load and focus windows. The product *appears* to already know them — which is the entire goal.

***

## Summary: What "Day 1 Intelligence" Looks Like

With these changes implemented, the first morning session for a new user would proceed as follows:

1. **Onboarding (2 minutes):** Select archetype → connect Outlook → calendar history is parsed in the background
2. **First morning interview:** AI opens with a specific, accurate observation about their day based on calendar data; asks one preference-resolving question; delivers a plan that accounts for their meeting load and peak energy window
3. **During the day:** Focus timer records actual task durations; task completions update the EMA; reordering and skip behaviour updates importance priors
4. **By end of day 3:** The EMA has at least 5–8 data points; estimate accuracy is already improving; the morning interview questions become progressively more specific
5. **By end of week 2:** The model has enough completions to produce noticeably personalised estimates; the archetype prior is being overwritten by real behaviour

This compresses the "2–4 weeks to personalisation" timeline described in the original product spec down to **3–5 days for meaningful personalisation** and **day 1 for contextual awareness** — which is the difference between a trial user churning at day 7 and converting at day 14.[^2][^1]

---

## References

1. [Cold-Start Personalization Approaches - Emergent Mind](https://www.emergentmind.com/topics/cold-start-personalization) - Cold-start personalization refers to the task of providing personalized recommendations, responses, ...

2. [Mastering Cold Start Challenges: Top Strategies for Personalized AI ...](https://www.shaped.ai/blog/mastering-cold-start-challenges) - Cold start challenges can derail personalization efforts by making it difficult to deliver relevant ...

3. [Cold-Start Personalization via Training-Free Priors from Structured ...](https://arxiv.org/html/2602.15012v1) - Cold-start personalization requires inferring user preferences through interaction when no user-spec...

4. [Voice Onboarding Sucks: We Cut It in Half with User Context (50 ...](https://www.reddit.com/r/AgentsOfAI/comments/1rht62v/voice_onboarding_sucks_we_cut_it_in_half_with/) - How it actually works (three layers of context pulled from the Onairos API and injected into the pro...

5. [Exponential Moving Average (EMA) Explained - Strategies and Tips](https://www.earn2trade.com/blog/exponential-moving-average/) - Exponential Moving Average or EMA is an advanced version of the simple average that weighs the most ...

6. [Time-on-task estimation for tasks lasting hours spread over multiple ...](https://pmc.ncbi.nlm.nih.gov/articles/PMC12445496/) - In this work, we take advantage of this new measurement method to explore duration estimation of tas...

7. [[PDF] A Tutorial on Thompson Sampling - Stanford University](https://web.stanford.edu/~bvr/pubs/TS_Tutorial.pdf) - ABSTRACT. Thompson sampling is an algorithm for online decision prob- lems where actions are taken s...

8. [Generative AI at Work* | The Quarterly Journal of Economics](https://academic.oup.com/qje/article/140/2/889/7990658) - Our findings show that access to generative AI suggestions can increase the productivity of individu...

