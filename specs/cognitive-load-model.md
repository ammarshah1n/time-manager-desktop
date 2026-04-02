# Cognitive Load Proxy Model Spec

**System:** Timed — Cognitive Intelligence Layer for C-Suite Executives
**Layer:** Episodic Memory (real-time state) feeding Semantic Memory (learned load patterns)
**Models:** Haiku 3.5 (real-time load estimation), Opus (nightly load pattern analysis)
**Stack:** Swift 5.9+, CoreData, Supabase, Claude API
**Status:** Implementation-ready

---

## 1. Purpose

Estimate the executive's current cognitive load in real time using only digital signals — no wearables, no self-report, no interruption. Use this estimate to gate task recommendations (never suggest strategic work during high load), detect overload before the executive feels it, and build a longitudinal load profile that reveals structural patterns (e.g., "Every Monday afternoon you're overloaded because of back-to-back meetings").

Cognitive load is the bridge between the chronotype model (what SHOULD the executive be doing now) and reality (what CAN the executive handle right now). A peak analytical window is wasted if the executive is at cognitive capacity from three consecutive meetings.

---

## 2. Scientific Foundation

### 2.1 Digital Phenotyping for Cognitive State

- **Saeb et al. (2015)**: Demonstrated that smartphone sensor data (GPS, screen interactions, call logs) predicts depressive symptoms with clinically meaningful accuracy. Established the field of "digital phenotyping" — inferring psychological states from digital behaviour.
- **Abdullah et al. (2016)**: Used keyboard typing dynamics to detect cognitive load changes with ~78% accuracy. Typing speed, error rate, and pause patterns are strong proxies for cognitive state.
- **Mark et al. (2014)**: Measured computer activity and self-reported stress in situ. Found that stressed participants switched screens more frequently (mean switch every 40 seconds vs 75 seconds for non-stressed). App-switching rate is one of the strongest non-invasive cognitive load indicators.
- **Zuger & Fritz (2015)**: Combined computer interaction data (mouse, keyboard, scrolling) with biometrics. Computer interaction data alone achieved 68% accuracy for binary load classification (low/high). Adding biometrics improved to 78%. This sets our ceiling without wearables.

### 2.2 Cognitive Load Theory

- **Sweller (1988), Cognitive Load Theory**: Three types — intrinsic (task complexity), extraneous (environment/distraction), germane (learning effort). For executives, the primary load driver is **context-switching between unrelated high-complexity threads**, which maximises all three types simultaneously.
- **Kahneman (1973), Attention as Resource**: Cognitive capacity is a finite, depletable resource. Tasks compete for the same pool. After sustained high-load work, subsequent task performance degrades measurably. The recovery time depends on load intensity and duration.
- **Wickens (2002), Multiple Resource Theory**: Different cognitive resources (visual, auditory, verbal, spatial) can be used in parallel with less interference. Meeting followed by email is higher load than meeting followed by walking. This matters for scheduling recovery activities.

### 2.3 Meeting Density and Cognitive Drain

- **Perlow et al. (2017, Harvard Business Review)**: Executives spend 23+ hours/week in meetings. Self-reported meeting quality: 71% said meetings are unproductive. Meeting recovery time: 15-23 minutes of reduced performance after a 60-minute meeting (consistent with Gloria Mark's interruption recovery research).
- **Rogelberg et al. (2007)**: Meeting load correlates with fatigue, subjective workload, and lower end-of-day well-being. The effect is cumulative — each additional meeting in a day reduces the effectiveness of subsequent work.
- **Microsoft Research (2021, "Brain Breaks")**: Back-to-back video meetings cause cumulative stress (measured via EEG beta wave activity). 10-minute breaks between meetings reset stress accumulation. Breaks did not merely pause the buildup — they reversed it.

---

## 3. Signal Sources

### 3.1 Primary Signals

#### Signal 1: Email Open-to-Response Latency

**What it measures:** When the executive takes longer than their personal baseline to respond to emails, they're likely under higher cognitive load — they can't spare the bandwidth to compose a response.

**Implementation:**
```swift
struct EmailLatencySignal {
    let emailId: String
    let receivedAt: Date
    let firstOpenedAt: Date       // Track via Graph read receipt or app open
    let respondedAt: Date?
    let openToResponseMinutes: Double?
    let personalBaseline: Double  // Rolling 14-day median for this priority tier
    
    var loadContribution: Float {
        guard let actual = openToResponseMinutes else { return 0.3 } // Opened but not responded = moderate signal
        let ratio = Float(actual / personalBaseline)
        return min(max((ratio - 1.0) * 0.5, 0.0), 1.0) // Linear scaling above baseline
    }
}
```

**Key detail:** Segment by email priority tier (urgent, normal, low). An executive ignoring low-priority email is normal. An executive ignoring urgent email is a load signal.

#### Signal 2: Draft Deletion Frequency

**What it measures:** Starting to compose then abandoning = the executive can't formulate a response. Higher cognitive load impairs complex language production.

**Implementation:** Count of draft-create-then-delete events per hour. Normalise against personal baseline. 2x baseline = moderate load signal. 4x+ = high load signal.

#### Signal 3: App-Switch Rate

**What it measures:** Rapid switching between applications without sustained activity in any one app. This is the single strongest non-invasive indicator of cognitive fragmentation (Mark et al., 2014).

**Implementation:**
```swift
struct AppSwitchSignal {
    let windowStart: Date         // 15-minute trailing window
    let windowEnd: Date
    let switchCount: Int          // NSWorkspace.didActivateApplicationNotification count
    let uniqueApps: Int           // Distinct apps activated
    let longestStaySeconds: Double // Longest continuous stay in one app
    let personalBaseline: Double  // Rolling 14-day median switches per 15 minutes
    
    var loadContribution: Float {
        let switchRatio = Float(switchCount) / Float(max(Int(personalBaseline), 1))
        let fragmentationBonus: Float = longestStaySeconds < 60 ? 0.2 : 0.0 // Extra signal if can't stay anywhere
        return min(max((switchRatio - 1.0) * 0.4 + fragmentationBonus, 0.0), 1.0)
    }
}
```

**macOS API:** `NSWorkspace.shared.notificationCenter` observing `NSWorkspace.didActivateApplicationNotification`. Requires no special permissions. Captures app name, timestamp, and bundle identifier.

#### Signal 4: Meeting Density (Trailing 2 Hours)

**What it measures:** Cumulative cognitive drain from recent meetings. Not just "are you in a meeting now" but "how much meeting load have you absorbed recently?"

**Implementation:**
```swift
struct MeetingDensitySignal {
    let windowStart: Date         // now - 2 hours
    let windowEnd: Date           // now
    let meetingMinutes: Int       // Total minutes in meetings during window
    let meetingCount: Int         // Number of distinct meetings
    let backToBackCount: Int      // Meetings with < 10 min gap
    let longestBreakMinutes: Int  // Longest gap between meetings
    
    var loadContribution: Float {
        let densityRatio = Float(meetingMinutes) / 120.0 // 120 minutes = max
        let backToBackPenalty = Float(backToBackCount) * 0.15
        let breakBonus = longestBreakMinutes > 15 ? -0.1 : 0.0 // Had a real break
        return min(max(densityRatio + backToBackPenalty + breakBonus, 0.0), 1.0)
    }
}
```

**Research note:** The 2-hour trailing window is based on Microsoft's EEG research showing that meeting stress accumulates over approximately 2 hours and resets after a 10+ minute break.

#### Signal 5: Calendar Whitespace Usage

**What it measures:** When the executive has free time between meetings, do they use it for deep work (low app-switching, sustained focus) or frittering (email checking, rapid app-switching, low-value tasks)? Frittering during free time is a strong overload indicator — they can't muster the cognitive resources for focused work.

**Implementation:** During detected free blocks (no calendar event, > 15 minutes), measure app-switch rate and task completion rate. Compare to the executive's baseline for free blocks.

### 3.2 Secondary Signals

| Signal | What It Measures | Weight |
|--------|-----------------|--------|
| **Typing speed variance** | Keystroke dynamics via NSEvent monitoring. Speed drops under load. | 0.15 |
| **Email length anomaly** | Unusually short responses to emails that normally warrant longer replies (Haiku-classified) | 0.10 |
| **Calendar modification frequency** | Rescheduling/cancelling meetings at the last minute = overloaded | 0.10 |
| **Focus session abandonment** | Starting a focus session and quitting early | 0.15 |
| **Late-night activity** | Working past their normal cognitive stop time = carrying over load from the day | 0.10 |
| **Response prioritisation inversion** | Responding to low-priority items while ignoring high-priority = avoidance under load | 0.15 |

---

## 4. Composite Load Score

### 4.1 Score Architecture

Two complementary scores:

**Real-Time Trailing Score (updated every 5 minutes):**
```swift
struct CognitiveLoadScore {
    let timestamp: Date
    let trailingScore: Float      // 0.0-1.0, last 30 minutes of signals
    let twoHourScore: Float       // 0.0-1.0, last 2 hours (captures meeting drain)
    let dailyAccumulated: Float   // 0.0-1.0, accumulated load since cognitive start today
    let level: LoadLevel
    let dominantFactor: String    // "meeting_density", "app_switching", "email_latency", etc.
    let confidence: Float         // Based on signal availability
}

enum LoadLevel {
    case low        // 0.0-0.25 — Executive has bandwidth. Good time for strategic/analytical work.
    case moderate   // 0.25-0.50 — Normal operating state. Most task types are fine.
    case high       // 0.50-0.75 — Elevated load. Suggest administrative or low-complexity tasks only.
    case overloaded // 0.75-1.0 — Cognitive capacity exhausted. Suggest break or easy wins only.
}
```

**Daily Accumulated Load:**
```
accumulated_load(t) = integral of trailing_score over [cognitive_start, t] / (t - cognitive_start)
```

This captures the cumulative effect of a hard day. An executive might have a low trailing score at 4pm (just had a break) but high accumulated load (9 hours of sustained high-load work). Both matter.

### 4.2 Score Computation

```swift
func computeTrailingLoad(signals: [LoadSignal], window: TimeInterval = 1800) -> Float {
    let windowSignals = signals.filter { $0.timestamp > Date().addingTimeInterval(-window) }
    
    guard !windowSignals.isEmpty else { return 0.0 }
    
    // Weighted combination — weights learned from executive's personal calibration
    let weights: [String: Float] = [
        "app_switch": 0.25,
        "meeting_density": 0.25,
        "email_latency": 0.20,
        "draft_deletion": 0.10,
        "whitespace_usage": 0.10,
        "secondary_composite": 0.10
    ]
    
    var weightedSum: Float = 0.0
    var weightTotal: Float = 0.0
    
    for (signalType, weight) in weights {
        if let signal = windowSignals.last(where: { $0.type == signalType }) {
            weightedSum += signal.contribution * weight
            weightTotal += weight
        }
    }
    
    return weightTotal > 0 ? weightedSum / weightTotal : 0.0
}
```

### 4.3 Personal Baseline Calibration

All signal contributions are computed relative to the executive's personal baseline, not absolute values.

**Baseline computation:** Rolling 14-day median for each signal, segmented by:
- Day of week (Monday baselines differ from Friday)
- Time of day (morning baselines differ from afternoon)
- Meeting context (post-meeting baselines differ from free-block baselines)

**Why 14-day rolling median:** Resistant to outliers. Adapts to gradual changes. Long enough to be stable, short enough to track drift.

**Cold start:** First 14 days use population averages. Morning session communicates: "I'm still calibrating your load patterns. I'll have a personalised model in about two weeks."

---

## 5. Task Recommendation Gating

### 5.1 Load-Aware Scheduling Rules

The scheduling engine checks the current load score before recommending tasks:

| Load Level | Allowed Task Types | Blocked Task Types |
|------------|-------------------|-------------------|
| **Low** (0.0-0.25) | All types. Ideal for analytical, creative, strategic. | None |
| **Moderate** (0.25-0.50) | Interpersonal, administrative, moderate-complexity analytical | High-complexity creative work (requires low load for divergent thinking) |
| **High** (0.50-0.75) | Administrative, routine, email processing, quick wins | Analytical, creative, strategic, important 1:1s |
| **Overloaded** (0.75-1.0) | Only: break, walk, easy wins, or "inbox zero" processing | Everything else. System suggests: "You've been running hard. A 15-minute break would reset your next hour." |

### 5.2 Proactive Load Warnings

When the scheduling engine detects that the current schedule will push load to overloaded before a high-priority task:

> "You have back-to-back meetings from 1:00-3:30. Your board strategy review is at 4:00. Based on your pattern, you'll be at high cognitive load by 3:30 — your analytical performance drops ~30% at that load level. Consider moving the strategy review to tomorrow morning, or blocking 3:30-4:00 as a recovery break."

### 5.3 Recovery Estimation

```swift
func estimateRecoveryTime(fromLoad: LoadLevel, toLoad: LoadLevel) -> TimeInterval {
    // Based on Microsoft Research (2021) and Mark et al. (2014)
    // Recovery is non-linear — going from high to low takes longer than high to moderate
    let recoveryMatrix: [LoadLevel: [LoadLevel: TimeInterval]] = [
        .overloaded: [.high: 10*60, .moderate: 20*60, .low: 35*60],
        .high:       [.moderate: 10*60, .low: 25*60],
        .moderate:   [.low: 10*60]
    ]
    return recoveryMatrix[fromLoad]?[toLoad] ?? 0
}
```

Recovery estimates are personalised after 4 weeks of data — some executives recover faster than others.

---

## 6. Interaction with Other Models

### 6.1 Chronotype Model Integration

The chronotype model provides the "expected" performance for a given time. The cognitive load model provides the "actual" capacity. The delta is the key signal:

```
effective_capacity(t) = chronotype_performance(t) * (1 - cognitive_load(t))
```

When `effective_capacity` drops below 0.3, the system blocks all non-trivial task recommendations regardless of chronotype peak.

### 6.2 Avoidance Detector Integration

High cognitive load makes avoidance more likely (Baumeister's ego depletion). When load is high AND an item with avoidance signals is on the schedule:

- Do NOT surface the avoidance in the moment (adds cognitive load)
- Note it for the morning session: "Yesterday afternoon you were at high load and the Sarah 1:1 got deferred again. This is a pattern — you tend to defer people decisions when load is high. Consider scheduling these for morning low-load windows."

### 6.3 Reflection Engine Integration

The nightly reflection engine receives the day's load curve and analyses:
- Peak load moments and their causes
- Load recovery patterns
- Correlation between load and task quality
- Structural load patterns (every Monday afternoon, every post-board-meeting day)

---

## 7. Data Model (CoreData)

```swift
@Model
class CognitiveLoadSnapshot {
    var id: UUID
    var timestamp: Date
    var trailingScore: Float      // 30-minute trailing
    var twoHourScore: Float       // 2-hour trailing
    var dailyAccumulated: Float   // Day-to-date
    var level: String             // "low", "moderate", "high", "overloaded"
    var dominantFactor: String
    var confidence: Float
    var signalBreakdown: Data     // JSON: per-signal contributions
}

@Model
class CognitiveLoadBaseline {
    var id: UUID
    var signalType: String        // "app_switch", "email_latency", etc.
    var dayOfWeek: Int            // 1-7
    var hourBin: Int              // 0-23
    var medianValue: Float
    var stdDev: Float
    var sampleCount: Int
    var lastUpdated: Date
}

@Model
class LoadPattern {
    var id: UUID
    var patternName: String       // "Monday Afternoon Overload"
    var description: String
    var dayOfWeek: Int?
    var hourRange: Data           // JSON: {start: 13, end: 17}
    var avgLoadLevel: Float
    var primaryCause: String      // "meeting_density", "context_switching"
    var occurrenceCount: Int
    var confidence: Float
    var isActive: Bool
    var createdAt: Date
}
```

### Supabase Schema

```sql
create table cognitive_load_snapshots (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    timestamp timestamptz not null,
    trailing_score real not null,
    two_hour_score real not null,
    daily_accumulated real not null,
    level text not null,
    dominant_factor text not null,
    confidence real not null,
    signal_breakdown jsonb not null default '{}',
    created_at timestamptz not null default now()
);

-- Downsample after 30 days: keep 15-minute granularity instead of 5-minute
-- Downsample after 90 days: keep hourly granularity
-- Keeps storage manageable while preserving long-term patterns

create index idx_load_user_time on cognitive_load_snapshots(user_id, timestamp desc);

create table cognitive_load_baselines (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    signal_type text not null,
    day_of_week smallint not null,
    hour_bin smallint not null,
    median_value real not null,
    std_dev real not null,
    sample_count integer not null default 0,
    updated_at timestamptz not null default now(),
    unique(user_id, signal_type, day_of_week, hour_bin)
);

create table load_patterns (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    pattern_name text not null,
    description text not null,
    day_of_week smallint,
    hour_range jsonb,
    avg_load_level real not null,
    primary_cause text not null,
    occurrence_count integer not null default 0,
    confidence real not null default 0.0,
    is_active boolean not null default true,
    created_at timestamptz not null default now()
);

-- RLS
alter table cognitive_load_snapshots enable row level security;
alter table cognitive_load_baselines enable row level security;
alter table load_patterns enable row level security;

create policy "own_data" on cognitive_load_snapshots for all using (auth.uid() = user_id);
create policy "own_data" on cognitive_load_baselines for all using (auth.uid() = user_id);
create policy "own_data" on load_patterns for all using (auth.uid() = user_id);
```

---

## 8. Processing Pipeline

### 8.1 Real-Time (Local — every 5 minutes)

No LLM needed for real-time load computation. Pure algorithmic:

```swift
class CognitiveLoadEngine {
    private var signalBuffer: [LoadSignal] = []
    private var baselines: [String: CognitiveLoadBaseline] = [:]
    private var timer: Timer?
    
    func start() {
        // Subscribe to signals
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appSwitched(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        
        // Compute every 5 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.computeAndStore()
        }
    }
    
    private func computeAndStore() {
        let trailing = computeTrailingLoad(signals: signalBuffer, window: 1800)
        let twoHour = computeTrailingLoad(signals: signalBuffer, window: 7200)
        let accumulated = computeDailyAccumulated()
        
        let snapshot = CognitiveLoadSnapshot(
            timestamp: Date(),
            trailingScore: trailing,
            twoHourScore: twoHour,
            dailyAccumulated: accumulated,
            level: LoadLevel.from(trailing),
            dominantFactor: identifyDominantFactor(),
            confidence: computeConfidence()
        )
        
        // Store to CoreData
        modelContext.insert(snapshot)
        
        // Notify scheduling engine if level changed
        if snapshot.level != previousLevel {
            NotificationCenter.default.post(name: .cognitiveLoadChanged, object: snapshot)
        }
    }
}
```

**Cost:** Zero LLM tokens for real-time load. Pure local computation. This runs even when offline.

### 8.2 Nightly (Opus — during reflection engine)

During reflection Stage 2:

1. Pull the day's load curve (all 5-minute snapshots)
2. Identify structural patterns (does this Tuesday look like last Tuesday?)
3. Correlate load with task outcomes (did high-load periods produce worse results?)
4. Update or create `LoadPattern` entries
5. Generate load-aware scheduling recommendations for tomorrow

**Opus prompt (within reflection pipeline):**
```
Analysing cognitive load patterns for [executive name].

Today's load curve:
[Array of CognitiveLoadSnapshot at 15-min intervals]

Today's calendar:
[Meeting schedule with durations and gaps]

Task completions and their load-at-time-of-completion:
[Task outcomes paired with load scores]

Known load patterns:
[Active LoadPattern entries]

Tasks:
1. Characterise today's load trajectory — what drove the peaks?
2. Did high load correlate with lower task quality or avoidance behaviour?
3. Does today match or deviate from known patterns?
4. Any new structural patterns emerging?
5. One load-management recommendation for tomorrow's morning briefing

Output as structured JSON.
```

---

## 9. Display and Surfacing

### 9.1 Menu Bar Indicator

The menu bar presence shows a subtle load indicator:

- **Green dot** — Low load. Bandwidth available.
- **Yellow dot** — Moderate load. Normal operating state.
- **Orange dot** — High load. System is gating recommendations.
- **Red dot** — Overloaded. System suggests recovery.

No numeric score visible — executives don't need a number. They need a traffic light.

### 9.2 Morning Briefing Load Intelligence

> "Yesterday you hit high load at 2:15pm after three consecutive meetings. Your task quality dropped measurably in the afternoon — you spent 40% longer on the finance review than your baseline. This happens most Tuesdays because of your recurring meeting block. Consider requesting a 15-minute gap between the 1:00 and 2:00 meetings, or moving the finance review to Wednesday morning when you're typically at low load."

### 9.3 Real-Time Nudges (Configurable)

If the executive opts in (off by default — respect autonomy):

- After 2+ hours at high load without a break: "You've been running at high cognitive load for 2 hours. A 10-minute break would improve your next hour's performance by approximately 25%."
- Before a scheduled high-priority task at high load: "Your strategy session starts in 30 minutes. You're currently at high load. Consider stepping away for 15 minutes first."

---

## 10. Validation

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Load-performance correlation** | r > 0.4 | Correlate load score with task completion velocity relative to estimate |
| **Self-report alignment** | > 65% agreement | Occasional morning session question: "On a scale, how drained did you feel at 3pm yesterday?" Compare to load score at that time |
| **Gating effectiveness** | Measurable quality improvement | Compare task quality when done in recommended load windows vs against recommendation |
| **False overload rate** | < 15% | Times system said "overloaded" but executive reports feeling fine |

---

## 11. Data Retention and Downsampling

| Age | Granularity | Storage |
|-----|------------|---------|
| 0-30 days | 5-minute snapshots | Full detail in CoreData and Supabase |
| 30-90 days | 15-minute snapshots | Downsample via Supabase cron function |
| 90+ days | Hourly averages | Downsample further; patterns preserved, raw data discarded |
| Patterns | Permanent | `LoadPattern` entries persist indefinitely |

---

## 12. Implementation Sequence

1. **NSWorkspace observer for app-switch tracking** — register for `didActivateApplicationNotification`, store in signal buffer
2. **Email latency tracking** — hook into `EmailSyncService` to compute open-to-response time
3. **Meeting density computation** — calendar parser that computes trailing meeting minutes
4. **CognitiveLoadEngine core** — 5-minute timer, composite score computation, CoreData storage
5. **Personal baseline system** — rolling 14-day median calculator, segmented by day/hour
6. **Menu bar load indicator** — traffic light dot in menu bar view
7. **Scheduling engine integration** — load-aware task gating
8. **Nightly reflection integration** — load curve analysis in Opus prompt
9. **Morning briefing load intelligence** — natural language load insights
10. **Downsampling cron** — Supabase Edge Function for data lifecycle management
11. **Optional real-time nudges** — configurable notification system
