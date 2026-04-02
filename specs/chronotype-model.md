# Chronotype Inference Model Spec

**System:** Timed — Cognitive Intelligence Layer for C-Suite Executives
**Layer:** Semantic Memory (derived from episodic observations)
**Models:** Haiku 3.5 (real-time signal collection), Sonnet (daily aggregation), Opus (nightly synthesis)
**Stack:** Swift 5.9+, CoreData, Supabase, Claude API
**Status:** Implementation-ready

---

## 1. Purpose

Detect the executive's actual cognitive performance curve from observed behaviour — not self-report, not population averages, not chronotype questionnaires. Build a per-task-type performance model that maps time-of-day to cognitive effectiveness, updated continuously as patterns shift.

This feeds directly into the morning briefing ("Your sharpest analytical window today is 9:15-11:00 — the board deck belongs there") and the scheduling engine (never place strategic work in a measured trough).

---

## 2. Scientific Foundation

### 2.1 Circadian Performance Variation

**Core research:**
- Wieth & Zacks (2011): Analytical problem-solving peaks during circadian-optimal times; insight/creative problems peak during non-optimal times (the "inspiration paradox"). This is critical — creative and analytical peaks are phase-shifted.
- Hasher, Zacks & May (1999): Inhibitory control follows circadian rhythm. Morning types show peak inhibition (and therefore analytical performance) in morning hours; evening types in evening hours.
- Valdez et al. (2012): Attention, working memory, and executive function all follow measurable circadian curves with 2-4 hour peak windows.
- Schmidt et al. (2007): Chronotype accounts for ~15-20% of variance in cognitive task performance by time-of-day.

**Key insight:** Performance curves are NOT flat bell curves with one peak. They are multi-modal and task-type-dependent. An executive may peak analytically at 9:30am but peak creatively at 3:00pm. These must be modelled independently.

### 2.2 Chronotype Inference from Behavioural Signals

**Research basis:**
- Roenneberg et al. (2003, MCTQ): Mid-sleep point is the gold standard for chronotype. We cannot observe sleep directly, but we can infer sleep-wake timing from first-activity and last-activity timestamps.
- Murnane et al. (2015): Smartphone usage patterns predict chronotype with r > 0.7. First unlock time, peak usage windows, and late-night activity are the strongest predictors.
- Wharton School research (Gunia et al., 2014): Morning people make better ethical decisions early; evening people make them late. Decision quality varies by alignment between chronotype and time-of-day.

**For Timed:** We have richer signals than smartphone studies — email timestamps, calendar patterns, task completion velocity, focus session data. Expected chronotype inference accuracy: r > 0.8 within 2 weeks.

### 2.3 Ultradian Rhythms

- Kleitman's Basic Rest-Activity Cycle (BRAC): ~90-120 minute oscillations in alertness. Partially supported by modern research (Ericsson et al., 1993 — expert performers work in ~90 minute blocks).
- For Timed: detectable from focus session durations, email burst patterns, and app-switch rate periodicity. Not primary — but useful as a refinement layer on top of the circadian curve.

---

## 3. Signal Sources

### 3.1 Primary Signals (high confidence, available day 1)

| Signal | Source | What It Measures | Collection Method |
|--------|--------|-----------------|-------------------|
| Task completion velocity | CoreData `CompletedTask` | Time-to-complete by task type by hour | `PlanningEngine.markTaskCompleted()` records `startedAt`, `completedAt`, `estimatedDuration`, `actualDuration`, `taskCategory` |
| Focus session duration | CoreData `FocusSession` | Natural focus block length by hour | Focus timer records `startTime`, `endTime`, `interruptions`, `taskCategory` |
| Email response latency | Microsoft Graph | Time from email receipt to response, by hour | `EmailSyncService` delta sync captures `receivedDateTime` and `sentDateTime` for reply pairs |
| Email response quality proxy | Microsoft Graph + Haiku | Response length, draft-delete count, revision count by hour | Haiku classifies response effort: quick-reply vs considered-response vs multi-draft |
| First meaningful activity | App lifecycle + email | Daily "cognitive start" time | First non-trivial action (not just opening the app — first email sent, first task started, first focus session begun) |
| Last meaningful activity | App lifecycle + email | Daily "cognitive stop" time | Last non-trivial action before extended inactivity |

### 3.2 Secondary Signals (medium confidence, enrich over time)

| Signal | Source | What It Measures |
|--------|--------|-----------------|
| App-switch rate by hour | NSWorkspace notifications | Attention fragmentation as inverse performance proxy |
| Calendar whitespace usage | Outlook calendar | Whether the executive uses free blocks for deep work or frittering |
| Voice session energy | Apple Speech (morning interview) | Vocal energy, speech rate, pause patterns at session time |
| Meeting engagement proxy | Post-meeting action velocity | Immediate email/task creation after meeting vs nothing — proxy for meeting cognitive impact |
| Error/typo rate in emails | Draft analysis via Haiku | Cognitive fatigue proxy (higher error rate = lower performance window) |

### 3.3 Signal Quality Requirements

- **Minimum granularity:** 30-minute bins. Finer than 30 minutes introduces noise without improving model quality.
- **Minimum observations per bin:** 5 data points before that bin has reportable confidence.
- **Outlier handling:** Sessions during travel, illness, weekends, and holidays flagged and excluded from steady-state model. Detected via calendar anomalies (timezone changes, out-of-office, all-day events tagged "leave/holiday/travel").

---

## 4. Model Architecture

### 4.1 Task Type Taxonomy

Four performance curves are maintained independently:

| Task Type | Classifier Signal | Examples |
|-----------|------------------|----------|
| **Analytical** | Deep focus sessions, spreadsheet/document work, low email, low app-switching | Board deck preparation, financial review, strategic planning |
| **Creative** | Brainstorming sessions, new document creation, divergent email threads | Product ideation, pitch creation, problem reframing |
| **Interpersonal** | Meetings, 1:1s, email threads with high back-and-forth, phone calls | Team 1:1s, stakeholder calls, coaching conversations |
| **Administrative** | High email throughput, short tasks, rapid app-switching, approvals | Inbox processing, expense approvals, scheduling, quick replies |

Task type is classified by Haiku at event ingestion time. The executive can correct classifications during the morning session, which feeds back into the classifier.

### 4.2 Performance Curve Representation

```swift
struct PerformanceCurve {
    let taskType: TaskType // .analytical, .creative, .interpersonal, .administrative
    var bins: [HourBin]    // 48 bins (30-min intervals, 00:00-23:30)
    var confidence: [HourBin: Float] // 0.0-1.0 per bin
    var modelVersion: Int
    var lastUpdated: Date
}

struct HourBin {
    let hourStart: Int     // 0-23
    let halfHour: Bool     // false = :00, true = :30
    var performanceScore: Float  // 0.0-1.0 normalised within task type
    var sampleCount: Int
    var variance: Float
    var trend: TrendDirection // .improving, .stable, .declining
}
```

### 4.3 Performance Score Computation

Each observation generates a raw performance score:

**Task completion velocity score:**
```
velocity_score = estimated_duration / actual_duration
```
Clamped to [0.2, 2.0]. Values > 1.0 mean faster than expected (high performance). Normalised per task type across the executive's own history (not population).

**Focus session quality score:**
```
focus_score = (session_duration / target_duration) * (1 - interruption_rate)
```
Where `interruption_rate` = number of app-switches or breaks / session duration in minutes.

**Email response quality score (Haiku-classified):**
```
email_score = quality_class_weight * (1 / response_latency_normalised)
```
Where `quality_class_weight`: quick-reply = 0.3, considered-response = 0.7, multi-draft = 1.0. This weights effortful responses more highly.

### 4.4 Aggregation Method: Bayesian Update with Exponential Decay

Each 30-minute bin maintains a Beta distribution posterior:

```
Prior: Beta(alpha_0, beta_0) — initialised from population chronotype prior (see Cold Start)
Observation: score_normalised ∈ [0, 1]
Update: alpha_new = alpha_old * decay + score * weight
         beta_new = beta_old * decay + (1 - score) * weight
```

**Decay factor:** `lambda = 0.97` per day. This means observations from 30 days ago contribute ~40% of their original weight. Recent behaviour dominates, but stable patterns persist.

**Why Bayesian:** Graceful cold-start from population priors. Naturally represents uncertainty. Confidence = `1 - variance(Beta(alpha, beta))`.

### 4.5 Peak Window Extraction

From the posterior means across all bins for a given task type:

```swift
func extractPeakWindows(curve: PerformanceCurve, minConfidence: Float = 0.6) -> [TimeWindow] {
    let confidentBins = curve.bins.filter { curve.confidence[$0]! >= minConfidence }
    let sorted = confidentBins.sorted { $0.performanceScore > $1.performanceScore }
    
    // Primary peak: contiguous block of top-quartile bins
    let primaryPeak = findContiguousBlock(in: sorted, percentile: 0.75)
    
    // Secondary peak: next contiguous block (handles bimodal curves)
    let secondaryPeak = findContiguousBlock(in: sorted, percentile: 0.75, excluding: primaryPeak)
    
    // Trough: contiguous block of bottom-quartile bins
    let trough = findContiguousBlock(in: sorted.reversed(), percentile: 0.25)
    
    return [primaryPeak, secondaryPeak, trough].compactMap { $0 }
}
```

The scheduling engine receives peak windows as hard constraints: analytical tasks are only placed in analytical peaks. Creative tasks are only placed in creative peaks. Administrative batches go in troughs.

---

## 5. Cold Start Strategy

### 5.1 Population Prior (Day 0)

Before any observation, initialise from the most common chronotype distribution (intermediate type, ~60% of population):

| Task Type | Default Peak | Default Trough |
|-----------|-------------|----------------|
| Analytical | 09:00-11:30 | 13:30-15:00 |
| Creative | 15:00-17:00 | 09:00-10:00 |
| Interpersonal | 10:00-12:00, 14:00-16:00 | Before 09:00, after 17:00 |
| Administrative | 08:00-09:00, 16:00-17:30 | 10:00-12:00 |

These are weak priors (low alpha/beta = high uncertainty). They serve as sensible defaults that get overwritten quickly.

### 5.2 Rapid Chronotype Detection (Days 1-3)

Three signals available immediately from calendar history bootstrap (90-day Outlook history):

1. **First email sent time** — distribution across 90 days. If median first email is 6:30am, strong lark signal. If 9:30am, intermediate or owl.
2. **Late-night email activity** — emails sent after 21:00. Frequency and quality (are they substantive or quick replies?).
3. **Meeting acceptance patterns** — does the executive accept 8am meetings? Do they propose meetings before 9am or after 5pm?

From these three signals, Haiku classifies into one of five chronotype buckets: strong-lark, mild-lark, intermediate, mild-owl, strong-owl. This shifts the population prior toward the appropriate chronotype curve.

### 5.3 Model Maturation Timeline

| Phase | Duration | Confidence Level | What's Available |
|-------|----------|-----------------|------------------|
| **Bootstrap** | Days 0-3 | Low (0.2-0.4) | Chronotype bucket + population-shifted priors |
| **Early Learning** | Days 4-14 | Medium (0.4-0.6) | Gross peak/trough identification, morning briefing says "early pattern suggests..." |
| **Reliable Model** | Days 15-28 | High (0.6-0.8) | Per-task-type peaks with scheduling recommendations |
| **Deep Model** | Day 29+ | Very High (0.8+) | Day-of-week variation, seasonal awareness, bimodal detection, cross-task-type interactions |

The morning session transparently communicates model maturity: "I've been observing your work patterns for 9 days. Early data suggests your analytical peak is between 9:00 and 11:00, but I need another week to be confident."

---

## 6. Adaptation and Drift Detection

### 6.1 Pattern Shift Triggers

The model must adapt when the executive's patterns change. Triggers for re-evaluation:

| Trigger | Detection Method | Response |
|---------|-----------------|----------|
| **Travel** | Calendar timezone change, out-of-office event | Pause model updates. Do not contaminate home-timezone model with jet-lag data. Resume 3 days after return. |
| **Seasonal shift** | Systematic drift in first-activity time across 14+ days | Gradually shift priors. Morning session notes: "Your start time has shifted 45 minutes later over the past 3 weeks — adjusting your peak windows." |
| **Role change** | Task type distribution shift (e.g., 60% analytical → 60% interpersonal) | Trigger accelerated learning period. Reduce decay factor temporarily (lambda = 0.90 for 14 days) to learn new patterns faster. |
| **Schedule change** | Recurring meeting pattern change detected | Re-evaluate which windows are available for discretionary work. Peaks are only useful if the executive can actually use them. |
| **Anomaly week** | 3+ days where observed performance deviates >2 sigma from model | Flag but do not update. Could be illness, personal event, crisis. Ask during morning session: "Your patterns this week look different from your baseline. Anything I should know?" |

### 6.2 Drift Detection Algorithm

```swift
func detectDrift(recentWindow: Int = 7, historicalWindow: Int = 30) -> DriftResult {
    let recentMean = computeMeanCurve(lastNDays: recentWindow)
    let historicalMean = computeMeanCurve(lastNDays: historicalWindow)
    
    // Kolmogorov-Smirnov test on the two distributions per task type
    for taskType in TaskType.allCases {
        let ks = kolmogorovSmirnovTest(
            recentMean.curve(for: taskType),
            historicalMean.curve(for: taskType)
        )
        if ks.pValue < 0.05 {
            // Statistically significant drift detected
            return .driftDetected(
                taskType: taskType,
                direction: classifyDrift(recent: recentMean, historical: historicalMean),
                magnitude: ks.statistic
            )
        }
    }
    return .stable
}
```

### 6.3 Day-of-Week Variation

After 4+ weeks of data, the model splits into weekday sub-models:

- **Monday model:** Often different from mid-week (post-weekend cognitive ramp-up, weekly planning meetings)
- **Friday model:** Often degraded analytical performance, higher administrative throughput
- **Mid-week model:** Tuesday-Thursday typically most consistent

This is only activated when day-of-week variation exceeds task-type variation by >15%, to avoid over-fitting on sparse data.

---

## 7. Data Model (CoreData)

```swift
// Stored observation — one per completed work block
@Model
class ChronotypeObservation {
    var id: UUID
    var timestamp: Date           // When the work block started
    var hourBin: Int              // 0-47 (30-min bins)
    var dayOfWeek: Int            // 1-7
    var taskType: String          // analytical, creative, interpersonal, administrative
    var performanceScore: Float   // 0.0-1.0 normalised
    var rawMetrics: Data          // JSON: velocity, focus quality, email quality — for audit
    var isOutlier: Bool           // Flagged by anomaly detection
    var contextFlags: [String]    // ["travel", "post-holiday", "crisis-mode"]
}

// Aggregated model — the current best estimate
@Model
class ChronotypeModel {
    var id: UUID
    var taskType: String
    var modelVersion: Int
    var lastUpdated: Date
    var bins: Data               // JSON: array of 48 BinPosterior objects
    var peakWindows: Data        // JSON: extracted peak/trough TimeWindows
    var chronotypeBucket: String // strong-lark, mild-lark, intermediate, mild-owl, strong-owl
    var confidenceLevel: Float   // Overall model confidence 0.0-1.0
    var dayOfWeekSplit: Bool     // Whether day-of-week sub-models are active
}

struct BinPosterior: Codable {
    let binIndex: Int       // 0-47
    var alpha: Float        // Beta distribution alpha
    var beta: Float         // Beta distribution beta
    var mean: Float         // alpha / (alpha + beta)
    var sampleCount: Int
}
```

### Supabase Schema

```sql
create table chronotype_observations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    timestamp timestamptz not null,
    hour_bin smallint not null check (hour_bin >= 0 and hour_bin <= 47),
    day_of_week smallint not null check (day_of_week >= 1 and day_of_week <= 7),
    task_type text not null check (task_type in ('analytical', 'creative', 'interpersonal', 'administrative')),
    performance_score real not null check (performance_score >= 0 and performance_score <= 1),
    raw_metrics jsonb not null default '{}',
    is_outlier boolean not null default false,
    context_flags text[] not null default '{}',
    created_at timestamptz not null default now()
);

create index idx_chrono_obs_user_time on chronotype_observations(user_id, timestamp desc);
create index idx_chrono_obs_task_type on chronotype_observations(user_id, task_type, hour_bin);

-- RLS: user can only read/write their own observations
alter table chronotype_observations enable row level security;
create policy "Users read own observations" on chronotype_observations
    for select using (auth.uid() = user_id);
create policy "Users insert own observations" on chronotype_observations
    for insert with check (auth.uid() = user_id);

create table chronotype_models (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    task_type text not null,
    model_version integer not null default 1,
    bins jsonb not null,              -- array of 48 BinPosterior
    peak_windows jsonb not null,      -- extracted TimeWindows
    chronotype_bucket text not null default 'intermediate',
    confidence_level real not null default 0.0,
    day_of_week_split boolean not null default false,
    updated_at timestamptz not null default now(),
    unique(user_id, task_type)
);
```

---

## 8. Processing Pipeline

### 8.1 Real-Time (Haiku — on every event)

When a task completes, focus session ends, or email reply is sent:

1. Haiku classifies the task type (if not already classified)
2. Compute raw performance score from the event metrics
3. Store `ChronotypeObservation` to CoreData and sync to Supabase
4. No model update at this stage — just data collection

**Token cost:** ~200 tokens per classification. At ~30 events/day = ~6,000 Haiku tokens/day.

### 8.2 Nightly (Opus — during reflection engine)

During the nightly reflection pipeline (Stage 2: first-order pattern extraction):

1. Pull all observations from the last 24 hours
2. Run outlier detection (flag anomalous days)
3. Update Beta distribution posteriors for each bin
4. Re-extract peak windows
5. Run drift detection against 30-day baseline
6. Generate natural-language chronotype insight for morning session

**Opus prompt structure (within reflection pipeline):**

```
You are analysing the chronotype data for [executive name].

Today's observations:
[Array of ChronotypeObservation objects for the day]

Current model state:
[Current ChronotypeModel for each task type]

30-day baseline statistics:
[Summary statistics]

Tasks:
1. Identify any observations that appear anomalous and should be flagged
2. Note any drift from the 30-day baseline
3. Extract the key chronotype insight for today (one sentence for the morning briefing)
4. If model confidence has crossed 0.6 for any task type, generate a scheduling recommendation

Output as structured JSON.
```

### 8.3 Morning Delivery

The morning briefing incorporates chronotype intelligence:

**Week 1 (low confidence):**
> "I'm still learning your rhythms. Early signals suggest you're sharpest before 11am. I'll have a reliable model in about two weeks."

**Week 3+ (high confidence):**
> "Your analytical peak today is 9:15-11:00. The compliance review belongs there — it's your hardest cognitive task. Your 1:1 with Sarah is at 2pm, which aligns well with your interpersonal window. I'd suggest batching email between 4:00 and 5:00 when your administrative throughput peaks."

**Drift detected:**
> "Your patterns have shifted over the past two weeks — your analytical peak has moved about 45 minutes later. This could be seasonal. I'm adjusting your recommended windows."

---

## 9. Validation and Quality

### 9.1 Ground Truth Proxy

We cannot directly measure "cognitive performance" — we use proxies. Validation checks:

- **Internal consistency:** Does the executive complete analytical tasks faster during modelled analytical peaks? (Circular if used for training — use held-out days.)
- **Self-report alignment:** During morning session, occasionally ask: "When did you feel sharpest yesterday?" Compare to model prediction. Track alignment over time.
- **Outcome quality:** For tasks with measurable outcomes (email response quality rated by Haiku, task completion without revision), compare quality in peak vs trough windows.

### 9.2 Failure Modes

| Failure Mode | Impact | Mitigation |
|-------------|--------|------------|
| Task type misclassification | Wrong curve gets the data point | Executive correction feedback loop; Haiku confidence threshold (reject < 0.7) |
| Calendar doesn't reflect reality | Model trained on "scheduled" not "actual" work | Use completion events, not calendar blocks, as ground truth |
| Insufficient data for a task type | Creative work may be rare; model never matures | Report confidence per type; fall back to population prior; morning session says "I don't have enough creative work data to model your creative peak yet" |
| Over-fitting to a bad week | Illness, crisis, personal event corrupts model | Exponential decay + outlier flagging + anomaly week detection |
| Executive gaming the system | Unlikely but possible — doing easy tasks in "peak" to inflate scores | Use task difficulty normalisation; Opus detects gaming patterns during nightly reflection |

---

## 10. Integration Points

| Consumer | What It Receives | How |
|----------|-----------------|-----|
| **Scheduling Engine** | `peakWindows` per task type | `ChronotypeModel` CoreData fetch |
| **Morning Briefing (Opus Director)** | Natural-language chronotype insight + today's recommended windows | Included in reflection output, cached in `morning_session_context` |
| **Task Scoring (PlanningEngine)** | Time-alignment bonus/penalty | Task scored higher when placed in its type's peak window; penalised in trough |
| **Cognitive Load Model** | Baseline performance expectation | Load model uses chronotype curve as the "expected" baseline; deviation from expected = load signal |
| **Reflection Engine** | Raw observations for pattern extraction | `ChronotypeObservation` records fed as episodic memories |

---

## 11. Implementation Sequence

1. **Add `ChronotypeObservation` CoreData entity and observation recording** — hook into `PlanningEngine.markTaskCompleted()`, `FocusTimer.sessionEnded()`, `EmailSyncService.replySent()`
2. **Add Haiku task-type classifier** — classify each completed event into the four task types
3. **Implement Bayesian bin model** — `ChronotypeModelEngine` class with Beta update, decay, and peak extraction
4. **Cold start from calendar history** — chronotype bucket detection from 90-day email/calendar timestamps
5. **Integrate into nightly reflection pipeline** — add chronotype analysis as a stage in the Opus reflection prompt
6. **Surface in morning briefing** — chronotype insight generation and delivery
7. **Connect to scheduling engine** — peak windows as scheduling constraints
8. **Add drift detection** — KS test, anomaly flagging, adaptation triggers
9. **Day-of-week split** — activate after 4 weeks when data supports it
10. **Supabase sync** — schema migration, RLS policies, observation sync
