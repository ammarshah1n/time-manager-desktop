# Morning Intelligence Session PRD

**Layer:** Delivery (Layer 4)
**Owner:** Ammar Shahin / Facilitated
**Status:** Spec — implementation-ready
**Last updated:** 2026-04-02

---

## 1. Purpose

The Morning Intelligence Session is the primary delivery mechanism for Timed's compounding intelligence. It is not a task list. It is not a daily planner. It is a cognitive briefing — modelled on the CIA President's Daily Brief — delivered by a system that has spent the night thinking about this specific executive.

The session opens with a **named pattern**, not a task. This is the single design decision that separates Timed from every productivity tool, coaching app, and AI assistant on the market.

---

## 2. Design Philosophy

### 2.1 The CIA President's Daily Brief (PDB) Model

The PDB is a 10-20 page document delivered to the US President every morning. Its design principles, refined over 60+ years, are directly applicable:

- **Lead with the most consequential intelligence, not the most recent.** The PDB does not start with "here's what happened overnight." It starts with "here is the judgment that matters most to your decisions today."
- **Named patterns over raw data.** Analysts name emerging patterns (e.g., "The Tehran Pivot") — a label makes a complex signal cognitively graspable in seconds.
- **Confidence levels are explicit.** Every assessment carries a confidence qualifier: "high confidence," "moderate confidence," "low confidence — early signal." The reader always knows the strength of the evidence.
- **Brevity is non-negotiable.** The President has the same 24 hours as everyone else. The PDB fits on a few pages because every word earns its place.
- **The briefer adapts to the reader.** Each President gets the PDB in a different format — Bush wanted oral briefings with discussion, Obama wanted written briefs he could read alone. The format adapts to the consumer.

### 2.2 Executive Coaching Session Structure

The best executive coaches (Marshall Goldsmith, Michael Bungay Stanier) follow a structure:

1. **Open with an observation, not a question.** "I've noticed you've deferred three people decisions this month" is more powerful than "How are you feeling about your team?"
2. **Ask one precise question.** Not five vague ones. The best coaching question is the one the executive hasn't asked themselves.
3. **Create a moment of insight, not a list of actions.** The executive remembers the insight; they figure out the actions.
4. **Close with forward commitment.** "What will you do differently this week?" — not a task list, but a direction.

### 2.3 What This Is NOT

- Not Siri's "Good morning, here's your schedule"
- Not a chatbot conversation
- Not a meditation/wellness check-in
- Not a task list read aloud
- Not a calendar summary
- Not a goal-setting exercise

---

## 3. Session Structure

Total target duration: **45-90 seconds of system delivery + optional user interaction.**

### Phase 1 — Pattern Headline (10 seconds)

The session opens with a single named pattern. This is the highest-priority intelligence from the overnight reflection engine.

**Format:** `[Pattern Name]: [One-sentence assessment]`

**Examples:**
- "The Thursday Crunch: You've compressed 60% of your weekly decisions into Thursday afternoons for three consecutive weeks. Your decision quality data shows a 40% revision rate on Thursday decisions versus 12% on Tuesdays."
- "Client Gravity: Acme Corp is absorbing 35% of your communication bandwidth. That's triple any other client. Your response latency to board members has increased 2.3x in the same period."
- "The People Delay: You have three unresolved team performance conversations. Your pattern is to defer these until they escalate. The last time you did this, in January, it cost six weeks to recover."

**Rules for pattern headlines:**
- Must be named (a short memorable label)
- Must include specific numbers from the user's data
- Must imply a consequence or trajectory — not just a fact
- Confidence level appended: [high confidence / moderate confidence / early signal]
- If the reflection engine has no novel pattern to surface, fall back to the most strategically relevant existing pattern with new data — never deliver a generic greeting

**Source:** The overnight Opus reflection engine (Layer 3) writes pattern candidates to `semantic_memories` with a `morning_surface` flag. The Morning Director selects the highest-priority pattern based on: (1) novelty, (2) consequence severity, (3) actionability today.

### Phase 2 — Cognitive State Assessment (15 seconds)

A concise assessment of where the executive is right now — energy, cognitive load, risk factors.

**Format:** Three compressed signals delivered as a single paragraph.

**Inputs to assessment:**
- Yesterday's completion data (tasks finished, overruns, abandonments)
- Calendar density for today (meeting count, back-to-back blocks, deep work availability)
- Sleep/recovery signals if available (HealthKit integration)
- Email queue state (unprocessed count, high-priority items waiting)
- Historical day-of-week patterns for this executive
- Active avoidance signals (tasks repeatedly deferred)

**Example delivery:**
"Today is a high-density day — six meetings, two back-to-back blocks after lunch. Your historical data shows cognitive performance drops 30% after consecutive afternoon meetings. You have one deep-work window: 9:00 to 10:30. Your email queue has 14 unprocessed items, three flagged high-priority. Energy estimate: moderate — you finished late yesterday and your Tuesday pattern tends toward slow starts."

**Rules:**
- Never ask "how are you feeling?" — tell them what the data says
- Always quantify: "30% drop" not "you might feel tired"
- Always identify the scarce resource today (time, energy, attention)
- If data is insufficient (cold start, early days), explicitly say: "Limited data — this assessment will sharpen over the next two weeks"

### Phase 3 — Day Intelligence (30 seconds)

The strategic framing for the day. Not a schedule readback. Not a task list. A cognitive plan.

**Structure:**
1. **The one thing that matters most today** — a single sentence identifying the highest-leverage action
2. **What to protect** — the time block(s) that must not be sacrificed, and why
3. **What to watch for** — a specific risk or pattern to be aware of today
4. **Scored task recommendations** — top 3-5 tasks with timing recommendations, ordered by Thompson sampling score with timing adjustments from the energy curve model

**Example:**
"The highest-leverage action today is the draft response to the Meridian term sheet. It's been open for four days and your pattern shows deal quality degrades after day five of deliberation. Protect the 9:00-10:30 block for this — it's your only deep-work window and your analytical performance peaks between 9 and 11. Watch for the post-lunch meeting block pulling you into reactive mode — last time this happened, you lost the afternoon to email catch-up."

**Followed by scored tasks:**
```
1. Meridian term sheet response — 9:00-10:30 [Score: 0.94, deadline pressure + analytical peak]
2. Review Sarah's quarterly plan — 11:00-11:45 [Score: 0.81, deferred 3 days, relationship signal]
3. Approve budget reallocation — 12:00-12:15 [Score: 0.73, quick decision, before energy dip]
```

**Rules:**
- Maximum 5 task recommendations — if Thompson sampling produces more, show top 5
- Each task has a WHY — not just the score number, the reason
- Timing recommendations respect calendar gaps, energy curve, and task-type matching (analytical work in peak windows, admin in valleys)
- Never say "your schedule looks busy" — that's zero-information

### Phase 4 — One Question (5-10 seconds)

The session closes with exactly one question. This question serves two purposes: (1) it provokes a moment of executive reflection, and (2) the answer is a high-value training signal for the intelligence model.

**Question selection criteria (priority order):**
1. **Active learning signal** — the model has a specific uncertainty about the executive's preferences, priorities, or reasoning. The question resolves that uncertainty. Example: "The reflection engine flagged two equal-priority items — the Meridian response and the board deck. Which matters more to you this week, and why?"
2. **Avoidance interrogation** — the model has detected a pattern of avoidance. The question names it without accusation. Example: "You've moved the Sarah conversation three times. What's making this one hard?"
3. **Calibration check** — the model wants to verify a pattern inference. Example: "I've noticed you take calls from David within 10 minutes but let Maria's sit for hours. Is that intentional, or is something else going on?"
4. **Strategic prompt** — no specific model uncertainty exists; instead, a thought-provoking question drawn from the executive's stated priorities. Example: "You said Q2 is about the product strategy pivot. You've spent 4 hours on it in 10 days. What would it take to make this week different?"

**Rules:**
- Exactly one question. Never two. Never zero.
- The question must be specific to this executive and this day — never generic
- Never ask "How do you feel about...?" — that's therapy framing, not intelligence framing
- The answer (voice-captured) is logged as a high-priority episodic memory with `source: morning_session_response` and immediately available to the next reflection cycle

---

## 4. Trigger Conditions

### Primary Trigger: App Open
When the user opens Timed in the morning (before the session has been delivered that day), the Morning Intelligence Session begins automatically.

### Secondary Trigger: Scheduled Time
User-configurable wake time (default: 7:30 AM). If the app is already open, the session activates at this time. If the app is not open, a macOS notification invites the user to open it.

### Tertiary Trigger: Manual
User can invoke the session at any time via Cmd+Shift+M or the menu bar "Brief me" action. Outside of the morning window, the system delivers an updated mid-day intelligence brief using the same structure but with afternoon-relevant signals.

### Session Availability State
The menu bar icon transitions to a `morning-session-available` state (subtle pulse) when a new session is ready. This state persists until the session is consumed or dismissed.

### Suppression Rules
- No session during focus timer (do not interrupt deep work to deliver a briefing)
- No session if the user has been active in the app for > 30 minutes that morning (they're already in flow — offer "Catch up on today's brief?" in menu bar instead)
- Weekend sessions are optional (user preference) and shorter (pattern headline + one question only)

---

## 5. Correction as Signal

Every aspect of the session is a feedback surface.

### Explicit Corrections
- User says "That's not why I deferred that" → logged as `correction` event with the system's inference and the user's stated reason. The reflection engine treats corrections as high-weight negative evidence against the pattern that produced the inference.
- User says "Skip" during any phase → logged as `session_skip` with phase identifier. Repeated skips of a specific phase trigger adaptive shortening.
- User disagrees with task ordering → logged as `ranking_override`. The Thompson sampling model treats this as a prior update on the overridden task's score components.

### Implicit Corrections
- User ignores the session entirely (opens app, immediately navigates away) → `session_ignored` event. If this happens 3+ days in a row, the system shortens the session and increases pattern headline novelty threshold.
- User completes the "one thing that matters most" → strong positive signal for the intelligence model
- User does NOT complete the "one thing" → neutral signal (many legitimate reasons), but tracked for pattern analysis over weeks

### Correction Processing
All corrections feed into the nightly reflection engine as first-class observations. The reflection engine maintains a `correction_memory` semantic category that tracks:
- What the system got wrong
- What the user said the truth was
- Whether the system's future inferences in that category improved

This creates a visible self-improvement loop: "Last week I suggested you were avoiding the Sarah conversation. You told me it was a timing issue with her travel schedule. I've adjusted — I now distinguish between deferral-by-avoidance and deferral-by-logistics."

---

## 6. Voice-First Delivery

The session is designed for voice delivery as the primary modality, with visual reinforcement on screen.

- **Voice output:** macOS system TTS (AVSpeechSynthesizer) using the premium Siri voice. See `morning-voice.md` for full voice interaction spec.
- **Visual reinforcement:** Each phase displays concise text on screen simultaneously — the executive can glance at the screen or close their eyes and listen
- **User response:** Apple Speech (on-device) captures the answer to the One Question and any corrections. See `morning-voice.md` for speech recognition spec.

---

## 7. Cold Start Behaviour

### Days 1-7: Archetype-Driven
- Pattern headline: "Getting to know you" — explains what the system is observing and what it will learn
- Cognitive state: Based on calendar density only (the one signal available immediately)
- Day intelligence: Calendar-aware task placement using archetype-derived energy curve
- One question: High-value onboarding questions — "What time of day do you do your best analytical thinking?", "Who are the three people whose emails you should always see immediately?"

### Days 8-14: First Patterns Emerge
- Pattern headline: First real patterns from observation data (email response times, task completion accuracy, calendar behaviour)
- Confidence levels explicitly low: "Early signal — 8 days of data"
- The system names patterns tentatively and invites correction

### Days 15-30: Model Sharpening
- Patterns become specific and personal
- Energy curve model has enough data for personalised timing recommendations
- Correction history begins influencing inference quality visibly

### Day 30+: Full Intelligence
- Deep patterns from the reflection engine
- Second-order synthesis (patterns about patterns)
- Procedural rules actively shaping recommendations
- The system references its own learning: "Three weeks ago I flagged the Thursday Crunch. You've redistributed 20% of Thursday decisions to earlier in the week. Your revision rate has dropped from 40% to 18%."

---

## 8. Acceptance Criteria

### Core Acceptance
- [ ] Session delivers actionable intelligence within 60 seconds of trigger
- [ ] Session opens with a named pattern, never a task list or greeting
- [ ] Pattern headline includes specific numbers from the user's data
- [ ] Cognitive state assessment is quantified, never vague
- [ ] Day intelligence identifies the single highest-leverage action
- [ ] Exactly one question closes the session
- [ ] The question is specific to this executive and this day
- [ ] User voice response is captured and stored as episodic memory
- [ ] Corrections (explicit and implicit) are logged as first-class events

### Quality Acceptance
- [ ] An executive with 30 seconds of patience finds the first 30 seconds valuable
- [ ] The session on Day 30 is measurably more specific than the session on Day 1
- [ ] The system references its own corrections and learning improvements
- [ ] No phase contains generic content that could apply to any executive
- [ ] Task recommendations include timing rationale tied to the user's energy model

### Technical Acceptance
- [ ] Morning Director receives full cached user model (semantic + procedural memories) in system prompt
- [ ] Pattern candidates are pre-selected by the reflection engine, not computed at session time
- [ ] Session generation latency < 3 seconds (Opus cached prompt, pre-computed intelligence)
- [ ] Voice delivery begins within 500ms of session trigger
- [ ] All session events (views, skips, corrections, responses) are written to episodic memory

---

## 9. Data Flow

```
[Overnight]
Reflection Engine (Opus, max effort)
  → Writes pattern candidates to semantic_memories (morning_surface = true)
  → Writes cognitive state signals to episodic_memories
  → Writes procedural rules for task scoring

[Morning — session trigger]
Morning Director (Opus, cached user model)
  ← Reads: top pattern candidates, current calendar, email queue state,
           energy model prediction, task scores, avoidance signals,
           correction history, active learning questions
  → Generates: 4-phase session content
  → Delivers: voice + visual

[During session]
  ← User voice response to One Question
  ← User corrections / overrides / skips
  → All logged as episodic_memories with source: morning_session

[Next night]
Reflection Engine
  ← Reads morning session events as first-class observations
  → Updates model, adjusts patterns, generates tomorrow's candidates
```

---

## 10. Metrics

### Intelligence Quality
- **Pattern hit rate:** Percentage of surfaced patterns the user engages with (doesn't skip/dismiss) — target > 70% by Day 30
- **Correction decay:** Number of explicit corrections per week should decrease over time
- **Task recommendation accuracy:** Did the user complete the recommended tasks? In the recommended order? At the recommended times?

### Engagement
- **Session completion rate:** Percentage of sessions where user reaches Phase 4 — target > 80%
- **Response rate:** Percentage of One Questions that receive a voice response — target > 60%
- **Manual trigger rate:** How often the user actively requests a brief outside the morning window — higher = more value perceived

### Compounding
- **Specificity score:** Average number of personal data points referenced per session — should increase monotonically over weeks
- **Self-reference rate:** How often the session references its own previous inferences, corrections, or learning — should increase after Day 14

---

## 11. Dependencies

| Dependency | Status | Required For |
|------------|--------|-------------|
| Reflection Engine (nightly Opus) | Designed, not built | Pattern candidates |
| UserIntelligenceStore (3-tier memory) | Designed, not built | All session content |
| Thompson sampling task scoring | Built (PlanningEngine.swift) | Phase 3 task recommendations |
| Energy curve model | Designed (archetype seed exists) | Timing recommendations |
| Apple Speech (on-device) | Built (VoiceCaptureService.swift) | User response capture |
| macOS TTS (AVSpeechSynthesizer) | Built (SpeechService.swift) | Voice delivery |
| Calendar sync | Built (GraphClient.swift) | Calendar density signals |
| Email queue state | Built (EmailSyncService.swift) | Email queue signals |

---

## 12. Open Questions

1. **Session length adaptation.** Should the system learn the user's preferred session length and adapt? Risk: shorter sessions lose intelligence depth. Proposal: track engagement drop-off point per phase and tighten, but never drop below pattern headline + one question.

2. **Multiple patterns.** Some mornings the reflection engine may surface 3+ high-priority patterns. Show only the top one? Or allow "Tell me more" to access the queue? Proposal: always lead with one, offer "There are two more patterns from last night" as a visual indicator the user can tap.

3. **Weekend/travel mode.** A CEO on a flight or on vacation. Should the session adapt to context? Proposal: detect travel from calendar/timezone changes, shift to strategic-only patterns (no operational intelligence), reduce to pattern + question only.

4. **Interruption during session.** User gets a phone call mid-session. Resume where they left off? Proposal: bookmark the phase, offer "Resume your brief?" when the user returns within 30 minutes.
