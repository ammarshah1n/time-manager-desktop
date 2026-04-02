# Named Pattern Library Spec

> Timed — Layer 3 Reflection Engine, Pattern Archetype Reference
> Version: 1.0 | 2026-04-02
> Purpose: Defines the 28 pattern archetypes Timed can detect, organised by category
> Usage: Pattern extraction (Stage 2) and synthesis (Stage 3) reference this library to classify, name, and surface patterns

---

## 1. Purpose

The Named Pattern Library defines every pattern archetype Timed is designed to detect. Each archetype has:
- A stable definition that doesn't change with individual users
- Detection signals specific to the available data (email, calendar, tasks, focus, voice, app usage)
- A minimum evidence threshold before the pattern is named
- Example morning session surface text showing how the pattern is communicated

Pattern archetypes are NOT hardcoded detections. They are a vocabulary — the reflection engine uses them to classify and name patterns it discovers. The engine can also discover patterns that don't fit any archetype (classified as `uncategorised` and flagged for library expansion).

---

## 2. Category: Avoidance (7 archetypes)

### 2.1 Task Avoidance

**Definition**: A specific task or deliverable is repeatedly planned, deferred, and not completed despite no change in priority or blocking dependencies.

**Detection signals**:
- Task appears on daily plan 3+ times without progress
- Task estimated time is not disproportionately large (eliminates "too big to start" tasks)
- No external blocker logged
- Other tasks of equal or lower priority are being completed
- Task may be opened briefly and closed without meaningful progress

**Minimum evidence**: 3 deferrals over 7+ days

**Example morning surface text**: "The vendor contract review has been on your plan 4 of the last 6 days without progress. Nothing is blocking it. The last time a contract decision sat this long was the Meridian deal — it took 3 weeks to resolve after you finally addressed it. Today might be a good day to close this."

---

### 2.2 Conversation Avoidance

**Definition**: Systematic non-engagement with a specific person or with communications about a specific topic.

**Detection signals**:
- Emails from a specific person/about a specific topic opened but not replied to for >72h
- Reply rate to this person/topic is significantly below baseline
- Other emails in the same time window are being responded to normally
- Meeting requests from this person declined or rescheduled without clear reason
- The person/topic appears in morning session mentions but no action follows

**Minimum evidence**: 3+ non-responses or deferrals over 10+ days

**Example morning surface text**: "You have 3 unanswered emails from Sarah Chen about the restructuring timeline, the oldest from 9 days ago. Your average reply time to Sarah on other topics is 4 hours. Is there something about the restructuring discussion that's worth naming?"

---

### 2.3 Decision Avoidance

**Definition**: A decision point that has been reached, acknowledged, and repeatedly deferred without resolution.

**Detection signals**:
- Decision explicitly mentioned in morning sessions or task descriptions
- Decision appears in email threads that go back and forth without resolution
- Information gathering continues well past the point of diminishing returns (over-research)
- The decision involves high stakes, ambiguity, or interpersonal consequences
- Deadlines associated with the decision have been extended

**Minimum evidence**: Decision unresolved for 10+ days with 2+ explicit deferrals

**Example morning surface text**: "The product pricing decision has been pending for 18 days. You've gathered input from 6 people and run 3 analyses. The last new data point came 8 days ago. At this point, additional information is unlikely to change the decision — the delay is the decision. What would it take to commit today?"

---

### 2.4 Category Avoidance

**Definition**: An entire class of work is systematically deprioritised relative to its stated importance.

**Detection signals**:
- Tasks in a specific category (people, strategic, financial) are deferred at a statistically higher rate than other categories
- Category appears in stated priorities (morning sessions) but not in completed work
- Pattern persists across specific tasks (not just one avoided item)
- Substitution: when a task from the avoided category is scheduled, tasks from preferred categories are completed instead

**Minimum evidence**: Statistical significance across 5+ tasks in the category over 14+ days

**Example morning surface text**: "Over the past 3 weeks, people-related tasks have been deferred at 3.4 times the rate of your operational tasks. This isn't about any single item — it's a category-level pattern. Staffing, performance conversations, and role changes are all accumulating. This is typically the type of work that compounds in difficulty the longer it's deferred."

---

### 2.5 Approach-Retreat

**Definition**: The executive begins engaging with an avoided item, then disengages before making meaningful progress. A repeated start-stop cycle.

**Detection signals**:
- Document or email draft opened multiple times
- Each session is short (<5 minutes)
- No meaningful changes saved between sessions
- The item is not completed or sent
- Sessions may cluster at the beginning of the day (intention) or end (guilt)

**Minimum evidence**: 3+ short-contact sessions with the same item over 5+ days

**Example morning surface text**: "You've opened the board memo draft 5 times in the last 8 days, averaging 2.5 minutes per session. Each time, you close it without significant changes. The pattern suggests you know you need to work on it but something about it is creating resistance. What's the specific sticking point?"

---

### 2.6 Temporal Displacement

**Definition**: Consistently deferring a task to a future time period without changed circumstances justifying the delay. "I'll do it next week" repeated weekly.

**Detection signals**:
- Task due date or plan date moved forward 3+ times
- Each move is approximately one unit of time (day → day, week → week)
- No corresponding change in environment, workload, or dependencies
- Task was originally self-assigned (not externally imposed)

**Minimum evidence**: 3+ forward moves over 14+ days

**Example morning surface text**: "The org structure proposal has been moved to 'next week' for 3 consecutive weeks. Your schedule each of those weeks was not materially different from the week you originally planned it. This pattern suggests the timeline isn't the constraint."

---

### 2.7 Productive Procrastination

**Definition**: Completing lower-priority work as a substitute for facing high-priority avoided work. Being busy as a defence against being effective.

**Detection signals**:
- High volume of completed tasks on days when high-priority work is deferred
- Completed tasks are measurably lower priority than the deferred task
- The executive appears productive (inbox zero, small tasks cleared) while strategic items stagnate
- Energy and engagement are high (not burnout-driven avoidance)

**Minimum evidence**: 3+ instances where high-volume low-priority completion coincides with high-priority deferral over 10+ days

**Example morning surface text**: "Yesterday you completed 14 tasks — your highest count this month. But the restructuring proposal, which you've identified as your top Q2 priority, didn't receive any time. On 3 of your 5 highest-volume days this month, the restructuring proposal was deferred. High activity isn't the same as high impact."

---

## 3. Category: Chronotype / Energy (4 archetypes)

### 3.1 Peak Performance Windows

**Definition**: Time-of-day slots where the executive's cognitive output quality is measurably highest for specific task types.

**Detection signals**:
- Document creation velocity peaks at consistent times
- Focus session duration peaks at consistent times
- Decision quality (reversal rate proxy) peaks at consistent times
- Email composition quality (length, completeness, response-generating power) peaks at consistent times
- Low interruption acceptance rate during these windows (natural protection)

**Minimum evidence**: 10+ observations across 14+ days showing consistent time-of-day effect

**Example morning surface text**: "Your sharpest strategic window is Monday through Wednesday, 9:00 to 11:15am. Documents produced in this window are 40% longer, your focus sessions run 2.3x longer, and decisions made here are reversed at half the rate of afternoon decisions. You have a strategy session scheduled at 3pm today — consider whether it could move to tomorrow morning."

---

### 3.2 Energy Troughs

**Definition**: Predictable periods of reduced cognitive performance, often correlating with time-of-day, meeting load, or specific triggers.

**Detection signals**:
- Consistent dip in output quality at specific times
- Post-lunch performance decline (if detectable from response latency and output volume)
- Post-meeting-marathon cognitive slowdown
- End-of-day quality decline
- Increased app-switching rate during troughs (restlessness proxy)

**Minimum evidence**: 8+ observations across 14+ days

**Example morning surface text**: "Your early afternoon slot (1:30-3:00pm) is consistently your lowest-output period. Email response quality drops, focus sessions are 60% shorter, and you accept more optional meetings. Today your 1:1 with the Head of Product is at 2pm — this is a relationship that matters. Consider moving it to a slot where you're bringing your best attention."

---

### 3.3 Recovery Patterns

**Definition**: The time and conditions the executive needs to return to baseline performance after specific types of cognitive load.

**Detection signals**:
- Time from end of high-load event (long meeting, board session, crisis) to first productive output
- Recovery time variation by load type (30min after a 1:1 vs 72h after a board meeting)
- What the executive does during recovery (email, low-stakes tasks, breaks)
- Whether recovery is conscious (scheduled break) or unconscious (unplanned low-productivity)

**Minimum evidence**: 5+ recovery episodes measured across 21+ days

**Example morning surface text**: "After meetings longer than 90 minutes, your recovery time before productive output averages 45 minutes. After back-to-back meetings totalling 3+ hours, it extends to 2 hours. You have 3 hours of consecutive meetings this morning ending at noon. Realistically, your afternoon won't be productive until about 2pm."

---

### 3.4 Weekly Energy Cycle

**Definition**: Day-of-week patterns in energy, output quality, and task type preferences.

**Detection signals**:
- Monday vs Friday output volume and quality comparison
- Day-of-week variation in email length, response time, and tone
- Meeting engagement variation by day (acceptance rate, post-meeting action speed)
- Strategic vs operational time allocation by day of week
- Focus session quality by day

**Minimum evidence**: 4+ weeks of data showing consistent day-of-week effects

**Example morning surface text**: "It's Thursday. Your Thursday pattern: high operational throughput, low strategic depth. Over the past 6 weeks, 80% of your strategic document work happened Monday through Wednesday, while Thursday and Friday skew heavily operational. Your schedule today has 2 strategic items — consider whether they'll get your best work or whether Monday morning would serve them better."

---

## 4. Category: Relationship (4 archetypes)

### 4.1 Communication Frequency Shifts

**Definition**: Directional change in interaction rate with a specific person or group over time — either increasing (escalating importance/concern) or decreasing (cooling/deprioritising).

**Detection signals**:
- Email volume per person per week tracked over rolling 4-week windows
- Meeting frequency per person tracked similarly
- 1:1 scheduling changes (biweekly → weekly = escalation, weekly → biweekly = cooling)
- Response time trend with specific people

**Minimum evidence**: Statistically significant trend across 3+ weeks

**Example morning surface text**: "Your communication frequency with James Park has dropped 60% over the past 3 weeks — from 8 emails and 2 meetings per week to 3 emails and no meetings. The last time a key relationship went this quiet for this long was with the Melbourne team lead, which required 6 weeks of rebuild. Worth a pulse check?"

---

### 4.2 Sentiment Trajectory

**Definition**: Detectable change in the emotional tone of communications with a specific person — from collaborative to directive, warm to formal, engaged to transactional.

**Detection signals**:
- Linguistic marker shifts: pronoun use (we → I/you), hedging increase/decrease, warmth tokens (greetings, acknowledgements), directness markers
- Email length changes with the same person (shorter = often cooler)
- Formality shifts (first name → title, casual → structured)
- Response time changes (faster can mean urgency or anxiety, slower can mean cooling)

**Minimum evidence**: Consistent directional shift across 5+ communications over 14+ days

**Example morning surface text**: "Your emails to the COO have shifted tone over the past 2 weeks. Earlier: 'Great idea, let's discuss next steps.' Recent: 'Please ensure this is completed by Friday.' The shift from collaborative to directive language is notable. Is this intentional — a management choice — or is frustration driving it?"

---

### 4.3 Response Priority Hierarchy

**Definition**: The implicit priority ranking the executive assigns to different people, revealed by response speed rather than stated importance.

**Detection signals**:
- Median response time per person, computed over 4+ week rolling window
- Ranking of contacts by response speed
- Discrepancy between stated priority (CEO mentions "the Board is my top stakeholder") and revealed priority (Board emails have 4x slower response than direct report emails)
- Time-of-day effects per person (some people get immediate responses at 7am, others wait until business hours)

**Minimum evidence**: 10+ response data points per person over 21+ days

**Example morning surface text**: "Your response time ranking this month — fastest to slowest: CFO (14min median), Head of Product (22min), your PA (35min), Board Chair (4.2 hours), Head of Legal (6.8 hours). The Board Chair is technically your most important stakeholder but receives your 4th-fastest responses. This may or may not be intentional — but it's the signal you're sending."

---

### 4.4 Relationship Maintenance Gap

**Definition**: A key relationship that has gone without interaction for longer than the historical norm, creating a maintenance gap that may be difficult to recover from.

**Detection signals**:
- Last interaction date per key contact
- Historical interaction cadence per contact
- Current gap compared to historical cadence (2x normal gap = warning, 3x = alert)
- Relationship importance score (derived from communication volume, meeting presence, email priority)

**Minimum evidence**: Gap exceeds 2x the historical interaction cadence for that relationship

**Example morning surface text**: "You haven't had any interaction with David Park (Advisory Board) in 19 days. Your historical cadence with David is weekly. The last time you went this long, you mentioned in your morning session that the relationship needed 'rebuilding.' A 5-minute email or a coffee invite might be well-timed."

---

## 5. Category: Cognitive Load (4 archetypes)

### 5.1 Overload Signals

**Definition**: Multiple simultaneous indicators that the executive's cognitive load has exceeded their productive capacity.

**Detection signals**:
- Email response latency >2x personal baseline across all contacts
- App-switching rate >2x baseline
- Email length <50% baseline (compression under load)
- Decision deferral rate spikes
- Focus session duration <50% baseline
- Calendar whitespace consumed within hours of appearing
- Meeting decline rate drops (accepting everything without filtering)

**Minimum evidence**: 3+ simultaneous overload signals persisting for 4+ hours or recurring on 3+ days in a 7-day window

**Example morning surface text**: "Yesterday showed multiple overload signals: your email replies were half their usual length, you switched apps 3x more than usual, and you accepted 2 meetings you'd normally decline. This follows 4 consecutive days of 6+ hours of meetings. Your system is showing the signs of cognitive overload. What can come off today's plate?"

---

### 5.2 Recovery Needs

**Definition**: Specific conditions and activities that correlate with faster return to baseline performance after periods of high load.

**Detection signals**:
- What the executive does after overload periods that precedes performance recovery
- Does exercise (calendar entries, HealthKit if authorised) accelerate recovery?
- Does a meeting-free morning accelerate recovery?
- Does reduced email volume correlate with faster recovery?
- What distinguishes a day that recovers from one that stays depleted?

**Minimum evidence**: 5+ overload-recovery cycles observed over 30+ days

**Example morning surface text**: "After your last 3 overload periods, your fastest recovery happened when the following morning was meeting-free until 10am. Your slowest recovery was when you went straight into back-to-back meetings the next day. Today is a recovery day — I've noted your first meeting isn't until 10:30. Protecting this morning would be high-value."

---

### 5.3 Context-Switch Cost

**Definition**: The measurable productivity cost when this executive switches between different types of work, and which transitions are most expensive.

**Detection signals**:
- Time-to-productive-output after switching from meetings → deep work
- Time-to-productive-output after switching from email → deep work
- Which transitions produce the longest recovery (meeting → strategic document is typically worst)
- Which transitions are nearly costless (email → email, admin → admin)
- Individual variation from population norms (Sophie Leroy's attention residue research suggests 23min average — what's this person's actual number?)

**Minimum evidence**: 10+ measured transitions per transition type over 21+ days

**Example morning surface text**: "Your most expensive context switch is meetings → strategic document work: you average 38 minutes before productive output begins. Today you have a strategy session immediately after a 2-hour team meeting. That 38-minute gap means you'll lose half the session to attention residue. A 15-minute buffer between them would recover most of that."

---

### 5.4 Capacity Ceiling

**Definition**: The maximum number of concurrent active projects, decisions, or communication threads this executive can manage before quality degrades.

**Detection signals**:
- Track concurrent active items (projects, decisions, email threads requiring substantive response)
- Correlate active item count with quality metrics (response quality, decision reversal rate, output volume)
- Identify the inflection point where adding one more item degrades everything
- Track whether the ceiling changes over time (adaptation, or permanent constraint)

**Minimum evidence**: 8+ weeks of concurrent load data with measurable quality variation

**Example morning surface text**: "You currently have 7 active projects requiring your attention. Your data suggests your quality starts degrading above 5 concurrent projects — specifically, decision latency increases 40% and email response quality drops. Two of these projects could potentially be delegated or paused. Would it be worth reviewing your active portfolio?"

---

## 6. Category: Strategic / Tactical (3 archetypes)

### 6.1 Time Allocation Ratio

**Definition**: The ratio of time spent on strategic work (long-term value creation) vs tactical/operational work (day-to-day execution), and how it compares to the executive's stated intentions.

**Detection signals**:
- Classify all activities as strategic, tactical, relational, or administrative
- Compute weekly ratios
- Compare to stated priorities from morning sessions
- Detect drift: when the ratio changes over time without a stated reason
- Research benchmark: effective CEOs typically spend 25-40% on strategic work

**Minimum evidence**: 3+ weeks of classified activity data

**Example morning surface text**: "This week your time allocation: 18% strategic, 52% operational, 22% relational, 8% administrative. Your stated Q2 priority is the product strategy, but strategic time has averaged 15% over the past 3 weeks — down from 30% in February. The operational work is expanding without a corresponding strategic event to justify it."

---

### 6.2 Strategic Drift Detection

**Definition**: A gradual, often unconscious shift away from stated strategic priorities toward operational comfort zones.

**Detection signals**:
- Strategic time allocation declining over a multi-week trend
- Morning session mentions of strategic priorities decreasing
- Calendar increasingly filled with operational meetings
- Strategic documents untouched for >7 days while operational output is high
- The executive's stated priorities haven't changed, but their behaviour has

**Minimum evidence**: 3+ week declining trend in strategic time allocation

**Example morning surface text**: "You identified 3 strategic priorities for Q2: product strategy, board governance reform, and the Asia expansion. Over the past 4 weeks, combined time on these three has declined from 12 hours/week to 4 hours/week. Operational demands haven't materially changed — the drift appears to be unconscious. Which of the three should reclaim time this week?"

---

### 6.3 Urgency Addiction

**Definition**: A pattern of preferentially engaging with urgent-but-low-importance work over important-but-non-urgent work, driven by the dopamine reward of immediate resolution.

**Detection signals**:
- High completion rate on urgent tasks regardless of importance
- Low completion rate on important non-urgent tasks
- Rapid context-switching to respond to new incoming items
- Time spent in email/Slack disproportionate to value created
- Morning session plans focused on strategic work that is abandoned within 2 hours for reactive tasks

**Minimum evidence**: Consistent pattern across 14+ days with measurable urgency-over-importance preference

**Example morning surface text**: "Your morning plans have included strategic work every day this week. By noon each day, you've switched to reactive tasks — emails, ad-hoc requests, quick approvals. Your strategic items have been deferred 4 days running. The urgent work feels productive in the moment, but it's displacing the work you've identified as most important."

---

## 7. Category: Decision Quality (3 archetypes)

### 7.1 Optimal Decision Conditions

**Definition**: The specific conditions (time of day, prior activities, information level, emotional state proxies) that correlate with this executive's best decisions — measured by reversal rate, outcome quality, and speed-to-resolution.

**Detection signals**:
- Decision timestamp correlated with reversal-within-48h rate
- Prior meeting load correlated with decision quality
- Information gathering depth correlated with decision quality (is there a sweet spot?)
- Day of week effects on decision quality
- Decision quality variation by category (financial, people, strategic, operational)

**Minimum evidence**: 15+ tracked decisions over 30+ days

**Example morning surface text**: "Your best decisions — the ones that stick without revision — happen before 11am on days with fewer than 3 prior meetings. Today you have a board-level decision on the acquisition due at EOD. Your morning is meeting-free until 10. This is your decision-making sweet spot — I'd suggest tackling it at 9am rather than letting it slide to the afternoon."

---

### 7.2 Decision Fatigue Indicators

**Definition**: Signals that the executive's decision quality is degrading due to accumulated decision load.

**Detection signals**:
- Increasing decision deferral rate within a single day
- Decisions becoming faster without additional information (snap judgments from exhaustion)
- Decreasing email length in decision communications (compression)
- Increasing use of delegation language ("just handle it", "your call") late in the day
- Post-3pm decisions reversed at higher rates

**Minimum evidence**: 5+ days showing intra-day decision quality degradation over 14+ days

**Example morning surface text**: "Today's agenda has 6 items requiring your decision. Based on your pattern, your decision quality starts declining after the 4th major decision in a day. I'd suggest ordering these by importance — your first 4 decisions will be your strongest. The remaining 2 might be better delegated or deferred to tomorrow morning."

---

### 7.3 Anchoring / Recency Bias

**Definition**: A tendency for this executive's decisions to be disproportionately influenced by the most recent information, the most vocal stakeholder, or the first option presented.

**Detection signals**:
- Decision alignment with the last opinion received (tracked via email/meeting sequence before decision)
- Decision reversals that correlate with new stakeholder input (not new data)
- Pattern of choosing the first option presented when multiple options exist
- Decisions that change after a single objection from a high-status person

**Minimum evidence**: 8+ decision instances showing the bias pattern over 30+ days

**Example morning surface text**: "A pattern I've observed in your strategic decisions: when you receive input from multiple people, your final decision tends to align with the last opinion you heard. In 6 of your last 8 multi-stakeholder decisions, your choice matched the final advisor's recommendation — even when earlier input was more data-grounded. You're meeting with the CFO last today before the budget decision. Worth being aware that their position may carry disproportionate weight simply because of timing."

---

## 8. Category: Communication (3 archetypes)

### 8.1 Style Shifting

**Definition**: The executive communicates differently with different audiences — and the shift reveals something about the relationship dynamic.

**Detection signals**:
- Email length variation by recipient (long/detailed for some, terse for others)
- Formality variation (casual with peers, formal with Board, directive with reports)
- Response time variation that doesn't correlate with importance
- Tone markers: collaborative language vs directive language vs deferential language
- Channel preference by person (email for some, phone for sensitive topics)

**Minimum evidence**: 10+ communications per person for at least 5 people over 21+ days

**Example morning surface text**: "Your communication style varies significantly by audience. With the CFO: collaborative, detailed, questions-oriented. With the Head of Ops: directive, brief, action-oriented. With the Board Chair: formal, hedged, longer-than-average. These differences may be deliberate and appropriate — or they may reveal unexamined power dynamics worth reflecting on."

---

### 8.2 Communication Load Threshold

**Definition**: The maximum number of active email threads and conversations the executive can manage before response quality degrades.

**Detection signals**:
- Track active thread count (threads with pending responses)
- Correlate thread count with response quality (length, completeness, timeliness)
- Identify the inflection point where quality drops
- Track whether the executive self-regulates (pauses new threads when overloaded)

**Minimum evidence**: 4+ weeks of thread count vs quality data

**Example morning surface text**: "You currently have 23 active email threads awaiting your response. Your quality data suggests your responses become noticeably shorter and less thorough above 15 active threads. Batching or delegating 8 lower-priority threads would bring you back to your productive range."

---

### 8.3 Written vs Verbal Processing

**Definition**: Whether this executive processes and decides better through writing (email, documents) or through conversation (meetings, voice), and for which types of decisions.

**Detection signals**:
- Decision quality correlated with decision channel (email decision vs meeting decision)
- Strategic work quality: written analysis vs discussion-based
- Which channel produces longer, more detailed engagement
- Self-selection: does the executive move certain topics to verbal channels voluntarily?

**Minimum evidence**: 15+ decisions tracked across both channels over 30+ days

**Example morning surface text**: "Your financial decisions are stronger when you process them in writing — your email-based financial decisions have a 6% reversal rate vs 22% for those made verbally in meetings. But your people decisions show the opposite: verbal processing produces better outcomes (11% reversal) than email-based (34%). The acquisition discussion is both financial and people-related — a written analysis followed by a short verbal discussion might be the optimal process."

---

## 9. Category: Energy Management (2 archetypes)

### 9.1 Meeting Drain Profile

**Definition**: How different types of meetings drain the executive's cognitive energy, and the specific recovery pattern for each type.

**Detection signals**:
- Post-meeting output volume and quality by meeting type
- Recovery time before next productive output by meeting type
- Meeting types: 1:1, team sync, board, external, workshop, interview
- Attendee count correlation with drain
- Meeting duration correlation with drain (linear or exponential?)
- Meeting content type correlation (conflict-heavy meetings drain more than informational)

**Minimum evidence**: 20+ meetings of each type observed over 30+ days

**Example morning surface text**: "Today's meeting schedule: a 90-minute team sync, a 30-minute 1:1, and a 2-hour board committee call. Based on your data, the team sync typically costs you 20 minutes of recovery, the 1:1 costs almost nothing, but the board committee call will likely need 90 minutes of recovery. That means your last productive window today is probably 2:30-3:00pm, not 5:00pm. Plan your must-do output accordingly."

---

### 9.2 Energy Restoration Activities

**Definition**: Activities or conditions that measurably restore the executive's cognitive performance after depletion.

**Detection signals**:
- What precedes fastest recovery from overload episodes
- Does a midday walk (calendar entry) correlate with better afternoon performance?
- Does a meeting-free morning after a heavy day correlate with recovery?
- Does reduced email engagement correlate with energy restoration?
- Are there specific people whose meetings are energising rather than draining? (positive energy sources)

**Minimum evidence**: 8+ depletion-recovery cycles over 30+ days

**Example morning surface text**: "Your three fastest cognitive recoveries this month all followed a meeting-free morning. Your slowest recovery followed jumping straight into a packed schedule. Today is the morning after your heaviest meeting day this week. The first 2 hours are free — I'd strongly suggest keeping them that way."

---

## 10. Detection Priority

Not all patterns are equally valuable. The reflection engine should prioritise detection in this order:

| Priority | Category | Rationale |
|----------|----------|-----------|
| 1 | Avoidance | Highest insight value — tells the user what they can't see about themselves |
| 2 | Decision Quality | Directly impacts outcomes — every improved decision compounds |
| 3 | Energy / Chronotype | Immediately actionable — changes today's schedule |
| 4 | Strategic / Tactical | Critical for long-term performance — prevents drift |
| 5 | Relationship | High-value but slower-moving — weekly surface cadence is sufficient |
| 6 | Cognitive Load | Important for real-time gating of intelligence delivery |
| 7 | Communication | Descriptive and useful but rarely urgent |

---

## 11. Pattern Naming Conventions

When the reflection engine discovers a pattern matching an archetype, it generates a **specific, human-readable name** that:

1. Includes the relevant context (person, time, task) — not the generic archetype name
2. Is concise (under 60 characters)
3. Is factual, not judgmental (no "bad habit" framing)
4. Would make sense to the user without explanation

**Good names**:
- "Post-Board 72-Hour Strategic Slowdown"
- "Monday Morning Focus Window"
- "People Decision Deferral Pattern"
- "Sarah Chen Communication Gap"
- "Afternoon Decision Quality Decline"
- "End-of-Quarter Operational Drift"

**Bad names**:
- "Avoidance Pattern #3" (meaningless)
- "Your Procrastination Problem" (judgmental)
- "Temporal Pattern: Friday" (robotic)
- "Behavioural Anomaly" (vague)

---

## 12. Archetype Expansion Protocol

The 28 archetypes above are the initial library. The reflection engine will discover patterns that don't fit existing archetypes. When this happens:

1. The pattern is classified as `uncategorised` and stored normally
2. After 3+ uncategorised patterns share structural similarity, Opus proposes a new archetype
3. The new archetype is added to the library with a definition, detection signals, and minimum evidence threshold
4. Existing uncategorised patterns are reclassified against the new archetype

Expected library growth: 28 → 35-40 archetypes by month 6, as the system discovers patterns specific to the individual that don't fit the general taxonomy.
