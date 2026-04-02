# Day Plan Generation Spec

**Status:** Implementation-ready
**Layer:** 4 (Intelligence Delivery) — consumes Layer 2 (Memory Store) + Layer 3 (Reflection Engine) outputs
**Owner:** Morning Opus Director
**Depends on:** PlanningEngine, UserIntelligenceStore, CalendarService, ReflectionEngine

---

## 1. Purpose

Generate a time-slotted, priority-ordered daily plan that reflects the system's compounding understanding of the executive. This is not a task list — it is a cognitive schedule that places the right work in the right windows based on who this person actually is, not who they think they are.

The plan is the primary output of the morning intelligence session. It is generated once (pre-morning), presented during the morning session, and then continuously re-evaluated throughout the day.

---

## 2. Inputs

### 2.1 Thompson Sampling Scores

Each active task carries Thompson sampling parameters (alpha, beta) representing the system's belief about the task's value distribution. At plan generation time:

- Draw a sample from Beta(alpha, beta) for each task
- Multiply by a deadline proximity multiplier: `1.0 + max(0, (1.0 - hoursUntilDeadline / 72.0))` (tasks within 72h get boosted, linear ramp)
- Multiply by a dependency multiplier: `1.3` if downstream tasks are blocked, `1.0` otherwise
- Multiply by a staleness multiplier: `1.0 + (daysSinceLastWorked * 0.05)` capped at `1.5` (tasks untouched for 10+ days hit ceiling)
- Result: `adjustedScore = sample * deadlineMultiplier * dependencyMultiplier * stalenessMultiplier`

These scores are stochastic by design — Thompson sampling ensures exploration of tasks the system is uncertain about, preventing the executive from only ever doing "safe" work.

### 2.2 EMA Duration Estimates

Exponential Moving Average duration estimates per task category, updated from focus session completion data:

```
EMA_new = alpha * actual_duration + (1 - alpha) * EMA_previous
```

- `alpha = 0.3` (default, responsive to recent performance)
- Per-category priors loaded at cold start (see cold-start.md)
- If a task has zero history and no category match: use `estimatedDuration` from task creation, flagged as `lowConfidence`
- Each estimate carries a confidence band: `[EMA * 0.7, EMA * 1.4]` — the upper bound is used for slot allocation to prevent optimistic packing

**Critical rule:** Always allocate using the upper confidence bound. Executives systematically underestimate duration. The system must not replicate this bias.

### 2.3 Chronotype Performance Curve

A 24-hour performance curve specific to this executive, stored as a `[Float]` array of 48 half-hour weights (0.0–1.0) in the semantic memory layer.

**How it is built:**

- **Week 1–2:** Population archetype curve (see cold-start.md) — one of 5 presets
- **Week 3–6:** Bayesian update from observed signals:
  - Focus session completion rate per half-hour window
  - Email response latency inverse (fast responses = high energy)
  - Task completion quality (tasks completed without revision in a window = high cognitive performance)
  - Voice session energy inference (morning session prosody → energy level)
- **Week 7+:** Fully personalised curve, updated weekly by reflection engine

**Curve interpretation for slot assignment:**

| Weight Range | Classification | Task Types |
|---|---|---|
| 0.8–1.0 | Peak | Deep analytical work, strategic decisions, complex writing |
| 0.5–0.79 | Active | Collaborative work, 1:1s, moderate-complexity tasks |
| 0.3–0.49 | Trough | Email processing, admin, routine approvals, reading |
| 0.0–0.29 | Recovery | No task assignment — buffer or break |

### 2.4 Calendar Gaps (from Microsoft Graph)

Calendar data fetched via Graph API (`Calendars.Read` scope). The CalendarService produces:

```swift
struct CalendarGap: Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let durationMinutes: Int
    let precedingEvent: CalendarEvent?  // context for transition time
    let followingEvent: CalendarEvent?
    let gapType: GapType  // .morning, .midday, .afternoon, .evening, .betweenMeetings
}

enum GapType {
    case morningBlock      // before first meeting
    case middayBlock       // lunch-adjacent
    case afternoonBlock    // after last meeting cluster
    case eveningBlock      // after business hours
    case betweenMeetings   // gaps between calendar events
}
```

**Gap filtering rules:**

- Gaps < 15 minutes are excluded (insufficient for meaningful work)
- Gaps between 15–30 minutes are flagged as `shallowOnly` — only admin/email tasks
- A 10-minute transition buffer is deducted from each gap adjacent to a meeting (executives do not teleport between mental contexts)
- Recurring "phantom" meetings (marked as tentative or historically no-showed > 50%) are treated as soft gaps — plan around them but mark the slot as `tentative`

### 2.5 Active Procedural Rules

Procedural rules from the memory store that apply to scheduling. Examples:

- `"Never schedule deep work after a board meeting"` — confidence 0.87, based on 6 observed instances of post-board cognitive depletion
- `"Pipeline review calls should be morning — performance drops 40% after 2pm"` — confidence 0.72
- `"Allow 30-minute buffer after any meeting with [specific person]"` — confidence 0.65

Rules are filtered by:
- `confidence >= 0.6` (below this, rules are still learning and are not applied)
- `status == .confirmed` (not `.emerging` or `.fading`)
- Relevance to today's specific calendar and task set

Rules are applied as hard constraints during slot assignment. If a rule conflicts with optimal placement, the rule wins and the conflict is logged for the morning session narrative ("I moved your deep work to 10am instead of 2pm because your data shows a 40% performance drop after lunch meetings").

### 2.6 Current Cognitive Load Estimate

A real-time composite score (0.0–1.0) representing the executive's current cognitive burden:

```swift
struct CognitiveLoadEstimate {
    let score: Float           // 0.0 (empty) to 1.0 (saturated)
    let components: [String: Float]  // breakdown
    let timestamp: Date
    let confidence: Float      // how sure the system is about this estimate
}
```

**Components:**

| Component | Weight | Source |
|---|---|---|
| Open task count (unresolved) | 0.15 | TaskStore |
| Overdue task count | 0.20 | TaskStore — tasks past deadline |
| Meeting density today | 0.15 | CalendarService — hours of meetings / total work hours |
| Email backlog (unactioned "Do First" count) | 0.15 | EmailService |
| Days since last recovery day | 0.10 | CalendarService — days since a <3-meeting day |
| Active high-stakes items | 0.15 | Semantic memory — items tagged as high-stakes |
| Yesterday's completion rate | 0.10 | PlanStore — tasks completed / tasks planned |

**How cognitive load affects planning:**

- Load < 0.3: Normal planning, full task set
- Load 0.3–0.6: Reduce planned tasks by 15%, increase buffer between tasks
- Load 0.6–0.8: Reduce planned tasks by 30%, flag overload in morning session, suggest deferral candidates
- Load > 0.8: Emergency mode — plan only top 3 tasks, morning session opens with "Your cognitive load is critically high. Here's what actually matters today."

---

## 3. Slot Assignment Algorithm

### 3.1 Overview

The algorithm is a constraint-satisfying greedy scheduler with performance-curve awareness. It is NOT an optimisation solver — exact optimality is less important than producing a plan that feels right and respects the executive's actual patterns.

### 3.2 Steps

**Step 0 — Build the time grid.**

Create 48 half-hour slots for the work window (default: 07:00–19:00, adjusted per executive's observed patterns). Mark each slot as:
- `blocked` (calendar event)
- `transition` (10-min buffer adjacent to meetings)
- `available` (open)
- `tentative` (soft meeting — historically skipped > 50%)

**Step 1 — Apply the 75% utilization cap.**

Calculate total available minutes. Multiply by 0.75. This is the maximum plannable time.

**Why 75%, not 90% or 100%:**

Executive work is inherently unpredictable. Research on knowledge worker time allocation (Mark, Gonzalez & Harris, 2005; Perlow, 1999) consistently shows that planned work occupies 60–70% of actual time even in the best case. The remaining time absorbs:

- Emergent requests that cannot be deferred (a direct report with an urgent issue, a client escalation, a board member calling)
- Tasks that exceed their estimated duration (this happens ~40% of the time even with EMA calibration)
- Cognitive recovery between tasks (attention residue from task-switching requires 5–15 minutes per Gloria Mark's interruption research)
- Spontaneous high-value interactions (hallway conversations, quick decisions that prevent larger problems)

A 75% cap means a 10-hour work day plans ~7.5 hours of task time and leaves ~2.5 hours of buffer. In practice, the buffer is consumed within the first 3 hours of a typical executive day. 100% utilization plans are fiction — they create the illusion of productivity while guaranteeing failure and re-planning overhead.

If the executive consistently finishes with buffer remaining (tracked over 2+ weeks), the reflection engine may recommend increasing the cap to 80%. The cap never exceeds 85%.

**Step 2 — Rank tasks by adjusted score.**

Sort all active tasks by `adjustedScore` (from 2.1) descending.

**Step 3 — Assign peak tasks first.**

Take the top N tasks classified as `deep` or `strategic` energy level. For each:
1. Find the highest-performance-curve slot that fits the task's estimated duration (upper bound)
2. Verify no procedural rule violation
3. Assign the task to that slot
4. Deduct the time from remaining budget

If a peak window is already consumed by calendar events, the morning session flags this: "Your calendar leaves no peak-performance window today. Your highest-value work will run at reduced capacity."

**Step 4 — Assign meetings where they are.**

Meetings are immovable (observation only — Timed never modifies calendars). They consume their slots. The plan annotates each meeting with:
- Preparation notes (from semantic memory about attendees, last interaction, open threads)
- Energy cost estimate (from procedural rules about this meeting type)
- Post-meeting recovery recommendation

**Step 5 — Assign active/moderate tasks.**

Remaining tasks with `moderate` energy requirements are placed in active-performance windows (0.5–0.79 on the curve). Same constraint-checking process.

**Step 6 — Assign shallow tasks in troughs.**

Email processing, admin, routine approvals placed in trough windows (0.3–0.49). These are explicitly labeled as "low-energy work for low-energy windows" in the plan output.

**Step 7 — Apply minimum gap rules.**

Ensure at least 5 minutes between any two consecutive task slots. If the executive's procedural rules specify longer gaps (e.g., "needs 15 minutes after any meeting before starting deep work"), apply those instead.

**Step 8 — Mark unplanned tasks.**

Any tasks that did not fit within the 75% budget are placed in an "overflow" list, ranked by score. The morning session presents these as: "These didn't make today's plan. The top candidate to add if time opens up is [X]."

### 3.3 Slot Output Format

```swift
struct DayPlan: Identifiable {
    let id: UUID
    let date: Date
    let generatedAt: Date
    let modelVersion: String         // snapshot ID of the cognitive model used
    let cognitiveLoadAtGeneration: Float
    let slots: [PlannedSlot]
    let overflow: [OverflowTask]
    let alerts: [PlanAlert]          // proactive intelligence surfaced during planning
    let narrative: MorningNarrative  // the morning session script
    let utilizationCap: Float        // 0.75 default, may be adjusted
    let actualUtilization: Float     // computed after slot assignment
}

struct PlannedSlot: Identifiable {
    let id: UUID
    let type: SlotType               // .task, .meeting, .buffer, .recovery, .shallow
    let task: TaskReference?         // nil for meetings and buffers
    let meeting: CalendarEvent?      // nil for tasks
    let startTime: Date
    let endTime: Date
    let durationMinutes: Int
    let performanceCurveScore: Float // the executive's expected performance in this window
    let energyMatch: EnergyMatch     // .optimal, .acceptable, .suboptimal
    let reasoning: String            // why this task is in this slot — shown in morning session
    let confidence: Float            // how confident the system is in this placement
    let isMovable: Bool              // false for meetings, true for tasks
    let proceduralRulesApplied: [String]  // IDs of rules that influenced placement
}

enum SlotType {
    case task
    case meeting
    case buffer
    case recovery
    case shallow
}

enum EnergyMatch {
    case optimal      // task energy matches window energy
    case acceptable   // within one tier
    case suboptimal   // mismatch — flagged in narrative
}

struct OverflowTask {
    let task: TaskReference
    let adjustedScore: Float
    let reason: OverflowReason       // .noPeakWindow, .budgetExhausted, .ruleConflict
}

struct PlanAlert {
    let type: AlertType              // .overload, .noPeakWindow, .ruleViolation, .patternWarning
    let message: String
    let severity: AlertSeverity      // .info, .warning, .critical
    let relatedPatternID: UUID?
}
```

---

## 4. Morning Session Output Format

The DayPlan includes a `MorningNarrative` — the script that the Morning Opus Director delivers during the morning session.

```swift
struct MorningNarrative {
    let opening: PatternBriefing       // named patterns, observations, avoidance callouts
    let planPresentation: PlanScript   // the actual plan with reasoning
    let elicitation: ElicitationQuestion?  // one targeted preference question (cold start and ongoing)
    let closing: ClosingInsight        // one forward-looking insight
}

struct PatternBriefing {
    let patterns: [PatternSummary]     // max 3 most relevant patterns for today
    let avoidanceCallout: String?      // if the system detects active avoidance
    let stateObservation: String?      // "You've been in back-to-back meetings for 3 days"
}

struct PlanScript {
    let totalPlannedHours: Float
    let totalBufferHours: Float
    let topPriorityExplanation: String // why #1 is #1 — references model knowledge
    let slotNarratives: [String]       // one-liner per slot explaining the placement
    let tradeoffExplanation: String?   // what was sacrificed and why
}
```

**Narrative rules:**

- Never open with "Here's your plan for today." Open with an observation, a pattern, or a question.
- Always explain WHY the top task is ranked first — reference the model, not generic logic.
- If avoidance is detected ("You've deferred the org restructure email for 4 consecutive days"), name it directly. Do not soften.
- If the plan is suboptimal due to calendar constraints, say so: "Your calendar makes today a firefighting day. I've protected your best 90 minutes for [X] — that's the only strategic window."
- Keep total narrative under 90 seconds when spoken aloud.

---

## 5. Re-Planning Triggers

The initial plan is generated pre-morning (typically 05:30–06:00, timed to the executive's wake pattern). Throughout the day, the plan may be re-evaluated.

### 5.1 Trigger Events

| Trigger | Detection | Response |
|---|---|---|
| **New high-priority email** | EmailSentinel (Haiku) classifies incoming email as `doFirst` with urgency > 0.8 | Re-score affected tasks. If the new email task outranks any planned task, generate a swap proposal. |
| **Calendar change** | Graph webhook or polling detects new/moved/cancelled meeting | Rebuild the time grid. Re-run slot assignment for affected windows only. |
| **User override** | Executive manually reorders, removes, or adds a task | Accept the change. Update Thompson sampling: if the user overrode the system's ranking, record this as implicit feedback (reduce alpha for the overridden task's priority signal). |
| **Task completion** | Executive marks a task complete (or focus session ends) | Remove the slot. If completed early, the freed time is added to buffer — NOT automatically filled. If completed late, compress subsequent slots and flag if budget is exceeded. |
| **Cognitive load spike** | CognitiveLoadEstimate crosses a threshold boundary (e.g., 0.5 → 0.7) | Reduce remaining planned tasks. Surface the load change in the next interaction. |
| **Significant pattern violation** | Executive is doing something that contradicts a confirmed procedural rule (e.g., deep work after a board meeting) | Do NOT intervene. Log the violation. If outcome is negative, reinforce the rule. If outcome is positive, weaken the rule. Never interrupt the executive. |

### 5.2 Re-Planning Behaviour

- Re-planning is **silent by default**. The plan updates in the background. The executive sees the updated plan next time they glance at the menu bar or open the app.
- Re-planning **never removes a task the executive has started**. In-progress work is sacred.
- If a re-plan produces a significantly different day structure (>40% of slots changed), the system surfaces a brief notification: "Your plan has shifted — [reason]. Tap to review."
- Re-planning respects the same 75% utilization cap. Freed time from completed tasks goes to buffer, not to cramming more tasks in.
- Maximum 6 re-plans per day. Beyond this, the system stops re-planning and flags that the day is too volatile for meaningful planning ("Today's been unpredictable. I'm holding your top 2 priorities and letting the rest flex.")

### 5.3 Feedback Loop

Every re-planning event is logged as a Layer 1 signal:

```swift
struct RePlanEvent: Signal {
    let timestamp: Date
    let trigger: RePlanTrigger
    let slotsChanged: Int
    let tasksPromoted: [UUID]
    let tasksDemoted: [UUID]
    let userAccepted: Bool?      // nil until user interacts with the re-plan
}
```

The reflection engine uses re-plan data to:
- Identify days that are systematically un-plannable (and adjust expectations)
- Detect triggers that always cause re-plans (e.g., "Monday mornings always blow up — start with 60% utilization instead of 75%")
- Learn which re-plan proposals the executive accepts vs rejects

---

## 6. Edge Cases

### 6.1 Zero-Task Day
If the executive has no active tasks, the plan contains only meetings and a narrative: "No tasks queued. Your calendar has [X] meetings. Consider: what's the one thing you should be working on that isn't in this system yet?"

### 6.2 All-Day Calendar
If calendar events consume >90% of the work window, the plan surfaces this as a critical alert and plans zero tasks. Narrative: "You have [X] hours of meetings today. There is no meaningful work window. The most valuable thing I can tell you is: you need to protect time tomorrow."

### 6.3 Conflicting Procedural Rules
If two rules conflict (e.g., "do deep work in the morning" and "never do deep work before the standup"), the higher-confidence rule wins. The conflict is logged and surfaced to the reflection engine for resolution.

### 6.4 Missing Data
If any input is unavailable:
- No calendar data → plan assumes fully open day, flag as `lowConfidence`
- No Thompson scores → fall back to deadline-based priority
- No performance curve → use archetype default
- No procedural rules → plan without constraints, flag as `earlyModel`

---

## 7. Performance Requirements

| Metric | Target |
|---|---|
| Plan generation time (initial) | < 5 seconds |
| Re-plan generation time | < 2 seconds |
| Morning narrative generation (Opus call) | < 15 seconds |
| Plan accuracy (tasks completed in planned slot ± 30 min) | > 60% by week 4, > 75% by month 3 |

---

## 8. CoreData Entities

```swift
// DayPlan entity
@objc(CDDayPlan)
class CDDayPlan: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var generatedAt: Date
    @NSManaged var modelVersion: String
    @NSManaged var cognitiveLoadAtGeneration: Float
    @NSManaged var utilizationCap: Float
    @NSManaged var actualUtilization: Float
    @NSManaged var narrativeJSON: Data       // encoded MorningNarrative
    @NSManaged var alertsJSON: Data          // encoded [PlanAlert]
    @NSManaged var replanCount: Int16
    @NSManaged var slots: NSSet              // -> CDPlannedSlot
    @NSManaged var overflowTasks: NSSet      // -> CDOverflowTask
    @NSManaged var replanEvents: NSSet       // -> CDReplanEvent
}

// PlannedSlot entity
@objc(CDPlannedSlot)
class CDPlannedSlot: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var slotType: String          // maps to SlotType
    @NSManaged var startTime: Date
    @NSManaged var endTime: Date
    @NSManaged var durationMinutes: Int16
    @NSManaged var performanceCurveScore: Float
    @NSManaged var energyMatch: String       // maps to EnergyMatch
    @NSManaged var reasoning: String
    @NSManaged var confidence: Float
    @NSManaged var isMovable: Bool
    @NSManaged var rulesAppliedJSON: Data    // [String] of rule IDs
    @NSManaged var plan: CDDayPlan
    @NSManaged var task: CDTask?
    @NSManaged var calendarEvent: CDCalendarEvent?
}
```

---

## 9. Dependencies

| Dependency | Required For |
|---|---|
| `PlanningEngine.swift` | Thompson sampling scores, task ranking |
| `CalendarService.swift` | Gap extraction, meeting data |
| `UserIntelligenceStore` | Memory tier access (procedural rules, semantic facts, performance curve) |
| `CognitiveLoadEstimator` | Load score computation |
| `MorningDirector` (Opus) | Narrative generation |
| `EmailSentinel` (Haiku) | Re-planning trigger for incoming email |

---

## 10. Open Questions for Reflection Engine

These are tracked for the nightly engine to evaluate once longitudinal data exists:

1. Should the utilization cap be per-day-of-week? (Monday may be systematically more volatile than Thursday)
2. Should task ordering account for "momentum" — placing a quick win first to build executive engagement?
3. At what confidence level should a procedural rule override Thompson sampling? Current threshold: 0.6. May need tuning.
4. Should the system learn the executive's preferred plan density, or always impose the 75% cap?
