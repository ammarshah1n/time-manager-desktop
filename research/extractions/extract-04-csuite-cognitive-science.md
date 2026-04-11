# Extraction 04 — C-Suite Cognitive Science

Source: `research/perplexity-outputs/v2/v2-04-csuite-cognitive-science.md`
193 references. Covers bias taxonomy, expert decision models, decision fatigue, executive time allocation, decision failure modes, and intervention design.

---

## DECISIONS

### Biases to detect first (ranked by detectability from digital signals x impact)

1. **Sunk cost escalation** — HIGH detectability, HIGH impact. Observable from calendar patterns (recurring meetings on failing initiatives that grow rather than shrink), email thread length on stalled projects, and document engagement spikes around commitment reviews. Meta-analysis (Sleesman, Conlon & McNamara 2012) confirms robust effect in executive populations.
2. **Overconfidence in forecasting/M&A** — MEDIUM-HIGH detectability, HIGHEST impact. Observable from compressed deliberation windows (time between first mention and commitment), shrinking information-seeking radius (fewer people consulted over time), declining response latency on high-stakes decisions. Malmendier & Tate (2008): overconfident CEOs 65% more likely to make acquisitions; Liu et al. (2018): measurable M&A performance degradation.
3. **Confirmation bias in strategy validation** — MEDIUM detectability, HIGH impact. Observable from email communication patterns — narrowing recipient set, repeated engagement with same sources, declining engagement with dissenting voices. Requires baseline communication graph to detect drift.
4. **Planning fallacy / optimism bias** — MEDIUM detectability, HIGH impact. Observable from systematic comparison of stated timelines (calendar blocks, meeting schedules for project milestones) vs actual completion patterns. Timed can track this longitudinally as a personal calibration score.
5. **Anchoring in financial decisions** — LOW-MEDIUM detectability. Requires visibility into what numbers appeared first in email threads before decisions. Harder to detect from metadata alone — needs email content analysis to identify first-mentioned figures.
6. **Availability bias** — LOW-MEDIUM detectability. Detectable when decision patterns correlate temporally with recent dramatic events (post-incident meetings spike, then fade). Calendar proximity analysis.
7. **Status quo bias** — LOW detectability. Manifests as absence of action — detectable only through persistent deferral patterns on flagged strategic decisions.
8. **Groupthink** — MEDIUM detectability from meeting structure. Signals: decreasing meeting participant diversity, shorter meeting durations for major decisions, compressed deliberation. Observable from calendar participant lists and meeting duration trends.

### System 1 vs System 2 distinction

Kahneman & Klein's 2009 convergence paper ("Conditions for Intuitive Expertise") is the implementation anchor:

- **System 1 (RPD) indicators**: Response latency <30 min on strategic emails, short email bodies, delegation without information requests, calendar slots <30 min for significant decisions, no document engagement before reply
- **System 2 (deliberative) indicators**: Response latency >2 hours on same email types, information-seeking behaviour (email queries to multiple people), document engagement spikes, longer calendar blocks, meeting requests with pre-reads
- **When System 1 is appropriate**: High-validity environments where the executive has genuine domain expertise and feedback loops. Klein's RPD model — experts with 10+ years in stable domains develop reliable intuition
- **When System 1 is dangerous**: Low-validity environments (M&A, new markets, novel strategy). No reliable cue-outcome mapping exists, so pattern-matching fires on superficial similarities

### Decision fatigue detection approach

Use a **composite digital signal model**, not any single marker:
- Response latency drift within the day (track baseline morning vs actual current)
- Email/message brevity increase (word count drops as day progresses)
- Decision deferral rate (messages marked for follow-up / snoozed / forwarded to delegate increase)
- Calendar: decisions scheduled after 4+ hours of continuous meetings are flagged as fatigue-risk
- Status quo defaulting: increasing "approve as-is" or "let's keep current plan" signals in late-day communications

Do NOT use ego depletion as the theoretical frame (replication issues — see ANTI-PATTERNS). Use **resource depletion with glucose/rest moderation** as the working model, supported by the Danziger et al. (2011) finding that favourable decisions dropped from 65% to near 0% within sessions, resetting after breaks.

### Intervention design principles

1. **Frame as pattern, not accusation** — "Your deliberation time on deals >$10M has compressed 40% this quarter vs last" not "You're being overconfident"
2. **Use comparison to self, not norms** — Executives dismiss population baselines but attend to their own longitudinal drift. Always anchor to personal baseline.
3. **Pre-decision timing only** — Interventions after commitment trigger defensive rationalisation. The window is during information-gathering, before the executive signals commitment.
4. **AI source advantage** — Research shows AI-delivered threatening information produces LESS reactance than the same information from human sources (the executive doesn't perceive status threat). Timed should lean into this.
5. **Question framing > statement framing** — "Have you consulted anyone who would argue against this?" outperforms "You may be exhibiting confirmation bias."
6. **Probabilistic language** — "Decisions made in conditions similar to your current pattern have a 70% reversal rate" not "This decision will fail."
7. **Metacognitive prompt** — Surface what cognitive mode the executive is likely in, not what bias they have. "You're operating in fast-decision mode on a decision type where your historical accuracy is 40%" is actionable. "You have overconfidence bias" is dismissable.
8. **Batch low-stakes, protect high-stakes** — Don't alert on every detected pattern. Reserve intervention capital for decisions where the stakes x confidence-in-detection product is highest.

---

## DATA STRUCTURES

### Bias Taxonomy Table

| Bias | Prevalence (Executive Pop.) | Impact | Observable Signal (Digital) | Detection Feasibility | Intervention Design |
|------|----------------------------|--------|----------------------------|----------------------|-------------------|
| **Overconfidence** | ~68% of CEOs score above mean on overconfidence scales (Malmendier & Tate 2005) | 65% more likely to make acquisitions; M&A destroys value in 70-75% of cases | Compressed deliberation windows, shrinking consultation radius, declining response latency on high-stakes items | MEDIUM-HIGH — requires baseline calibration period | Show personal prediction accuracy score; compare stated vs actual timelines |
| **Sunk Cost Escalation** | Universal but intensity varies; meta-analysis confirms robust executive-level effect (Sleesman et al. 2012) | Project escalation consumes 20-40% more resources before abandonment | Growing meeting cadence on stalled initiatives, increasing email thread length on flagged projects, resource allocation patterns | HIGH — calendar + email metadata sufficient | Surface cumulative investment trajectory; pre-mortem prompt ("If this fails, what preceded it?") |
| **Confirmation Bias** | Pervasive; amplified by CEO power dynamics (fewer contradictors) | Strategy validation on incomplete evidence; missed market signals | Narrowing email recipient diversity, declining engagement with historically dissenting contacts, information source homogeneity | MEDIUM — requires communication graph baseline | "Your information sources on [decision X] are 30% less diverse than your baseline" |
| **Anchoring** | Universal in financial decisions; amplified under time pressure | Valuation errors, negotiation outcomes biased toward first numbers | Correlation between first-mentioned figures in email threads and final decision values | LOW-MEDIUM — needs email content, not just metadata | Surface the anchor explicitly: "The first number you encountered was X — your final number is within 15% of it" |
| **Availability Bias** | Spikes post-crisis; executive populations highly susceptible due to information filtering | Risk assessment distortion, over-investment in recent-event categories | Temporal correlation between dramatic events and meeting/email spikes on related topics, then decay | MEDIUM — calendar + email time-series analysis | "Your attention to [risk category] spiked 400% after [event] — your pre-event assessment was [X]" |
| **Status Quo Bias** | Strongest in transformation decisions; correlates with tenure length | Delayed strategic pivots, missed market transitions | Decision deferral patterns, "approve as-is" rates, absence of change-related calendar activity on flagged items | LOW — manifests as absence, hard to distinguish from intentional patience | Surface industry peer movement; "3 of 5 comparable companies have initiated [category] changes in past 6 months" |
| **Planning Fallacy** | Near-universal; studies show executives 25-40% optimistic on timelines (Buehler et al. 1994, 2002) | Resource misallocation, cascading deadline failures | Systematic gap between stated milestone dates and actual completion; calendar block durations vs actual task completion times | HIGH — longitudinal tracking makes this trivially detectable | Personal calibration score: "Your projects complete in 1.4x your estimated time on average" |
| **Groupthink** | Increases with team tenure and leader dominance; Janis (1972, 1982) | Bay of Pigs-class strategic failures; suppression of dissent | Decreasing participant diversity in decision meetings, shorter meeting durations for major decisions, absence of devil's advocate patterns | MEDIUM — calendar participant analysis + meeting duration trends | "Decision meetings for [initiative] have 60% participant overlap — your highest-quality decisions historically had >40% unique participants" |
| **Optimism Bias** | Overlaps with overconfidence; stronger in founder-CEOs | Timeline and resource underestimation | Same signals as planning fallacy + linguistic optimism markers in email if content is analysed | MEDIUM — needs longitudinal data | Show outcome distribution of past similar-scope decisions |

### Decision Failure Mode Map

| Failure Category | Preceding Observable Conditions | Detection Window | Reversal Rate |
|-----------------|-------------------------------|-----------------|--------------|
| **M&A value destruction** | Compressed due diligence (shorter calendar blocks), shrinking advisory circle, CEO personal involvement intensity spike, overriding dissent signals | 2-6 weeks before commitment | 70-75% of 40,000 deals studied fail to create value (Fortune/analysis 2024) |
| **Strategic initiative abandonment** | Escalating meeting frequency followed by sudden silence, resource reallocation signals, executive disengagement (declining attendance) | 4-12 weeks before abandonment | — |
| **Executive hiring failures** | Speed-biased process (compressed interview calendars), insufficient reference-checking signals, small candidate pool indicators | 1-4 weeks during search | 40-60% of executive hires fail within 18 months (various studies) |
| **Capital misallocation** | Anchoring on historical allocation patterns, absence of zero-base review meetings, status quo in budget cycle calendars | Annual cycle — detectable from budget season calendar patterns | — |
| **Timing failures** | Either premature action (compressed deliberation) or excessive delay (decision deferral patterns), misread of external cycle signals | Ongoing — requires market context overlay | — |

### Cognitive Mode Detection Framework

| Observable State | Timed Signals | Cognitive Mode | Risk Profile |
|-----------------|--------------|---------------|-------------|
| Fast response, short messages, no information-seeking, immediate delegation | Response latency <30 min, email word count below personal mean, no outgoing queries, calendar shows back-to-back | **RPD / System 1** | Low risk in high-validity domains (operations, known markets). HIGH risk in novel/strategic decisions |
| Slow response, multiple queries, document engagement, extended calendar blocks | Response latency >2h, multiple outgoing queries, document open/read signals, dedicated calendar blocks | **Deliberate / System 2** | Generally appropriate for strategic decisions. Risk: analysis paralysis if sustained too long |
| Declining response quality late-day, increasing deferral, shortened messages, status quo defaults | Response latency drift >1.5x morning baseline, word count declining, "approve" / "fine" / deferral language increasing | **Fatigue-Degraded System 2** | HIGH risk — executive believes they're deliberating but quality is impaired. Most dangerous for decisions requiring nuance |
| Rapid group consensus, short decision meetings, no dissent signals, uniform participant sets | Meeting durations shorter than decision complexity warrants, no post-meeting individual follow-ups, participant homogeneity | **Groupthink-Susceptible** | HIGH risk for strategic/novel decisions. Decisions feel good but lack stress-testing |
| Context switching >8x/hour, fragmented calendar, email response time variance high, incomplete threads | Calendar fragmentation score high, email thread abandonment rate elevated, response times erratic | **High Cognitive Load** | MEDIUM-HIGH — executive is spread thin. Decisions made in this state have higher reversal rates |

---

## ALGORITHMS

### Decision Fatigue Estimation

```
Input: executive's digital signal stream for current day
Output: fatigue_score (0.0 - 1.0), confidence (0.0 - 1.0)

1. Establish personal baselines (rolling 30-day):
   - morning_response_latency (first 2 hours of work)
   - morning_email_length (word count)
   - morning_deferral_rate
   - morning_delegation_rate

2. Compute current-window signals (rolling 90-min window):
   - current_response_latency
   - current_email_length
   - current_deferral_rate
   - current_delegation_rate
   - hours_since_last_break (>15 min gap in activity)
   - continuous_meeting_hours (back-to-back calendar blocks)
   - decision_count_today (emails/messages requiring decision, classified by Haiku)

3. Compute drift ratios:
   - latency_drift = current_response_latency / morning_response_latency
   - brevity_drift = morning_email_length / current_email_length
   - deferral_drift = current_deferral_rate / max(morning_deferral_rate, 0.01)

4. Fatigue score = weighted_sum(
     latency_drift × 0.25,
     brevity_drift × 0.20,
     deferral_drift × 0.25,
     hours_since_last_break × 0.15 (normalised to 0-1 over 4h range),
     continuous_meeting_hours × 0.15 (normalised to 0-1 over 6h range)
   )

5. Confidence = f(days_of_baseline_data, signal_completeness)
   - <7 days baseline: confidence cap 0.3
   - 7-30 days: confidence cap 0.6
   - >30 days: confidence cap 0.9
   - Multiply by signal_completeness (fraction of signals available)

6. Alert threshold: fatigue_score > 0.7 AND confidence > 0.5
   AND executive has upcoming decision-requiring event in next 2 hours
```

### Cognitive Mode Inference

```
Input: recent behavioural signals (last 60 min)
Output: inferred_mode (RPD | deliberative | degraded | groupthink_risk | overloaded)

Signal vector per decision-event:
  - response_latency (minutes)
  - information_seeking (count of outgoing queries in window)
  - email_word_count (relative to personal mean)
  - consultation_breadth (unique recipients in window)
  - calendar_block_type (back-to-back vs dedicated block)

Classification rules (threshold-based, refine with executive-specific data):

IF response_latency < personal_p25 AND information_seeking == 0 AND email_word_count < personal_mean * 0.6:
  → RPD / System 1
  → Flag if decision_complexity (classified by Haiku) > "operational"

IF response_latency > personal_p75 AND information_seeking >= 2 AND consultation_breadth > 3:
  → Deliberative / System 2
  → Flag if sustained >48h on single decision (analysis paralysis risk)

IF fatigue_score > 0.6 AND response_latency increasing AND email_word_count decreasing:
  → Fatigue-Degraded System 2
  → ALWAYS flag — this is the most dangerous state

IF meeting_participant_diversity < 0.4 (Jaccard vs typical) AND meeting_duration < expected_for_complexity:
  → Groupthink-Susceptible
  → Flag if decision is strategic/irreversible

IF context_switch_rate > 8/hour AND calendar_fragmentation > personal_p90:
  → High Cognitive Load / Overloaded
  → Flag for any non-trivial decision in this window
```

### Bias Detection Heuristics

**Sunk cost detection:**
```
FOR each tracked initiative:
  IF meeting_frequency is increasing
  AND project_health_signals are declining (budget overrun, timeline slip — from email classification)
  AND executive engagement is NOT decreasing:
    → sunk_cost_risk = HIGH
    → Intervention: surface cumulative investment + pre-mortem prompt
```

**Overconfidence detection:**
```
Maintain personal_calibration_score:
  FOR each forecasted outcome (timeline, budget, deal close):
    actual_outcome = observed completion
    calibration_error = |predicted - actual| / predicted
    rolling_calibration = EMA(calibration_error, alpha=0.1)

IF rolling_calibration > 0.3 AND executive is entering new forecast/commitment:
  → overconfidence_risk = HIGH
  → Intervention: "Your last 10 estimates averaged 1.4x actuals"
```

**Confirmation bias detection:**
```
Maintain communication_diversity_graph:
  FOR each decision domain:
    track unique_contacts_consulted, source_diversity, dissent_ratio

IF unique_contacts is trending down for a decision in active deliberation
AND the contacts being consulted have historically agreed with executive:
  → confirmation_bias_risk = MEDIUM-HIGH
  → Intervention: "Your consultation set for [decision] is 40% less diverse than your typical strategic decision"
```

---

## APIS & FRAMEWORKS

### Research-to-Implementation Mapping

| Research | Implementation Approach |
|----------|----------------------|
| Klein's RPD model (1985, 1999) | Classify decisions as RPD-appropriate vs not based on domain validity. Use Kahneman & Klein 2009 criteria: high-validity environment + adequate learning opportunity = trust intuition. Low validity = flag fast decisions. |
| Kahneman's System 1/2 (2011) | Don't try to change the mode. Detect which mode is active, assess appropriateness for decision type, surface mismatch. |
| Tetlock's Superforecasting (2015) | Personal calibration scoring. Track executive's prediction accuracy over time. Superforecasters update incrementally — track whether executive updates or anchors. |
| Kahneman & Klein "Conditions for Intuitive Expertise" (2009) | Core framework for when to trust vs flag RPD decisions. Two conditions: (1) environment has valid cues, (2) executive has had opportunity to learn the cues. Both must be true. |
| Danziger, Levav & Avnaim-Pesso (2011) | Decision fatigue is real but mechanism is breaks/glucose, not pure ego depletion. Track break patterns. |
| Baumeister ego depletion (2010) + Carter et al. replication failure (2015) + Vohs et al. (2021) | Use ego depletion as directional heuristic only, not causal mechanism. Weight: 0.6 (some effect exists but smaller than originally claimed). |
| Porter & Nohria (2018) — Harvard CEO Time Study | Baseline time allocation metrics. 60,000 hours tracked across 27 CEOs. Key ratios to track against. |
| Bandiera, Prat, Hansen & Sadun (2020, JPE) | "Leader" vs "manager" CEO typology from 1,114 CEOs. Leader-type (more external, more one-on-ones, more strategic) correlates with 3-year superior performance. 17% of CEOs mismatched to firm needs. |
| McKinsey executive time survey (1,500 executives) | Only 9% of executives satisfied with time allocation. 52% report misalignment between where time goes and where it should go. |
| Janis (1972, 1982) — Groupthink | 8 symptoms. Detectable subset from digital signals: illusion of unanimity (no dissent in communication), self-censorship (declining email participation from team members), mindguards (gatekeeper patterns in email forwarding). |

### Debiasing Intervention Frameworks

| Framework | Application in Timed |
|-----------|---------------------|
| **Pre-mortem** (Klein 2007) | Prompt before major commitments: "Imagine this failed — what preceded it?" Veinott et al. (2010): pre-mortems increase identification of potential problems by 30%. |
| **Consider the opposite** (Lord, Lepper & Preston 1984) | When confirmation bias detected, surface counter-evidence or prompt: "What would change your mind on this?" |
| **Reference class forecasting** (Kahneman & Tversky 1979) | For planning fallacy — show base rates from executive's own historical similar decisions, not population norms. |
| **Nudge architecture** (Thaler & Sunstein 2008) | Applied to information presentation order, default options in morning briefing, salience of critical items. Caution: nudges designed for general populations may backfire on sophisticated decision-makers. |
| **Metacognitive prompting** | Surface the cognitive mode, not the bias. "You're in fast-decision mode on a slow-decision problem" is more actionable than naming the bias. |

---

## NUMBERS

### Executive Time Allocation Baselines (Porter & Nohria, Harvard 2018)

- **Total study**: 60,000 hours tracked across 27 CEOs over 13 weeks each
- Face-to-face meetings: 61% of work time
- Working alone: 25% of work time
- Phone/video: 15% of work time
- Meetings with direct reports: 46% of meeting time
- Internal vs external: 70% internal, 30% external
- Planned vs reactive: 75% planned, 25% reactive
- Average workweek: 62.5 hours

### Bandiera/Prat/Hansen/Sadun (2020 JPE)

- **Scale**: 1,114 CEOs, time-use diaries
- "Leader" CEOs (more planned, more one-on-ones, more external, more multi-function) outperform "manager" CEOs by measurable 3-year performance lag
- **17% mismatch rate** — CEOs operating in wrong mode for their firm's needs
- One standard deviation increase in leader-type behaviour → 1.75% increase in sales growth

### McKinsey Executive Time Survey

- **1,500 executives** surveyed
- Only **9%** satisfied with their time allocation
- **52%** report misalignment between actual and ideal time spend
- **40% of executive time** spent on activities that don't align with stated strategic priorities

### Decision Fatigue Effect Sizes

- **Danziger et al. (2011)**: Favourable parole decisions dropped from 65% at session start to near 0% before break, returning to 65% after break. (N=1,112 decisions over 10 months)
- **Ego depletion meta-analysis** (Carter et al. 2015): Original effect size d=0.62 (Hagger et al. 2010) reduced to d=0.20 or non-significant after correcting for publication bias. Vohs et al. (2021) multi-lab replication: small but detectable effect (d=0.28), confirming something exists but much smaller than claimed.
- **Time-of-day effects**: Multiple studies confirm decision quality degrades 10-40% from morning to late afternoon, moderated by breaks and glucose.

### Bias Prevalence in Executive Populations

- **Overconfidence**: ~68% of acquiring CEOs classified as overconfident by revealed-preference measures (Malmendier & Tate 2005, 2008)
- **Planning fallacy**: Executives underestimate project duration by 25-40% on average (Buehler, Griffin & Ross 1994, 2002)
- **M&A failure rate**: 70-75% fail to create value (analysis of 40,000 deals over 40 years, Fortune 2024)
- **Executive hiring failure**: 40-60% of executive hires fail within 18 months (multiple sources)
- **Sunk cost escalation**: Meta-analytic confirmation of robust effect; executives show similar or greater escalation compared to general population when ego-involvement is high (Sleesman et al. 2012)

### Executive Coaching Effectiveness (Intervention Benchmark)

- Executive coaching produces ROI of 500-700% (Manchester Inc. / MetrixGlobal studies, various)
- Behaviour change sustained at 6-month follow-up in 70% of coached executives
- Timed's benchmark: match or exceed coaching-level behaviour change rates at scale

---

## ANTI-PATTERNS

### Interventions that trigger reactance/dismissal

- **Naming the bias directly** — "You're exhibiting overconfidence bias" triggers identity threat and defensive rationalisation. Executives interpret this as questioning their competence. Frame as pattern observation instead.
- **Using population norms** — "Most executives make this mistake" is dismissed as "I'm not most executives." Always use personal historical data.
- **Post-commitment intervention** — Once the executive has publicly committed (email sent, meeting called, announcement made), any contrary insight triggers cognitive dissonance resolution via rationalisation, not updating. The intervention window is pre-commitment only.
- **Excessive frequency** — Alert fatigue is real. More than 2-3 cognitive insights per day will cause the entire system to be ignored. Reserve for high-stakes decisions only.
- **Unsolicited advice framing** — Discovery.ucl.ac.uk research shows unsolicited advice produces negative emotional reactions even when correct. Frame as data presentation ("here's what I'm seeing in your patterns") not advice ("you should...").
- **Certainty language** — "You will regret this decision" triggers reactance. "Decisions made under similar conditions in your history have been reversed 60% of the time" is the same information with less reactance.

### Biases that CANNOT be detected from digital behaviour alone

- **Anchoring** — Requires knowing what number the executive saw first. Metadata doesn't reveal this without email content analysis. Even with content, inferring what "anchored" someone is speculative.
- **Availability bias** — Can detect attention spikes post-event but cannot confirm the executive is weighting recent events disproportionately vs legitimately updating. The spike itself is not the bias — the failure to revert is.
- **Representativeness heuristic** — No reliable digital signal. Requires understanding the executive's mental model of similarity, which is not observable.
- **Framing effects** — How a decision was framed to the executive (gain vs loss frame) is often in verbal conversation, not digital signals.
- **Hindsight bias** — Post-hoc, no real-time detection possible.
- **Dunning-Kruger** — Requires domain-specific competence assessment that passive observation cannot provide.

### The ego depletion replication debate — current state

- **Original claim** (Baumeister et al. 1998, 2010): Self-control depletes a limited resource, degrading subsequent decisions. Large effect size (d=0.62, Hagger et al. 2010 meta-analysis).
- **Replication failure** (Carter et al. 2015): After correcting for publication bias, effect size drops to d=0.20 or non-significant. Registered Replication Report (Hagger et al. 2016): 23 labs, no significant effect.
- **Partial rehabilitation** (Vohs et al. 2021): Multi-lab replication finds small but detectable effect (d=0.28). Something exists, but it's ~40% the size originally claimed.
- **Implementation guidance**: Do NOT build fatigue detection on ego depletion theory. Instead, use empirically robust markers: time-since-break (Danziger), time-of-day effects (replicated across multiple domains), decision count (cognitive load theory, which has never had replication problems), and continuous meeting hours. The theoretical mechanism doesn't matter for engineering — the behavioural markers of degraded decision quality are robust even if the causal story is contested.

### Oversimplified bias detection (correlation ≠ causation)

- **Fast response ≠ bias**: An executive responding quickly may be exercising legitimate expertise (RPD). Speed is only a risk signal when combined with low-validity environment + high stakes + deviation from personal deliberation norms for that decision type.
- **Narrow consultation ≠ confirmation bias**: The executive may have already gathered diverse input offline/verbally. Digital signals only capture digital communication. Always mark confidence accordingly and never present inferences as certainties.
- **Meeting brevity ≠ groupthink**: Some teams are genuinely aligned. Short meetings are only a groupthink signal when combined with participant homogeneity + absence of dissent + decision complexity that warrants longer deliberation.
- **Decision deferral ≠ fatigue**: Could be strategic patience, waiting for information, or legitimate delegation. Only flag when deferral rate deviates from personal baseline AND other fatigue signals co-occur.
- **General rule**: Never infer a cognitive state from a single signal. Require 2+ co-occurring signals from different categories (timing + content + social) before inferring any bias or mode. Present all inferences with explicit confidence levels and evidence counts.
