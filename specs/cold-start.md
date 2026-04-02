# Cold Start Strategy Spec

**Status:** Implementation-ready
**Layer:** Cross-cutting — affects Layer 1 (Signal Ingestion), Layer 2 (Memory Store), Layer 3 (Reflection Engine), Layer 4 (Intelligence Delivery)
**Owner:** ColdStartService
**Depends on:** OnboardingFlow, CalendarService (Graph), PlanningEngine, MorningDirector, UserIntelligenceStore

---

## 1. Purpose

Timed's value proposition is compounding intelligence. But compounding starts from zero. The cold start problem: how does the system provide useful intelligence before it has observed enough to build a meaningful model?

**Time-to-first-value target: useful intelligence by day 3.**

This means:
- Day 1: A day plan that is better than what the executive would make themselves (barely, but measurably)
- Day 3: Time estimates that start beating the executive's self-estimates
- Day 7: First named pattern detected and surfaced
- Day 14: Model specificity sufficient to exit cold start mode

The cold start strategy uses three mechanisms:
1. Archetype-based prior loading (immediate)
2. Calendar history bootstrap (day 1, 90-day import)
3. Active preference elicitation (days 1–14, one question per morning session)

---

## 2. Archetype Picker

### 2.1 Onboarding Flow

After Microsoft OAuth sign-in, the executive is presented with an archetype selection screen. This is not a personality quiz — it is a 30-second selection of the profile that best matches their role.

**Screen copy:**
"I need a starting point to build your model. Pick the profile closest to your role. I'll refine from here."

### 2.2 Archetype Definitions

Five executive archetypes, each pre-loaded with scoring weights, scheduling preferences, and category priors.

#### Archetype 1: CEO / Managing Director

**Profile:** Strategic orientation, high meeting load, relationship-driven, time split across all functions.

```swift
static let ceo = ExecutiveArchetype(
    id: "ceo",
    label: "CEO / Managing Director",
    description: "Strategic direction, board management, high external visibility",
    
    // Chronotype: Default morning peak (most CEOs are early risers per Christensen et al.)
    defaultChronotypeWeights: generateCurve(
        peakStart: 8.5,    // 08:30
        peakEnd: 11.0,     // 11:00
        secondaryPeakStart: 14.5, // 14:30
        secondaryPeakEnd: 16.0,   // 16:00
        troughStart: 12.0,        // 12:00
        troughEnd: 14.0           // 14:00
    ),
    
    // Thompson sampling priors (alpha, beta per category)
    categoryPriors: [
        .strategic:     (alpha: 8.0, beta: 2.0),   // high prior on strategic work
        .operational:   (alpha: 4.0, beta: 4.0),   // balanced
        .relational:    (alpha: 7.0, beta: 3.0),   // high — relationships are CEO currency
        .administrative:(alpha: 2.0, beta: 6.0),   // low — should be delegated
        .creative:      (alpha: 5.0, beta: 4.0),   // moderate
        .deepAnalysis:  (alpha: 6.0, beta: 3.0),   // high — but less than strategic
    ],
    
    // EMA duration priors (minutes per category)
    durationPriors: [
        .strategic:     60,   // strategy sessions run long
        .operational:   30,
        .relational:    25,   // 1:1s, catch-ups
        .administrative:15,
        .creative:      45,
        .deepAnalysis:  50,
        .email:         20,   // per batch
    ],
    
    // Scheduling preferences
    defaultUtilizationCap: 0.70,  // CEOs have more interruptions — lower cap
    preferredDeepWorkWindow: .morning,
    meetingTolerance: 6,          // hours per day before flagging overload
    minimumBreakMinutes: 10,
    
    // Expected patterns (seeded for faster detection)
    expectedPatterns: [
        "High external meeting load",
        "Email volume spikes Monday and Friday",
        "Strategic work displaced by operational urgency"
    ]
)
```

#### Archetype 2: CFO / Finance Director

**Profile:** Analytical orientation, deadline-driven (reporting cycles), precision focus, lower meeting load than CEO.

```swift
static let cfo = ExecutiveArchetype(
    id: "cfo",
    label: "CFO / Finance Director",
    description: "Financial oversight, reporting cycles, analytical decision-making",
    
    defaultChronotypeWeights: generateCurve(
        peakStart: 8.0, peakEnd: 11.5,
        secondaryPeakStart: 14.0, secondaryPeakEnd: 16.5,
        troughStart: 12.0, troughEnd: 13.5
    ),
    
    categoryPriors: [
        .strategic:     (alpha: 5.0, beta: 4.0),
        .operational:   (alpha: 3.0, beta: 5.0),
        .relational:    (alpha: 4.0, beta: 5.0),
        .administrative:(alpha: 3.0, beta: 5.0),
        .creative:      (alpha: 3.0, beta: 6.0),
        .deepAnalysis:  (alpha: 8.0, beta: 2.0),   // highest — CFO core skill
    ],
    
    durationPriors: [
        .strategic:     45,
        .operational:   25,
        .relational:    20,
        .administrative:20,
        .creative:      30,
        .deepAnalysis:  75,   // CFOs do long analytical sessions
        .email:         15,
    ],
    
    defaultUtilizationCap: 0.75,
    preferredDeepWorkWindow: .morning,
    meetingTolerance: 4,           // lower tolerance — analytical workers need blocks
    minimumBreakMinutes: 15,
    
    expectedPatterns: [
        "End-of-month/quarter reporting crunch",
        "Deep analysis sessions cluster in mornings",
        "Email response time increases during close periods"
    ]
)
```

#### Archetype 3: CTO / Technology Director

**Profile:** Maker-manager hybrid, context-switching between technical depth and leadership, irregular schedule.

```swift
static let cto = ExecutiveArchetype(
    id: "cto",
    label: "CTO / Technology Director",
    description: "Technical leadership, maker-manager balance, product and engineering oversight",
    
    defaultChronotypeWeights: generateCurve(
        peakStart: 9.0, peakEnd: 12.0,      // later start — tech leaders skew later
        secondaryPeakStart: 15.0, secondaryPeakEnd: 17.5,
        troughStart: 13.0, troughEnd: 14.5
    ),
    
    categoryPriors: [
        .strategic:     (alpha: 6.0, beta: 3.0),
        .operational:   (alpha: 5.0, beta: 4.0),
        .relational:    (alpha: 4.0, beta: 5.0),
        .administrative:(alpha: 2.0, beta: 7.0),
        .creative:      (alpha: 7.0, beta: 3.0),   // high — technical creativity
        .deepAnalysis:  (alpha: 7.0, beta: 3.0),   // high — architecture, code review
    ],
    
    durationPriors: [
        .strategic:     50,
        .operational:   25,
        .relational:    25,
        .administrative:10,
        .creative:      60,   // maker sessions run long
        .deepAnalysis:  55,
        .email:         15,
    ],
    
    defaultUtilizationCap: 0.75,
    preferredDeepWorkWindow: .morning,
    meetingTolerance: 4,
    minimumBreakMinutes: 15,
    
    expectedPatterns: [
        "Maker-manager context-switching cost",
        "Late-day technical deep dives",
        "Meeting-free mornings preferred"
    ]
)
```

#### Archetype 4: COO / Operations Director

**Profile:** Execution-oriented, high meeting load, process-driven, responsive to operational signals.

```swift
static let coo = ExecutiveArchetype(
    id: "coo",
    label: "COO / Operations Director",
    description: "Operational execution, cross-functional coordination, process management",
    
    defaultChronotypeWeights: generateCurve(
        peakStart: 7.5, peakEnd: 10.5,      // early — ops leaders start early
        secondaryPeakStart: 13.5, secondaryPeakEnd: 15.5,
        troughStart: 11.5, troughEnd: 13.0
    ),
    
    categoryPriors: [
        .strategic:     (alpha: 4.0, beta: 5.0),
        .operational:   (alpha: 8.0, beta: 2.0),   // highest — core function
        .relational:    (alpha: 6.0, beta: 3.0),   // cross-functional = relationship-heavy
        .administrative:(alpha: 4.0, beta: 4.0),   // more admin than CEO
        .creative:      (alpha: 3.0, beta: 6.0),
        .deepAnalysis:  (alpha: 4.0, beta: 5.0),
    ],
    
    durationPriors: [
        .strategic:     40,
        .operational:   30,
        .relational:    20,
        .administrative:20,
        .creative:      30,
        .deepAnalysis:  40,
        .email:         25,   // COOs process more email
    ],
    
    defaultUtilizationCap: 0.70,   // high interruption rate
    preferredDeepWorkWindow: .earlyMorning,
    meetingTolerance: 7,            // high — COOs live in meetings
    minimumBreakMinutes: 10,
    
    expectedPatterns: [
        "Reactive email patterns — high volume, fast response",
        "Cross-functional meeting clusters",
        "Operational fires displace strategic time"
    ]
)
```

#### Archetype 5: General Executive

**Profile:** Balanced defaults for executives who don't fit the other profiles. Department heads, VPs, general managers.

```swift
static let general = ExecutiveArchetype(
    id: "general",
    label: "General Executive",
    description: "Department head, VP, or general management — balanced profile",
    
    defaultChronotypeWeights: generateCurve(
        peakStart: 9.0, peakEnd: 11.5,
        secondaryPeakStart: 14.0, secondaryPeakEnd: 16.0,
        troughStart: 12.0, troughEnd: 13.5
    ),
    
    categoryPriors: [
        .strategic:     (alpha: 5.0, beta: 5.0),   // all balanced
        .operational:   (alpha: 5.0, beta: 5.0),
        .relational:    (alpha: 5.0, beta: 5.0),
        .administrative:(alpha: 5.0, beta: 5.0),
        .creative:      (alpha: 5.0, beta: 5.0),
        .deepAnalysis:  (alpha: 5.0, beta: 5.0),
    ],
    
    durationPriors: [
        .strategic:     45,
        .operational:   30,
        .relational:    25,
        .administrative:15,
        .creative:      40,
        .deepAnalysis:  45,
        .email:         20,
    ],
    
    defaultUtilizationCap: 0.75,
    preferredDeepWorkWindow: .morning,
    meetingTolerance: 5,
    minimumBreakMinutes: 10,
    
    expectedPatterns: []   // no pre-seeded patterns — learn from scratch
)
```

### 2.3 Archetype Data Structure

```swift
struct ExecutiveArchetype: Codable, Identifiable {
    let id: String
    let label: String
    let description: String
    let defaultChronotypeWeights: [Float]           // 48 half-hour weights
    let categoryPriors: [TaskCategory: ThompsonPrior]
    let durationPriors: [TaskCategory: Int]          // minutes
    let defaultUtilizationCap: Float
    let preferredDeepWorkWindow: TimePreference
    let meetingTolerance: Int                         // hours/day
    let minimumBreakMinutes: Int
    let expectedPatterns: [String]
}

struct ThompsonPrior: Codable {
    let alpha: Float
    let beta: Float
}

enum TimePreference: String, Codable {
    case earlyMorning    // 06:00–08:00
    case morning         // 08:00–11:00
    case afternoon       // 13:00–16:00
    case evening         // 17:00–20:00
    case variable        // no consistent preference
}
```

### 2.4 Archetype Decay

Archetype priors are not permanent. They serve as the initial belief, then observations update the belief through Bayesian updating:

- **Thompson sampling:** Each completed task updates alpha/beta, gradually overriding the archetype prior. By week 3, the archetype prior contributes < 20% of the posterior for actively-used categories.
- **Chronotype curve:** Each observed performance signal updates the curve. By week 4, the personalised curve should differ measurably from the archetype default.
- **Duration estimates:** Each focus session updates the EMA. By week 2, category estimates with 5+ observations are personalised.

The system tracks `archetypeInfluence` — the proportion of any given parameter that still derives from the archetype vs observed data. When `archetypeInfluence < 0.1` for all parameters, cold start mode exits.

---

## 3. Calendar History Bootstrap

### 3.1 90-Day Outlook Import

Immediately after Microsoft OAuth completes, the system imports 90 days of calendar history via Microsoft Graph:

```
GET /me/calendarView?startDateTime={90_days_ago}&endDateTime={now}&$top=500
```

### 3.2 What Is Extracted

From 90 days of calendar data, the system infers:

**Meeting patterns:**
```swift
struct CalendarBootstrapResult {
    // Volume
    let totalMeetings: Int
    let averageMeetingsPerDay: Float
    let meetingHoursPerWeek: Float
    
    // Timing
    let firstMeetingDistribution: [Int: Int]    // hour -> count (what time does first meeting typically start?)
    let lastMeetingDistribution: [Int: Int]     // what time does last meeting typically end?
    let peakMeetingHours: [Int]                 // hours with most meetings
    let meetingFreeWindows: [TimeWindow]        // recurring gaps with no meetings
    
    // Recurrence
    let recurringMeetings: [RecurringMeetingPattern]  // standup at 9am M-F, board meeting monthly, etc.
    let oneOffMeetingRatio: Float               // one-off / total
    
    // People
    let frequentAttendees: [(String, Int)]      // name -> meeting count
    let internalVsExternalRatio: Float          // requires domain inference
    
    // Cancellation patterns
    let cancellationRate: Float
    let mostCancelledDayOfWeek: Int
    let mostCancelledTimeOfDay: Int
    
    // Chronotype hints
    let inferredChronotype: ChronotypeHint
    let earliestConsistentActivity: Date        // earliest recurring meeting or accepted early meeting
    let latestConsistentActivity: Date
}

struct ChronotypeHint {
    let type: ChronotypeClass               // .earlyBird, .intermediate, .nightOwl
    let confidence: Float                    // how strong the signal is
    let evidence: String                     // "First meetings average 07:45, last meetings average 16:30"
}

enum ChronotypeClass {
    case earlyBird       // first activity consistently before 08:00
    case intermediate    // first activity 08:00–09:30
    case nightOwl        // first activity consistently after 09:30 or late meetings
}
```

### 3.3 How Bootstrap Data Is Used

| Inference | Applied To | Mechanism |
|---|---|---|
| Average meetings/day | Cognitive load baseline | Sets the "normal" meeting load so deviations can be detected |
| Meeting-free windows | Day plan generation | Pre-seeds the gap finder with known available windows |
| Recurring meetings | Calendar prediction | Anticipate schedule shape before Graph API returns today's data |
| Frequent attendees | Relationship map seed | Pre-populate the relationship tracker with names and frequency |
| Chronotype hint | Performance curve adjustment | If calendar data contradicts archetype default, shift the curve toward the observed pattern |
| Cancellation patterns | Tentative meeting scoring | Meetings on high-cancellation days/times are weighted as soft gaps |

### 3.4 Bootstrap Timing

- Import starts immediately after OAuth success
- Expected completion: 5–15 seconds (Graph API is fast for calendar views)
- The onboarding flow shows a progress indicator: "Importing your calendar history..."
- If the import fails or returns < 30 days of data, the system proceeds with archetype defaults only and retries the import in the background

---

## 4. Communicating Uncertainty

During cold start (days 1–14), the system explicitly communicates its confidence level. This builds trust — the executive knows the system is honest about what it does and doesn't know.

### 4.1 Confidence Framing

Every intelligence output during cold start includes a confidence indicator:

```swift
enum ConfidenceFrame: String {
    case learning   = "Still learning"          // < 7 days
    case emerging   = "Emerging understanding"  // 7–14 days
    case developing = "Developing model"        // 14–30 days
    case confident  = ""                        // > 30 days (no qualifier needed)
}
```

### 4.2 Morning Session Uncertainty Language

**Day 1:**
"This is our first morning session. I'm working from your [archetype] profile and 90 days of calendar history. My recommendations today are educated guesses — treat them as starting points, not instructions. Every correction you make teaches me."

**Day 3:**
"Low confidence — still learning your patterns. I've observed 3 days of your behaviour. My time estimates are based on category averages, not your personal data yet. Override freely — every override makes me smarter."

**Day 7:**
"Emerging understanding. I've detected 2 possible patterns but haven't confirmed them yet: [pattern descriptions]. My time estimates have improved — you're averaging [X]% closer to actual duration than my day-1 estimates."

**Day 14:**
"Developing model. I now have [X] facts about how you operate with an average confidence of [Y]. My first confirmed pattern: [pattern name and description]. From here, the system accelerates — every week adds significantly more intelligence than the last."

### 4.3 Query Response Uncertainty

During cold start, query responses include explicit uncertainty markers:

- "Low confidence — I have only [X] days of observation on this topic."
- "Based on your [archetype] profile, not your personal data yet."
- "I found [X] relevant memories, but they're all from the last [Y] days — this may not be representative."

### 4.4 Plan Uncertainty

Day plans during cold start include wider confidence intervals:

- Slot times carry ± 30 minutes (vs ± 10 minutes post-cold-start)
- The overflow list is larger (more tasks marked as "uncertain placement")
- Buffer allocation is 30% (vs 25% post-cold-start) to account for worse estimation

---

## 5. Active Preference Elicitation

### 5.1 Strategy

One targeted question per morning session during the first 14 days. The questions are sequenced to maximise information gain — each question fills the biggest gap in the current model.

### 5.2 Question Sequence

The system selects from a pool of elicitation questions, choosing the one that addresses the lowest-confidence area of the model at that point.

**Question Pool:**

```swift
struct ElicitationQuestion {
    let id: String
    let question: String
    let targetParameter: String        // which model parameter this updates
    let priority: Int                  // base priority (lower = asked earlier)
    let prerequisite: String?          // must be asked after this question
}

static let questionPool: [ElicitationQuestion] = [
    // Day 1-3: Fundamentals
    ElicitationQuestion(
        id: "deep_work_preference",
        question: "When during the day do you do your best thinking? Early morning, late morning, or afternoon?",
        targetParameter: "chronotypeWeights",
        priority: 1,
        prerequisite: nil
    ),
    ElicitationQuestion(
        id: "meeting_tolerance",
        question: "How many hours of meetings in a day before you feel drained? Three? Five? More?",
        targetParameter: "meetingTolerance",
        priority: 2,
        prerequisite: nil
    ),
    ElicitationQuestion(
        id: "biggest_time_waste",
        question: "What's the one thing that wastes your time most? Email? Meetings without outcomes? Context switching?",
        targetParameter: "avoidancePatterns",
        priority: 3,
        prerequisite: nil
    ),
    
    // Day 4-7: Work style
    ElicitationQuestion(
        id: "strategic_allocation",
        question: "In a perfect week, how many hours would you spend on strategic work vs operational?",
        targetParameter: "categoryPriors",
        priority: 4,
        prerequisite: nil
    ),
    ElicitationQuestion(
        id: "interruption_tolerance",
        question: "When you're doing deep work, do you prefer zero interruptions or are some pings acceptable?",
        targetParameter: "focusPreferences",
        priority: 5,
        prerequisite: "deep_work_preference"
    ),
    ElicitationQuestion(
        id: "email_rhythm",
        question: "How do you handle email — throughout the day, in batches, or only when forced?",
        targetParameter: "emailProcessingPattern",
        priority: 6,
        prerequisite: nil
    ),
    
    // Day 8-10: Relationships and patterns
    ElicitationQuestion(
        id: "key_relationships",
        question: "Who are the three people whose communications you should never miss?",
        targetParameter: "relationshipPriorities",
        priority: 7,
        prerequisite: nil
    ),
    ElicitationQuestion(
        id: "avoidance_awareness",
        question: "What type of work do you tend to put off? People decisions? Financials? Long-term planning?",
        targetParameter: "avoidancePatterns",
        priority: 8,
        prerequisite: "biggest_time_waste"
    ),
    ElicitationQuestion(
        id: "energy_recovery",
        question: "After a heavy meeting block, what helps you recover? A walk? Coffee? Switching to easy tasks?",
        targetParameter: "recoveryPatterns",
        priority: 9,
        prerequisite: "meeting_tolerance"
    ),
    
    // Day 11-14: Refinement
    ElicitationQuestion(
        id: "decision_style",
        question: "Do you make better decisions quickly or do you need to sleep on them?",
        targetParameter: "decisionStyle",
        priority: 10,
        prerequisite: nil
    ),
    ElicitationQuestion(
        id: "feedback_preference",
        question: "Would you rather I tell you about patterns bluntly or frame them gently?",
        targetParameter: "communicationStyle",
        priority: 11,
        prerequisite: nil
    ),
    ElicitationQuestion(
        id: "weekend_work",
        question: "Do you work weekends? If so, what kind of work — strategic catch-up or email?",
        targetParameter: "weekendPatterns",
        priority: 12,
        prerequisite: nil
    ),
]
```

### 5.3 Question Selection Algorithm

```
1. Filter pool to questions not yet asked
2. Filter by prerequisite satisfaction
3. For each remaining question:
   a. Look up the target parameter's current confidence in the model
   b. Compute information gain: 1.0 - parameterConfidence
4. Rank by: (information_gain * 0.7) + (base_priority_inverse * 0.3)
5. Select the top-ranked question
```

This ensures the system asks the question that fills the biggest knowledge gap, not just the next in a fixed sequence.

### 5.4 Response Integration

Each response is processed by Haiku to extract structured data:

```
Executive said: "I do my best thinking early, like 6:30 to 9. After that it's meetings."

Extract:
- Parameter: chronotypeWeights
- Peak window: 06:30–09:00
- Confidence: 0.7 (self-report — will be validated against observed behaviour)
- Action: Shift the archetype chronotype curve to peak at 06:30–09:00
```

The extracted preference is stored as a semantic memory with `source: .selfReport` and `confidence: 0.7` (self-reports are weighted lower than observed behaviour — executives overestimate their own patterns by 20–30% per Czerwinski et al. 2004).

---

## 6. EMA Cold Start

### 6.1 The Problem

EMA (Exponential Moving Average) duration estimates require historical completion data. On day 1, there is none.

### 6.2 Category Averages

Initial EMA values are set from the archetype's `durationPriors` (see Section 2). These are population-level estimates for each task category.

### 6.3 Update Schedule

```
Day 1: EMA = archetype duration prior
Day 1 (first completion): EMA = alpha * actual + (1-alpha) * prior, alpha = 0.5 (aggressive initial learning)
Day 2-7: alpha = 0.4 (still aggressive)
Day 8-14: alpha = 0.35 (settling)
Day 15+: alpha = 0.3 (steady state)
```

The higher initial alpha means the system learns fast from the first few data points, then stabilises as confidence grows.

### 6.4 Cross-Category Transfer

If a task has no category-specific history but a related category does, the system uses transfer learning:

```
Similar categories:
- strategic ↔ deepAnalysis (0.7 similarity)
- operational ↔ administrative (0.6 similarity)
- relational ↔ email (0.5 similarity)
- creative ↔ deepAnalysis (0.6 similarity)

Transfer: EMA_new_category = similarity * EMA_known_category + (1-similarity) * archetype_prior
```

This means if the executive has completed 5 deep analysis tasks (and the EMA is calibrated), their first strategic task uses 70% of the deep analysis EMA + 30% of the archetype strategic prior.

---

## 7. Cold Start Exit Criteria

The system exits cold start mode when ALL of the following are true:

| Criterion | Threshold | Rationale |
|---|---|---|
| Days of observation | >= 14 | Minimum for meaningful pattern detection |
| Morning sessions completed | >= 7 | Enough voice data for energy inference |
| Focus sessions completed | >= 10 | Enough for EMA calibration across categories |
| Semantic facts stored | >= 30 | Minimum model breadth |
| Average semantic confidence | >= 0.45 | Model has begun differentiating from archetype |
| Archetype influence | < 0.3 | Personalised data outweighs archetype priors |
| At least 1 confirmed pattern | True | System has detected something real |

When cold start exits, the morning session announces it:
"I've been learning for [X] days and I'm now confident enough to move past my initial assumptions. My model of you is still early, but it's mine — built from observing how you actually operate, not from a profile template. From here, every week gets measurably smarter."

---

## 8. Edge Cases

| Scenario | Behaviour |
|---|---|
| Executive skips archetype selection | Default to `general` archetype. All priors are balanced (alpha=5, beta=5). No pre-seeded patterns. The system learns purely from observation — slower but not broken. |
| Calendar import returns 0 events (new Outlook account) | Skip bootstrap. Rely entirely on archetype + elicitation. Flag: "I couldn't find calendar history to learn from. My first few days will be less accurate — I'll improve fast once I see your actual schedule." |
| Executive provides contradictory elicitation answers | Store both with reduced confidence (0.5 instead of 0.7). The reflection engine will resolve the contradiction from observed behaviour within 1-2 weeks. |
| Executive doesn't do morning sessions (days 1-7) | Elicitation questions queue up. When the executive does a morning session, ask the highest-priority unanswered question. Don't ask 3 at once — still one per session. The system can learn from passive signals (calendar, email) even without morning sessions — it just learns slower. |
| Executive changes archetype mid-onboarding | Allow re-selection within the first 7 days. After 7 days, the archetype is overridden by observed data and changing it has negligible effect — don't offer the option. |
| Task created with no category | Assign the `general` archetype's balanced priors. Prompt the executive (once) to categorise the task. If they don't, infer category from task title using Haiku. |
| Day 3 and system has nothing useful to say | Be honest: "I don't have enough data to give you a useful briefing yet. Today's plan is based on your [archetype] profile defaults. The most valuable thing you can do right now is complete a few focus sessions — that teaches me how long things actually take you." |

---

## 9. Cold Start Timeline Summary

| Day | What Happens | What the Executive Experiences |
|---|---|---|
| 0 | OAuth, archetype selection, 90-day calendar import | "Pick your profile" → brief loading → first plan |
| 1 | First morning session + elicitation Q1. Archetype defaults active. Calendar bootstrap applied. | Plan feels generic but structurally sound. Slots match calendar. Uncertainty is explicit. |
| 2 | Second morning session + elicitation Q2. First focus sessions feeding EMA. | Plan slightly adapted from yesterday's observations. Time estimates still rough. |
| 3 | **First-value target.** EMA has 2-3 data points per active category. Calendar patterns emerging. | Time estimates start beating the executive's own guesses. Plan feels less generic. |
| 5 | 5 morning sessions complete. Elicitation Q5 asked. First potential patterns flagged as `.emerging`. | Morning session mentions "I'm starting to see something in your afternoon patterns — not confirmed yet." |
| 7 | **First pattern confirmation possible.** Weekly snapshot taken. | Morning session presents first named pattern. System feels like it's starting to understand. |
| 10 | Elicitation nearing completion. EMA calibrated for common categories. Chronotype curve personalising. | Plan accuracy noticeably improved. Fewer overrides needed. |
| 14 | **Cold start exit evaluation.** If criteria met, transition to normal operation. | System announces transition. Confidence markers removed from output. |

---

## 10. CoreData Entities

```swift
@objc(CDColdStartState)
class CDColdStartState: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var archetypeID: String
    @NSManaged var archetypeSelectedAt: Date
    @NSManaged var calendarBootstrapCompleted: Bool
    @NSManaged var calendarBootstrapResultJSON: Data?
    @NSManaged var questionsAskedJSON: Data         // [String] of question IDs
    @NSManaged var coldStartExited: Bool
    @NSManaged var coldStartExitedAt: Date?
    @NSManaged var daysOfObservation: Int16
    @NSManaged var morningSessionsCompleted: Int16
    @NSManaged var focusSessionsCompleted: Int16
    @NSManaged var archetypeInfluence: Float        // 1.0 at start, decays toward 0
}

@objc(CDElicitationResponse)
class CDElicitationResponse: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var questionID: String
    @NSManaged var askedAt: Date
    @NSManaged var rawResponse: String              // executive's verbatim answer
    @NSManaged var extractedParameterJSON: Data     // structured extraction
    @NSManaged var targetParameter: String
    @NSManaged var appliedConfidence: Float
}
```

---

## 11. Metrics for Cold Start Quality

How to measure whether the cold start strategy is working:

| Metric | Target | Measured How |
|---|---|---|
| Time to first useful plan | Day 1 | Executive completes >= 1 planned task on day 1 |
| Time to first accurate estimate | Day 3 | EMA estimate within 20% of actual for any category |
| Time to first confirmed pattern | Day 7 | Reflection engine confirms a pattern |
| Override rate reduction | 50% reduction by day 14 vs day 1 | Count of plan overrides per day |
| Elicitation completion rate | > 80% of questions answered by day 14 | Questions asked / questions answered |
| Cold start exit by day 14 | > 70% of users | CDColdStartState.coldStartExited |
| Executive retention through cold start | > 85% still using at day 14 | Morning session completion rate |

The 30-day intelligence report (see intelligence-report.md) includes a cold start retrospective for first-time reports: "Here's how the system evolved from day 1 to day 30. Your archetype was [X]. By day [Y], your model had diverged from the archetype in these ways: [specifics]."
