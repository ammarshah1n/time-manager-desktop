# Timed ML Audit — Competitive Analysis & Improvement Roadmap

## Executive Summary

Timed's three learning loops are architecturally sound but operate with signals that are 1–2 generations behind what competitors have deployed. The email classifier (Loop 1) is correct-by-rule, not learned-by-pattern. The time estimator (Loop 2) matches by exact sender address — an approach that suffers constant cold-start for a single-user app with high sender variety. The behaviour engine (Loop 3) runs weekly on a batch of 200 events — too slow to correct a bad planning week before the next one begins. The scoring model is a well-calibrated linear sum that works today but has a hard ceiling because it ignores time-of-day energy, task interaction effects, and completion-rate feedback. Crucially, the schema is already ahead of the application code: `tasks.embedding vector(1536)`, `email_messages.embedding vector(1536)`, and `behaviour_events.hour_of_day` are all defined and indexed — they just need to be populated and queried.

***

## 1. Competitor ML Comparison

### How Each Competitor Actually Learns

| Competitor | Core ML Technique | Primary Signal | What Timed Lacks vs Them |
|---|---|---|---|
| **SaneBox** | Header-only Bayesian + sender fingerprinting | Open rate, reply rate, archive rate, folder drags — metadata only, never body[^1][^2] | SaneBox tracks *interaction frequency* per sender, building a soft importance score. Timed's `sender_rules` table is binary (inbox_always / black_hole) with no gradient [^2] |
| **Reclaim.ai** | Priority × deadline × availability window; rule-based habit rescheduling | Calendar availability, user-set priority, time-window preferences[^3][^4] | Reclaim auto-reschedules when conflicts appear and records when habits get moved, updating time-window preferences[^4]. Timed has no concept of placing tasks in calendar time slots at all |
| **Motion** | Constraint satisfaction (deadline-backward scheduling), greedy task-to-slot assignment | Deadline, duration, priority, calendar gaps[^5][^6] | Motion reasons backward from deadlines ("a 3hr task due Friday needs to start by Wednesday")[^5]. Timed's greedy knapsack does not do temporal placement — it selects *which* tasks to do, not *when* today |
| **Clockwise** | Constraint satisfaction + reinforcement learning + neural networks for meeting clustering[^7] | Calendar patterns, how user reschedules, focus-time goals | Clockwise tests millions of calendar arrangements and learns from reschedule behaviour[^8][^7]. Timed has no focus-block defence or meeting-cluster reasoning |
| **Superhuman** | Hybrid BM25 + vector search over 5+ years of email; sentiment + urgency detection on body; social graph[^9][^10] | Email body content, sender relationship depth, reply tone, thread velocity[^10] | Superhuman reads the body and uses embedding-based semantic retrieval for context[^9]. Timed's `classify-email` only reads subject + 2000-char snippet; `email_messages.embedding` is defined but not populated |
| **Todoist Smart Schedule** | Deep learning trained on aggregate user base + individual history; task clustering by importance[^11] | Individual completion history + population-level task importance signals[^12][^11] | Todoist cross-references individual behaviour against millions of users. By design Timed is single-user — crowd signals are unavailable — but Todoist's individual learning (pattern → suggested day) is still ahead of Timed's estimate-by-category default |

### What No Competitor Does That Timed Does

- **Voice-native morning interview**: none of the above competitors have a hands-free, voice-driven planning ritual. This is a genuine moat.
- **DishMeUp context-aware task serving** (desk/transit/flight modes): no direct equivalent exists in any listed competitor.
- **Three-tier estimation with prompt-cached LLM fallback**: Timed's `estimate-time` function  is more cost-efficient and transparent than any competitor discloses.
- **Confidence-weighted behaviour rules fed into a deterministic scoring function**: traceable, auditable, and debuggable in a way that competitor black-box schedulers are not.

***

## 2. Deep Evaluation of the Three Learning Loops

### Loop 1 — Email Classification

**Architecture (what it does)**

`classify-email/index.ts`  runs Claude Haiku 4.5 with a system-prompt cached at Anthropic's server. The user message contains the last 15 triage corrections as few-shot examples, any matching `sender_rules`, and the email's subject + snippet. It returns one of four buckets: `inbox`, `later`, `black_hole`, `cc_fyi`.

**Is 15 corrections enough?**

For a 4-class problem using a state-of-the-art LLM in few-shot mode, 15 total examples averages to ~3-4 per class — which is marginal. Active learning research on text classification shows that performance improves sharply between 10–50 labeled examples per class, plateauing around 50–100. With 15 total examples across 4 classes, the model is relying on its pre-training to do the heavy lifting, not on user-specific examples. In practice this means:[^13][^14]

1. The few-shot examples only prevent regressions on senders the user has already corrected.
2. Novel sender patterns (new job, new vendor) start from the model's priors, which may be wrong.
3. There is no mechanism to detect when the model is *uncertain* — all classifications are treated equally.

**How SaneBox's sender fingerprinting compares**

SaneBox builds a continuous importance score per sender from five implicit signals: open rate, reply rate, archive rate, response time, and drag-to-folder corrections. This is fundamentally different from Timed's binary `sender_rules` (inbox_always / black_hole). SaneBox's gradient allows it to represent "this sender is usually important but occasionally sends noise" — something Timed cannot currently express. The key insight is that SaneBox's training signal is *zero-effort* (it fires on any interaction), whereas Timed's training signal is *high-effort* (requires a conscious drag-to-correct).[^1][^2]

**Should we use embeddings instead?**

The schema already provisions `email_messages.embedding vector(1536)` with an IVFFlat cosine index. The comment in the migration confirms the intent: "for correction retrieval (few-shot similarity)". The `classify-email` function does not yet use this index — it pulls the 15 most-recent corrections by date, not by semantic similarity to the current email. Switching to embedding-based retrieval would:
- Select the 15 *most similar* past corrections rather than the 15 *most recent*
- Dramatically improve few-shot quality for novel-but-similar emails
- Cost one embedding call per classification (~$0.00002 for `text-embedding-3-small`)

Fine-tuning a small classifier model is **not** recommended at this stage — single-user data volume (hundreds of corrections per year) is far below the fine-tuning threshold for any modern text model.

**What to add: implicit signals (zero-effort learning)**

Add a `sender_reply_latency_minutes` computed column to `sender_rules`, updated whenever the user sends a reply to that sender's email. Senders the user replies to in under 2 minutes are almost certainly important — no explicit correction needed. This mirrors SaneBox's reply-rate signal without requiring body access.

***

### Loop 2 — Time Estimation

**Architecture (what it does)**

`estimate-time/index.ts`  is a three-tier cascade:
1. Historical match: `estimation_history` filtered by `workspace_id + profile_id + bucket_type + from_address`, requires ≥2 sender-specific records or ≥3 bucket records, returns an exponentially-weighted average of `actual_minutes`.
2. Claude Sonnet fallback: passes title, description, bucket type, and category default to the model.
3. Category default: hardcoded constants (reply_email: 2min, action: 30min, etc.).

**Is bucket_type + sender too coarse?**

Yes, for actions and reads — the two buckets with the highest variance. Consider:
- `reply_email` from a specific sender: sender match is appropriate. A reply to a known vendor is consistently 2min.
- `action` bucket: tasks named "Review Q1 board deck", "Call lawyer re: contract", "Fix deployment pipeline" all land in `action` but have wildly different durations. Bucket + sender is meaningless for this bucket.

The schema already provisions `tasks.embedding vector(1536)` with an IVFFlat cosine index and `estimation_history.title_tokens text[]` for "structured matching" — but neither field is populated or queried in `estimate-time`. The vector index is the right answer for `action` bucket tasks: embed the task title and retrieve the 5 most cosine-similar completed tasks by their `actual_minutes`.

**Convergence speed vs Motion/Reclaim**

Motion and Reclaim do not expose duration estimation learning — they rely on user-set durations and track slippage to generate warnings but do not auto-correct. Timed's three-tier system will converge faster *per bucket* than any competitor because it starts from an LLM prior on day one. However, the `action` bucket will remain inaccurate indefinitely without embedding similarity, because the category default (30min) is a weak prior and sender matching rarely applies to action items.

**Bayesian upgrade path**

Replace the exponential weighted average with a Gaussian conjugate prior. For each `(bucket_type, title_embedding_cluster)` combination, maintain a running `(μ, σ²)` over `actual_minutes`. Each new completion updates:

\[ \mu_n = \frac{\sigma_0^2 \bar{x}_n + \sigma_n^2 \mu_0}{\sigma_0^2 + \sigma_n^2} \]

where \( \mu_0 \) is the category default and \( \sigma_0^2 \) is the initial uncertainty. This gives you:
1. A posterior mean (use as estimate)
2. A credible interval (use to flag high-uncertainty tasks to the morning interview)
3. Natural warm-start from category defaults with graceful convergence to personal history

This is implementable as a simple update to the `weightedAverage` function in `estimate-time/index.ts`  — no model change required.

***

### Loop 3 — Behaviour Inference

**Architecture (what it does)**

`generate-profile-card/index.ts`  is a weekly pg_cron job (Sunday 02:00 UTC) that assembles up to 200 behaviour events + 50 completion records from the last 90 days, passes them to Claude Opus 4.6 with a prompt-cached system instruction, and receives a JSON blob of `profile_summary` + typed rules (scheduling / avoidance / estimation / context). Rules are upserted into `behaviour_rules` by matching on `rule_text`.

**Is weekly too slow?**

For a single-user executive app: yes, in two scenarios. First, if the user works a pattern for 3 days that diverges from their established rules (e.g., switches to morning calls during a travel week), the planning engine will apply stale rules for up to 6 more days before Opus corrects them. Second, and more importantly, the `confidence` field is only updated when Opus runs — there is no confidence decay between runs. A rule inferred from March behaviour that has been contradicted by April events will still carry its March confidence until the next Sunday.

**What Reclaim's "habits" do differently**

Reclaim's habits update their time-window preferences immediately when the user moves a habit event. The rescheduling algorithm re-evaluates the window the moment a conflict is detected. This is not a weekly batch — it is event-driven. For Timed, the equivalent would be: when a `plan_order_override` or `task_deferred` event fires, immediately increment/decrement the `confidence` of any `ordering` rule that was contradicted, without waiting for Opus. This costs zero AI tokens.[^4]

**Real-time rule updates (zero-LLM path)**

The following rule types can be updated deterministically on each behaviour event, without calling Opus:

- `ordering` rules: if user moves task of bucket A above bucket B, bump bucket A's ordering confidence +0.05; cap at 1.0.
- `avoidance` rules: if task is deferred for the third time, create/update an avoidance rule with confidence proportional to `deferred_count / 10`.
- `timing` rules: if `hour_of_day` is consistently < 10 for `calls` completions, upsert a timing rule "calls in morning" with confidence growing per data point.

The weekly Opus run should be retained for *new* rule synthesis — discovering patterns the deterministic rules cannot catch — but the above three rule types should not wait for Opus.

**Energy curve: the `hour_of_day` signal is being collected and ignored**

`behaviour_events.hour_of_day` is defined, indexed, and populated. The `PlanningEngine` does not read it. Chronotype-task alignment research confirms that creative and executive function tasks performed at off-peak energy times show measurably worse outcomes. A simple histogram of `task_completed` events by `hour_of_day × bucket_type` would produce a per-bucket hourly preference score that could be added as a `timingBump` component in `scoreTask()` — a pure additive term requiring no ML.[^15][^16]

***

## 3. Scoring Model Evaluation

### Current Model

`PlanningEngine.scoreTask()`  computes:

\[ \text{score} = \text{bucketBase} + \text{priorityBase} + \text{quickWin} + \text{durationPenalty} + \text{overdueBump} + \text{deadlineBump} + \text{moodBump} + \text{behaviourBump} \]

All terms are additive. The knapsack is greedy (score descending, fill until budget exhausted). The model is deterministic and pure — no I/O, no async — which is a significant engineering virtue.

### Is this too naive?

For a single executive user who reviews the plan every morning, a linear weighted sum is **not** too naive — it is appropriate. The morning interview's manual confirmation step provides a correction layer that would be redundant in a fully automated system. The real gaps are in what signals are *missing from* the scoring function, not in the aggregation method itself.

**What the current model misses:**

1. **Time-of-day energy**: calls at 9am score the same as calls at 4pm, despite `hour_of_day` data showing the user completes calls earlier.
2. **Completion-rate feedback**: the overdue/deferred signals are proxies for completion failure, but `CompletionRecord` data (actual vs estimated, completion rate per bucket) is not fed back into scoring weights.
3. **Interaction effects**: `deepFocus` mode kills non-action tasks with a -9999 penalty (correct) but does not *boost* action tasks by relative urgency within the focus session.
4. **Context-switching cost**: the 5-minute buffer between tasks is fixed. A transition from `calls` → `read` is cognitively cheaper than `calls` → `action`. This could be a small additive term based on bucket transition type.

### Should we use RL, neural ranking, or constraint satisfaction?

**Multi-armed bandit / Thompson sampling**: Appropriate for exploration when the reward function is unknown and you want to discover which task types produce the highest completion rate. For a single user doing ~5–10 tasks/day, convergence to a stable policy takes roughly 30–60 days. Thompson sampling over bucket types (with completion-rate as reward) is a low-risk, tractable upgrade with real payoff once ≥50 completions are logged.[^17][^18]

**Reinforcement learning (completion rate as reward)**: Full RL (policy gradient, Q-learning) is overkill for a single user. The signal is too sparse (1 plan per day = 1 update) and the state space (task backlog × calendar × mood) is large enough that sample complexity would preclude convergence. Not recommended.

**Neural ranking models**: Not warranted. Neural ranking (LambdaRank, etc.) requires thousands of preference pairs to train effectively. A single executive will not generate that data volume within a product lifetime.

**Constraint satisfaction (Motion-style)**: Worth adding as an *optional* layer on top of the existing knapsack — specifically, the "can't do X before Y is done" dependency chain signal and "no calls after 4pm per user preference" hard constraint. These are not ML problems — they are constraint problems, and the greedy knapsack already handles them if the score constants are set correctly. Motion's genuine advantage is calendar slot assignment (temporal placement), which is a different problem from Timed's score-then-knapsack approach.[^5]

**Recommendation**: Keep the linear weighted sum + greedy knapsack. Add `timingBump` from the `hour_of_day` histogram and a lightweight Thompson sampler over bucket completion rates as the next scoring layer. This delivers the highest accuracy per implementation hour.

***

## 4. Missing Signals — Priority Analysis

### Signal Inventory

| Signal | Data Required | Currently Collected | Effort to Add | Expected Impact |
|---|---|---|---|---|
| **Sender reply latency** | `email_messages.received_at`, `replied_at` | `received_at` only | Low — add reply timestamp to Graph sync | High for email classification |
| **Thread velocity** | Message count × time-window per thread | Not tracked | Medium | Medium for urgency scoring |
| **Hour-of-day energy curve** | `behaviour_events.hour_of_day × bucket_type` | **Already collected** | Very low — query existing data | High for plan ordering |
| **Calendar meeting fatigue** | Meeting duration + count before focus block | `CalendarBlock` available in app | Low — add pre-block meeting load signal | Medium |
| **Task dependency chains** | Explicit predecessor/successor links | Not in schema | High — requires UI changes | Medium (niche use) |
| **Interruption patterns** | Mid-task context switches | Not tracked | Medium — requires active session tracking | Low–medium |
| **Estimate correction patterns** | `estimate_override` events + delta | `estimate_override` event exists | Low — compute in `generate-profile-card` | High for Loop 2 |
| **Email social graph (reply rate per sender)** | `replied_to_address` on outbound emails | Not tracked | Medium — add to Graph sync | High for Loop 1 |

**Most impactful gap**: The social graph. Timed classifies emails without knowing whether the user *replies to* that sender. SaneBox's entire learning edge comes from this signal. A sender the user replies to in <2 minutes is implicitly `inbox_always`. A sender the user never replies to is implicitly `later`. This can be inferred from the existing Graph delta sync (`EmailSyncService`) by tracking outbound reply-to addresses.[^2][^1]

***

## 5. Concrete Improvements Ranked by Impact × Implementation Effort

The following improvements are ranked for a single-executive product where the bottleneck is data volume, not compute.

### Rank 1 — Populate `tasks.embedding` + Use in `estimate-time` (High Impact / Low Effort)

**What**: Generate a `text-embedding-3-small` embedding on task creation (or on first edit). In `estimate-time`, when no sender match is found, execute a `<->` cosine similarity search against `estimation_history` filtered to completed tasks, returning the top 5 neighbours and their `actual_minutes`.

**Why now**: The IVFFlat index is already built. The `estimate-time` function already has the OpenAI client available (Anthropic SDK is imported; swapping to OpenAI embedding is one import). This replaces the category default (30min for `action`) with a semantically-informed prior for every novel task. Expected estimation error reduction for `action` bucket: 30–50%.

**Code change**: ~40 lines in `estimate-time/index.ts`.

### Rank 2 — Energy Curve from `hour_of_day` (High Impact / Very Low Effort)

**What**: Add a new `rule_type: "timing"` to `generate-profile-card`. The Opus prompt already receives behaviour events with `hour_of_day` — the prompt just needs to be told to emit timing rules in the format: `{"bucket_type": "calls", "preferred_hour_range": [8, 11], "confidence": 0.8}`. In `PlanningEngine.scoreTask()`, add a `timingBump` that reads timing rules and applies a score multiplier when the current hour falls within the preferred range.

**Why now**: This is the only signal where the data is already there, the infrastructure is already there (behaviour_rules table, confidence-weighted scoring), and the gap vs competitors (Clockwise, Reclaim) is most visible to the user.

**Code change**: ~20 lines in `generate-profile-card/index.ts` (prompt update) + ~30 lines in `PlanningEngine.swift`.

### Rank 3 — Real-Time Rule Updates on Task Completion (Medium-High Impact / Low Effort)

**What**: When a `task_completed` or `task_deferred` event is written to `behaviour_events`, fire a lightweight Supabase database function (not an LLM call) that:
1. Increments the `confidence` of any matching `ordering` rule by `+0.05`.
2. Decrements the `confidence` of contradicted `ordering` rules by `−0.03`.
3. For `task_deferred` with `deferred_count >= 2`, upserts an `avoidance` rule.

**Why now**: This reduces Loop 3 lag from up to 7 days to minutes, with zero API cost. The weekly Opus job becomes a *synthesis* job (discovering new patterns) rather than the sole update mechanism.

**Code change**: One Supabase database trigger function (~60 lines SQL/PL/pgSQL).

### Rank 4 — Reply Latency Social Graph for Email (High Impact / Medium Effort)

**What**: Extend `EmailSyncService` to track outbound replies: when the Graph delta returns a sent message with `inReplyToId`, record `(from_address: recipient, reply_latency_minutes: elapsed)` in a new `sender_signals` table or extend `sender_rules`. In `classify-email`, pass reply latency as a signal alongside the existing sender_rules lookup.

**Why now**: This is the core signal SaneBox uses and Timed currently has nothing comparable. A sender the user routinely replies to within 5 minutes should be `inbox_always` even without an explicit correction. This reduces the correction burden on the user.

**Code change**: ~80 lines in `EmailSyncService.swift` + schema extension + `classify-email` prompt update.

### Rank 5 — Active Learning for Email (Medium Impact / Medium Effort)

**What**: Track `triage_confidence` per classification. When confidence falls below 0.65 for an email, surface a passive "Was this right?" nudge in the triage UI (not a blocking dialog). Store the response as a `triage_correction` regardless of whether the user agrees or disagrees. This selectively grows the correction dataset on uncertain edges rather than uniformly.

**Why now**: Research on active few-shot learning shows that selecting uncertain samples for annotation achieves equivalent accuracy with 3–5× fewer labels than random selection. This is especially valuable because corrections are cognitively expensive for an executive user.[^14][^13]

**Code change**: Confidence threshold check in email triage UI + nudge component (~50 lines Swift + `classify-email` already returns confidence).

### Rank 6 — Bayesian Time Estimation with Uncertainty Intervals (Medium Impact / Medium Effort)

**What**: Replace the exponential weighted average in `weightedAverage()` with a running `(μ, σ²)` Gaussian estimate stored in a new `estimation_priors` table or in `estimation_history` aggregate columns. Surface uncertainty intervals in the morning interview's Step 2 (estimate review) — high-σ tasks get a "⚠ uncertain" flag prompting user override.

**Why now**: The morning interview already has an inline stepper for estimate overrides — this makes the uncertainty visible rather than silent. The Bayesian update is computationally trivial.

**Code change**: ~40 lines in `estimate-time/index.ts` + schema column addition + UI flag in `MorningInterviewPane.swift`.

### Rank 7 — Thompson Sampling for Bucket Ordering (Medium Impact / High Effort)

**What**: For each `(bucket_type, hour_range)` combination, maintain a Beta(α, β) distribution where α = completions and β = deferrals. When generating the plan, sample each bucket's expected completion probability and use it as a multiplier on the existing score. This creates exploration (occasionally trying a bucket at a non-preferred time) without destroying the deterministic scoring guarantees.

**Why now**: This is the right long-term architecture for the scoring model, but it requires ~50 days of completion data to produce meaningful per-bucket per-hour estimates. It should be implemented after Rank 2 (energy curve) has been running for a month.

**Code change**: New `bucket_completion_stats` table + Thompson sampling in `PlanningEngine` or a new edge function that returns sampled scores.

***

## 6. What Competitors Cannot Copy

The ML analysis reveals three structural advantages in Timed's architecture that competitors have not matched:

1. **Ground-truth actual minutes**: `CompletionRecord` captures `actualMinutes` at task completion. Motion and Reclaim track whether a task was done, not how long it actually took. This is the foundation for all time estimation improvements above.

2. **Mood-as-context at plan generation**: The `MoodContext` enum (easy_wins / avoidance / deep_focus) feeds directly into scoring at plan time. No competitor offers this as a first-class planning primitive. It is also the key signal for chronotype-aligned scheduling if combined with the energy curve.

3. **Causal chain from event to plan**: `behaviour_events` → `behaviour_rules` → `PlanningEngine.behaviourBump` is a fully traceable pipeline. When a plan is wrong, you can audit which rule caused it. Clockwise and Motion are black boxes to the user. This auditability is a product moat for an executive who needs to trust the system.

---

## References

1. [SaneBox Privacy Review: Hacking the Hedonic Treadmill of Inbox ...](https://baizaar.tools/sanebox-privacy-review-hedonic-adaptation/) - What it is: SaneBox is a privacy-first email sorting tool that analyses only message headers (sender...

2. [How does SaneBox determine trainings?](https://www.sanebox.com/help/186-how-does-sanebox-determine-trainings) - SaneBox uses a combination of artificial intelligence (AI) and your own actions to determine how to ...

3. [How Reclaim manages your schedule automatically](https://help.reclaim.ai/en/articles/6207587-how-reclaim-manages-your-schedule-automatically) - Reclaim automatically schedules and reschedules events on your calendar, so you don't have to manual...

4. [Introducing Habits: smart, automatic time blocking for your routines](https://reclaim.ai/blog/block-time-automatically-habits-routines) - When you create a Habit, Reclaim analyzes your calendar for the next three weeks to see what your sc...

5. [Is Motion Worth It? Honest Review of the AI Calendar App (2026)](https://get-alfred.ai/blog/is-motion-worth-it/) - Motion auto-schedules tasks into your calendar. The algorithm is impressive. But it only works if yo...

6. [Motion AI Review: AI Calendar Support For Executive Functioning](https://lifeskillsadvocate.com/blog/motion-ai-review/) - Motion's AI Tasks can then create, prioritize, and schedule tasks onto your calendar based on deadli...

7. [AI Clockwise Full Report | PDF | Project Management - Scribd](https://www.scribd.com/document/975632147/AI-Clockwise-Full-Report) - Clockwise employs a combination of constraint satisfaction algorithms, reinforcement learning, and n...

8. [Boost Productivity with Clockwise Calendar Management - LinkedIn](https://www.linkedin.com/posts/tech-retriever_your-calendar-is-secretly-stealing-your-focus-activity-7407744491857645568-DTxL) - Clockwise changes that. Here's how: • Proactive Calendar Management: Optimizes your schedule daily, ...

9. [Superhuman Mail trusts 5x more emails to turbopuffer](https://turbopuffer.com/customers/superhuman) - Superhuman Mail trusts 5x more emails to turbopuffer. Superhuman Mail's previous vector database was...

10. [Why Smart Leaders Choose AI Email Management Over Manual ...](https://blog.superhuman.com/ai-email-management/) - According to our productivity research, Superhuman customers who use AI save 37% more time than thos...

11. [Todoist Launches Smart Schedule, an AI-Based Feature to ...](https://www.macstories.net/news/todoist-launches-smart-schedule-an-ai-based-feature-to-reschedule-overdue-tasks/) - Smart Schedule is a complementary scheduling feature that works with overdue tasks and tasks that ha...

12. [Todoist uses machine learning to predict your task due dates](https://techcrunch.com/2016/11/16/todoist-uses-machine-learning-to-predict-your-task-due-dates/) - Popular task-management service Todoist wants to help you reschedule your tasks and even out the wor...

13. [[2502.18782] Active Few-Shot Learning for Text Classification - arXiv](https://arxiv.org/abs/2502.18782) - We propose an active learning-based instance selection mechanism that identifies effective support i...

14. [[PDF] Active Few-Shot Learning for Text Classification - ACL Anthology](https://aclanthology.org/2025.naacl-long.340.pdf) - Our contributions can be summarized as follows: 1) We introduce an Active Learning-based sample sele...

15. [What's Your Chronotype? How Brain Science Can Boost Performance](https://knowledge.wharton.upenn.edu/article/whats-your-chronotype-how-brain-science-can-boost-performance/) - ... researchers explored how the time of day affects creative performance. Employees completed a chr...

16. [[PDF] The alignment between chronotype and time of day](https://ink.library.smu.edu.sg/cgi/viewcontent.cgi?article=7688&context=lkcsb_research) - A closer look at studies on the alignment between chronotype and time of day for task performance pr...

17. [[PDF] Learning to Schedule Online Tasks with Bandit Feedback - IFAAMAS](https://www.ifaamas.org/Proceedings/aamas2024/pdfs/p1975.pdf) - Bandit Algorithms. Cambridge Uni- versity Press. [25] Haifang Li and Yingce Xia. 2017. Infinitely Ma...

18. [Multi-armed bandit - Wikipedia](https://en.wikipedia.org/wiki/Multi-armed_bandit) - The multi-armed bandit problem is a classic reinforcement learning problem that exemplifies the expl...

