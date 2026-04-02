# Focus Timer PRD

**Layer:** Delivery (Layer 4) + Signal Ingestion (Layer 1)
**Owner:** Ammar Shahin / Facilitated
**Status:** Spec — implementation-ready
**Last updated:** 2026-04-02

---

## 1. Purpose

The focus timer is both a delivery mechanism (it helps the executive protect deep work time) and a signal ingestion surface (it generates the highest-fidelity behavioural data in the system). Every focus session produces: actual duration, distraction count, app-switch log, session quality score, and completion status. This data feeds directly into the EMA time estimation model, the energy curve model, and the chronotype inference engine.

The focus timer is not a Pomodoro clone. It is an instrumented deep work environment that learns from every session.

---

## 2. Design Philosophy

### 2.1 The Timer Serves the Intelligence, Not the Other Way Around

Most focus timers are standalone productivity tools. Timed's focus timer exists to close the feedback loop:

```
Morning session recommends task + timing
  → Executive starts focus session
  → Timer observes: duration, distractions, completion, quality
  → Data feeds EMA model (better time estimates)
  → Data feeds energy curve (better timing recommendations)
  → Data feeds chronotype inference (better daily planning)
  → Tomorrow's morning session is smarter
```

The timer's user-facing value (protected focus time, distraction awareness) is real but secondary. Its primary value is as the system's most precise instrument for understanding how this executive works.

### 2.2 Ultradian Rhythm Research

The Basic Rest-Activity Cycle (BRAC) research (Kleitman 1963; Rossi 2002; Ericsson et al. 1993) suggests:

- **90-120 minute cycles** of high-to-low alertness throughout the day
- **Peak performance within a cycle** lasts approximately 90 minutes before a natural trough
- **Ericsson's deliberate practice research** found that elite performers work in ~90-minute blocks with breaks, across domains
- **The "20-minute trough"** at the end of a cycle is a natural break point — pushing through it produces diminishing returns
- **Individual variation is significant** — some people cycle at 80 minutes, others at 110. The system must learn the individual's rhythm, not impose a population average.

**Implication for Timed:** Default session length is 90 minutes. The system tracks actual productive duration per session and, over 2-3 weeks, infers the executive's personal ultradian cycle length. Break recommendations adapt.

### 2.3 Interruption Cost Research

Gloria Mark's research (Mark et al. 2008; Mark et al. 2016):

- Average recovery time after interruption: **23 minutes** (widely cited, but varies by task type)
- **Self-interruptions** (checking email voluntarily) are as costly as external interruptions
- **Longer focus sessions** don't linearly increase productivity — there's a diminishing return after the ultradian peak
- **Anticipated interruptions** (knowing you might be interrupted) reduce cognitive performance even when interruption doesn't occur

**Implication for Timed:** Distraction logging must capture both external interruptions (notifications) and self-interruptions (user-initiated app switches). The proactive alert system respects focus state (see `proactive-alerts.md`). The menu bar suppresses visual changes during focus.

---

## 3. Core Functionality

### 3.1 Start Session

**Entry points:**
- Menu bar: "Start Focus" button in popover
- Main app: "Start Focus" on any task card or task detail view
- Keyboard: Cmd+Shift+F (starts with next recommended task)
- Morning session: "Start [task name]" voice command after session delivery
- Command palette: Cmd+K → "Focus" → select task

**On start:**
1. A task must be linked. Focus sessions without a linked task are not allowed — the system needs task-level data to learn.
2. Timer begins counting from 0 upward (not counting down from a fixed duration). The recommended duration is shown as a target marker, not a hard stop.
3. Menu bar transitions to `focus_active` state (see `menu-bar.md`)
4. macOS Do Not Disturb is optionally enabled (user preference: "Enable DnD during focus")
5. Distraction monitoring begins (see Section 4)
6. Session start event written to episodic memory:
   ```json
   {
     "type": "focus_session_start",
     "task_id": "...",
     "task_category": "...",
     "start_time": "2026-04-02T09:15:00Z",
     "recommended_duration_minutes": 90,
     "energy_model_prediction": 0.82,
     "time_of_day": "morning_peak"
   }
   ```

### 3.2 During Session

**Timer display:**
- Count-up timer: `MM:SS` elapsed
- Target marker: a subtle line or colour shift on the progress ring at the recommended duration
- No alarm at the target — the executive decides when to stop. The target is a suggestion, not a boundary.

**Distraction monitoring:** Active (see Section 4)

**Break suggestions:** If the session exceeds the executive's inferred ultradian cycle length by > 10 minutes, a gentle suggestion appears (see Section 5)

**Interruption from Timed:** Only S1 critical alerts can interrupt (see `proactive-alerts.md`). All other alerts queue until focus ends.

### 3.3 Pause Session

**Trigger:** Pause button in menu bar popover, main app, or Cmd+Shift+P

**On pause:**
- Timer stops counting
- Pause event logged with reason (if detectable): "user-initiated", "app backgrounded", "lock screen"
- Menu bar shows `[Task] · paused`
- Distraction monitoring pauses (pausing is an explicit choice, not a distraction)

**On resume:**
- Timer continues from paused position
- Resume event logged
- Distraction monitoring resumes

**Auto-pause:** If the screen locks or the Mac sleeps, the session auto-pauses. On wake, a "Resume focus?" prompt appears. If the user doesn't resume within 5 minutes, the session is ended with status `abandoned_idle`.

### 3.4 End Session

**Trigger:** Stop button in menu bar popover, main app, or Cmd+Shift+S (stop)

**On end:**
1. Timer stops
2. Completion prompt: "Did you finish this task?" → Yes / Partially / No
   - **Yes:** Task marked complete. Actual duration recorded.
   - **Partially:** Estimated remaining time requested (slider or voice: "About 30 more minutes"). This directly updates the EMA model for this task.
   - **No:** Task remains active. Session recorded as work-in-progress.
3. Session quality score calculated (see Section 6)
4. Session end event written to episodic memory:
   ```json
   {
     "type": "focus_session_end",
     "task_id": "...",
     "actual_duration_minutes": 72,
     "recommended_duration_minutes": 90,
     "completion_status": "partial",
     "estimated_remaining_minutes": 30,
     "distraction_count": 3,
     "session_quality_score": 0.74,
     "time_of_day": "morning_peak",
     "day_of_week": "wednesday",
     "consecutive_focus_hours_today": 2.1
   }
   ```
5. Data fed to EMA model immediately (see Section 7)
6. Menu bar transitions back to idle state
7. Break recommendation if applicable (see Section 5)

### 3.5 Abandon Session

If the session ends without the user explicitly stopping it:

**Triggers:**
- App force-quit during focus
- Screen locked for > 5 minutes with no resume
- User navigates away from focus view and doesn't return for > 10 minutes

**On abandon:**
- Session logged with status `abandoned`
- Duration up to last active moment is recorded
- Session quality score penalised (see Section 6)
- No completion prompt (the user already left)

---

## 4. Distraction Logging

### 4.1 What Counts as a Distraction

A distraction is an **app switch away from the focus context** during an active focus session.

**Detection method:**
- `NSWorkspace.shared.notificationCenter` observes `NSWorkspace.didActivateApplicationNotification`
- Every time the frontmost application changes during a focus session, the event is logged

**Classification:**

| App Switch Type | Classification | Weight |
|----------------|---------------|--------|
| Timed → Another app (any) | Distraction | 1.0 |
| Another app → Timed (return) | Recovery | -0.5 (partial recovery credit) |
| Timed → Same app within 5 seconds (accidental) | Ignored | 0.0 |
| Timed → Calendar/Outlook (quick check) | Micro-distraction | 0.3 |
| Timed → Browser → return within 30s | Research break | 0.5 |
| Timed → Slack/Teams/Messages | Communication interrupt | 1.0 |
| Timed → Email | Communication interrupt | 1.0 |
| System notification banner clicked | External interrupt | 0.8 |

**Note on privacy:** The system logs **which app** was switched to and **for how long**, but never the content (no screen capture, no URL logging, no message reading). The signal is: "switched to Slack for 45 seconds" — not what was read in Slack.

### 4.2 Distraction Event Structure

```json
{
  "type": "distraction_event",
  "session_id": "...",
  "timestamp": "2026-04-02T09:47:23Z",
  "destination_app": "Slack",
  "duration_seconds": 45,
  "classification": "communication_interrupt",
  "weight": 1.0,
  "return_to_focus": true,
  "time_in_session_minutes": 32
}
```

### 4.3 Distraction Patterns Over Time

The nightly reflection engine analyses distraction logs to extract:

- **Distraction-prone times:** "Your distractions spike between 2-3 PM — 3x your morning rate"
- **Distraction-prone apps:** "Slack accounts for 60% of your focus interruptions"
- **Session fragility curve:** "Your focus sessions are stable for the first 45 minutes, then distraction rate increases exponentially"
- **Self-interruption vs external:** "70% of your distractions are self-initiated (you opened the app voluntarily)"

These patterns feed into proactive alerts (see `proactive-alerts.md`) and morning session intelligence.

---

## 5. Break Recommendations

### 5.1 When to Suggest a Break

Break recommendations are triggered by:

1. **Ultradian cycle exceeded.** The session has exceeded the executive's inferred cycle length (default 90 minutes, personalised over time) by 10+ minutes.
2. **Consecutive focus hours exceeded.** The executive has been in focus sessions (with only short breaks) for > 3 hours cumulative today. Ericsson's research on deliberate practice suggests 4 hours/day as the sustainable maximum for elite performers.
3. **Quality degradation detected.** Distraction rate in the current session's last 15 minutes is > 2x the session's first 15 minutes. The executive is pushing through diminishing returns.
4. **Calendar conflict approaching.** A meeting starts in 15 minutes and the session should wind down for transition.

### 5.2 Break Recommendation Format

Breaks are suggested, never imposed. The timer keeps running if the executive ignores the suggestion.

**Menu bar:** Status text changes to `[Task] · break?`
**Popover card:**
```
┌─────────────────────────────────────┐
│  BREAK SUGGESTED                    │
│                                     │
│  You've been focused for 97 minutes │
│  — past your typical 88-minute peak.│
│  Distraction rate is climbing.      │
│                                     │
│  Suggested: 12-minute break         │
│  (your recovery data shows 10-15m   │
│   is optimal for session refresh)   │
│                                     │
│  [Take Break]  [Keep Going]         │
└─────────────────────────────────────┘
```

### 5.3 Break Duration

Default: 15 minutes.
Personalised (Day 14+): Based on the executive's actual recovery patterns.

**How recovery is measured:** If the executive takes a break and then starts a new focus session, the session quality of the post-break session (especially distraction rate in the first 15 minutes) indicates recovery quality. Over time, the system learns the optimal break duration:

- "After a 5-minute break, your next session quality averages 0.6"
- "After a 15-minute break, your next session quality averages 0.85"
- "After a 30-minute break, your next session quality averages 0.82 (diminishing returns beyond 15 minutes)"

This data produces a personalised break duration recommendation.

### 5.4 Break Activities (Not Prescriptive)

The system does not tell the executive what to do during a break. It is not a wellness app. However, if asked, it can surface: "Your data shows that breaks involving physical movement (standing, walking) correlate with 15% higher post-break session quality compared to breaks spent at your desk."

---

## 6. Session Quality Score

### 6.1 Calculation

Session quality is a 0.0 to 1.0 score calculated at session end.

```
quality = 1.0
         - (distraction_penalty)
         - (fragmentation_penalty)
         - (abandonment_penalty)
         + (completion_bonus)

Where:
  distraction_penalty = min(0.5, weighted_distraction_count × 0.05)
    // Each weighted distraction costs 5%, capped at 50%
    // A session with 6 weighted distractions: 0.30 penalty

  fragmentation_penalty = min(0.3, (total_pause_time / total_session_time) × 0.5)
    // If you spent 30% of the session paused, that's a 0.15 penalty
    // Capped at 0.3

  abandonment_penalty = 0.3 if session was abandoned, 0 otherwise

  completion_bonus = 0.1 if task was completed during or immediately after session
    // Reward for closing the loop

quality = max(0.0, min(1.0, quality))
```

### 6.2 Quality Score Usage

| Consumer | How Quality Score Is Used |
|----------|--------------------------|
| **EMA model** | Sessions with quality < 0.4 are downweighted in time estimation — a heavily distracted session doesn't represent the executive's actual work speed |
| **Energy curve model** | Quality scores by time-of-day build the executive's performance curve. Low quality at 2 PM consistently = post-lunch dip confirmation |
| **Chronotype inference** | Peak quality sessions clustered in the morning = morning chronotype. Peak quality sessions in the evening = evening chronotype. |
| **Morning session** | "Yesterday's focus sessions averaged 0.82 quality. Your best session was the 9 AM Meridian deck work." |
| **Menu bar** | Today's average focus score displayed in popover progress section |
| **Break recommendations** | Declining quality within a session triggers break suggestion |
| **Nightly reflection engine** | Quality trends over weeks feed pattern detection: "Your Wednesday afternoon focus quality has been declining for 3 weeks" |

### 6.3 Quality Calibration

The quality score formula above is the initial model. Over time, the system calibrates:

- **What does "distracted" mean for THIS executive?** Some executives check Slack briefly and fully recover. Others lose 20 minutes. The weight of a distraction event should be personalised based on recovery time data.
- **What does "fragmented" mean?** Some executives pause to think (legitimate). Others pause because they're stuck (different signal). The system learns to distinguish from post-pause behaviour.
- **What's this executive's baseline quality?** An executive who consistently scores 0.7 is not "low quality" — 0.7 is their normal. A session at 0.5 is notable for them. Anomaly detection should be relative to individual baseline.

---

## 7. Data Feeds

### 7.1 EMA Time Estimation Model

Every completed focus session (completion_status = "yes" or "partial") feeds the Exponential Moving Average model.

**For completed tasks:**
```
actual_duration = session_duration_minutes
estimated_duration = task.estimated_duration_minutes (from planning)
error = actual_duration - estimated_duration

// EMA update (existing implementation in PlanningEngine.swift)
new_estimate = α × actual_duration + (1 - α) × previous_estimate
// α = 0.3 (default, learnable per category)
```

**For partially completed tasks:**
```
progress_ratio = 1 - (estimated_remaining / original_estimate)
implied_total = actual_duration / progress_ratio
// Use implied_total as a data point for EMA, but with lower weight (α × 0.5)
// because the "estimated remaining" is self-reported and noisy
```

### 7.2 Energy Curve Model

Focus session quality scores, indexed by time-of-day, build the executive's daily energy curve.

**Data structure:**
```json
{
  "time_slot": "09:00-09:30",
  "average_quality": 0.87,
  "session_count": 14,
  "confidence": "high",
  "task_type_breakdown": {
    "analytical": 0.91,
    "creative": 0.78,
    "administrative": 0.85
  }
}
```

**Granularity:** 30-minute slots throughout the day. Each slot accumulates quality data over weeks.

**Output:** The energy curve is used by the morning session to recommend task timing. "Your analytical work peaks at 9-11" comes from consistently high-quality focus sessions on analytical tasks in that window.

### 7.3 Chronotype Inference

Over 2-4 weeks, the pattern of peak quality sessions reveals the executive's chronotype.

**Chronotype categories (simplified from Roenneberg's Munich Chronotype Questionnaire):**
- **Early chronotype (lark):** Peak quality 6-10 AM, trough after 2 PM
- **Intermediate:** Peak quality 9-12, trough 2-4 PM, secondary peak 4-6 PM
- **Late chronotype (owl):** Slow morning, peak quality 11 AM-2 PM and 6-9 PM

**Detection method:**
```
For each 30-minute time slot:
  compute average_quality across all sessions in that slot (min 3 sessions for significance)

Find the slot with highest average_quality = "peak"
Find the slot with lowest average_quality (where sessions exist) = "trough"

Map peak/trough pattern to chronotype classification
```

**Cold start:** Until sufficient data exists (typically 14 days with 3+ focus sessions per day), the system uses the archetype-derived chronotype from onboarding.

### 7.4 Task Category Learning

Focus session data, bucketed by task category, builds category-specific intelligence:

- "Your 'financial analysis' tasks average 73 minutes actual vs 45 minutes estimated — you consistently underestimate these by 60%"
- "Your 'email batch' tasks average 0.92 quality — you handle these efficiently"
- "Your 'people conversations' preparation sessions have the highest distraction rate (0.4 avg) — these may be anxiety-related avoidance"

This data feeds the morning session's task recommendations and the avoidance detection system.

---

## 8. Focus Timer and Proactive Alert Interaction

### 8.1 Protection Rules

| Alert Severity | During Focus | Behaviour |
|---------------|-------------|-----------|
| S1 (Critical) | Delivered | Only S1 can break through focus. Timer pauses. Alert displayed. Timer resumes after dismissal/action. |
| S2 (Important) | Queued | Alert stored in queue. Delivered within 60 seconds of focus session ending. |
| S3 (Advisory) | Queued | Available in menu bar popover but not pushed. |
| Calendar reminder | Suppressed | Timed does not deliver calendar reminders during focus (macOS Calendar handles those independently). Exception: if "Event imminent" warning is enabled and event is in < 5 minutes, a subtle menu bar text change occurs — no sound, no notification. |

### 8.2 Post-Focus Alert Delivery

When a focus session ends:
1. Session completion flow runs (quality score, completion prompt)
2. 30-second buffer (let the executive mentally transition)
3. Any queued S2 alerts are delivered
4. S3 advisories become visible in menu bar

---

## 9. Connection to Calendar

### 9.1 Calendar-Aware Session Length

When starting a focus session, the system checks the calendar:

- If a meeting starts in 45 minutes: "You have 40 minutes before your next meeting. Start a focused 35-minute session?" (5-minute buffer for transition)
- If the next meeting is 3 hours away: "You have a 2.5-hour deep work window. Your typical focus cycle is 88 minutes — start a full session?"
- If no meetings remain today: no constraint — session length is fully up to the executive

### 9.2 Transition Warning

When a focus session is running and a calendar event approaches:

- **15 minutes before event:** Menu bar status text appends `· mtg 15m` (if space allows)
- **5 minutes before event:** Subtle chime (if user has sounds enabled) + popover card: "Meeting in 5 minutes. End session?"
- **Event start time:** If session is still running, it continues — the executive decides. The system does not force-end sessions.

---

## 10. Cold Start Behaviour

### Days 1-7
- Default session target: 90 minutes (based on ultradian research)
- Default break suggestion: 15 minutes
- Quality score calculated with default weights
- Time estimation uses task's original estimate (no EMA history yet)

### Days 8-14
- EMA model begins influencing time estimates (2-4 data points per category)
- Energy curve has preliminary data (high uncertainty, communicated in morning session)
- Distraction patterns beginning to emerge

### Days 15-30
- Ultradian cycle length personalised (enough sessions to detect individual rhythm)
- Break duration personalised (enough post-break data)
- Energy curve confidence moves to "moderate"
- Category-specific time estimation active

### Day 30+
- Full personalisation across all models
- Chronotype inferred
- The morning session can say: "Based on 30 days of focus data, your peak analytical window is 9:15-10:45 and your natural cycle length is 85 minutes"

---

## 11. Implementation Notes

### 11.1 Existing Code to Extend

| Component | File | Current State | Extension Needed |
|-----------|------|---------------|-----------------|
| Focus timer | Exists in app (basic Pomodoro) | Start/stop/pause, persistence | Count-up mode, task linking, quality score, distraction logging |
| EMA model | `PlanningEngine.swift` | CompletionRecord → EMA update | Wire focus session completion into EMA pipeline |
| DataStore | `DataStore.swift` | Local JSON persistence | Add focus session records, distraction events |
| Menu bar | Exists (Now/Next/Later) | Basic menu bar presence | State machine integration, focus timer display |

### 11.2 New Components Needed

| Component | Purpose |
|-----------|---------|
| `FocusSession` model | Data model for a focus session (task, duration, quality, distractions) |
| `DistractionMonitor` | Observes NSWorkspace notifications, classifies app switches, logs events |
| `SessionQualityCalculator` | Computes quality score from session data |
| `EnergyCurveModel` | Accumulates quality-by-time-of-day data, produces energy curve |
| `ChronotypeInference` | Maps energy curve to chronotype classification |
| `BreakRecommender` | Determines when and how long to suggest breaks |
| `UltradianTracker` | Learns individual cycle length from session quality decay patterns |

### 11.3 NSWorkspace Observation

```swift
// Distraction monitoring during focus sessions
let center = NSWorkspace.shared.notificationCenter
center.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          let bundleID = app.bundleIdentifier else { return }
    
    // Log app switch event if focus session is active
    if focusSessionActive {
        logDistractionEvent(
            destinationApp: app.localizedName ?? bundleID,
            bundleID: bundleID,
            timestamp: Date()
        )
    }
}
```

**Permissions:** `NSWorkspace` notifications do not require special entitlements. App activation events are publicly observable by any running process. No Accessibility API access needed for this level of monitoring.

---

## 12. Acceptance Criteria

### Core
- [ ] Focus sessions are always linked to a specific task
- [ ] Timer counts up with a target marker (not countdown)
- [ ] App switches during focus are logged as distraction events with classification
- [ ] Session quality score (0-1) is calculated at session end
- [ ] Completion prompt captures actual outcome (finished / partial / not finished)
- [ ] Focus session data feeds EMA model for time estimation
- [ ] Menu bar displays task name + elapsed time during focus

### Quality
- [ ] Distraction events are classified (communication, research, self-interrupt) not just counted
- [ ] Break recommendations cite the executive's personal data, not generic advice
- [ ] Quality score is personalised to the individual's baseline by Day 30
- [ ] Energy curve has enough data for meaningful timing recommendations by Day 14
- [ ] No audio/visual interruptions during focus except S1 critical alerts

### Intelligence
- [ ] Focus session quality data feeds the energy curve model
- [ ] Session data by time-of-day enables chronotype inference by Day 30
- [ ] Category-specific time estimation accuracy improves measurably over 4 weeks
- [ ] Distraction patterns are surfaced in the morning session (top distraction apps, distraction-prone times)
- [ ] Break duration recommendations are personalised by Day 14

### Technical
- [ ] NSWorkspace observation has negligible CPU/memory overhead
- [ ] No content is captured from other apps — only app name and activation time
- [ ] Focus session data persists across app restarts (DataStore)
- [ ] Calendar-aware session length adjustments work with both synced and local calendars
- [ ] Auto-pause on screen lock, auto-resume prompt on wake

---

## 13. Open Questions

1. **Should the timer show seconds?** Seconds create urgency and time-watching behaviour, which is counterproductive for deep work. Proposal: show `MM:SS` in the main app focus view (where the user has deliberately opened the timer) but only `MMm` in the menu bar (glanceable, not anxiety-inducing).

2. **Multiple focus sessions on the same task.** If the executive starts a focus session on a task, ends it (partial), takes a break, and starts another session on the same task — should these be linked? Proposal: yes. Linked sessions share a `task_focus_group_id` so total time on a task across sessions is aggregable. Each session retains its own quality score.

3. **Focus session with no linked task.** Some executives might want to focus on something not in the task list (e.g., thinking time, reading). Should unlinked sessions be allowed? Proposal: allow them with a category tag ("thinking", "reading", "admin") instead of a task link. These feed the energy curve but not the task-specific EMA model.

4. **Gamification temptation.** Streaks, badges, and "focus scores" over time are tempting to add. Research on gamification for high-status professionals (Hamari et al. 2014) is mixed — it works for habit formation but can feel patronising. Proposal: no gamification. Present data neutrally. The executive interprets their own performance. The system never says "Great session!" or "You're on a streak!"

5. **Background audio during focus.** Some people work better with music or ambient sound. Should Timed detect or control audio state? Proposal: out of scope. Timed is a cognitive intelligence layer, not an environment manager. If the executive plays music, that's their choice. The system doesn't observe or influence it.
