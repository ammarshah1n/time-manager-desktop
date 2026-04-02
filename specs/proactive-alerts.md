# Proactive Alert Spec

**Layer:** Delivery (Layer 4)
**Owner:** Ammar Shahin / Facilitated
**Status:** Spec — implementation-ready
**Last updated:** 2026-04-02

---

## 1. Purpose

Proactive alerts are the system's mechanism for surfacing time-sensitive intelligence outside the morning session. They are the executive equivalent of a chief of staff walking into the room unannounced — it only happens when something genuinely matters.

The defining constraint: **alerts must be rare to be respected.** The moment alerts become frequent, they become notifications. The moment they become notifications, they get ignored. The moment they get ignored, the system has lost its most powerful delivery channel.

---

## 2. Design Philosophy

### 2.1 The Rarity Principle

Research on executive notification tolerance (Mark et al., 2016; Mehrotra et al., 2016) consistently shows:

- **3+ interruptions per hour** → executives disable notifications entirely within 2 weeks
- **1-2 per day** → tolerated if consistently high-value
- **2-3 per day absolute maximum** → the threshold where perceived value starts declining regardless of actual value
- **Zero on some days** → essential. If every day has alerts, they're not alerts — they're a feed

Timed's alert budget: **0-3 alerts per day, with most days at 0-1.** The system earns the right to interrupt through demonstrated accuracy. A false positive costs more than a missed true positive in the first 30 days.

### 2.2 The Interrupt-Value Equation

Every alert must pass this test before delivery:

```
Alert Value = (Consequence Severity × Time Sensitivity × Confidence) / User Cost

Where:
- Consequence Severity: 0-1 (what happens if the user doesn't see this?)
- Time Sensitivity: 0-1 (does this lose value in the next 2 hours?)
- Confidence: 0-1 (how certain is the system?)
- User Cost: context switch cost based on current state
  - In focus timer: cost = 5x (highest protection)
  - In meeting (calendar block active): cost = 3x
  - Between tasks: cost = 1x (lowest cost to interrupt)
  - Idle (no active task): cost = 0.5x

Delivery threshold: Alert Value > 0.6
```

If the alert doesn't clear the threshold, it is queued for the next morning session or the next menu bar check-in — never discarded, just deferred to a lower-cost delivery channel.

### 2.3 What Proactive Alerts Are NOT

- Not reminders ("Your meeting starts in 5 minutes") — Calendar.app does this
- Not notifications ("You have 3 new emails") — Mail.app does this
- Not wellness check-ins ("Time for a break!") — patronising for a C-suite executive
- Not achievement badges ("You completed 5 tasks!") — gamification is insulting at this level
- Not status updates ("Email sync complete") — system status belongs in logs

Proactive alerts are **intelligence that loses value if delayed**. If it can wait until tomorrow's morning session, it's not an alert.

---

## 3. Alert Triggers

### 3.1 Avoidance Escalation

**What it detects:** A task or decision has been deferred multiple times and is approaching a critical threshold.

**Signal sources:**
- Task deferral count (moved to tomorrow 3+ times)
- Task age vs estimated duration (a 30-minute task that's been on the list for 8 days)
- Pattern match against known avoidance behaviours for this executive
- Relationship-linked tasks (e.g., a difficult conversation with a direct report)

**Trigger condition:**
```
deferral_count >= 3
AND task_consequence_score > 0.5
AND (today's calendar has a window where this task fits
     OR tomorrow's calendar is worse than today's)
```

**Alert format:**
> "The [task name] has been deferred [N] times over [N] days. Your calendar has a [duration] window at [time] today. Tomorrow is back-to-back meetings."

**Confidence requirement:** High. The system must have strong evidence that the deferral is avoidance (not legitimate reprioritisation). Signals that distinguish avoidance from reprioritisation:
- Avoidance: task stays on the list, gets moved daily, no replacement task of higher value added
- Reprioritisation: task removed from list or replaced by a clearly higher-priority item
- Avoidance: task is people-related or uncomfortable (learned from executive's correction history)
- Reprioritisation: task is operational and genuinely less urgent than new items

### 3.2 Cognitive Overload Warning

**What it detects:** The executive's cognitive load has exceeded their historical performance threshold and decision quality is at risk.

**Signal sources:**
- Meeting count in the last 3 hours (continuous meetings without breaks)
- Context switches per hour (app switching frequency during focus time)
- Email response latency dropping below normal (reactive emailing = overwhelm)
- Task completion rate dropping mid-day vs morning baseline
- Calendar: no recovery block in the next 2 hours

**Trigger condition:**
```
(consecutive_meeting_hours >= user's_historical_drop_threshold  // typically 2.5-3h
  AND no_break_in_next_60_minutes)
OR (context_switches_per_hour > 2σ above user's baseline
  AND active_task_in_progress)
```

**Alert format:**
> "You've been in back-to-back meetings for [N] hours. Your historical data shows a [N]% cognitive performance drop after [threshold]. Your next decision-heavy item is [task] at [time]. Consider a 15-minute break before then."

**Confidence requirement:** Moderate-to-high. The system needs at least 14 days of baseline data to calibrate the overload threshold for this specific executive.

### 3.3 Relationship Decay

**What it detects:** A key professional relationship is showing signs of decay based on communication pattern changes.

**Signal sources:**
- Communication frequency with specific contacts dropping below their baseline cadence
- Response latency to a contact increasing over 2+ weeks
- Sentiment shift detected in recent email exchanges (more formal, shorter, less reciprocal)
- Calendar: recurring 1:1 cancelled or skipped 2+ times
- Contact importance score (inferred from historical attention allocation)

**Trigger condition:**
```
contact_importance_score > 0.7  // top-tier relationship
AND communication_gap > 2x their normal cadence
AND (sentiment_trend is negative
     OR recurring_meeting_skip_count >= 2)
```

**Alert format:**
> "You haven't had a substantive exchange with [Name] in [N] days. Your typical cadence with them is every [N] days. Last interaction: [brief context]. Their next availability on your calendar: [date/time or 'none scheduled']."

**Confidence requirement:** Moderate. Relationship signals are noisy — business travel, project phases, and personal leave all cause legitimate gaps. The system must learn this executive's relationship cadences individually, not use population averages.

**Safeguard:** Never alert on relationship decay in the first 30 days. The system needs baseline data for each relationship before it can detect deviation.

### 3.4 Deadline Risk

**What it detects:** A deadline is at risk of being missed based on the current progress trajectory and remaining calendar availability.

**Signal sources:**
- Task deadline (explicit from task metadata)
- Estimated remaining duration (from EMA model)
- Available calendar slots between now and deadline
- Historical on-time completion rate for this task category
- Current progress signals (has the task been started? How much time has been invested?)

**Trigger condition:**
```
remaining_available_hours < estimated_remaining_duration × 1.3  // 30% buffer
AND deadline is within 48 hours
AND task_priority_score > 0.6
```

**Alert format:**
> "[Task name] is due [deadline]. Estimated remaining time: [duration]. Your available deep-work slots before the deadline: [list slots, total hours]. You need to start by [latest start time] to finish without rushing."

**Confidence requirement:** High for time estimates (requires sufficient EMA history for this task category). If the system's time estimates for this category have a wide confidence interval, the alert explicitly states: "My time estimate for this type of work is still calibrating — treat the deadline risk as approximate."

### 3.5 Strategic Drift

**What it detects:** The executive's time allocation has diverged significantly from their stated priorities.

**Signal sources:**
- Stated priorities (captured in morning sessions, task labels, explicit priority declarations)
- Actual time allocation (tracked via focus timer, calendar analysis, task completion logs)
- Drift metric: `|actual_time_allocation - stated_priority_allocation|` per category, calculated weekly

**Trigger condition:**
```
drift_metric for a stated top-2 priority > 0.4  // 40%+ mismatch
AND this has persisted for > 5 business days
AND the priority hasn't been explicitly deprioritised
```

**Alert format:**
> "You identified [priority] as your top Q2 focus. In the last [N] business days, you've spent [N hours] on it — [N]% of your deep-work time. Operational work has consumed [N]%. This is the third consecutive week of this pattern."

**Confidence requirement:** High. The system must have clear stated priorities (from morning session responses or explicit declarations) and accurate time tracking data. Strategic drift alerts without clear priority baselines will feel presumptuous.

**Frequency cap:** Maximum once per week. Strategic drift is a slow pattern — alerting daily would be nagging, not intelligence.

---

## 4. Alert Severity Levels

| Level | Name | Visual | Sound | Frequency Cap | Use Case |
|-------|------|--------|-------|---------------|----------|
| **S1** | Critical | Menu bar icon turns red, alert banner | Single alert tone | 1 per day max | Deadline will be missed today, avoidance on a task with severe consequences |
| **S2** | Important | Menu bar icon pulses amber, alert badge | None (silent) | 2 per day max | Cognitive overload, relationship decay approaching critical, strategic drift |
| **S3** | Advisory | Menu bar badge count increments | None (silent) | No cap (but queued, not pushed) | Low-confidence early signals, calibration insights, pattern observations |

**Rules:**
- S1 and S2 are pushed (appear proactively)
- S3 is pulled (visible when user checks menu bar, not pushed to attention)
- S1 alerts override the focus timer "do not interrupt" rule — they are the only thing that can
- S2 alerts respect the focus timer — they queue until the current focus session ends
- Total S1 + S2 alerts per day: maximum 3. This is a hard cap. If more qualify, the system ranks by alert value and defers the rest to the morning session.

---

## 5. Alert Delivery

### 5.1 Menu Bar Presentation

When an alert is triggered:

1. Menu bar icon transitions to alert state (see `menu-bar.md` for visual spec)
2. Alert content is displayed in the menu bar popover when clicked
3. Alert persists until acknowledged (tapped) or dismissed (swiped/X)

**Alert card format in menu bar:**
```
┌─────────────────────────────────────────┐
│ [Severity Icon]  [Alert Type Label]     │
│                                         │
│ [2-3 sentence alert content]            │
│                                         │
│ [Contextual action suggestion]          │
│                                         │
│ [Timestamp]          [Dismiss] [Act On] │
└─────────────────────────────────────────┘
```

**"Act On" is never an automatic action.** It opens the relevant view (task detail, contact, calendar) so the executive can decide and execute. Timed's observation-only constraint applies to alerts too.

### 5.2 macOS Notification Centre

S1 alerts also deliver a macOS notification via `UNUserNotificationCenter`:
- Title: Alert type label
- Body: First sentence of alert content
- Action: Opens Timed to the alert detail

S2 alerts do not use Notification Centre — they are menu bar only. The executive should not see Timed alerts in their notification stack alongside Slack messages and email notifications. That reduces perceived quality.

### 5.3 Voice Delivery (Optional)

If the user has enabled "Speak critical alerts" in Settings:
- S1 alerts are spoken via TTS when delivered
- Same voice and personality rules as morning session
- Maximum 2 sentences spoken — detail is on screen

---

## 6. Dismissal as Signal

**Dismissal is first-class negative feedback.** When the user dismisses an alert, the system learns.

### 6.1 Dismissal Types

| Action | Signal Interpretation | System Response |
|--------|----------------------|-----------------|
| **Read + Act On** | Alert was valuable, well-timed | Reinforce: this trigger type, at this severity, for this context, was correct |
| **Read + Dismiss** | Alert was seen but not actionable right now | Neutral-to-negative. Track over time — if this trigger type is consistently read-then-dismissed, lower its severity or delivery priority |
| **Immediate dismiss** (< 2 seconds after appearing) | Alert was not valuable or poorly timed | Strong negative signal. If this trigger type gets immediate-dismissed 3+ times, suppress it until the model recalibrates |
| **Ignored** (alert expires without interaction) | User didn't see it or chose to ignore it | Weak negative signal. Could be context (in a meeting, away from desk). Track but don't penalise heavily |

### 6.2 Dismissal Feedback Loop

```
Alert dismissed
  → dismissal_event written to episodic_memory:
      {
        alert_type: "avoidance_escalation",
        severity: "S2",
        dismissal_type: "immediate",
        user_state_at_time: "focus_timer_active",  // was the timing bad?
        alert_value_score: 0.65,                    // the score that triggered it
        timestamp: "..."
      }
  → Nightly reflection engine reviews dismissal patterns
  → Adjusts trigger thresholds:
      - If avoidance_escalation alerts are dismissed > 50% of the time: raise trigger threshold
      - If cognitive_overload alerts are consistently acted on: maintain or lower threshold
      - If alerts during focus_timer are always dismissed: enforce stricter focus protection
```

### 6.3 Alert Accuracy Tracking

The system maintains a rolling accuracy score per alert type:

```
accuracy[alert_type] = acted_on_count / (acted_on_count + dismissed_count)
```

Target accuracy per type: > 0.6 (60% of alerts are acted on). If accuracy drops below 0.4 for any alert type over a 14-day window, that alert type is suspended and escalated to the morning session for discussion: "I've been flagging [type] alerts, but you've dismissed most of them. Should I keep watching for this, change what I look for, or stop?"

---

## 7. Alert Timing

### 7.1 When to Deliver

Alerts are not delivered the instant they trigger. They are staged and delivered at the optimal moment.

**Delivery window selection:**
1. **Between tasks** (no focus timer active, no calendar block) → deliver immediately
2. **After a focus session ends** → deliver within 60 seconds of focus timer stopping
3. **After a meeting ends** (calendar block ends) → deliver within 2 minutes
4. **During idle** (no task active, no meeting, user at computer) → deliver within 30 seconds

**Never deliver:**
- During focus timer (except S1 critical)
- During a calendar-blocked meeting
- Within 5 minutes of morning session delivery (the session IS the intelligence delivery)
- Between 9 PM and configured morning window start (respect off-hours)
- More than 3 S1+S2 alerts in a single day

### 7.2 Alert Queue Management

If multiple alerts trigger simultaneously or during a protected period:

1. Rank by alert value score
2. Deliver the highest-value alert at the next delivery window
3. If 2+ alerts are queued, deliver the top one and show a badge count for the rest
4. If queue exceeds daily cap (3), defer excess to tomorrow's morning session with a "Yesterday I held back two alerts — here's what they were" segment

### 7.3 Time-Sensitive Decay

Some alerts lose value over time:
- Deadline risk: value increases as deadline approaches (deliver sooner, not later)
- Cognitive overload: value decays — if the user is already past the overload period, the alert is stale
- Avoidance escalation: value is stable within the day but resets overnight (the morning session handles it)
- Relationship decay: value is stable for days (not time-sensitive within hours)
- Strategic drift: value is stable for days (weekly pattern)

**Decay rule:** If an alert's time-adjusted value drops below the delivery threshold while queued, it is silently deferred to the morning session.

---

## 8. Cold Start Behaviour

### Days 1-7: No Proactive Alerts
The system has insufficient baseline data to alert with confidence. Alerts are suppressed entirely. This builds trust — the user learns that when Timed does alert them (Day 8+), it means something.

### Days 8-14: Advisory Only (S3)
First alerts appear as advisory items in the menu bar. Not pushed. The user discovers them by checking the menu bar. This introduces the concept gently.

### Days 15-30: Important Alerts Enabled (S2)
S2 alerts begin. Maximum 1 per day during this period (tighter cap than steady state). Each alert includes a confidence qualifier: "15 days of data — moderate confidence."

### Day 30+: Full Alert System
All severity levels active. Caps at steady-state values. The system has enough baseline data for personalised thresholds.

**Exception:** Deadline risk alerts are available from Day 1 — they use task metadata (explicit deadlines), not learned patterns, so they don't need a cold-start period. They still respect the daily cap.

---

## 9. Acceptance Criteria

### Core
- [ ] Maximum 3 alerts (S1 + S2) per day — hard cap, no exceptions
- [ ] Alerts never interrupt focus timer (except S1 critical)
- [ ] Every alert includes specific data (names, numbers, dates) — never generic
- [ ] Dismissal is logged as negative feedback with full context
- [ ] Alert accuracy is tracked per type with 14-day rolling window
- [ ] Cold start: no proactive alerts in first 7 days

### Quality
- [ ] Alert accuracy > 60% (acted-on rate) per type by Day 30
- [ ] Alert format is 2-3 sentences maximum — never a paragraph
- [ ] Each alert suggests a specific action without executing it
- [ ] Alert types that drop below 40% accuracy are auto-suspended with user notification
- [ ] The system explains why it alerted: "This triggered because [specific reason]"

### Technical
- [ ] Alert value calculation runs on every qualifying event (not batched)
- [ ] Alert queue respects delivery windows and never interrupts protected states
- [ ] S1 alerts deliver via macOS Notification Centre in addition to menu bar
- [ ] Time-sensitive alerts decay appropriately while queued
- [ ] All alert events (trigger, delivery, dismissal, action) written to episodic memory

---

## 10. Data Flow

```
[Continuous — Background Agents (Haiku swarm)]
  Email sentinel → flags communication gaps, sentiment shifts
  Calendar watcher → detects meeting density, deadline proximity
  Completion logger → tracks deferral counts, time-on-list
  Drift detector → compares time allocation to stated priorities

[Event occurs that qualifies as alert candidate]
  → Alert value calculation (consequence × time-sensitivity × confidence / user-cost)
  → If value > threshold: add to alert queue with severity level
  → If value < threshold: defer to morning session candidates

[Alert queue → delivery window]
  → Check daily cap (not exceeded?)
  → Check user state (not in focus, not in meeting?)
  → Deliver highest-value queued alert
  → Start dismissal/engagement timer

[User interaction with alert]
  → Action taken / dismissed / ignored
  → Written to episodic memory
  → Fed to nightly reflection engine
  → Reflection engine adjusts thresholds for this alert type
```

---

## 11. Dependencies

| Dependency | Status | Required For |
|------------|--------|-------------|
| Background Haiku agents (email sentinel, calendar watcher, etc.) | Designed, not built | All trigger detection |
| UserIntelligenceStore (semantic + episodic memory) | Designed, not built | Pattern baselines, dismissal history |
| Focus timer state | Built | Delivery window decisions |
| Menu bar presence | Built | Alert display |
| Thompson sampling task scores | Built (PlanningEngine.swift) | Task consequence scoring for avoidance/deadline alerts |
| Email sync | Built (EmailSyncService.swift) | Communication pattern monitoring |
| Calendar sync | Built (GraphClient.swift) | Meeting density, deadline proximity |
| EMA time estimation | Built | Deadline risk calculation |

---

## 12. Open Questions

1. **Should the user be able to request "more alerts" or "fewer alerts"?** Risk: the user asks for more, quality drops, they lose trust. Proposal: allow "fewer" (raises thresholds) but not "more" (the system decides when something is worth interrupting). If the user wants more, they check the menu bar more often.

2. **Alert snooze.** Should the user be able to snooze an alert for N hours? Risk: snooze becomes the default action, defeating the purpose. Proposal: no snooze. Act on it, dismiss it, or it queues for tomorrow's morning session.

3. **Cross-device alerts.** If the user is away from their Mac (phone, iPad), should alerts be delivered via push notification to another device? This requires a server component. Proposal: defer to v2. The Mac is the primary device; alerts are available when the user returns.

4. **Alert escalation.** If an S2 alert is dismissed but the underlying condition worsens (e.g., deadline moves closer, avoidance continues), should it re-trigger at S1? Proposal: yes, but only once. A condition can escalate from S2 to S1 exactly one time. After that, it goes to the morning session.
