# Avoidance Pattern Detector Spec

**System:** Timed — Cognitive Intelligence Layer for C-Suite Executives
**Layer:** Procedural Memory (rules about how the executive operates)
**Models:** Haiku 3.5 (real-time signal collection), Sonnet (pattern aggregation), Opus (nightly classification + surfacing)
**Stack:** Swift 5.9+, CoreData, Supabase, Claude API
**Status:** Implementation-ready

---

## 1. Purpose

Detect when the executive is avoiding a task versus rationally deprioritising it. Surface avoidance patterns during the morning session so the executive confronts them with full awareness — not as an accusation, but as a mirror.

This is one of the highest-value capabilities in Timed. No other tool does this. An executive coach charges $500/hour and takes months to identify avoidance patterns. Timed detects them from behavioural data in real time.

---

## 2. The Core Distinction: Avoidance vs Rational Deprioritisation

This is the hardest classification problem in the system. Both look similar on the surface — a task gets deferred. The difference is the WHY:

| Dimension | Avoidance | Rational Deprioritisation |
|-----------|-----------|--------------------------|
| **Cause** | Emotional discomfort, anxiety, conflict aversion, perfectionism, unclear next step | Changed priorities, new information, resource constraint, dependency |
| **Pattern** | Repeated deferral without context change | Single deferral with context change |
| **Behavioural signature** | Engagement without completion (viewing, drafting, deleting) | Clean removal or rescheduling with rationale |
| **Metacognitive state** | Executive often unaware they're avoiding | Executive can articulate why they deprioritised |
| **Category affinity** | People decisions, confrontational emails, ambiguous strategic choices | Operational tasks, dependent tasks, genuinely lower priority items |

---

## 3. Scientific Foundation

### 3.1 Computational Procrastination Detection

- **Steel (2007), "The Nature of Procrastination"**: Meta-analysis identifying four predictors: task aversiveness, task delay (remoteness of deadline), self-efficacy, impulsiveness. For executives, task aversiveness is the dominant factor — specifically emotional aversiveness (people decisions, confrontation, ambiguity).
- **Sirois & Pychyl (2013)**: Procrastination as emotion regulation failure — people avoid tasks to avoid negative emotions associated with the task, not because of poor time management. This is critical for detection: look for emotional signatures, not scheduling patterns.
- **Gustavson et al. (2014)**: Procrastination shares genetic variance with impulsivity but is behaviourally distinct. For executives, avoidance is typically domain-specific (they're decisive in operations but avoid people issues, or vice versa).

### 3.2 Hybrid Brain Models and Executive Function

- **Kahneman (2011), System 1/System 2**: Avoidance is a System 1 response — automatic emotional withdrawal from aversive stimuli. The executive's System 2 rationalises ("I'll get to it tomorrow" / "Not the right time"). Timed needs to detect the System 1 pattern beneath the System 2 rationalisation.
- **Baumeister's Ego Depletion Model** (partially replicated): Decision fatigue reduces willingness to engage with aversive tasks. Avoidance is more likely late in the day and after high-cognitive-load periods. This interacts with the Cognitive Load Model.
- **Gross (2015), Emotion Regulation**: Avoidance is a form of situation selection (avoiding the situation that triggers negative emotion). Detectable because the avoidance behaviour is consistent across instances — the same emotional trigger produces the same avoidance pattern.

### 3.3 Executive-Specific Avoidance Research

- **Goldsmith, "What Got You Here Won't Get You There" (2007)**: Executives have specific blind spots that they systematically avoid addressing. Most common: giving difficult feedback, admitting uncertainty, delegating what they enjoy, confronting underperformers.
- **Lencioni, "The Five Dysfunctions of a Team" (2002)**: Avoidance of conflict is the second dysfunction. Executives who avoid conflict create information vacuums detectable from communication patterns (key conversations that should happen but don't).

---

## 4. Signal Sources

### 4.1 Primary Avoidance Signals

#### Signal 1: Repeated Deferral (3+ times)

**Definition:** A task or email appears on the plan, gets deferred to the next day (or later), and this happens 3 or more times without any change in the task's context (deadline, dependencies, priority).

**Data source:** CoreData `Task` entity — track `deferralCount`, `originalDueDate`, `currentDueDate`, `lastDeferredAt`.

**Scoring:**
```swift
struct DeferralSignal {
    let taskId: UUID
    let deferralCount: Int
    let daysSinceCreation: Int
    let contextChanged: Bool  // Did deadline, priority, or dependencies change?
    
    var avoidanceScore: Float {
        if contextChanged { return 0.0 } // Rational deferral
        switch deferralCount {
        case 0...2: return 0.0            // Normal
        case 3: return 0.4                // Mild signal
        case 4: return 0.6                // Moderate signal
        case 5: return 0.8                // Strong signal
        default: return 0.95             // Near-certain avoidance
        }
    }
}
```

#### Signal 2: Draft-Then-Delete on Emails

**Definition:** The executive opens an email, starts composing a reply, then deletes the draft or navigates away without sending. Repeated instances for the same thread.

**Data source:** Microsoft Graph drafts API + email sync. Detect draft creation events for a thread followed by draft deletion or abandonment.

**Implementation:**
```swift
struct DraftDeleteSignal {
    let threadId: String
    let draftAttempts: Int        // Number of draft-start events
    let completedDrafts: Int      // Number actually sent
    let avgDraftDuration: TimeInterval // How long they spent before abandoning
    
    var avoidanceScore: Float {
        let abandonRate = 1.0 - (Float(completedDrafts) / Float(max(draftAttempts, 1)))
        return min(abandonRate * Float(draftAttempts) * 0.3, 0.95)
    }
}
```

#### Signal 3: Rescheduling Without Context Change

**Definition:** A meeting or task gets rescheduled but the stated reason (if any) doesn't map to an actual context change. The meeting with the underperforming direct report gets moved three times. The "quarterly review" keeps sliding.

**Data source:** Outlook calendar change events via Graph delta sync. Track `rescheduledCount` per recurring series and per unique meeting.

**Scoring:** Same logic as deferral signal but applied to calendar events. Weight higher for 1:1 meetings (which the executive controls) vs group meetings (which may have legitimate scheduling conflicts).

#### Signal 4: Task That Surfaces Then Disappears

**Definition:** A task appears (created or mentioned in morning session), exists briefly, then gets deleted or archived without completion. Re-appears days or weeks later. The cycle repeats.

**Data source:** CoreData `Task` lifecycle tracking — `createdAt`, `archivedAt`, `deletedAt`, `restoredAt`. Track zombie tasks that keep coming back.

**Scoring:**
```swift
struct ZombieTaskSignal {
    let taskId: UUID
    let creationCount: Int        // Times created/restored
    let deletionCount: Int        // Times deleted/archived
    let totalLifespanDays: Int    // Days since first appearance
    
    var avoidanceScore: Float {
        if creationCount >= 3 && deletionCount >= 2 {
            return min(Float(creationCount) * 0.25, 0.95)
        }
        return 0.0
    }
}
```

#### Signal 5: Long View Time Without Action

**Definition:** The executive opens a task detail or email, spends significant time viewing it (> 60 seconds for a task, > 90 seconds for an email), then closes without taking any action (no reply, no status change, no delegation, no scheduling).

**Data source:** App analytics — track view duration per item. Distinguish "reading to decide" (normal, ends with action) from "reading and freezing" (avoidance, ends with close).

**Scoring:**
```swift
struct ViewWithoutActionSignal {
    let itemId: UUID
    let itemType: ItemType       // .task, .email, .meeting
    let viewCount: Int           // Times opened without action
    let totalViewDuration: TimeInterval
    let avgViewDuration: TimeInterval
    
    var avoidanceScore: Float {
        let longView = avgViewDuration > 60 // seconds
        let repeated = viewCount >= 2
        if longView && repeated {
            return min(Float(viewCount) * 0.25, 0.90)
        }
        return 0.0
    }
}
```

### 4.2 Secondary Signals (enrichment)

| Signal | Description | Weight |
|--------|-------------|--------|
| **Task category clustering** | Avoided items cluster in specific categories (e.g., all "people decisions" or all "ambiguous/strategic") | +0.15 if category match with known avoidance domain |
| **Time-of-day pattern** | Avoidance is more common at specific times (usually after cognitive load peaks) | +0.10 if occurring in known low-performance window |
| **Substitute activity** | Executive does low-value busy work instead of the avoided task (email triage when strategic work is pending) | +0.20 if substitute activity detected |
| **Verbal hedging in morning session** | Executive mentions the task but uses hedging language ("I should probably...", "I need to get around to...") | +0.15 if Haiku detects hedging markers |
| **Physical avoidance proxy** | Executive switches to a different app immediately after viewing the avoided item | +0.10 if rapid context-switch detected |

---

## 5. Classification Pipeline

### 5.1 Composite Avoidance Score

For each item (task, email thread, meeting, decision):

```swift
struct AvoidanceAssessment {
    let itemId: UUID
    let itemType: ItemType
    let signals: [AvoidanceSignal]     // All observed signals for this item
    let compositeScore: Float          // Weighted combination
    let confidence: Float              // Based on signal count and consistency
    let classification: AvoidanceClass
    let suggestedCategory: String?     // "people-decision", "confrontation", "ambiguity", etc.
    let firstDetected: Date
    let daysSinceFirstDetected: Int
}

enum AvoidanceClass {
    case notAvoiding              // score < 0.3
    case possibleAvoidance        // score 0.3-0.5 — monitor, don't surface yet
    case likelyAvoidance          // score 0.5-0.7 — surface with soft framing
    case strongAvoidance          // score > 0.7 — surface with direct framing
}
```

**Composite score formula:**
```
composite = max(individual_signals) * 0.6 + mean(individual_signals) * 0.3 + category_bonus * 0.1
```

Using max-weighted rather than pure average because a single very strong signal (5x deferral) is more diagnostic than multiple weak signals.

### 5.2 Confidence Thresholds

| Condition | Action |
|-----------|--------|
| `compositeScore < 0.3` | No avoidance detected. Item is being rationally managed. |
| `compositeScore 0.3-0.5, signals < 3` | Possible avoidance but insufficient evidence. Add to watch list. Do not surface. |
| `compositeScore 0.3-0.5, signals >= 3` | Possible avoidance with corroborating signals. Surface gently in morning session as observation, not assertion. |
| `compositeScore 0.5-0.7` | Likely avoidance. Surface in morning session with evidence: "This is the third time this has moved. Worth considering why." |
| `compositeScore > 0.7` | Strong avoidance. Surface prominently. If pattern matches a known avoidance domain, name the pattern. |

### 5.3 False Positive Mitigation

The worst outcome is the system incorrectly accusing the executive of avoidance when they're being rational. Mitigations:

1. **Context change check:** Before classifying any deferral as avoidance, verify no context changed (deadline moved, dependency added, priority explicitly lowered, new information received). If context changed, reset the signal.

2. **Executive override:** If the executive says "I'm not avoiding this, I'm waiting on X" — record the override. If the stated reason resolves and the item still doesn't move, the override expires and the signal reactivates.

3. **Category calibration:** Track false positive rate per avoidance category. If the executive consistently overrides "people-decision" avoidance flags, reduce the category weight. The system learns what this specific executive avoids vs what they legitimately defer.

4. **Asymmetric cost function:** A false positive (calling rational deprioritisation "avoidance") is more costly than a false negative (missing real avoidance). Set the surfacing threshold conservatively — better to miss some avoidance than to cry wolf.

---

## 6. Pattern Recognition and Naming

### 6.1 Avoidance Domain Classification

Opus, during nightly reflection, classifies avoided items into domains:

| Domain | Pattern | Typical Items |
|--------|---------|---------------|
| **People decisions** | Avoids difficult conversations, performance reviews, hiring/firing decisions | 1:1 with underperformer, "have the conversation with X" task, HR escalation |
| **Confrontation** | Avoids sending emails or having meetings where they must disagree or push back | Reply to board member, vendor renegotiation, "say no to Y" |
| **Ambiguity** | Avoids tasks with unclear scope, undefined next steps, or no obvious right answer | Strategic planning items, "figure out the Q3 approach", open-ended research |
| **Perfectionism** | Avoids completing and shipping work that feels "not ready" | Board deck finalisation, investor update, product launch sign-off |
| **Delegation resistance** | Avoids handing off tasks they enjoy or feel only they can do well | Detailed operational tasks, hands-on technical work, client-facing presentations |

### 6.2 Named Pattern Generation

When Opus detects a recurring avoidance pattern (3+ instances in the same domain over 30 days), it generates a named pattern:

```json
{
    "pattern_name": "The People Freeze",
    "domain": "people-decisions",
    "description": "You consistently defer decisions involving direct feedback to team members. The average deferral is 4.2 times before action. This pattern has appeared 5 times in 30 days.",
    "instances": [
        {"item": "1:1 with Sarah re: performance", "deferrals": 5, "resolved": false},
        {"item": "Reply to Tom's proposal", "deferrals": 3, "resolved": true, "resolution_trigger": "deadline forced action"},
        {"item": "HR escalation for Q4 hire", "deferrals": 4, "resolved": false}
    ],
    "insight": "The pattern resolves only when external deadlines force action. Without a forcing function, these items can drift for weeks.",
    "cost_estimate": "The average delay on people decisions is 12 days. In the Sarah case, this allowed the performance issue to compound — she missed two additional deliverables during the delay period."
}
```

### 6.3 Connection to Procedural Memory

Named avoidance patterns become procedural rules:

```json
{
    "rule_type": "avoidance_pattern",
    "rule": "When a people-decision task is deferred for the second time, flag it prominently in the next morning session",
    "confidence": 0.82,
    "evidence_count": 5,
    "created_by": "reflection_engine_v12",
    "created_at": "2026-04-15T02:00:00Z"
}
```

These rules persist in procedural memory and are loaded into the morning Opus Director's system prompt, so the system proactively watches for the pattern.

---

## 7. Surfacing in Morning Session

### 7.1 Framing Principles

Avoidance surfaces as observation, not judgment. The system is a mirror, not a critic.

**Tone calibration:**
- Never: "You're avoiding this task."
- Never: "You should stop procrastinating on this."
- Yes: "This is the third time this item has moved. It might be worth asking yourself what's making it hard to start."
- Yes: "I've noticed a pattern — tasks involving direct feedback to team members tend to defer 4-5 times before you act. The Sarah 1:1 is following the same trajectory."
- Yes: "The compliance review has been on your list for 8 days without progress. Last time you had a task like this, it resolved when you broke it into a 15-minute first step."

### 7.2 Escalation Ladder

| Day Count | Surfacing Approach |
|-----------|--------------------|
| First detection (day ~3) | No mention. Add to watch list. |
| Second detection (day ~5-7) | Brief mention: "The [item] has moved a few times. Want to tackle it today?" |
| Third detection (day ~8-12) | Pattern naming: "This is following the same pattern as [previous instance]. You tend to defer [domain] items until [trigger]. Worth considering?" |
| Fourth+ detection (day 12+) | Cost surfacing: "The [item] has been deferred [N] times over [D] days. Here's what I've observed about the cost of the delay: [specific consequence]." |

### 7.3 Positive Reinforcement

When the executive completes an item that was flagged as avoidance:

> "You completed the Sarah 1:1 today after 5 deferrals. The pattern I've observed is that once you start these conversations, they take about 20 minutes and you consistently describe feeling relieved afterward. Worth remembering next time one of these stalls."

This creates a procedural memory linking completion of aversive tasks to positive outcomes, which the system references in future avoidance situations.

---

## 8. Data Model (CoreData)

```swift
@Model
class AvoidanceSignal {
    var id: UUID
    var itemId: UUID                  // Task, email thread, or meeting ID
    var itemType: String              // "task", "email", "meeting", "decision"
    var signalType: String            // "deferral", "draft_delete", "reschedule", "zombie", "view_no_action"
    var timestamp: Date
    var signalScore: Float            // 0.0-1.0
    var metadata: Data                // JSON: signal-specific details
}

@Model
class AvoidanceAssessment {
    var id: UUID
    var itemId: UUID
    var itemType: String
    var compositeScore: Float
    var confidence: Float
    var classification: String        // "not_avoiding", "possible", "likely", "strong"
    var domain: String?               // "people", "confrontation", "ambiguity", "perfectionism", "delegation"
    var daysTracked: Int
    var surfacingLevel: Int           // 0 = watch, 1 = mention, 2 = pattern, 3 = cost
    var executiveOverride: Bool       // User said "not avoiding"
    var overrideReason: String?
    var overrideExpiresAt: Date?
    var resolved: Bool
    var resolvedAt: Date?
    var resolutionTrigger: String?    // "completed", "delegated", "cancelled", "deadline_forced"
    var lastUpdated: Date
}

@Model
class AvoidancePattern {
    var id: UUID
    var patternName: String           // "The People Freeze"
    var domain: String
    var description: String
    var instanceIds: [UUID]           // AvoidanceAssessment IDs
    var instanceCount: Int
    var avgDeferralCount: Float
    var avgResolutionDays: Float
    var insight: String
    var isActive: Bool
    var createdAt: Date
    var lastTriggered: Date
}
```

### Supabase Schema

```sql
create table avoidance_signals (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    item_id uuid not null,
    item_type text not null check (item_type in ('task', 'email', 'meeting', 'decision')),
    signal_type text not null,
    signal_score real not null,
    metadata jsonb not null default '{}',
    created_at timestamptz not null default now()
);

create table avoidance_assessments (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    item_id uuid not null,
    item_type text not null,
    composite_score real not null,
    confidence real not null,
    classification text not null,
    domain text,
    days_tracked integer not null default 0,
    surfacing_level integer not null default 0,
    executive_override boolean not null default false,
    override_reason text,
    override_expires_at timestamptz,
    resolved boolean not null default false,
    resolved_at timestamptz,
    resolution_trigger text,
    updated_at timestamptz not null default now(),
    unique(user_id, item_id, item_type)
);

create table avoidance_patterns (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    pattern_name text not null,
    domain text not null,
    description text not null,
    instance_ids uuid[] not null default '{}',
    instance_count integer not null default 0,
    avg_deferral_count real,
    avg_resolution_days real,
    insight text,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    last_triggered timestamptz
);

-- RLS policies (same pattern as other tables)
alter table avoidance_signals enable row level security;
alter table avoidance_assessments enable row level security;
alter table avoidance_patterns enable row level security;

create policy "own_data" on avoidance_signals for all using (auth.uid() = user_id);
create policy "own_data" on avoidance_assessments for all using (auth.uid() = user_id);
create policy "own_data" on avoidance_patterns for all using (auth.uid() = user_id);
```

---

## 9. Processing Pipeline

### 9.1 Real-Time (Haiku — on every event)

**On task deferral:**
1. Increment `deferralCount` on the task
2. Check if context changed (deadline, priority, dependencies)
3. If no context change and `deferralCount >= 3`, create/update `AvoidanceSignal`
4. Check for substitute activity (did the executive immediately do low-value work?)

**On email draft event:**
1. Track draft creation per thread
2. If draft deleted or abandoned (no send within 10 minutes of last edit), create `AvoidanceSignal`
3. If same thread has 2+ abandoned drafts, escalate signal score

**On calendar change:**
1. Detect rescheduled meetings
2. Check if the executive initiated the reschedule
3. If executive-initiated and no stated reason, create `AvoidanceSignal`

**On item view:**
1. Track view duration per item
2. If view > 60s with no subsequent action within 5 minutes, create `AvoidanceSignal`

**Token cost:** ~150 tokens per signal evaluation. At ~15-20 potential signals/day = ~3,000 Haiku tokens/day.

### 9.2 Nightly (Opus — during reflection engine)

During reflection Stage 2 (first-order pattern extraction):

1. Pull all `AvoidanceSignal` records from the last 24 hours
2. Compute/update `AvoidanceAssessment` for each unique item
3. Check for cross-item patterns (are multiple avoided items in the same domain?)
4. Update or create `AvoidancePattern` if domain clustering detected
5. Generate natural-language avoidance insight for morning session
6. Update procedural memory rules if new patterns emerged

**Opus prompt (within reflection pipeline):**
```
You are analysing the avoidance patterns for [executive name].

Today's avoidance signals:
[Array of AvoidanceSignal objects]

Current active assessments:
[Array of AvoidanceAssessment objects with composite_score > 0.3]

Known avoidance patterns:
[Array of active AvoidancePattern objects]

Executive's avoidance history:
[Summary: which domains, resolution triggers, false positive overrides]

Tasks:
1. Update composite scores for each active assessment
2. Classify any new items that crossed the threshold
3. Detect domain clustering across active items
4. If a named pattern should be created or updated, output it
5. For items reaching surfacing_level 2+, generate the morning session text
6. Distinguish genuine avoidance from rational deprioritisation — explain your reasoning

Output as structured JSON.
```

---

## 10. Validation

### 10.1 Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Precision at surfacing** | > 80% | Fraction of surfaced items where executive does NOT override | 
| **Time to detection** | < 7 days | Average days from first deferral to first surfacing |
| **Pattern accuracy** | > 70% | Fraction of named patterns that executive confirms as real |
| **Resolution rate** | Track only | Fraction of detected avoidance items that eventually resolve |
| **Override rate** | < 20% | If > 20%, thresholds are too aggressive |

### 10.2 Feedback Loop

Executive corrections feed directly back:
- "I'm not avoiding this" → record override, reduce score, track if item still stalls after stated reason resolves
- "You're right, I have been putting this off" → confirm classification, strengthen pattern confidence
- "This pattern name is accurate" → lock pattern, increase procedural memory confidence
- Silence (executive ignores the surfacing) → ambiguous, do not interpret as confirmation or denial

---

## 11. Implementation Sequence

1. **Add deferral tracking to Task model** — `deferralCount`, `lastDeferredAt`, `contextChangedSinceDeferral`
2. **Implement AvoidanceSignal recording** — hook into task deferral, email draft lifecycle, calendar changes, item view tracking
3. **Build composite scoring engine** — `AvoidanceEngine` class with signal aggregation and classification
4. **Implement context change detection** — compare task metadata at deferral time vs creation time
5. **Add to nightly reflection pipeline** — avoidance analysis stage in Opus prompt
6. **Build surfacing escalation ladder** — track surfacing level, generate appropriate morning session text
7. **Implement executive override flow** — UI for "I'm not avoiding this" with reason field and expiry
8. **Add pattern detection** — domain clustering, named pattern generation, procedural memory integration
9. **Positive reinforcement on resolution** — detect completed avoidance items, generate reinforcement text
10. **Supabase sync** — schema migration, RLS policies, assessment sync
