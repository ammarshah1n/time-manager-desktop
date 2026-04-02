# Menu Bar Presence Spec

**Layer:** Delivery (Layer 4)
**Owner:** Ammar Shahin / Facilitated
**Status:** Spec — implementation-ready
**Last updated:** 2026-04-02

---

## 1. Purpose

The menu bar is Timed's ambient intelligence surface. It is always visible, never intrusive, and glanceable in under 2 seconds. It is the executive's peripheral awareness of what the system knows — a steady, quiet presence that becomes more detailed on demand.

The menu bar does not compete for attention. It earns the executive's glance by consistently showing the one thing that matters right now.

---

## 2. Design Philosophy

### 2.1 macOS Menu Bar Conventions

Timed's menu bar presence must feel native to macOS. Executives who have used Macs for years have strong expectations:

- **Menu bar items are small.** Icon + optional short text. No wide custom views in the bar itself.
- **Click expands to a popover or dropdown.** This is where detail lives.
- **Status is encoded in the icon.** A spinning icon means processing. A badge means attention needed. A static icon means stable state.
- **Menu bar items do not animate unless something changed.** Continuous animation is hostile to peripheral vision.

### 2.2 Information Density Principles

The menu bar operates at three zoom levels:

| Level | Interaction | Information Density | Time to Consume |
|-------|-------------|-------------------|-----------------|
| **Glance** | Eyes flick to menu bar | Current state in 1-3 words | < 1 second |
| **Check** | Click menu bar icon | Intelligence summary + active context | < 10 seconds |
| **Dive** | Click into sections within popover | Full detail on patterns, tasks, alerts | < 30 seconds |

Each level must be independently valuable. The glance must be useful without the check. The check must be useful without the dive.

---

## 3. Resting State (Glance Level)

### 3.1 Layout

The menu bar item consists of:

```
[Icon] [Status Text]
```

- **Icon:** SF Symbol, 16x16pt, template rendering (adapts to light/dark mode automatically)
- **Status text:** Maximum 25 characters. Truncated with ellipsis if longer.
- **Font:** System font (SF Pro), menu bar standard weight and size

### 3.2 State-Dependent Display

| State | Icon | Status Text | Example |
|-------|------|-------------|---------|
| **Focus active** | `timer` (SF Symbol) | Task name + time remaining | `Meridian deck · 47m` |
| **Focus paused** | `pause.circle` | Task name + "paused" | `Meridian deck · paused` |
| **Next event imminent** (< 15 min) | `calendar` | Event name + countdown | `Board sync · 12m` |
| **Idle (tasks available)** | `brain.head.profile` | Next recommended task | `Next: Sarah 1:1 prep` |
| **Idle (no tasks)** | `brain.head.profile` | Cognitive state summary | `Light afternoon` |
| **Morning session available** | `brain.head.profile` with badge | "Brief ready" | `Brief ready` |
| **Alert pending** | `exclamationmark.circle` | Alert type | `Deadline risk` |
| **Off-hours** | `moon` | Nothing or "Rest" | (icon only, no text) |

### 3.3 State Priority

When multiple states are active simultaneously, the menu bar shows the highest-priority state:

1. **Focus active** (always wins — the user is in flow, show their current context)
2. **Alert pending (S1)** (critical alert overrides everything except active focus)
3. **Alert pending (S2)** (important alert)
4. **Morning session available**
5. **Next event imminent**
6. **Idle**
7. **Off-hours**

### 3.4 Icon Behaviour

- **Static:** Default. No animation. The icon sits quietly.
- **Subtle pulse:** Morning session is available and hasn't been consumed. A slow (2s cycle), subtle opacity pulse on the icon only. Stops after 30 minutes or when the session is consumed.
- **Colour shift to amber:** S2 alert pending. The icon tints amber (using SF Symbol palette rendering).
- **Colour shift to red:** S1 alert pending. The icon tints red.
- **No animation during focus.** Even if an alert is pending, the icon does not pulse or change colour during focus mode (except S1 critical). Focus protection extends to peripheral visual distraction.

---

## 4. Expanded State (Check Level)

### 4.1 Popover Layout

Clicking the menu bar icon opens a popover (NSPopover) anchored to the menu bar item. The popover contains the intelligence summary.

**Popover dimensions:** 320pt wide, variable height (max 480pt, scrollable if needed).

**Layout structure:**

```
┌──────────────────────────────────────┐
│  [Intelligence Summary]              │
│  "Your analytical peak passed at     │
│   11:00. Afternoon is operational    │
│   work territory."                   │
│                                      │
├──────────────────────────────────────┤
│  ACTIVE PATTERNS           [N total] │
│  ┌────────────────────────────────┐  │
│  │ ▸ Thursday Crunch [high conf]  │  │
│  │ ▸ Client Gravity  [moderate]   │  │
│  └────────────────────────────────┘  │
│                                      │
├──────────────────────────────────────┤
│  TODAY'S PROGRESS                    │
│  ████████░░░░ 5/8 tasks · 62%       │
│  Deep work: 2.1h / 3.5h target      │
│  Focus score: 0.78 (above avg)      │
│                                      │
├──────────────────────────────────────┤
│  NEXT UP                             │
│  ┌────────────────────────────────┐  │
│  │ 2:00 PM  Product sync (30m)   │  │
│  │ 3:00 PM  Open: Board deck     │  │
│  │ 4:30 PM  David 1:1 (30m)      │  │
│  └────────────────────────────────┘  │
│                                      │
├──────────────────────────────────────┤
│  [Brief Me] [Start Focus] [Settings]│
└──────────────────────────────────────┘
```

### 4.2 Section Specifications

#### Intelligence Summary (always visible, top of popover)

A single sentence of contextual intelligence. Changes throughout the day based on the current moment.

**Morning (before session):** "Your morning brief is ready."
**Morning (after session):** "Your analytical peak is 9-11. Protect the next [N] minutes."
**Midday:** "You're [N] hours into meetings. Next break opportunity: [time]."
**Afternoon:** "5 tasks remaining. [N] hours of calendar availability. Highest priority: [task]."
**Evening:** "Day wrapping up. [N] tasks completed, [N] deferred. Tomorrow's brief generates overnight."

**Source:** Generated by a lightweight prompt (Haiku) that receives: current time, calendar state, task progress, energy model position, active alerts. Regenerated every 15 minutes or on state change.

#### Active Patterns

List of named patterns currently tracked by the intelligence model. Each shows:
- Pattern name (clickable → opens pattern detail in main app)
- Confidence level badge: `[high]` `[moderate]` `[early signal]`
- Count of total active patterns (most days: 2-5)

Patterns are sorted by relevance to today (not by confidence). A pattern relevant to today's decisions ranks above a general long-term pattern.

#### Today's Progress

Quantified progress through the day's plan:
- **Task completion:** `[completed]/[total] tasks · [%]`
- **Deep work time:** `[actual]h / [target]h` — target is from the morning session or the user's configured daily deep work goal
- **Focus score:** Rolling average session quality score from today's focus sessions (see `focus-timer.md`)

The progress bar uses a neutral colour (system grey). No green/red gamification. The executive can decide if 62% is good or bad — the system presents data, not judgment.

#### Next Up

The next 2-4 items on the executive's timeline. Mixes calendar events and recommended tasks:
- Calendar events: show name + duration + type (meeting, focus block, etc.)
- Recommended tasks: prefixed with "Open:" to distinguish from fixed calendar events
- Tasks are placed in calendar gaps, respecting the energy model and Thompson sampling scores

**Interaction:** Clicking a task opens task detail in the main app. Clicking a calendar event is a no-op (Timed is observation-only — it doesn't open Outlook).

#### Bottom Actions

Three action buttons:
- **Brief Me:** Triggers the morning intelligence session (or mid-day variant). Disabled if session is in progress.
- **Start Focus:** Opens focus timer with the next recommended task pre-selected. See `focus-timer.md`.
- **Settings:** Opens Timed settings (not a submenu — opens the main app to Settings).

---

## 5. Alert State in Menu Bar

When a proactive alert is pending (see `proactive-alerts.md`):

### 5.1 S1 (Critical)

- Menu bar icon tints red
- Status text shows alert type: "Deadline risk"
- Clicking opens the popover with the alert card at the top, above the intelligence summary
- Alert card format: see `proactive-alerts.md` Section 5.1
- The alert card has [Dismiss] and [Act On] buttons
- After dismissal or action, the menu bar returns to its previous state

### 5.2 S2 (Important)

- Menu bar icon tints amber
- Badge count appears on the icon (standard macOS badge)
- Status text shows alert type
- Alert card appears in the popover but below the intelligence summary
- Same card format and interaction as S1

### 5.3 S3 (Advisory)

- No icon change
- Badge count increments
- Advisory items appear in the popover under a collapsed "Insights" section
- User must expand the section to see them
- No urgency signaling

---

## 6. Focus Timer Integration

When a focus session is active, the menu bar becomes the focus timer's status display.

### 6.1 During Focus

- **Icon:** `timer` SF Symbol
- **Status text:** `[Task name] · [MM]m` — truncated task name + minutes remaining
- **Popover top section:** Replaces intelligence summary with focus session info:
  ```
  FOCUS SESSION
  [Task name]
  ████████████░░░░ 43m remaining
  Interruptions: 0  |  Quality: high
  
  [Pause] [End Session]
  ```
- **Popover sections below:** Collapsed or dimmed. The executive is in focus — don't distract them with patterns and progress when they check the timer.

### 6.2 Focus Session Ending

When the focus timer reaches zero:
- Menu bar shows: `[Task name] · done`
- Icon changes to `checkmark.circle`
- After 10 seconds, transitions back to normal idle state
- A brief "Session complete" card appears in the popover with the quality score

### 6.3 Break Recommendation

When the focus timer suggests a break (ultradian rhythm, see `focus-timer.md`):
- Status text: `Break · [Nm]`
- Icon: `cup.and.saucer` SF Symbol
- Popover shows break recommendation with reason

---

## 7. State Machine

```
States:
  [idle]                    — No active task, no pending events
  [focus_active]            — Focus timer running
  [focus_paused]            — Focus timer paused
  [focus_break]             — Break period between focus sessions
  [event_imminent]          — Calendar event starts within 15 minutes
  [alert_s1]                — S1 alert pending
  [alert_s2]                — S2 alert pending
  [morning_session_ready]   — Morning brief generated, not yet consumed
  [off_hours]               — Outside configured work hours

Transitions:
  [idle] → [focus_active]           : User starts focus timer
  [idle] → [event_imminent]         : Calendar event within 15m
  [idle] → [alert_s1]              : S1 alert triggered
  [idle] → [alert_s2]              : S2 alert triggered
  [idle] → [morning_session_ready]  : Nightly engine completes + morning window
  [idle] → [off_hours]             : Clock passes configured end-of-day

  [focus_active] → [focus_paused]   : User pauses focus
  [focus_active] → [idle]           : Focus timer ends or user stops
  [focus_active] → [focus_break]    : Break recommendation triggered
  [focus_active] → [alert_s1]       : S1 critical override (ONLY S1 can interrupt focus)

  [focus_paused] → [focus_active]   : User resumes focus
  [focus_paused] → [idle]           : User ends session

  [focus_break] → [focus_active]    : User starts next focus session
  [focus_break] → [idle]            : Break ends without new focus session

  [event_imminent] → [idle]         : Event starts (no longer imminent) or passes
  [event_imminent] → [focus_active] : User starts focus despite event (user's choice)

  [alert_s1] → [idle]              : Alert dismissed or acted on
  [alert_s2] → [idle]              : Alert dismissed or acted on

  [morning_session_ready] → [idle]  : Session consumed or expired (window passed)

  [off_hours] → [idle]             : Clock passes configured start-of-day
  [off_hours] → [morning_session_ready] : Morning window opens with session ready

Priority (highest wins when multiple states are valid):
  focus_active > alert_s1 > alert_s2 > morning_session_ready >
  event_imminent > focus_paused > focus_break > idle > off_hours
```

---

## 8. Visual Design

### 8.1 macOS Integration

- **Icon rendering:** SF Symbol with `.renderingMode(.template)` — adapts to system light/dark mode automatically
- **Popover:** Standard `NSPopover` with `.contentViewController`
- **Background:** Uses `.ultraThinMaterial` for the popover background (matches macOS system popovers)
- **Typography:** SF Pro (system font), respecting Dynamic Type for accessibility
- **Colours:** System semantic colours (`Color.primary`, `Color.secondary`, `Color.accentColor`) — never hardcoded hex values in menu bar UI. The exception: S1 red (`Color.red`) and S2 amber (`Color.orange`) for alert states.
- **Spacing:** 12pt padding inside popover, 8pt between sections, 4pt between list items

### 8.2 SF Symbols Used

| State | Symbol | Notes |
|-------|--------|-------|
| Idle / default | `brain.head.profile` | The intelligence layer — a brain, not a clock |
| Focus active | `timer` | Clear timer metaphor |
| Focus paused | `pause.circle` | Standard pause |
| Focus break | `cup.and.saucer` | Break = rest, not just "timer stopped" |
| Event imminent | `calendar` | Calendar context |
| Alert S1 | `exclamationmark.circle.fill` | Filled = urgent |
| Alert S2 | `exclamationmark.circle` | Outlined = important but not urgent |
| Session complete | `checkmark.circle` | Completion confirmation |
| Off-hours | `moon` | Rest state |
| Session available | `brain.head.profile` + badge dot | Standard macOS badge pattern |

### 8.3 Animation Specifications

| Animation | Specification | Duration |
|-----------|--------------|----------|
| Session available pulse | Opacity 0.5 → 1.0 → 0.5, ease-in-out | 2s cycle, repeating, stops after 30m |
| Alert state transition | Cross-dissolve icon + colour | 0.3s |
| Focus timer countdown | Status text updates every 60s (minutes, not seconds) | N/A |
| Popover open | Standard NSPopover animation (system-provided) | System default |
| Progress bar fill | Animates width on update | 0.5s ease-out |

**No animation during focus.** Even the session-available pulse is suppressed. Peripheral visual changes during focus mode are distractions.

---

## 9. Refresh Cadence

| Data | Refresh Trigger | Source |
|------|----------------|--------|
| Focus timer remaining | Every 60 seconds (display is minutes, not seconds) | Local timer |
| Next calendar event | On calendar sync + every 5 minutes | GraphClient |
| Intelligence summary | Every 15 minutes or on state change | Haiku generation |
| Active patterns | On morning session delivery + on nightly refresh | Semantic memory |
| Today's progress | On task completion or focus session end | Local DataStore |
| Alert state | On alert trigger/dismissal | Alert queue |

**Battery consideration:** The menu bar item is lightweight. The intelligence summary Haiku call (every 15 min) is the only API call. All other data is local. Total menu bar energy impact should be negligible.

---

## 10. Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+Space | Toggle popover open/closed (global hotkey, works from any app) |
| Cmd+Shift+M | Trigger morning session |
| Cmd+Shift+F | Start focus timer (with next recommended task) |
| Escape | Close popover |

Global hotkeys are registered via `CGEvent` tap or `MASShortcut`-style registration. They work when Timed is not the frontmost app.

---

## 11. Acceptance Criteria

### Core
- [ ] Menu bar displays current state at a glance in < 1 second of reading
- [ ] Click expands to intelligence summary consumable in < 10 seconds
- [ ] State machine transitions are correct — focus always wins (except S1 alert)
- [ ] Focus timer shows task name + time remaining in menu bar
- [ ] Alert states change icon colour (amber S2, red S1)
- [ ] Morning session available state shows subtle pulse

### Quality
- [ ] Menu bar item uses SF Symbols with template rendering (native light/dark)
- [ ] Popover uses system materials and typography — feels like a native macOS component
- [ ] No animation during focus mode (except focus timer countdown)
- [ ] Intelligence summary updates are contextually relevant (not stale or generic)
- [ ] Progress metrics use neutral presentation — no gamification colours

### Technical
- [ ] Popover renders within 100ms of click (all data is local or cached)
- [ ] Intelligence summary Haiku calls are batched (every 15 min, not per-popover-open)
- [ ] Global hotkeys work from any application
- [ ] Menu bar item does not leak memory on repeated popover open/close cycles
- [ ] State machine handles all edge cases (focus ends during alert, session available during focus, etc.)

---

## 12. Dependencies

| Dependency | Status | Required For |
|------------|--------|-------------|
| Focus timer | Built (basic Pomodoro) | Focus state display, session quality |
| Calendar sync | Built (GraphClient.swift) | Next event display |
| Task scoring | Built (PlanningEngine.swift) | "Next up" task recommendations |
| Morning session | This spec (morning-session.md) | Session available state |
| Proactive alerts | This spec (proactive-alerts.md) | Alert states |
| Intelligence summary generation | Not built (Haiku call) | Dynamic summary text |
| Energy curve model | Designed, not built | "Analytical peak" references in summary |

---

## 13. Open Questions

1. **Multiple monitors.** If the executive uses multiple displays, the menu bar item appears on the primary display only (macOS default). Should there be an option to show on all displays? Proposal: follow macOS default. Don't over-engineer.

2. **Popover vs window.** NSPopover closes when you click outside it. A detachable popover (NSPopover with `.behavior = .semitransient`) stays open until explicitly dismissed. Proposal: semitransient — the executive may want to keep the popover visible while working. Clicking inside the popover keeps it open; clicking outside closes it after a 0.5s delay.

3. **Width of resting state text.** Long task names make the menu bar item wide, pushing other items. Proposal: hard cap at 25 characters, truncate with ellipsis. The popover has the full name.

4. **When the app is fully closed.** If Timed is not running, the menu bar item is not visible. Should Timed launch at login as a menu bar agent? Proposal: yes, with user consent at onboarding. Timed registers as a login item (LSUIElement agent) that shows only the menu bar item. Opening the main app is optional.
