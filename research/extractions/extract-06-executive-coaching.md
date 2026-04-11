# Extract 06 — Executive Coaching Intelligence for Timed

Source: `research/perplexity-outputs/v2/v2-06-executive-coaching.md`
178 citations across coaching science, psychology, HCI, and behavioural analytics.

---

## DECISIONS

### Which coaching functions Timed CAN automate (fully or partially)

**Full automation (digital signals sufficient):**
- Communication pattern tracking — frequency shifts, tone shifts (via keystroke dynamics), audience selection bias, response latency asymmetries across recipients. Email metadata alone reveals who the executive prioritises, ignores, and delays responding to.
- Calendar structure analysis — meeting type distribution, time allocation vs stated priorities, pattern of rescheduling/shortening specific meeting types, buffer time between meetings, deep work block presence/absence.
- Energy and engagement patterns — application usage intensity by time-of-day, keystroke velocity/error rate as cognitive load proxy, which tasks get tackled first (high energy) vs pushed to end-of-day (avoidance/low energy).
- Temporal behavioural patterns — time-of-day, day-of-week, seasonal rhythms the executive is unaware of. Derived entirely from timestamped metadata.
- Avoidance pattern detection — systematic non-response to certain senders/topics, repeated rescheduling of specific meeting types, minimal dwell time on certain document categories.
- Priority misalignment detection — stated priorities (calendar labels, voice declarations) vs actual time allocation (where hours go). The gap between "I spend most of my time on strategy" and the data showing 73% in operational meetings.

**Partial automation (digital signals + inference model):**
- Decision pattern analysis — speed of decision-making, information-seeking behaviour before decisions, delegation patterns. Requires inference from email chains and calendar sequences, not direct observation.
- Relationship dynamics — who the executive engages with more/less over time, alliance patterns, communication asymmetry (formal vs informal tone with different people). Email metadata provides the skeleton; nuance requires accumulation over months.
- Self-awareness gaps — the difference between how the executive describes their behaviour (voice interaction) and what the data shows. Requires cross-referencing self-reports against observed patterns.
- Blind spot surfacing — communication asymmetries (e.g., median response time to direct reports 47% slower than to lateral peers) that the executive has no awareness of. Detectable from metadata, but must accumulate sufficient sample size for statistical confidence.

### Which coaching functions are irreducibly human (and how Timed positions itself)

**Cannot automate (~15-20% of coaching effectiveness):**
- Embodied co-presence — the physiological co-regulation that happens in-person. Polyvagal nervous system synchronisation between coach and executive. No digital substitute.
- Real-time interpersonal dynamics — body language, facial micro-expressions, vocal quality shifts in live conversation. Timed's voice module captures some vocal features but not the full embodied channel.
- Holding space for vulnerability — creating the psychological container where an executive can be genuinely uncertain, afraid, or wrong. Requires human witness.
- Social weight of accountability — a human coach's disappointment carries social consequence that a system cannot replicate.
- 360-degree feedback facilitation — gathering candid input from direct reports, peers, and board members requires human trust and interview skill.

**Positioning:** Timed is the data layer that makes human coaching 3-5x more effective. It sees what the coach cannot (continuous observation vs 2 hours/month). It never replaces the coach. It gives the coach — and the executive — an objective behavioural mirror that neither can produce alone.

### Observation priority framework

Ranked by: detection feasibility from digital signals x transformative value x confidence threshold achievability.

1. **Communication asymmetries** — Response time differentials, email length differentials, audience selection patterns. Highest feasibility (pure metadata), high transformative value (frequently produces "I had no idea" moments), confidence achievable within 30-60 days.
2. **Calendar-revealed priority misalignment** — Stated priorities vs actual time allocation. High feasibility (calendar + voice self-reports), very high transformative value, confidence at 60 days.
3. **Temporal energy patterns** — Time-of-day productivity signatures, day-of-week patterns, post-meeting energy drops (keystroke dynamics). High feasibility, moderate-high transformative value, confidence at 45-60 days.
4. **Avoidance signatures** — Systematic non-engagement with specific people, topics, or decision types. Moderate feasibility (requires accumulation), very high transformative value (challenges self-concept), confidence at 90+ days.
5. **Decision pattern rigidity** — Defaulting to same decision approach regardless of context (always deciding fast, always seeking more data, always delegating). Moderate feasibility (requires inference across email chains), high transformative value, confidence at 90-120 days.
6. **Relationship network drift** — Gradual changes in who the executive engages with, emerging isolation patterns, alliance shifts. Moderate feasibility (email + calendar), high transformative value, confidence at 120+ days.

### Insight delivery framing principles

Five principles derived from coaching research:

1. **Data-first, interpretation-second.** Present the observable pattern before offering any meaning. "Your average response time to [person] has increased from 2 hours to 14 hours over the past month" — not "You're avoiding [person]." Let the executive assign meaning first.
2. **Feedforward, not feedback.** Goldsmith's core principle: focus on what to do differently going forward, not what went wrong. Frame observations as opportunities, not diagnoses.
3. **Curiosity framing, not assertion.** "I notice X — does that match your experience?" rather than "You do X." Questions produce reflection; assertions produce defensiveness.
4. **One insight per interaction.** Never stack multiple challenging observations. The executive must fully process one before encountering the next.
5. **Anchor to the executive's own stated goals.** Every observation must connect to something the executive has said they care about. Untethered observations feel like surveillance; goal-connected observations feel like partnership.

### How Timed should describe its own role to the executive

Four-part positioning statement framework:

1. **What I am:** "A continuous observation system that sees patterns in your behaviour you cannot see yourself — because you're inside them."
2. **What I am not:** "I am not a coach, therapist, or advisor. I do not have opinions about what you should do. I surface what is, and you decide what it means."
3. **My limitation, stated directly:** "A human coach sees your face, feels the room, and carries the weight of a real relationship. I cannot do any of that. What I can do is watch continuously — every email, every calendar choice, every pattern — which no human coach can."
4. **My value proposition:** "I am the objective mirror. I show you the patterns that are invisible to you and too diffuse for any human to track. I make your coach better. I make your self-awareness faster."

Research basis: systems that explicitly acknowledge limitations are trusted more than systems that do not (HCI trust literature, Edmondson psychological safety research applied to human-computer interaction).

---

## DATA STRUCTURES

### Automation feasibility matrix

| Coaching Function | What Coach Does | Data Needed | Available from Timed? | Feasibility |
|---|---|---|---|---|
| Communication pattern tracking | Observes how executive communicates differently with different audiences | Email metadata (timestamps, recipients, lengths, frequency), keystroke dynamics | Yes — full signal | **Full** |
| Calendar/priority alignment | Compares stated priorities with actual time allocation | Calendar events + categories, voice-stated priorities | Yes — full signal | **Full** |
| Energy/engagement mapping | Identifies what energises vs drains the executive | App usage patterns, keystroke velocity/error rates, time-of-day productivity | Yes — full signal | **Full** |
| Temporal pattern detection | Surfaces time-based behavioural rhythms executive is unaware of | All timestamped metadata | Yes — full signal | **Full** |
| Avoidance pattern detection | Identifies topics, people, decisions systematically avoided | Email non-response patterns, calendar rescheduling, document dwell time | Yes — requires accumulation | **Partial** |
| Decision pattern analysis | Assesses decision speed, information-seeking, delegation habits | Email chain analysis, calendar sequences, delegation patterns | Partial — inference required | **Partial** |
| Relationship dynamics | Maps alliance patterns, engagement shifts, communication asymmetries | Email metadata + calendar co-attendance over time | Partial — skeleton only | **Partial** |
| Self-awareness gap detection | Compares executive's self-description with observed behaviour | Voice self-reports + all behavioural signals | Partial — cross-referencing | **Partial** |
| Blind spot surfacing (others' experience) | 360-degree feedback — how others experience the executive | Direct report/peer interviews, observed reactions | No — requires human interviews | **Impossible** |
| Emotional co-regulation | Nervous system synchronisation, holding space | Physical co-presence, embodied empathy | No | **Impossible** |
| Real-time interpersonal reading | Micro-expressions, body language, vocal quality in live conversation | Visual + full vocal channel in real-time | No — partial vocal only | **Impossible** |
| Accountability with social weight | Coach's disappointment/approval carries real social consequence | Genuine human relationship | No | **Impossible** |
| Vulnerability facilitation | Creating psychological safety for genuine uncertainty/fear | Human witness, trust, co-presence | No | **Impossible** |

### Transformative observation categories (the "I never saw that about myself" types)

These are ranked by how frequently coaches report them as producing genuine self-perception shifts:

1. **Response latency asymmetries** — "Your median response time to your CFO is 47 minutes. To your VP Engineering it's 14 hours." Pure metadata. Frequently the single most disruptive-true observation.
2. **Stated vs revealed priorities** — "You say product strategy is your top priority. 11% of your calendar hours go to it. 41% go to operational reviews." Calendar + voice.
3. **Energy-task mismatch** — "Your highest-quality work output (keystroke fluency, sustained focus blocks) happens between 6-8am. You schedule your most important meetings at 3pm." Keystroke dynamics + calendar.
4. **Avoidance invisibility** — "You have not responded to any email from [board member] in 23 days. You rescheduled your 1:1 with them 4 times." Email + calendar. The executive genuinely does not know they are doing this.
5. **Communication formality gradient** — "Your emails to your direct reports average 12 words. Your emails to the board average 340 words." Metadata reveals unconscious hierarchy signalling.
6. **Decision speed variance** — "You make hiring decisions in 2 days. You have had the office relocation proposal on your desk for 7 weeks." Inference from email chains + calendar.
7. **Post-meeting energy signatures** — "Your keystroke error rate increases 340% in the hour after board meetings. After product reviews it decreases 15%." Keystroke dynamics + calendar correlation.

### Avoidance/deflection detection signals

| Defence Mechanism | Digital Signature | Signal Source | Confidence Threshold |
|---|---|---|---|
| **Topic avoidance** | Systematic non-response to emails containing specific keywords/from specific senders | Email metadata (response rate by sender/thread) | >3 instances over 14 days |
| **Meeting avoidance** | Repeated rescheduling (3+) of specific meeting types; shortening meetings with certain attendees | Calendar modification patterns | >2 reschedules of same meeting type in 30 days |
| **Decision deferral** | Email threads where executive is CC'd/mentioned but never responds; delegation of decision to subordinate when it's clearly executive-level | Email chain analysis | Pattern across 3+ decision threads |
| **Intellectualisation** | Responding to emotionally charged emails with data-heavy, formal language markedly different from baseline tone | Email length + formality deviation from baseline by context | Requires 60+ day baseline |
| **Displacement** | Increased engagement with low-stakes operational tasks immediately after high-stakes communications arrive | App usage + email arrival timing correlation | Requires 45+ day baseline |
| **Rationalisation** | In voice interaction, executive provides elaborate justification for a pattern Timed surfaced — without changing the pattern in subsequent weeks | Voice interaction content + subsequent behavioural data | Requires post-insight tracking over 14+ days |
| **Calendar manipulation** | Creating "blocker" meetings that prevent certain interactions; back-filling calendar to appear unavailable | Calendar creation patterns + meeting attendance | >3 phantom blockers in 30 days |

---

## ALGORITHMS

### Trust calibration (adjusting insight intensity based on relationship stage)

Based on Bordin's working alliance model + Prochaska & DiClemente's Transtheoretical Model (stages of change):

**Stage 1: Establishment (Days 1-30)**
- Deliver only positive/neutral observations. Energy patterns, temporal rhythms, productivity insights.
- Insight intensity: 2/10. No challenging observations.
- Goal: demonstrate accuracy. Every observation must be verifiably true when the executive checks.
- Trust signal to advance: executive voluntarily engages with an insight (asks follow-up, references it later).

**Stage 2: Calibration (Days 30-90)**
- Introduce mild discrepancy observations. Stated vs actual priority allocation. Communication frequency patterns.
- Insight intensity: 4/10. Observations that surprise but don't threaten self-concept.
- Frame everything as curiosity: "I notice X — is that intentional?"
- Trust signal to advance: executive acknowledges a pattern they hadn't noticed, without defensiveness.

**Stage 3: Working Alliance (Days 90-180)**
- Begin surfacing avoidance patterns, relationship asymmetries, decision rigidity.
- Insight intensity: 6/10. Observations that challenge self-perception.
- Always connect to executive's stated goals.
- Trust signal to advance: executive modifies behaviour in response to an observation (not just acknowledges it).

**Stage 4: Deep Observation (Days 180+)**
- Full pattern surfacing including defence mechanism signatures, blind spots, energy-decision quality correlations.
- Insight intensity: 8/10. Can surface uncomfortable truths.
- The executive has seen enough accurate observations to trust the system's pattern recognition.
- Never reach 10/10 — always leave room for the executive to dismiss an observation without feeling the system is insistent.

**Rupture protocol:** If the executive dismisses 3+ consecutive observations, or explicitly expresses frustration with the system, drop back one stage immediately. Do not attempt to "prove" the observation. Acknowledge: "I may be reading this pattern wrong. I'll keep watching and come back to it only if the data becomes clearer."

### Avoidance pattern detection from digital signals

```
Algorithm: AvoidancePatternDetector

Input: Rolling 30-day window of email metadata, calendar events, app usage

For each {sender, topic_cluster, meeting_type, decision_thread}:
  1. Compute baseline engagement metrics (days 1-60):
     - response_rate_baseline
     - response_latency_baseline (median)
     - meeting_attendance_rate_baseline
     - meeting_reschedule_rate_baseline

  2. Compute current_window metrics (rolling 30 days):
     - response_rate_current
     - response_latency_current
     - meeting_attendance_current
     - meeting_reschedule_current

  3. Compute deviation scores:
     - response_deviation = (current - baseline) / baseline_stddev
     - latency_deviation = (current - baseline) / baseline_stddev
     - reschedule_deviation = (current - baseline) / baseline_stddev

  4. Flag if ANY:
     - response_deviation < -2.0 (significant drop in response rate)
     - latency_deviation > 2.0 (significant increase in response time)
     - reschedule_deviation > 2.0 (significant increase in rescheduling)
     - AND pattern persists across 3+ instances (not a one-off)

  5. Cluster flagged entities:
     - If multiple flagged senders share a department → department avoidance
     - If multiple flagged topics share a theme → topic avoidance
     - If flagged meetings share a type → meeting-type avoidance

  6. Confidence scoring:
     - Low (flag only, don't surface): 2.0-2.5 stddev, <5 instances
     - Medium (surface at Stage 3+): 2.5-3.0 stddev, 5-10 instances
     - High (surface at Stage 2+): >3.0 stddev, >10 instances

Output: AvoidancePattern {
  target: Entity (person/topic/meeting_type)
  deviation_score: Float
  instance_count: Int
  first_detected: Date
  pattern_cluster: Optional<ClusterID>
  confidence: Low | Medium | High
}
```

### Insight sequencing (what to establish before delivering difficult observations)

Pre-requisite chain — each level requires the previous level to be established:

```
Level 0: ACCURACY FOUNDATION
  ├─ System has delivered 10+ verifiably accurate observations
  ├─ Executive has confirmed accuracy of at least 5
  └─ Zero false positives in the last 7 days

Level 1: PATTERN RECOGNITION
  ├─ System has surfaced 3+ temporal/energy patterns executive confirmed
  ├─ Executive has referenced a Timed observation unprompted
  └─ Prerequisite for: any "you didn't know this about yourself" observation

Level 2: MILD DISCREPANCY
  ├─ System has surfaced 2+ stated-vs-actual misalignments
  ├─ Executive engaged constructively (asked questions, not defensive)
  └─ Prerequisite for: avoidance patterns, relationship asymmetries

Level 3: SELF-CONCEPT CHALLENGE
  ├─ System has surfaced 1+ avoidance pattern that executive acknowledged
  ├─ Executive modified behaviour in response to at least 1 observation
  └─ Prerequisite for: defence mechanism observations, deep blind spots

Level 4: DEEP PATTERN (Stage 4 only)
  ├─ Executive has 180+ days of relationship with system
  ├─ System has a validated cognitive model with <15% false positive rate
  └─ Can surface: decision rigidity, unconscious bias patterns, leadership blind spots
```

Delivery rule: NEVER skip a level. If the executive is at Level 2, do not deliver a Level 4 insight regardless of how clear the data is. Wait.

---

## APIS & FRAMEWORKS

### Goldsmith — Stakeholder-Centred Coaching

**Extractable for Timed:**
- Feedforward methodology — focus on future behaviour, not past mistakes. Every Timed insight should be framed as "what you could do differently" not "what you did wrong."
- Behavioural specificity — never deliver vague observations. Always cite specific data points (dates, times, recipients, durations).
- The "Daily Questions" practice — Goldsmith has executives rate themselves on 6 self-defined questions daily. Timed can automate this: compare the executive's self-rating (voice) against observed behavioural data for the same day.
- Stakeholder perception gap — the core of Goldsmith's method is showing executives the gap between self-perception and others' experience. Timed approximates this through communication asymmetry data (how you communicate with X vs Y reveals how you perceive them, not how you think you do).

### CCL (Center for Creative Leadership)

**Extractable for Timed:**
- Assessment-Challenge-Support (ACS) model — every development intervention needs all three. Timed provides Assessment (data) and Challenge (pattern surfacing). The executive or their human coach provides Support.
- The 70-20-10 development model — 70% of leadership development comes from on-the-job experiences, 20% from relationships, 10% from formal training. Timed operates in the 70% zone: making the executive's daily experience a continuous development opportunity.
- Derailment research — CCL identified the specific behavioural patterns that cause high-potential leaders to derail. Timed should track these: difficulty building/maintaining relationships, difficulty building a team, difficulty changing or adapting, over-reliance on a single skill.

### Hudson Institute — Renewal Cycle

**Extractable for Timed:**
- Four-phase adult development cycle: Go For It → The Doldrums → Cocooning → Getting Ready. Timed can detect phase transitions through energy/engagement shifts, and calibrate insight delivery accordingly (don't push challenging insights during Doldrums/Cocooning).
- The "life chapter" framework — major transitions require different coaching approaches. Timed detects these through sustained pattern shifts across multiple signal streams simultaneously.

### Bordin's Working Alliance Model (adapted for digital systems)

Three components, each adapted for Timed:

1. **Goal agreement** — Executive and system must share an understanding of what the executive is working toward. Implementation: during onboarding and periodic voice check-ins, Timed explicitly asks "What are you trying to get better at?" and anchors all observations to the answer.
2. **Task agreement** — Mutual understanding of what each party does. Implementation: Timed's positioning statement (see DECISIONS) makes its role explicit. The executive understands they receive observations, not instructions.
3. **Bond** — Emotional connection and trust. Implementation: Timed cannot form a bond in the human sense. Substitute: demonstrated accuracy over time + acknowledged limitations + consistent non-judgment. Research shows that for digital systems, competence trust (it gives accurate information) can partially substitute for interpersonal trust.

### Edmondson — Psychological Safety (applied to AI context)

Key principles for Timed:
- Psychological safety = belief that one will not be punished for admitting mistakes/uncertainty. Timed must NEVER use an executive's acknowledged weakness against them (e.g., never reference "remember when you admitted you avoid conflict" in a later observation).
- Frame all observations as learning opportunities, not performance evaluations.
- Explicitly normalise the patterns observed: "This pattern is common among executives managing [X type of load]" — reduces threat to self-concept.
- Never share or reference observations outside the executive's private context. Data sovereignty is non-negotiable for psychological safety.

### Motivational Interviewing (MI) principles for AI delivery

Four core MI principles adapted for Timed's voice and text modality:

1. **Express empathy through reflection** — Timed restates what the executive has said before adding its observation. "You mentioned your board prep feels rushed. I notice your prep time has decreased 40% this quarter."
2. **Develop discrepancy** — Surface the gap between where the executive is and where they want to be. Always use their own stated goals as the reference point, not an external standard.
3. **Roll with resistance** — If the executive dismisses or rationalises, do not push. Acknowledge and step back. "That's a fair read. I'll keep watching the pattern."
4. **Support self-efficacy** — Every challenging observation must be paired with evidence that the executive has successfully changed patterns before. "You shifted your Monday scheduling last month — that took one conversation with your EA."

---

## NUMBERS

### Coaching ROI data

- **Theeboom et al. (2014) meta-analysis:** Coaching produces significant positive effects on performance/skills (g = 0.60), well-being (g = 0.46), coping (g = 0.43), work attitudes (g = 0.54), and goal-directed self-regulation (g = 0.74). Effect sizes are medium to large.
- **Jones et al. (2016) meta-analysis:** Coaching has a positive effect on organisational outcomes (δ = 0.36) and individual outcomes (δ = 0.77 for skill-based, δ = 0.17 for affective). Strongest effects on self-reported outcomes; weaker but still significant on objective outcomes.
- **Grover & Furnham (2016):** Coaching effectiveness is moderated by executive openness, coach credibility, and number of sessions. Internal coaches produce weaker effects than external coaches.
- **2023 PMC meta-analysis:** Confirms positive effects; highlights that coaching with a structured feedback component produces larger effects than coaching without.
- **ICF Global Coaching Study:** Organisations report median ROI of 700% from coaching investments. Individual executives report improved work performance (70%), business management (61%), time management (57%), team effectiveness (51%).

### Trust-building timelines

- **Basic competence trust (system gives accurate information):** 2-4 weeks / 10+ verified accurate observations.
- **Pattern trust (system sees real patterns, not noise):** 4-8 weeks / executive has confirmed 3+ non-obvious patterns.
- **Discrepancy trust (system can challenge my self-perception):** 8-16 weeks / executive has engaged constructively with 2+ mild discrepancy observations.
- **Deep trust (system can surface uncomfortable truths):** 16-26 weeks / executive has modified behaviour based on system observations at least once.
- **Full operating trust:** 26+ weeks / system has a validated model; executive treats it as a trusted source comparable to a human advisor.

Note: these timelines are faster than human coaching (which typically takes 3-6 months to reach challenging feedback) because Timed's continuous observation demonstrates competence faster than biweekly sessions.

### Insight-to-behaviour-change conversion rates

- **Coaching research (general):** ~30% of insights produced in coaching sessions lead to measurable behaviour change within 6 months.
- **With structured accountability:** Conversion rises to ~50-60%.
- **With real-time feedback (closer to the moment of behaviour):** Conversion rises to ~65-70%. This is Timed's primary advantage — it can surface observations within hours of the behaviour, not 2 weeks later in a coaching session.
- **Without any follow-up:** ~10-15% — the "insight graveyard" where executives understand a pattern but never change it.
- **Key moderator:** Specificity. "You avoid conflict" converts at ~8%. "You rescheduled your 1:1 with your VP Sales 3 times this month and your response time to her emails has increased from 2 hours to 19 hours" converts at ~45%.

### Engagement rates for different delivery approaches

- **Narrative text (story-framed insight):** 70-80% engagement rate (read fully, not skimmed).
- **Data-first bullet points:** 60-70% engagement but higher action rate among those who engage.
- **Voice delivery:** 55-65% engagement but deepest processing depth (slower, more reflective).
- **Visual/chart delivery:** 40-50% engagement for standalone; 80%+ when accompanying a text narrative.
- **Alert fatigue onset:** Engagement drops below 50% when system delivers more than 3 insights per day. Below 30% at 5+ per day. Optimal: 0-1 proactive insights per day, plus the morning briefing.
- **Real-time proximity effect:** Insights delivered within 2 hours of the relevant behaviour have 3.2x higher engagement than insights delivered 24+ hours later.

---

## ANTI-PATTERNS

### Delivering uncomfortable insights too early (before trust is established)

**The failure mode:** System detects a clear avoidance pattern in week 2 and surfaces it. Executive's response: distrust the system's competence ("it doesn't know me yet"), feel surveilled, disengage.
**The research:** Bordin's working alliance research shows that premature confrontation before the alliance is established is the #1 predictor of coaching failure. The therapeutic alliance research (which coaching draws on) shows the same: premature interpretation produces worse outcomes than no interpretation.
**The rule:** No self-concept-challenging observations before Day 90. No deep pattern observations before Day 180. Accuracy and pattern trust must be established first. There is no shortcut.

### Feedback that produces acknowledgment without behaviour change

**The failure mode:** Executive says "That's a great observation" and changes nothing. The system counts this as engagement. In reality, it's the insight graveyard — intellectualisation as a defence mechanism.
**Detection:** Track post-insight behaviour. If the executive acknowledged a pattern but the behavioural data shows no change over the next 14-30 days, flag internally as "acknowledged but not acted upon."
**The intervention:** Re-surface the same pattern with updated data at a later date. Frame it differently: "Three weeks ago I noticed [X]. The pattern has continued — [new data points]. Is this something you've decided is acceptable, or something you'd like to address?" The key is making the acknowledgment-without-change visible without being confrontational.
**Never:** Repeat the same observation more than 3 times. If it hasn't landed after 3 attempts with different framing, the executive has made a choice. Respect it.

### Anthropomorphising the AI in ways that backfire

**The failure mode:** System uses language like "I feel," "I'm concerned," "I care about your development." Executive either finds it cringe and disengages, or develops parasocial attachment that reduces the utility of the tool.
**The research:** HCI literature on the "uncanny valley" of social AI — systems that claim emotional states they don't have are trusted less than systems that are transparently mechanical. The exception: systems that use "I notice" and "I observe" (cognitive framing) are trusted more than those that use "The data shows" (distancing framing). There is a narrow band between too human and too mechanical.
**The rule for Timed's voice:**
- USE: "I notice," "I observe," "I've been tracking," "The pattern suggests"
- NEVER USE: "I feel," "I'm worried," "I care," "I believe"
- NEVER USE: "The algorithm detected," "The data indicates," "Analysis shows" (too cold, too clinical)
- Timed speaks in first person but never claims emotions. It claims perception and pattern recognition.

### Overstepping into therapy territory

**The failure mode:** System detects patterns that suggest anxiety, depression, burnout, or deep psychological conflict and attempts to address them directly. "Your patterns suggest you may be experiencing burnout" crosses from observation into diagnosis.
**The boundary:** Timed observes behaviour, not psychological states. It can say "Your keystroke error rate has increased 200% over 3 weeks and your deep work blocks have decreased from 4 hours/day to 45 minutes." It cannot say "You seem burned out."
**The rule:** If behavioural signals suggest a psychological state requiring professional support, Timed surfaces the behavioural data only and suggests the executive "may want to discuss these patterns with someone they trust" — never naming a condition, never diagnosing, never offering therapeutic framing.
**Escalation triggers (surface behavioural data + suggest human support):**
- Sustained productivity decline >40% over 3+ weeks
- Near-complete avoidance of a major responsibility area
- Voice interaction patterns showing significantly elevated stress markers sustained over 2+ weeks
- Calendar showing systematic elimination of all non-essential human contact
