# Second-Order Insight Synthesis Spec

> Timed — Layer 3 Reflection Engine, Stage 3
> Version: 1.0 | 2026-04-02
> Dependency: First-Order Pattern Extraction (Stage 2), Memory Store (Layer 2)
> Runs: Nightly, after first-order extraction completes
> Model: Claude Opus 4.6 at maximum reasoning effort

---

## 1. Purpose

Second-order synthesis is where Timed becomes genuinely intelligent. It takes the raw regularities discovered by first-order extraction and asks: **"What do these patterns mean when considered together?"**

A first-order pattern says: "Board email response time increases on Fridays."
Another says: "Strategic document work drops 60% in the 72h after board meetings."
Another says: "Meeting acceptance rate for optional meetings increases by 40% the day after board meetings."

Second-order synthesis connects these: **"Post-board fatigue reduces strategic output for 72 hours — the executive compensates by filling time with low-stakes meetings and defers difficult communication."**

This is a named insight. It has explanatory power. It predicts future behaviour. It is actionable.

---

## 2. What Second-Order Synthesis Produces

### 2.1 Named Insights

The primary output. A named insight is a cross-pattern finding with a human-readable title, an evidence chain, and a confidence score.

Named insights are the unit of intelligence delivered to the user in the morning session. They are what make the user say: "This system understands me."

### 2.2 Candidate Rules

When a named insight has sufficient confidence and clear actionability, it generates a candidate rule for the Rule Generation stage (Stage 4). Not all insights produce rules — some are purely descriptive ("You process information differently on Mondays vs Fridays"). Only insights with a clear IF-THEN structure become candidate rules.

### 2.3 Semantic Memory Updates

Insights that reveal stable facts about the user update the semantic memory store. Example: if the insight "post-board fatigue" persists for 2+ months, it becomes a permanent semantic memory: "This executive experiences a 72-hour cognitive recovery period after board meetings."

### 2.4 Model Corrections

Occasionally, synthesis reveals that a previously stored semantic memory or procedural rule is wrong. Example: "The system believed Thursday was the executive's best strategic thinking day, but cross-referencing decision quality data shows it's actually Tuesday morning. Thursday's apparent productivity was administrative throughput, not strategic depth." This generates a correction that updates the semantic store.

---

## 3. Cross-Domain Correlation Engine

### 3.1 Correlation Matrix

The synthesis stage systematically looks for correlations across pattern categories. Every first-order pattern is tagged with one or more domains:

| Domain | Signal sources |
|--------|---------------|
| **Calendar** | Meeting density, meeting types, free time, scheduling patterns |
| **Email** | Response times, volume, length, sentiment, recipients |
| **Task** | Completion rates, deferral rates, time-on-task, category distribution |
| **Focus** | Session duration, interruption rate, time-of-day, app context |
| **Voice** | Morning session sentiment, energy markers, topic emphasis |
| **Behaviour** | App switching, document engagement, routine adherence |

The synthesis prompt instructs Opus to specifically look for cross-domain correlations:

```
For each first-order pattern in domain A, examine whether any pattern in domain B, C, D, E, or F
shows temporal co-occurrence (within 24-72h window), directional correlation (both increase/decrease
together), or inverse correlation (one increases as the other decreases).
```

### 3.2 Minimum Cross-Domain Requirement

A valid second-order insight must draw from **at least 2 different first-order patterns** from **at least 2 different domains**. Single-domain combinations remain first-order patterns — they are refinements, not syntheses.

Examples:
- Calendar pattern + Email pattern = valid cross-domain
- Email pattern + Email pattern = NOT valid (same domain — this is a first-order refinement)
- Calendar pattern + Task pattern + Focus pattern = valid (3-domain, stronger)

### 3.3 Temporal Alignment

Correlated patterns must have temporal overlap or a consistent temporal relationship:

- **Co-occurrence**: Patterns manifest in the same time window (same day, same week)
- **Sequential**: Pattern A consistently precedes Pattern B by a fixed lag (e.g., board meeting → 72h fatigue)
- **Inverse cycle**: Pattern A peaks when Pattern B troughs (e.g., email volume up when deep work down)

Temporal alignment is verified by checking the episodic memory timestamps underlying each pattern. If two patterns share no temporal structure, they are not combined regardless of how compelling the narrative might be.

---

## 4. Confidence Gating

### 4.1 Input Pattern Requirements

Only first-order patterns with status `developing` or higher (confidence >= 0.50) are eligible for second-order synthesis. `Emerging` patterns are excluded — they need more evidence.

### 4.2 Minimum Span

The contributing first-order patterns must collectively span a **minimum of 14 calendar days**. This prevents short-term coincidences from becoming named insights.

### 4.3 Synthesis Confidence Calculation

```
insight_confidence = geometric_mean(contributing_pattern_confidences) * alignment_factor * evidence_depth_factor
```

Where:
- `geometric_mean` ensures that one weak pattern pulls down the whole insight (arithmetic mean would mask weakness)
- `alignment_factor` (0.5 - 1.0): How strong is the temporal/causal alignment between patterns?
  - 0.5: Loose temporal co-occurrence only
  - 0.7: Consistent sequential relationship
  - 0.9: Strong directional correlation with statistical backing
  - 1.0: Causal mechanism is plausible and supported by multiple evidence types
- `evidence_depth_factor` = min(1.0, total_unique_episodic_memories / 15): Rewards insights backed by more raw evidence. Saturates at 15 unique episodic memories.

### 4.4 Confidence Thresholds for Actions

| Insight confidence | What happens |
|-------------------|--------------|
| < 0.35 | Not stored. Logged as a synthesis attempt for future reference. |
| 0.35 - 0.50 | Stored as `hypothesis`. Not surfaced to user. Re-evaluated nightly. |
| 0.50 - 0.65 | Stored as `emerging_insight`. May be surfaced in morning session with hedged language ("I'm noticing a possible pattern..."). |
| 0.65 - 0.80 | Stored as `active_insight`. Surfaced in morning session with moderate confidence framing. Eligible for candidate rule generation. |
| 0.80 - 0.95 | Stored as `confirmed_insight`. Surfaced assertively. Generates candidate rules. Updates semantic memory. |

---

## 5. Named Insight Format

### 5.1 Schema

```json
{
  "insight_id": "uuid-v4",
  "created_at": "ISO-8601",
  "updated_at": "ISO-8601",

  "name": {
    "title": "Post-Board Fatigue Cycle",
    "slug": "post-board-fatigue-cycle",
    "one_liner": "Board meetings trigger a 72-hour cognitive recovery period that suppresses strategic output"
  },

  "evidence_chain": {
    "contributing_patterns": [
      {
        "pattern_id": "uuid",
        "pattern_title": "Strategic document work drops post-board",
        "category": "behavioural",
        "confidence": 0.74,
        "role_in_insight": "Primary signal — measures the output reduction"
      },
      {
        "pattern_id": "uuid",
        "pattern_title": "Email latency spike post-board",
        "category": "relational",
        "confidence": 0.71,
        "role_in_insight": "Corroborating signal — confirms cognitive load increase across domains"
      },
      {
        "pattern_id": "uuid",
        "pattern_title": "Optional meeting acceptance surge post-board",
        "category": "behavioural",
        "confidence": 0.62,
        "role_in_insight": "Compensatory behaviour — executive fills time with low-stakes activities"
      }
    ],
    "cross_domain_count": 2,
    "total_episodic_memories": 23,
    "temporal_relationship": "sequential",
    "temporal_lag": "0-72 hours after board meeting conclusion",
    "observation_span_days": 42
  },

  "confidence": {
    "score": 0.68,
    "status": "active_insight",
    "trend": "strengthening",
    "calculation": {
      "geometric_mean_patterns": 0.69,
      "alignment_factor": 0.85,
      "evidence_depth_factor": 1.0,
      "result": 0.68
    }
  },

  "actionability": {
    "score": 0.82,
    "reasoning": "Clear trigger (board meetings are scheduled in advance), clear recommendation (protect 72h post-board from strategic scheduling), measurable outcome (strategic output volume in the protected window)",
    "candidate_rule": true,
    "rule_draft": "IF post-board-meeting AND within-72h THEN avoid-scheduling-strategic-work"
  },

  "narrative": {
    "morning_session_text": "After your last three board meetings, your strategic output dropped significantly for about 72 hours. You spent that time in optional meetings and email catch-up — useful, but not the high-value work you'd normally prioritise. This pattern has been consistent over 6 weeks. Your next board meeting is Thursday — I'd suggest keeping Friday and Monday light on strategic commitments.",
    "detail_text": "Analysis of 42 days of data across 3 board meeting cycles shows a consistent pattern: in the 72 hours following a board meeting, strategic document creation drops 64%, email response latency increases 2.1x, and acceptance of optional/informational meetings increases 40%. This appears to be a cognitive recovery period — the executive compensates by filling time with lower-demand activities. The pattern holds across all 3 observed cycles with no counter-examples.",
    "evidence_summary": "Based on 23 observations across email response patterns, document engagement logs, and calendar acceptance data over 6 weeks."
  },

  "connections": {
    "related_insight_ids": ["uuid"],
    "contributes_to_rules": ["rule_id"],
    "updates_semantic_memories": ["memory_id"],
    "supersedes_insights": ["insight_id (if this is a refined version of an earlier insight)"]
  },

  "metadata": {
    "synthesis_model": "opus-4.6",
    "synthesis_date": "ISO-8601",
    "reinforcement_count": 3,
    "last_surfaced": "ISO-8601",
    "user_feedback": "confirmed | dismissed | corrected | null",
    "version": 1
  },

  "embedding": {
    "vector_id": "string",
    "text_for_embedding": "Post-board fatigue cycle: board meetings trigger 72-hour cognitive recovery suppressing strategic output, increasing email latency, and driving compensatory low-stakes meeting acceptance"
  }
}
```

### 5.2 Actionability Score

Not all insights are actionable. Some are descriptive ("You communicate differently with finance vs engineering teams"). The actionability score determines whether an insight becomes a candidate rule.

```
actionability_score = trigger_clarity * recommendation_clarity * outcome_measurability
```

Each factor is scored 0.0 - 1.0:
- **trigger_clarity**: Is there a clear, observable trigger event? (board meeting = 1.0, "when stressed" = 0.3)
- **recommendation_clarity**: Can the system make a specific recommendation? ("protect 72h post-board" = 0.9, "be more strategic" = 0.1)
- **outcome_measurability**: Can the system measure whether the recommendation helped? ("strategic output volume in window" = 0.8, "felt better" = 0.2)

Insights with actionability >= 0.60 generate candidate rules.

---

## 6. Synthesis Process

### 6.1 Nightly Synthesis Pipeline

```
┌──────────────────────────────────────────────────────────────┐
│                   NIGHTLY SYNTHESIS PIPELINE                  │
│                                                              │
│  INPUT:                                                      │
│  ├── All first-order patterns (developing+)                  │
│  ├── Existing named insights (for reinforcement/revision)    │
│  ├── User semantic profile                                   │
│  ├── Recent user feedback on surfaced insights               │
│  └── Calendar context (upcoming events for proactive alerts) │
│                                                              │
│  STEP 1: Cross-Domain Pairing                                │
│  ├── Generate all valid cross-domain pattern pairs           │
│  ├── Filter by temporal alignment                            │
│  ├── Score pairs by correlation strength                     │
│  └── Pass top 30 pairs + all existing insights to Opus       │
│                                                              │
│  STEP 2: Opus Synthesis (API call)                           │
│  ├── For each high-scoring pair/group:                       │
│  │   ├── Assess causal plausibility                          │
│  │   ├── Check for confounding patterns                      │
│  │   ├── Generate narrative explanation                      │
│  │   ├── Score confidence and actionability                  │
│  │   └── Draft morning session text                          │
│  ├── For existing insights:                                  │
│  │   ├── Check for reinforcing new evidence                  │
│  │   ├── Check for contradicting new evidence                │
│  │   ├── Update confidence scores                            │
│  │   └── Refine narratives if evidence base changed          │
│  └── Generate model corrections if any                       │
│                                                              │
│  STEP 3: Insight Store Update                                │
│  ├── Create new insight entries                              │
│  ├── Update existing insight confidence/evidence             │
│  ├── Merge insights that have converged                      │
│  ├── Flag insights for deprecation if contradicted           │
│  ├── Pass actionable insights to Rule Generation (Stage 4)   │
│  └── Update semantic memory with confirmed insight facts     │
│                                                              │
│  STEP 4: Morning Session Preparation                         │
│  ├── Select top 3-5 insights for tomorrow's session          │
│  ├── Prioritise by: recency, confidence, actionability       │
│  ├── Include 1 proactive insight (calendar-triggered)        │
│  └── Generate session script draft for Morning Director      │
└──────────────────────────────────────────────────────────────┘
```

### 6.2 Opus Synthesis Prompt Structure

The synthesis prompt provides Opus with:

1. **Structured pattern inventory**: All developing+ first-order patterns in tabular format (id, title, category, subtype, confidence, last_observed, observation_count)
2. **High-scoring cross-domain pairs**: The top 30 pairs from the pairing step, with temporal alignment details
3. **Existing insights**: Current named insights with their evidence chains and confidence scores
4. **User profile**: Semantic memory summary — role, key relationships, current priorities, known tendencies
5. **Calendar lookahead**: Next 7 days of scheduled events (for proactive insight generation)
6. **Recent feedback**: Any user confirmations, dismissals, or corrections from the past 7 days

The prompt explicitly instructs Opus to:
- Look for cross-domain explanatory narratives, not just correlations
- Distinguish causal from coincidental co-occurrence
- Consider alternative explanations for each proposed insight
- Rate its own confidence and flag where it is uncertain
- Generate morning session language that is specific, evidence-backed, and non-judgmental
- Identify when existing insights need revision based on new evidence

---

## 7. Insight-to-Rule Bridge

When an insight's actionability score exceeds 0.60, the synthesis stage generates a **candidate rule** as part of its output. This is a structured IF-THEN proposal passed to Stage 4 (Rule Generation).

### 7.1 Candidate Rule Format

```json
{
  "candidate_rule_id": "uuid-v4",
  "source_insight_id": "uuid",
  "source_insight_title": "Post-Board Fatigue Cycle",
  "proposed_rule": {
    "trigger": "Board meeting concluded within the past 72 hours",
    "condition": "Strategic work (document creation, strategy sessions, long-form writing) is scheduled",
    "recommendation": "Reschedule strategic work to 72+ hours post-board. Fill the window with operational tasks, 1:1s, or email processing.",
    "confidence": 0.68
  },
  "evidence_summary": "3 board meeting cycles observed over 42 days. Strategic output drops 64% in 72h post-board window across all cycles.",
  "expected_outcome": "Strategic output quality maintained by avoiding low-performance windows",
  "measurement": "Compare strategic output volume and quality in post-board windows before and after rule activation"
}
```

### 7.2 Promotion Criteria

Not every candidate rule becomes an active rule. Stage 4 evaluates candidate rules for:
- Sufficient confidence (>= 0.60 from the source insight)
- No conflict with existing active rules
- Clear measurability
- The user has not previously dismissed the underlying insight

---

## 8. Insight Lifecycle

```
                     confidence >= 0.35
                          │
                          ▼
[not stored] ──────► [hypothesis] ──────► [emerging_insight] ──────► [active_insight] ──────► [confirmed_insight]
                          │                      │                        │                         │
                          ▼                      ▼                        ▼                         ▼
                     [dissolved]            [dissolved]               [fading]                  [fading]
                                                                         │                         │
                                                                         ▼                         ▼
                                                                    [archived]                [archived]
```

**Transitions:**
- `hypothesis` → `emerging_insight`: confidence reaches 0.50, OR 2+ new reinforcing observations since creation
- `emerging_insight` → `active_insight`: confidence reaches 0.65, AND insight has been stable for 7+ days
- `active_insight` → `confirmed_insight`: confidence reaches 0.80, AND user has not dismissed it, AND 30+ day evidence span
- Any → `fading`: No reinforcing evidence in 21 days, OR confidence drops below the threshold for current status
- `fading` → `archived`: No reinforcing evidence in 42 days
- `hypothesis` / `emerging_insight` → `dissolved`: Confidence drops below 0.35 before reaching active status. Not stored permanently — dissolved insights are logged but not maintained.

**Insight merging**: When two insights share 2+ contributing patterns and their narratives overlap, the synthesis stage proposes a merge. The merged insight inherits the stronger confidence and the combined evidence chain.

---

## 9. Examples

### Example 1: Cross-Domain Behavioural Insight

**Title**: "Monday Morning Strategic Clarity Window"

**Contributing patterns**:
1. Temporal: "Peak document creation velocity occurs Monday 9:00-11:30am" (confidence 0.78)
2. Behavioural: "Longest uninterrupted focus sessions occur Monday morning" (confidence 0.72)
3. Email: "Email response volume is lowest Monday 9:00-11:00am" (confidence 0.81)
4. Calendar: "Monday mornings have the fewest scheduled meetings" (confidence 0.85)

**Synthesis**: "Monday morning is this executive's highest-leverage strategic window. Calendar is naturally lighter, email is deferred, focus sessions run 2.3x longer than any other slot, and document output quality peaks. This window is currently unprotected — 2 of the last 4 Monday mornings were disrupted by ad-hoc meetings."

**Confidence**: 0.76 (active_insight)
**Actionability**: 0.88 (clear trigger, clear protection recommendation, measurable output)
**Candidate rule**: "IF Monday AND 9:00-11:30am THEN protect-from-meetings AND flag-strategic-work-scheduling CONFIDENCE 0.76"

### Example 2: Relational + Cognitive Insight

**Title**: "CFO Conversations Trigger Decision Acceleration"

**Contributing patterns**:
1. Relational: "Response time to CFO emails is fastest among all Board members" (confidence 0.69)
2. Cognitive: "Decision latency on financial matters drops 60% within 24h of CFO meeting" (confidence 0.64)
3. Calendar: "Ad-hoc 1:1s with CFO are scheduled 2x more frequently than with any other Board member" (confidence 0.73)

**Synthesis**: "The CFO relationship functions as a decision catalyst. After CFO interactions, financial decisions that have been pending for days are resolved within 24 hours. The executive appears to use the CFO as a sounding board for decisions they've already formed but haven't committed to. Scheduling a CFO touchpoint before major financial decisions may accelerate resolution."

**Confidence**: 0.62 (emerging_insight — needs more cycles to confirm)
**Actionability**: 0.71 (trigger: pending financial decisions; recommendation: schedule CFO touchpoint; measurement: decision latency)

### Example 3: Avoidance + Temporal Insight

**Title**: "End-of-Quarter People Decision Bottleneck"

**Contributing patterns**:
1. Avoidance: "People-related decisions (hiring, role changes, performance conversations) deferred at 3.4x rate of operational decisions" (confidence 0.77)
2. Temporal: "Deferral rate for people decisions increases 2x in weeks 10-13 of each quarter" (confidence 0.58)
3. Task: "HR-tagged tasks accumulate without completion — average 4.2 pending at any time vs 1.1 for other categories" (confidence 0.71)
4. Calendar: "1:1 meetings with HR head cancelled or shortened 3 times in past 6 weeks" (confidence 0.55)

**Synthesis**: "People decisions are this executive's primary avoidance category, and the avoidance intensifies as quarter-end approaches — likely because quarter-end operational demands provide a convenient justification for deferral. The backlog then creates a compounding problem: deferred people decisions become more complex and urgent, requiring more cognitive resources, driving further avoidance. The 1:1 cancellations with HR suggest the executive is aware of the backlog and is avoiding the accountability conversation."

**Confidence**: 0.58 (emerging_insight — the quarterly temporal pattern needs another cycle to confirm)
**Actionability**: 0.65 (trigger: quarter weeks 8-9; recommendation: front-load people decisions before operational crunch; measurement: people decision completion rate by quarter week)

---

## 10. Performance Budgets

| Metric | Budget |
|--------|--------|
| Cross-domain pairing (on-device) | < 15 seconds |
| Context assembly | < 10 seconds |
| Opus synthesis call | < 180 seconds API time, < 50K input tokens, < 12K output tokens |
| Insight store update | < 5 seconds on-device |
| Morning session preparation | < 10 seconds |
| Total Stage 3 time | < 4 minutes |

The synthesis call is the most expensive in the nightly pipeline (larger context than first-order extraction because it includes all patterns + existing insights). Approximately $0.80-1.20/night at current Opus pricing.

---

## 11. Quality Metrics

### 11.1 Insight Quality

Evaluated monthly:
- **Explanatory power**: Does the insight explain observed behaviour better than any single contributing pattern alone? (Human evaluation on sample)
- **Predictive accuracy**: When the insight predicts future behaviour (e.g., "post-board fatigue will occur"), does it? Track prediction-vs-outcome over 30-day windows.
- **User resonance**: Percentage of surfaced insights the user confirms vs dismisses. Target: >60% confirmation rate at month 3, >75% at month 6.
- **Non-obviousness**: Are insights telling the user something they didn't already know? (Self-reported via optional morning session feedback)

### 11.2 Compounding Indicators

Monthly tracking:
- Total active insights
- Average contributing patterns per insight (should increase over time as the pattern web densifies)
- Cross-domain coverage (how many domain pairs have at least one insight)
- Insight stability (percentage of insights that survive 30+ days without dissolution)
- Rule generation rate (insights converting to candidate rules)

Month 1: 2-5 hypothesis-level insights, mostly tentative. Month 3: 10-20 insights across statuses, first confirmed insights emerging, 3-5 candidate rules generated. Month 6: 25-40 insights, robust confirmed set, 10+ active rules, insights referencing each other forming an interconnected intelligence web.
