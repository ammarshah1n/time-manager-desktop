# Thompson Sampling Task Scorer — Implementation Spec

> Timed v1 Intelligence Layer | Last updated: 2026-04-02

---

## 1. Purpose

Timed ranks tasks not by a fixed formula but by a learning system that gets better at predicting what the executive should do next. Thompson Sampling provides principled exploration-exploitation: the system mostly recommends what it's learned works best, while occasionally surfacing lower-confidence recommendations to gather information and improve.

This is a multi-armed bandit formulation where each task category is an arm, the reward signal is task completion behaviour, and the system learns which types of work the executive actually completes when recommended.

---

## 2. Multi-Armed Bandit Formulation

### 2.1 Arms = Task Categories (Not Individual Tasks)

Individual tasks are ephemeral — they're created, completed or deferred, and gone. Learning per-task is impossible because each task is seen only once. Instead, the system maintains priors **per task category**.

**Category taxonomy:**

```swift
enum TaskCategory: String, CaseIterable {
    // Deep work
    case strategicPlanning      // Long-range planning, strategy docs
    case creativeWork           // Writing, design, ideation
    case analysis               // Data analysis, financial review, research
    case technicalWork          // Code, architecture, technical docs
    
    // People work
    case oneOnOne               // 1:1 meetings, coaching
    case teamMeeting            // Group meetings the exec leads
    case externalMeeting        // Client/partner/board meetings
    case peopleDecision         // Hiring, firing, performance reviews
    case conflictResolution     // Interpersonal issues, mediation
    
    // Communication
    case emailDeepResponse      // Emails requiring thought (>5 min)
    case emailBatch             // Routine email processing
    case phoneCall              // Scheduled calls
    case presentation           // Preparing or delivering presentations
    
    // Administrative
    case scheduling             // Calendar management, logistics
    case delegation             // Assigning and following up
    case review                 // Reviewing others' work, approvals
    case administrative         // Expenses, compliance, routine ops
    
    // Personal
    case learning               // Reading, courses, skill development
    case exercise               // Physical activity (if tracked)
    case recovery               // Intentional breaks, walks, decompression
}
```

**Category assignment:** When a task is created (via morning interview, email triage, or manual entry), Haiku classifies it into one of these categories. The classification is stored on the task and does not change.

### 2.2 State Per Category

Each task category maintains a Beta distribution:

```swift
struct CategoryPrior {
    let category: TaskCategory
    var alpha: Double           // Success count + prior
    var beta: Double            // Failure count + prior
    var lastUpdated: Date
    
    /// Expected success rate (mean of Beta distribution)
    var expectedRate: Double { alpha / (alpha + beta) }
    
    /// Uncertainty (variance of Beta distribution)
    var uncertainty: Double { 
        (alpha * beta) / ((alpha + beta) * (alpha + beta) * (alpha + beta + 1)) 
    }
    
    /// Draw a Thompson sample
    func sample() -> Double {
        // Sample from Beta(alpha, beta) distribution
        return BetaDistribution.sample(alpha: alpha, beta: beta)
    }
}
```

**Interpretation:**
- `alpha` grows when tasks in this category are completed successfully (on time, focused).
- `beta` grows when tasks in this category are deferred, overdue, or abandoned.
- The Beta distribution captures both the estimated success rate AND the uncertainty.
- A category with `Beta(5, 2)` has high expected success and low uncertainty.
- A category with `Beta(2, 2)` has moderate expected success and high uncertainty — Thompson sampling will explore this category more.

### 2.3 Reward Signal

| Event | Signal | Update |
|-------|--------|--------|
| Task completed on time | **Success** | alpha += 1.0 |
| Task completed via focus timer (full session) | **Strong success** | alpha += 1.2 |
| Task completed late (after deadline) | **Weak success** | alpha += 0.3, beta += 0.3 |
| Task deferred once | **Mild failure** | beta += 0.5 |
| Task deferred twice+ | **Strong failure** | beta += 1.0 |
| Task overdue and untouched | **Failure** | beta += 1.0 |
| Task abandoned/deleted | **Failure** | beta += 0.7 |
| User manually re-ranks task UP | **Correction: under-valued** | alpha += 0.5 (see Section 5) |
| User manually re-ranks task DOWN | **Correction: over-valued** | beta += 0.5 (see Section 5) |

**Fractional updates** are intentional. A single deferral shouldn't collapse the distribution — it should gently nudge it. Strong signals (full focus timer completion, repeated deferral) get full-weight updates.

---

## 3. Cold Start: Archetype-Based Priors

### 3.1 The Problem

A new user has no history. With uniform `Beta(1, 1)` priors on all categories, the system has no basis for intelligent recommendations. The first 2 weeks would be random.

### 3.2 Archetype Picker (Onboarding)

At onboarding, the executive selects the archetype closest to their role. Each archetype provides pre-loaded priors based on research on executive work patterns.

**Archetypes:**

```swift
enum ExecutiveArchetype: String {
    case operationalCEO         // Runs the machine. Heavy on meetings, ops, decisions.
    case strategicCEO           // Sets direction. Heavy on strategy, external, creative.
    case founderCEO             // Does everything. Heavy on technical, creative, people.
    case cfo                    // Numbers-driven. Heavy on analysis, review, compliance.
    case cto                    // Technical leader. Heavy on technical, architecture, team.
    case coo                    // Operations. Heavy on process, delegation, meetings.
    case boardDirector          // Governance. Heavy on review, external, strategic.
}
```

### 3.3 Archetype Prior Tables

Each archetype defines starting `Beta(alpha, beta)` values for every task category.

**Example: Operational CEO**

| Category | Alpha | Beta | Expected Rate | Interpretation |
|----------|-------|------|---------------|----------------|
| strategicPlanning | 3.0 | 4.0 | 0.43 | Often deprioritised under operational pressure |
| creativeWork | 2.0 | 4.0 | 0.33 | Rarely gets to it |
| analysis | 4.0 | 2.0 | 0.67 | Completes when scheduled |
| oneOnOne | 5.0 | 1.5 | 0.77 | High commitment to direct reports |
| teamMeeting | 5.0 | 2.0 | 0.71 | Core activity |
| externalMeeting | 4.0 | 2.0 | 0.67 | Completes — often highest priority |
| peopleDecision | 2.5 | 3.5 | 0.42 | Tends to delay |
| emailDeepResponse | 3.0 | 3.0 | 0.50 | Inconsistent |
| emailBatch | 4.0 | 2.0 | 0.67 | Gets done in batches |
| delegation | 3.5 | 2.5 | 0.58 | Should do more, does some |
| review | 4.0 | 2.0 | 0.67 | Bottleneck awareness |
| administrative | 2.0 | 5.0 | 0.29 | Actively avoids |
| learning | 1.5 | 4.0 | 0.27 | Deprioritised |
| recovery | 1.5 | 5.0 | 0.23 | Skips breaks |

**Note:** These are low-weight priors (alpha + beta ~5-7). After ~20 real observations per category, the executive's actual behaviour dominates the archetype prior. The priors provide a reasonable starting point, not a permanent bias.

### 3.4 Calendar History Bootstrap

On onboarding, if the executive grants calendar access, Timed reads 90 days of Outlook calendar history. From this:
- Infer meeting-related category priors (which meeting types get rescheduled vs kept)
- Detect routine patterns (weekly 1:1s that are never cancelled → high oneOnOne alpha)
- Estimate operational vs strategic time allocation → adjust archetype priors

This bootstrap provides ~50-100 pseudo-observations, equivalent to ~2 weeks of active use.

---

## 4. Thompson Sampling Process

### 4.1 Per-Task Score Generation

When the system needs to rank tasks (morning planning, mid-day re-rank, user opens task list):

```swift
func scoreTask(_ task: Task, context: ScoringContext) -> Double {
    // 1. Thompson sample from the task's category distribution
    let categoryPrior = priors[task.category]!
    let thompsonSample = categoryPrior.sample()  // Beta(α, β) sample ∈ [0, 1]
    
    // 2. Urgency score
    let urgency = computeUrgency(task: task)  // [0, 1] — see Section 4.2
    
    // 3. Deadline pressure
    let deadline = computeDeadlinePressure(task: task)  // [0, 1] — see Section 4.3
    
    // 4. Energy match
    let energyMatch = computeEnergyMatch(task: task, context: context)  // [0, 1] — see Section 4.4
    
    // 5. Chronotype alignment
    let chronoMatch = computeChronotypeAlignment(task: task, context: context)  // [0, 1] — see Section 4.5
    
    // 6. Composite score
    let score = (
        0.30 * thompsonSample +      // What the model has learned
        0.25 * urgency +              // How urgent objectively
        0.20 * deadline +             // Deadline proximity pressure
        0.15 * energyMatch +          // Does current energy suit this task?
        0.10 * chronoMatch            // Is this the right time of day for this type?
    )
    
    return score
}
```

**Why Thompson sampling gets 0.30 weight (not 1.0):**
Thompson sampling alone would only optimise for "what will the executive actually do" — which could mean surfacing only easy, comfortable tasks. The urgency and deadline components inject objective importance. Energy and chronotype match inject cognitive science. The blend ensures the system recommends what's both likely to be done AND important to do.

### 4.2 Urgency Score

```swift
func computeUrgency(task: Task) -> Double {
    // LLM-assigned at task creation: 1-10 scale, normalised to [0, 1]
    // Factors: stated importance, stakeholder involved, downstream dependencies
    return Double(task.urgencyRating) / 10.0
}
```

Urgency is assigned once at task creation by Haiku and doesn't change unless the user manually overrides.

### 4.3 Deadline Pressure

```swift
func computeDeadlinePressure(task: Task) -> Double {
    guard let deadline = task.deadline else { return 0.3 }  // No deadline = moderate default
    
    let hoursRemaining = deadline.timeIntervalSinceNow / 3600
    let estimatedHours = task.estimatedDuration / 3600  // From EMA engine
    
    // Ratio of time needed to time available
    let ratio = estimatedHours / max(hoursRemaining, 0.5)
    
    // Sigmoid mapping: gentle curve that ramps sharply as deadline approaches
    // ratio < 0.3 → low pressure (~0.2)
    // ratio ~ 0.5 → moderate pressure (~0.5)
    // ratio > 0.8 → high pressure (~0.85)
    // ratio > 1.0 → overdue (~0.95+)
    return 1.0 / (1.0 + exp(-8.0 * (ratio - 0.5)))
}
```

### 4.4 Energy Match

```swift
func computeEnergyMatch(task: Task, context: ScoringContext) -> Double {
    let taskEnergyDemand = energyDemand(for: task.category)  // .high | .medium | .low
    let currentEnergy = context.currentEnergyLevel             // Inferred from time, meetings, etc.
    
    // High-energy task + high-energy period = good match (1.0)
    // High-energy task + low-energy period = bad match (0.2)
    // Low-energy task + low-energy period = good match (0.8)
    switch (taskEnergyDemand, currentEnergy) {
    case (.high, .high):   return 1.0
    case (.high, .medium): return 0.6
    case (.high, .low):    return 0.2
    case (.medium, .high): return 0.8
    case (.medium, .medium): return 0.7
    case (.medium, .low):  return 0.5
    case (.low, .high):    return 0.5  // Waste of peak energy, but not wrong
    case (.low, .medium):  return 0.7
    case (.low, .low):     return 0.8
    }
}
```

**Energy demand mapping (hardcoded initially, learnable later):**
| Category | Energy Demand |
|----------|---------------|
| strategicPlanning, creativeWork, analysis | High |
| oneOnOne, peopleDecision, conflictResolution, technicalWork | High |
| externalMeeting, presentation, emailDeepResponse | Medium |
| teamMeeting, phoneCall, delegation, review | Medium |
| emailBatch, scheduling, administrative, learning | Low |
| recovery, exercise | Low (intentionally — don't block these behind high energy) |

### 4.5 Chronotype Alignment

```swift
func computeChronotypeAlignment(task: Task, context: ScoringContext) -> Double {
    let hour = Calendar.current.component(.hour, from: context.currentTime)
    let taskType = cognitiveType(for: task.category)  // .analytical | .creative | .interpersonal | .administrative
    let chronotype = context.executiveChronotype       // .morning | .evening | .intermediate
    
    // Performance curve lookup (from chronobiology research)
    // Returns [0, 1] — how well this cognitive type performs at this hour for this chronotype
    return performanceCurve(taskType: taskType, hour: hour, chronotype: chronotype)
}
```

**Performance curve (morning chronotype, research-based defaults):**

| Hour | Analytical | Creative | Interpersonal | Administrative |
|------|-----------|----------|---------------|----------------|
| 6-8  | 0.7       | 0.4      | 0.3           | 0.5            |
| 8-10 | 0.95      | 0.5      | 0.6           | 0.6            |
| 10-12| 1.0       | 0.6      | 0.8           | 0.7            |
| 12-14| 0.5       | 0.4      | 0.7           | 0.8            |
| 14-16| 0.6       | 0.8      | 0.9           | 0.7            |
| 16-18| 0.7       | 1.0      | 0.8           | 0.5            |
| 18-20| 0.5       | 0.7      | 0.4           | 0.3            |

These curves are initial defaults from Wieth & Zacks (2011) and Hasher et al. Creative work peaks during non-optimal circadian periods (the "inspiration paradox"). The curves will be personalised over time as the system observes actual completion patterns by time of day.

---

## 5. User Corrections and Distribution Updates

### 5.1 Re-Ranking Events

When the executive manually reorders tasks (drag-and-drop, explicit "do this first" command):

```swift
func handleUserReRank(task: Task, oldRank: Int, newRank: Int) {
    let rankDelta = oldRank - newRank  // Positive = moved up, negative = moved down
    
    if rankDelta > 0 {
        // User thinks this task is MORE important than the system suggested
        let magnitude = min(Double(rankDelta) / 5.0, 1.0)  // Cap at 1.0
        priors[task.category]!.alpha += 0.5 * magnitude
    } else {
        // User thinks this task is LESS important than the system suggested
        let magnitude = min(Double(abs(rankDelta)) / 5.0, 1.0)
        priors[task.category]!.beta += 0.5 * magnitude
    }
}
```

**Magnitude scaling:** Moving a task up by 1 position is a mild correction; moving it up by 5 positions is a strong correction. The update magnitude reflects this.

### 5.2 Override Events

When the executive ignores the system's recommendation entirely (e.g., system suggests deep work, executive does email):

```swift
func handleOverride(suggestedTask: Task, actualTask: Task) {
    // Penalise the suggested category (system was wrong about timing)
    priors[suggestedTask.category]!.beta += 0.3
    
    // Reward the actual category (executive chose it over the suggestion)
    priors[actualTask.category]!.alpha += 0.3
}
```

### 5.3 Decay for Temporal Relevance

People change. The executive who always deferred strategic planning in Q1 might prioritise it in Q2. To prevent stale priors from dominating:

**Monthly prior decay:**

```swift
func decayPriors() {
    // Run monthly — gentle regression toward a less certain state
    for category in TaskCategory.allCases {
        let prior = priors[category]!
        // Multiply both alpha and beta by 0.95 — preserves ratio but reduces certainty
        prior.alpha = max(1.0, prior.alpha * 0.95)
        prior.beta = max(1.0, prior.beta * 0.95)
    }
}
```

This shrinks both alpha and beta by 5% monthly, gently increasing uncertainty and making the distribution more responsive to recent data. The `max(1.0, ...)` floor prevents the distribution from collapsing to a degenerate state.

---

## 6. Exploration vs Exploitation Balance

### 6.1 Thompson Sampling's Natural Balance

Thompson Sampling inherently balances exploration and exploitation through its sampling mechanism:

- **High-certainty categories** (large alpha + beta): Samples cluster tightly around the mean. Little exploration.
- **High-uncertainty categories** (small alpha + beta): Samples are spread across [0, 1]. Frequent exploration.
- **New categories** (never observed): `Beta(1, 1)` = uniform distribution. Maximum exploration.

This means no manual epsilon-greedy or UCB exploration bonus is needed. The sampling mechanism IS the exploration strategy.

### 6.2 When Exploration is Inappropriate

Some contexts should suppress exploration:

```swift
func scoreTask(_ task: Task, context: ScoringContext) -> Double {
    let thompsonSample: Double
    
    if context.isHighStakesDay {
        // On critical days (board meetings, deadlines), use expected value not sample
        thompsonSample = priors[task.category]!.expectedRate
    } else {
        thompsonSample = priors[task.category]!.sample()
    }
    
    // ... rest of scoring
}
```

**High-stakes detection:** A day is flagged `isHighStakesDay` if:
- It contains a meeting with importance ≥ 8
- A deadline with importance ≥ 8 is within 24 hours
- The executive explicitly said "critical day" in the morning interview

On high-stakes days, the system exploits only — it recommends the most proven task ordering without random exploration.

### 6.3 Exploration Logging

Every Thompson sample is logged for analysis:

```swift
struct ThompsonSampleLog {
    let timestamp: Date
    let taskId: UUID
    let category: TaskCategory
    let alpha: Double
    let beta: Double
    let sampledValue: Double
    let expectedValue: Double  // Mean of Beta distribution (for comparison)
    let wasExplorative: Bool   // sampledValue > expectedValue + 0.1 or < expectedValue - 0.1
    let finalRank: Int
}
```

This log enables:
- Measuring actual exploration rate (should be ~15-25% of recommendations)
- Detecting if the system is over-exploring (high deferral rate on exploratory recommendations)
- Auditing scoring decisions for debugging

---

## 7. Persistence

### 7.1 Local Storage (CoreData)

```swift
@Model
class TaskCategoryPrior {
    @Attribute(.unique) var category: String  // TaskCategory.rawValue
    var alpha: Double
    var beta: Double
    var lastUpdated: Date
    var totalObservations: Int                // alpha + beta - prior
    var lastDecayedAt: Date
}
```

### 7.2 Supabase Sync

```sql
create table task_category_priors (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users not null,
    category text not null,
    alpha double precision not null,
    beta double precision not null,
    last_updated timestamptz not null default now(),
    total_observations int not null default 0,
    last_decayed_at timestamptz not null default now(),
    unique(user_id, category)
);

-- RLS
alter table task_category_priors enable row level security;
create policy "users_own_priors" on task_category_priors
    for all using (auth.uid() = user_id);
```

### 7.3 Event Log (for replay and analysis)

```sql
create table scoring_events (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users not null,
    event_type text not null,  -- 'completion', 'deferral', 'rerank', 'override', 'abandonment'
    task_id uuid,
    category text not null,
    alpha_before double precision,
    beta_before double precision,
    alpha_after double precision,
    beta_after double precision,
    metadata jsonb,
    created_at timestamptz not null default now()
);
```

---

## 8. Convergence and Learning Speed

### 8.1 Expected Convergence Timeline

With archetype priors (starting alpha + beta ~5-7 per category):

| Observation count per category | Uncertainty (std dev of Beta) | Model state |
|-------------------------------|-------------------------------|-------------|
| 0 (archetype prior only)     | ~0.15-0.18                    | Generic |
| 10                            | ~0.10-0.12                    | Learning |
| 30                            | ~0.06-0.08                    | Personalised |
| 100                           | ~0.03-0.04                    | Calibrated |
| 300+                          | ~0.02                         | Converged |

At ~5-10 tasks/day across 20 categories, most categories reach "personalised" within 2-3 weeks and "calibrated" within 2-3 months.

### 8.2 Rare Categories

Some categories (e.g., `conflictResolution`) may only occur once a month. For these:
- Archetype priors persist longer (low observation count)
- Monthly decay prevents even these priors from becoming overconfident
- The system explicitly flags low-confidence categories in the morning briefing: "I'm less certain about how to prioritise conflict resolution for you — I've only seen 3 instances."

---

## 9. Testing Strategy

- **Distribution math:** Verify Beta sampling produces correct distribution shapes. Sample 10,000 times from known parameters, verify mean and variance match analytical values within 2%.
- **Reward signal updates:** For each event type, verify alpha and beta change by exactly the specified amount.
- **Cold start:** Verify that archetype priors produce reasonable initial rankings — operational CEO should rank oneOnOne above creativeWork.
- **Convergence test:** Simulate 100 days of a consistent executive (always completes analysis, always defers admin). Verify that after 30 days, analysis ranks above admin with >95% probability.
- **Decay test:** After convergence, run 3 months of monthly decay. Verify uncertainty increases but ratio remains stable.
- **User correction test:** Simulate repeated re-ranking of a category UP. Verify alpha increases proportionally.
- **High-stakes suppression:** On a high-stakes day, verify that no exploration occurs (all samples equal expected value).
- **Replay test:** Delete all priors, replay all events from the scoring_events log, verify priors converge to the same values.
