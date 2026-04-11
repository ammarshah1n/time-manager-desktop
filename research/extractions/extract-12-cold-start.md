# Extract 12 — Cold Start Architecture

Source: `research/perplexity-outputs/v2/v2-12-cold-start.md`

---

## DECISIONS

### What Opus can infer from first 48 hours
- **Reliably inferable (high confidence, 48h):** Extraversion, network centrality, communication energy, email response time distribution, calendar density/fragmentation, meeting-to-deep-work ratio, top contact clusters
- **NOT inferable (requires 2-4 weeks minimum):** Conscientiousness, decision-making style (deliberative vs intuitive), agreeableness, delegation patterns, stress response shifts
- **Evidence base:** 578-executive email metadata study achieved 83.56% top-performer identification from metadata alone — direct validation for Timed's email pipeline
- **Boundary rule:** Trait inferability follows Ambady's thin-slice hierarchy — observable/externalised traits (extraversion, dominance) converge fast; evaluative/internal traits (conscientiousness, neuroticism) require extended observation or self-report

### Optimal onboarding sequence
- **12 minutes is the ceiling.** Beyond that, marginal information gain does not justify the attention cost for a C-suite executive
- **SOKA model (Vazire) inverts the intuitive design:**
  - ASK about: neuroticism, internal experience, stress triggers, risk tolerance, personal priorities — only the executive knows these
  - INFER behaviourally: intellect, leadership effectiveness, communication style, reactivity, delegation patterns — others (and behavioural data) outperform self-report for evaluative traits
  - Never ask "how reactive are you?" — the calendar tells a more honest story
- **Sequence:** Internal state questions first (what only they know) → defer evaluative traits to observation → compare self-report vs observed after 1-2 weeks
- **Instrument choice:** REI (Rational-Experiential Inventory) over MBTI for cognitive style. Big Five has predictive validity for executive behaviour; MBTI does not

### Default intelligence library (20-30 base-rate insights)
- Calendar-derived: fragmented time blocks unusable for deep work, meeting density vs Porter/Nohria CEO baselines, back-to-back meeting chains with no recovery, ratio of 1:1 vs group meetings, evening/weekend calendar bleed
- Email-derived: response time distribution (reactive vs batched), email volume by hour (cognitive load proxy), contact network centrality, ratio of sent:received, after-hours email patterns
- Cross-signal: calendar says "free" but email volume is peak (phantom availability), meeting prep time vs meeting count mismatch
- Research-backed framing: every insight references the specific study (e.g., "Gloria Mark's research: 23 minutes to recover from an interruption — you have 7 context switches before noon")

### Expectation gap management
- **Frame the cold start as a feature:** "I can already see your calendar structure. I cannot yet comment on how your communication style shifts under board pressure — that requires 3-4 weeks of observation."
- **Endowed progress effect (Nunes & Dreze):** Pre-populate the cognitive model with dimensions already measured (communication style: observable from hour 1) and explicitly leave others empty with reasons. This produces the 34% vs 19% completion/retention rate difference
- **Qualitative calibration over quantified progress:** "I can now distinguish your strategic contacts from your operational contacts" beats "I'm 15% through learning your patterns"
- **Pygmalion framing:** Tell the executive the system will become dramatically more intelligent — this increases initial engagement (positive expectation effect)

### Value trajectory design
- **Day 1:** Base-rate intelligence from calendar/email structure. Valuable to any executive. No personalisation required
- **Day 3:** First thin-slice inferences — communication energy, network centrality, time allocation vs CEO baselines
- **Week 1:** First pattern observations — recurring scheduling inefficiencies, email response rhythms, meeting cluster analysis
- **Week 2:** First cross-signal correlations — email volume spikes before certain meeting types, calendar fragmentation correlated with response delays
- **Week 4:** First predictive insights — anticipating overload weeks, identifying emerging contact importance shifts
- **Month 3:** First deep cognitive model outputs — decision-making style characterisation, stress-response patterns, delegation tendency predictions

---

## DATA STRUCTURES

### Onboarding sequence schema (week 1 day-by-day)

```
Day 0 (Setup, ~12 min):
  - Grant Microsoft Graph permissions (email + calendar read-only)
  - 4-5 SOKA-informed questions:
    1. "What keeps you up at night about your role right now?" (internal state)
    2. "When you need to make a high-stakes decision, what does your process look like?" (cognitive style — self-report, will verify against observed)
    3. "What does a good week look like for you vs a bad week?" (personal benchmark)
    4. "Who are the 3-5 people whose input matters most to your decisions?" (network seed)
    5. Optional: "What should I know about you that wouldn't be visible from your calendar and email?" (unknown unknowns)
  - System begins background ingestion of last 90 days email metadata + calendar

Day 1:
  - Morning session: first base-rate intelligence delivery
  - Calendar structure analysis (fragmentation, meeting density, deep work availability)
  - Email metadata analysis (volume, response time distribution, contact clustering)
  - Frame: "Here is what I can see from your calendar and email structure, calibrated against research on 27 CEOs tracked over 13 weeks."

Day 2-3:
  - First thin-slice inferences generated
  - Communication energy classification (high-volume/rapid vs deliberate/batched)
  - Network centrality map (who gets fastest responses, who gets most meetings)
  - Confidence: moderate. Framed as hypotheses, not conclusions

Day 4-7:
  - Pattern observation begins
  - First recurring inefficiency detection (e.g., Monday back-to-back chains, Friday email surge)
  - Begin comparing self-reported decision process vs observed calendar patterns
  - Deliver first "this week vs last week" comparison
```

### Default intelligence templates

**Calendar-based (available hour 1):**
- Deep work availability score: total uninterrupted blocks >= 90 min this week
- Meeting load vs Porter/Nohria baseline (CEOs average 72% in meetings, 28% alone)
- Context-switch count: number of meeting-to-different-topic transitions per day
- Recovery gap analysis: meetings with <15 min buffer
- Evening/weekend calendar bleed index

**Email-based (available hour 1):**
- Response time distribution (median, p90, p99) — reactive vs batched classification
- Email volume by hour heatmap — cognitive load temporal profile
- Contact network tier map (top 10 by frequency, top 10 by response speed)
- Sent:received ratio — information producer vs consumer classification
- After-hours email percentage

**Universal (no data required):**
- Gloria Mark attention residue cost (23 min recovery per context switch)
- Kahneman System 1/2 decision fatigue research applied to meeting sequencing
- Klein RPD model — pattern recognition degrades after 4+ hours without breaks
- Eisenhardt fast strategic decision research — simultaneous alternatives outperform sequential

### Value milestone framework

```
Milestone        | Intelligence type        | Confidence | Signal source
-----------------|--------------------------|------------|---------------------------
Hour 1           | Calendar structure        | High       | Calendar alone
Hour 1           | Email volume/timing       | High       | Email metadata alone
Day 1            | Base-rate benchmarking    | High       | Calendar + email vs research baselines
Day 3            | Thin-slice personality    | Moderate   | Email patterns + calendar style
Day 3            | Network centrality map    | Moderate   | Email + calendar attendees
Week 1           | Recurring inefficiencies  | Moderate+  | 7-day pattern detection
Week 1           | Self-report vs observed   | Low-Mod    | Onboarding answers vs data
Week 2           | Cross-signal correlation  | Moderate   | Email × calendar × app usage
Week 4           | Predictive (overload)     | Moderate+  | 4-week pattern + trend
Week 4           | Decision-style inference  | Moderate   | Meeting patterns + email style shifts
Month 3          | Deep cognitive model      | High       | Full behavioural convergence
Month 3          | Stress-response mapping   | High       | Multi-signal pattern over time
```

### Cold-start prompt templates for Claude Opus

**Day 1 system prompt structure:**
```
You are the intelligence layer of Timed. You have:
1. Raw calendar data for the past [N] days
2. Email metadata (timestamps, contact frequency, response times) for the past [N] days
3. Research baselines: Porter & Nohria CEO time study (27 CEOs, 60,000 hours), Gloria Mark attention research, Klein RPD model
4. Executive's onboarding answers: [injected]

Your task: Generate 3-5 insights that are genuinely valuable to a C-suite executive. Each insight must:
- Reference a specific pattern in THEIR data
- Calibrate against research baselines
- Be actionable (what could change) without prescribing action
- Include confidence level and what additional observation would increase confidence

Do NOT generate generic productivity advice. Every insight must be grounded in this executive's actual data.
```

**Thin-slice inference prompt (Day 3):**
```
Given 48 hours of email metadata and calendar data, generate hypotheses about:
1. Communication energy (high-throughput rapid responder vs deliberate batched processor)
2. Network structure (hub-and-spoke vs distributed vs hierarchical)
3. Time sovereignty (controls own calendar vs calendar-controlled)
4. Cognitive load trajectory (building through week vs front-loaded vs chaotic)

For each: state the hypothesis, the specific data points supporting it, confidence level (low/moderate/high), and what data over the next 2 weeks would confirm or disconfirm.

Frame as: "Based on 48 hours, here is what I'm beginning to see. I'll have higher confidence by [date]."
```

---

## ALGORITHMS

### Thin-slice inference from 48 hours
1. **Email metadata clustering:** Group contacts by response time (strategic tier: fastest responses; operational tier: batched responses; low-priority tier: slowest/ignored). 48h is sufficient for tier classification if email volume is >= 20/day
2. **Calendar fragmentation scoring:** Count blocks >= 90 min with no interruption. Score against Porter/Nohria baseline (CEOs average 28% alone time). Fragmentation = 1 - (longest_uninterrupted_block / total_work_hours)
3. **Communication energy classification:** Median response time < 15 min = reactive/high-energy; 15-60 min = moderate; > 60 min = deliberate/batched. Cross-validate with time-of-day distribution
4. **Network centrality extraction:** From email sender/receiver frequency + calendar attendee co-occurrence, build weighted contact graph. Hub contacts (top 5 by combined email + meeting frequency) are identifiable within 48h

### Rapid rapport building sequence
1. **Mirror detected communication style in first output.** If executive emails are terse/direct, Timed's first morning session should be terse/direct. If verbose/analytical, match that register
2. **Lead with specificity, not capability claims.** First interaction: "Your calendar shows 3h12m of fragmented time this week across 11 blocks — none long enough for deep strategic work per Gloria Mark's research" — not "I'm an AI that will learn your patterns"
3. **Demonstrate observation before asking for trust.** Show the executive something true about their own behaviour they hadn't quantified. This is the computational equivalent of a coach's "I noticed that..." opening
4. **Acknowledge uncertainty explicitly.** "I can see your calendar structure clearly. I cannot yet read the intent behind your scheduling choices — that takes 2-3 weeks." Calibrated confidence builds trust faster than false confidence

### Progressive personalisation (generic -> thin-slice -> pattern -> predictive)
```
Stage 1 (Day 1): Generic + data-grounded
  Input: Calendar + email structure + research baselines
  Output: Base-rate insights calibrated to their specific numbers
  Confidence: High for structure, N/A for behaviour

Stage 2 (Day 2-3): Thin-slice inference
  Input: 48h behavioural data + Ambady/Kosinski priors
  Output: Personality/style hypotheses with explicit confidence
  Confidence: Moderate for externalised traits, low for internal

Stage 3 (Week 1-2): Pattern detection
  Input: 7-14 day behavioural sequences
  Output: Recurring patterns, cross-signal correlations
  Confidence: Moderate-high for scheduling patterns, moderate for behavioural

Stage 4 (Week 4+): Predictive
  Input: 4+ weeks of multi-signal data
  Output: Anticipatory intelligence (predict overload, flag anomalies)
  Confidence: Moderate-high, improving with each week

Stage 5 (Month 3+): Deep cognitive model
  Input: Full behavioural history + reflection engine synthesis
  Output: Decision-style characterisation, stress-response predictions, cognitive model
  Confidence: High
```

### Engagement monitoring during learning period
- Track morning session engagement: did the executive read it? How long? Did they interact?
- If engagement drops 2 consecutive days: escalate insight specificity (shift from base-rate to thin-slice even at lower confidence — the risk of boring them exceeds the risk of a wrong hypothesis)
- If engagement drops 5 consecutive days: trigger a "recalibration" prompt — "Based on my first [N] days of observation, here are the 3 most important things I've learned about how you work. Are any of these wrong?"
- Never let more than 48h pass without delivering at least one novel insight. Repetition = death

---

## APIS & FRAMEWORKS

### Ambady thin-slice research methodology
- **Core finding:** Observers can make accurate personality judgments from as little as 30 seconds of behavioural data (Ambady & Rosenthal, 1992)
- **Timed application:** Email metadata and calendar structure are a digital thin slice. 48 hours of email/calendar data is orders of magnitude more information than Ambady's 30-second video clips
- **Trait-dependent accuracy:** Extraversion and dominance converge fastest; conscientiousness and agreeableness require longer observation
- **Implementation:** Use thin-slice confidence tiers — classify each inferred trait by expected convergence time and present accordingly

### Vazire SOKA model (Self-Other Knowledge Asymmetry)
- **Core finding:** People have privileged access to their internal states (neuroticism, anxiety, values) but poor access to their externalised behaviours (how they come across, leadership effectiveness, communication style). Others are better judges of evaluative/observable traits
- **Timed application:** Ask the executive ONLY about what they uniquely know (internal experience, priorities, stress triggers). NEVER ask about what behaviour reveals better (reactivity, delegation effectiveness, communication dominance). Infer the latter from data
- **Implementation:** Onboarding questions map to SOKA "self-better" quadrant exclusively. All "other-better" traits are inferred from Graph API data and never asked about

### Porter & Nohria CEO time study baselines
- **Study:** 27 CEOs tracked for 13 weeks each (60,000+ hours total), published HBR 2018
- **Key baselines for Timed:**
  - 72% of time in meetings (range: 55-90%)
  - 28% alone time (the most effective CEOs protect more of this)
  - 25% of time on strategy, 25% on people/culture, 16% on functional review
  - 61% face-to-face, 15% phone/video, 24% electronic
  - Average CEO works 9.7 hours per weekday, 3.9 hours per weekend day
- **Implementation:** Use as the prior for calendar analysis. "Your meeting load is 81% — above the CEO median of 72%. The highest-performing CEOs in Porter & Nohria's study actively protected more alone time."

### Endowed progress effect (Nunes & Dreze)
- **Core finding:** People given artificial advancement toward a goal (e.g., a loyalty card with 2 of 10 stamps pre-filled) complete at 34% vs 19% for equivalent effort with no pre-fill
- **Timed application:** Pre-populate the cognitive model dashboard with dimensions already measured (communication style: filled; network map: filled; calendar structure: filled). Leave explicitly empty: decision-making style (requires 3-4 weeks), stress-response pattern (requires 6-8 weeks). The executive sees progress from hour 1
- **Implementation:** Cognitive model has N dimensions. Show which are populated, which are empty, and WHY each empty one requires more time. The executive experiences forward momentum from the first session

---

## NUMBERS

### Thin-slice judgment accuracy (digital footprints)
- **Kosinski (2015):** Computer models using digital footprints (Facebook Likes) outperform human personality judges. 10 Likes > coworker accuracy. 70 Likes > friend. 150 Likes > family member. 300 Likes > spouse
- **Email metadata study (578 executives):** 83.56% accuracy identifying top performers from email metadata alone (response times, volume, network patterns)
- **Ambady thin-slice:** 30-second behavioural clips produce personality judgments that correlate 0.32-0.76 with long-term assessments depending on trait

### Onboarding optimal duration
- **12 minutes is the ceiling** for C-suite executive attention in an onboarding flow
- **5-minute option:** Captures 3 high-value SOKA questions. Sufficient if email/calendar history is available for backfill
- **15-minute option:** Diminishing returns beyond 12 minutes. Behavioural data will correct self-report inaccuracies within days regardless
- **45 minutes:** Actively harmful. Signals that the system does not respect executive time. Coach-equivalent intake sessions are 45-60 min but coaches have reciprocal human rapport — an AI onboarding does not

### Minimum observation period for first personalised insight
- **Hour 1:** Calendar structure insights (not personalised, but data-specific)
- **48 hours:** First personality thin-slice inferences (communication energy, network tier map)
- **7 days:** First recurring pattern detection (weekly scheduling rhythms)
- **14 days:** First cross-signal correlations (email patterns x calendar patterns)
- **28 days:** First predictive insights (anticipating overload)
- **Email patterns stabilise faster than decision-making patterns** — email rhythm is detectable in 3-5 days; decision style requires 3-4 weeks minimum

### Executive coach human baseline
- **First meeting:** Coach forms initial impressions (equivalent to thin-slice)
- **Sessions 3-4 (weeks 3-6):** Coach reports "beginning to understand" the executive
- **Sessions 6-8 (months 2-4):** Coach reports feeling they have an accurate mental model
- **Timed target:** Match session 3-4 understanding by week 2 (data advantage over human), match session 6-8 by month 2 (continuous observation advantage)

### Endowed progress effect magnitude
- **34% vs 19% completion rate** when artificial advancement is provided (Nunes & Dreze, 2006)
- **Application:** Pre-filling 4-5 cognitive model dimensions from hour-1 data creates the endowed progress that bridges the executive across the 2-4 week personalisation gap

---

## ANTI-PATTERNS

### Generic advice that triggers "this is just AI"
- Never deliver an insight that could apply to anyone without their data. "You should batch your email" without citing their specific response time distribution = death
- Every insight must reference a specific number from their data. "Your median email response time is 8 minutes — research shows this reactive pattern costs 23 minutes of attention residue per switch" survives. "Consider batching your email" does not
- The generic-to-specific ratio in any morning session must be 0:N. Zero generic insights, ever

### Self-report instruments with known inaccuracy
- **MBTI:** Do not use. No predictive validity for executive behaviour. Test-retest reliability is poor. Executives who identify as MBTI types will resist contradictory behavioural data
- **Self-reported reactivity/productivity style:** Do not ask. Vazire SOKA model confirms people are systematically inaccurate about their own externalised behaviours. Infer from data instead
- **Self-reported "how do you spend your time":** CEOs are off by 20-30% on time allocation estimates vs tracked data (Porter & Nohria). Never trust self-report for time use — use calendar data

### Quantifying learning progress
- **"I'm 15% through learning your patterns"** — actively harmful. Creates a metric the executive will judge against and find wanting
- **Percentages, progress bars, "learning scores"** — all harmful. They invite comparison to a completion state and make the current state feel inadequate
- **Correct approach:** Qualitative calibration. "I can now distinguish your strategic contacts from your operational contacts but I don't yet have enough data to comment on how your communication style shifts under board-level pressure." This communicates progress without quantifying it

### Over-promising early capabilities
- Never claim the system "understands" the executive in week 1. Use: "I can see your calendar structure and email patterns. Understanding how you think requires more observation"
- Never predict behaviour before week 4. Premature prediction that turns out wrong destroys credibility permanently
- Frame limitations as evidence of rigour: "I'm not yet commenting on your decision-making style because that requires 3-4 weeks of observation to characterise reliably. Here's what I can comment on with confidence today..."
- The Pygmalion effect works for future promises ("this will become dramatically more intelligent") but backfires for current overclaims ("I already understand your patterns")
