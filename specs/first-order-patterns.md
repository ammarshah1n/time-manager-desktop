# First-Order Pattern Extraction Spec

> Timed — Layer 3 Reflection Engine, Stage 2
> Version: 1.0 | 2026-04-02
> Dependency: Episodic Memory Store (Layer 2), Signal Ingestion (Layer 1)
> Runs: Nightly, as second stage of Opus reflection pipeline
> Model: Claude Opus 4.6 at maximum reasoning effort

---

## 1. Purpose

First-order patterns are regularities extracted directly from raw episodic data. They answer the question: **"What is this person doing repeatedly, and when/how/with whom are they doing it?"**

First-order patterns are the foundational unit of Timed's intelligence. They are never surfaced directly to the user — they feed into second-order synthesis (Stage 3), which produces named insights. However, first-order patterns are stored persistently and accumulate as evidence for higher-order reasoning.

A first-order pattern is a statement about observed regularity with statistical backing. It is NOT an interpretation, recommendation, or insight. Interpretation happens at the second-order stage.

---

## 2. Pattern Taxonomy

### 2.1 Temporal Patterns

Regularities bound to time — clock time, day of week, calendar position, seasonal cycles.

**Detection signals:**
- Recurring action at consistent time windows (e.g., email triage 7:15-7:45am on 7/9 observed weekdays)
- Performance variation correlated with time-of-day (response quality drops after 3pm)
- Day-of-week effects (Friday response latency to Board emails is 2.1x Monday's)
- Post-event timing (strategic document work begins 48-72h before board meetings, never earlier)
- Seasonal or monthly cycles (end-of-quarter meeting density increases 40%)

**Subtypes:**
| Subtype | Definition | Example |
|---------|-----------|---------|
| `clock_regularity` | Action recurs at consistent clock time | "Email triage occurs between 7:10-7:50am on 8 of 10 weekdays" |
| `day_of_week_effect` | Measurable performance or behaviour shift by weekday | "Response time to Board members increases 2.1x on Fridays vs Mondays" |
| `calendar_relative` | Action timing relative to a calendar anchor | "Board presentation prep starts 48-72h before the meeting, never >96h" |
| `post_event_latency` | Recovery or transition time after specific event types | "No strategic document work occurs within 90min of a 3+ person meeting" |
| `cyclic_drift` | Weekly, monthly, or quarterly recurring shifts | "Meeting density increases 35-45% in final week of each quarter" |

### 2.2 Behavioural Patterns

Regularities in what the user does — action sequences, task handling, work patterns.

**Detection signals:**
- Task completion sequences (always checks email before starting deep work)
- Duration patterns (focus sessions average 47min before first context switch)
- Completion vs abandonment ratios by task category
- Substitution behaviour (low-value tasks performed instead of high-value deferred ones)
- Batch vs serial processing preferences (emails batched vs continuous)

**Subtypes:**
| Subtype | Definition | Example |
|---------|-----------|---------|
| `action_sequence` | Repeated ordered sequence of actions | "Morning routine: email scan → calendar review → Slack check → first task, observed 11/14 days" |
| `duration_regularity` | Consistent time-on-task for specific activity types | "Focus sessions on financial documents: median 52min, IQR 44-61min" |
| `completion_pattern` | Predictable completion/abandonment by task attributes | "Tasks tagged 'people decisions' completed same-day only 23% of time vs 71% for operational tasks" |
| `substitution` | Systematic replacement of one activity with another | "When 'staffing review' is scheduled, email processing volume increases 3x in the preceding hour" |
| `batch_preference` | Consistent batching or serialising of specific work types | "Email replies batched into 2 windows: 7:15-7:45am and 5:30-6:00pm on 9/12 weekdays" |

### 2.3 Relational Patterns

Regularities in communication and interaction with specific people or groups.

**Detection signals:**
- Response latency distribution per contact/group (Board vs direct reports vs external)
- Email length variation by recipient
- Meeting acceptance/decline rates by organiser
- Communication frequency trends (increasing, stable, declining per relationship)
- Channel preference by person (email for X, Teams for Y)
- Sentiment trajectory per relationship (detected via linguistic markers)

**Subtypes:**
| Subtype | Definition | Example |
|---------|-----------|---------|
| `response_priority` | Systematic response speed differences by person/group | "CFO emails: median response 14min. Marketing VP emails: median response 4.2h" |
| `communication_frequency_shift` | Directional change in interaction rate with a person | "1:1 meetings with Head of Product increased from biweekly to weekly over 3 weeks" |
| `sentiment_trend` | Detectable tone/formality shift in communications with a person | "Emails to COO shifted from collaborative ('we should', 'let's') to directive ('please ensure', 'I need') over 2 weeks" |
| `selective_non_response` | Consistent pattern of not responding to specific people or topics | "3 of 4 emails from Legal re: compliance review unanswered for >72h" |
| `channel_switching` | Moving communication with a person to a different channel | "Conversations with Board Chair moved from email to phone (inferred from calendar 'call' entries) starting 10 days ago" |

### 2.4 Cognitive Patterns

Regularities in decision-making, thinking quality, and information processing.

**Detection signals:**
- Decision latency by decision type (fast operational, slow strategic)
- Decision reversal frequency and timing
- Information-gathering depth before decisions (emails sent, documents opened)
- Document revision patterns (single-draft vs heavy iteration)
- Time-of-day correlation with decision quality (proxied by reversal rate)

**Subtypes:**
| Subtype | Definition | Example |
|---------|-----------|---------|
| `decision_latency` | Consistent time-to-decision by decision category | "Operational decisions: median 2.1h. People decisions: median 8.4 days" |
| `decision_quality_window` | Time periods where decisions are less likely to be reversed | "Decisions made before 11am reversed 12% of time. After 3pm: 31%" |
| `information_seeking` | Pre-decision research intensity patterns | "Before financial decisions: 4.2 documents opened avg. Before people decisions: 0.7 documents" |
| `revision_intensity` | Editing depth correlated with document type or recipient | "Board-facing documents: avg 4.7 revision sessions. Internal docs: avg 1.3 sessions" |
| `cognitive_throughput` | Volume of meaningful decisions/outputs per time unit | "Strategic output (docs created, decisions logged) peaks Mon-Wed, drops 60% Thu-Fri" |

### 2.5 Avoidance Patterns

Regularities in what the user systematically defers, abandons, or circumvents. Highest-value pattern category for executive intelligence.

**Detection signals:**
- Repeated task deferral (task appears on plan N times without progress)
- Draft-then-delete cycles (email/document started and abandoned)
- Meeting rescheduling without environmental justification
- Phantom tasks (mentioned in morning sessions, never worked on)
- Substitution behaviour tied to specific avoided items
- Topic non-response in email threads (answers everything except the hard question)
- Short contact time (opens avoided item, switches away within <3 minutes)

**Subtypes:**
| Subtype | Definition | Example |
|---------|-----------|---------|
| `task_avoidance` | Specific task repeatedly deferred or abandoned | "Staffing review document opened 7 times in 14 days, edited 0 times, deferred from plan 5 times" |
| `conversation_avoidance` | Systematic non-engagement with specific person or topic | "3 emails from Board re: governance review — opened, no reply sent, avg age 9 days" |
| `decision_avoidance` | Decision point reached and deferred repeatedly | "Product pricing decision flagged as 'pending' for 18 days across 4 plan appearances" |
| `category_avoidance` | Entire class of work systematically deprioritised | "People-related tasks (tagged or inferred) deferred at 3.4x the rate of operational tasks" |
| `approach_retreat` | Starts engaging with avoided item then disengages quickly | "Opened draft email to [person] 4 times, avg session 2.1min, never sent" |

---

## 3. Evidence Threshold

### 3.1 Minimum Observation Count

A first-order pattern requires a **minimum of 3 independent observations** before it is stored as an `emerging` pattern. This prevents single occurrences or coincidences from polluting the pattern store.

| Observation count | Pattern status | Confidence floor |
|-------------------|---------------|-----------------|
| 1-2 | Not stored as pattern. Raw episodic memories only. | — |
| 3-4 | `emerging` | 0.30 - 0.50 |
| 5-9 | `developing` | 0.50 - 0.70 |
| 10-19 | `established` | 0.70 - 0.85 |
| 20+ | `confirmed` | 0.85 - 0.95 |

### 3.2 Temporal Span Requirement

Observations must span a **minimum of 5 calendar days** for temporal/behavioural patterns and **7 calendar days** for relational/cognitive/avoidance patterns. This prevents mistaking a single bad week for a persistent pattern.

Exception: avoidance patterns with 3+ observations in 5 days AND emotional valence signals (draft-delete, short contact time) may be flagged as `emerging` at 5 days. Avoidance is time-sensitive — the longer it takes to surface, the worse the outcome.

### 3.3 Counter-Evidence Handling

Every stored pattern tracks counter-evidence: observations that contradict the pattern. A pattern is not invalidated by counter-evidence — it reduces confidence proportionally.

```
adjusted_confidence = base_confidence * (supporting_count / (supporting_count + counter_count * counter_weight))
```

`counter_weight` defaults to 1.5 (counter-evidence is weighted more heavily than supporting evidence, per confirmation bias prevention).

---

## 4. Extraction Methods

### 4.1 Statistical Extraction (Layer 2 preprocessing)

Runs before Opus reflection, on structured data. Computationally cheap, high precision, low recall.

**Methods:**
- **Frequency analysis**: Count action occurrences per time bucket (hourly, daily, weekly). Flag any action that occurs in the same time bucket on 3+ occasions within the observation window.
- **Distribution comparison**: For continuous metrics (response latency, session duration), compute per-context distributions. Flag when a context-specific distribution differs from the global distribution by >1 standard deviation.
- **Sequence mining**: Apply sequential pattern mining (PrefixSpan or GSP) on action sequences to find repeated ordered subsequences with minimum support threshold of 3.
- **Anomaly detection**: Compute rolling baselines for key metrics. Flag deviations >2 sigma as potential pattern-breaking events (which may themselves be patterns if recurrent).
- **Correlation analysis**: Pairwise correlation between all metric time series. Flag correlations with |r| > 0.5 and p < 0.05 for Opus review.

**Output**: A structured candidate list passed to Opus as input context for the LLM extraction stage.

### 4.2 LLM-Based Extraction (Opus nightly reflection)

Opus receives:
1. The statistical candidate list from 4.1
2. Raw episodic memories from the past 24h (full detail)
3. Episodic memory summaries from the past 7 days
4. Existing first-order patterns (for reinforcement or contradiction)
5. The user's semantic memory profile (for contextual interpretation)

Opus performs extraction that statistics cannot:
- **Contextual pattern recognition**: "The statistical system flagged Friday response latency, but looking at the raw data, it's specifically Friday afternoons after Board committee calls — the pattern is post-board, not Friday-specific."
- **Intent inference**: "The 7 opened-but-not-edited documents are all related to the restructuring decision. This isn't random document avoidance — it's decision avoidance on a specific topic."
- **Cross-signal synthesis**: "Email brevity increased, meeting acceptance dropped, and focus session duration shortened — all in the same 3-day window following the budget rejection."
- **Narrative coherence**: Patterns that only make sense when you understand the executive's current context (a new hire, a board conflict, a product launch).

**Key principle**: Statistical extraction finds candidates. Opus extraction finds meaning. Both are required — neither alone is sufficient.

### 4.3 Hybrid Pipeline

```
┌─────────────────────────────────────────────────────────┐
│                    NIGHTLY PIPELINE                       │
│                                                           │
│  1. Statistical Pre-processing (on-device, no LLM cost)  │
│     ├── Frequency analysis on structured signals          │
│     ├── Distribution comparisons per context              │
│     ├── Sequence mining on action logs                    │
│     ├── Anomaly detection on rolling baselines            │
│     └── Correlation analysis on metric pairs              │
│     OUTPUT: candidate_patterns[] + anomalies[]            │
│                                                           │
│  2. Context Assembly                                      │
│     ├── Retrieve 24h episodic memories (full)             │
│     ├── Retrieve 7d episodic summaries                    │
│     ├── Retrieve existing first-order patterns            │
│     ├── Retrieve user semantic profile                    │
│     └── Merge with statistical candidates                 │
│     OUTPUT: reflection_context{}                          │
│                                                           │
│  3. Opus First-Order Extraction (API call)                │
│     ├── Validate statistical candidates                   │
│     ├── Discover non-statistical patterns                 │
│     ├── Assign pattern types and subtypes                 │
│     ├── Calculate confidence scores                       │
│     ├── Link to supporting episodic memories              │
│     └── Generate human-readable descriptions              │
│     OUTPUT: extracted_patterns[]                          │
│                                                           │
│  4. Pattern Store Update                                  │
│     ├── Merge with existing patterns (reinforce/update)   │
│     ├── Create new pattern entries                        │
│     ├── Update confidence on existing patterns            │
│     ├── Mark contradicted patterns for review             │
│     └── Promote patterns by evidence threshold            │
│     OUTPUT: updated pattern store                         │
└─────────────────────────────────────────────────────────┘
```

---

## 5. Pattern Storage Format

### 5.1 Schema

```json
{
  "pattern_id": "uuid-v4",
  "created_at": "ISO-8601",
  "updated_at": "ISO-8601",
  "last_observed": "ISO-8601",

  "taxonomy": {
    "category": "temporal | behavioural | relational | cognitive | avoidance",
    "subtype": "string (from taxonomy table)",
  },

  "description": {
    "title": "Short human-readable name, max 80 chars",
    "summary": "One-sentence factual description with evidence counts",
    "detail": "2-3 sentence expanded description with specific numbers and dates"
  },

  "evidence": {
    "supporting_observations": ["episodic_memory_id", "..."],
    "counter_observations": ["episodic_memory_id", "..."],
    "supporting_count": 7,
    "counter_count": 2,
    "first_observed": "ISO-8601",
    "last_observed": "ISO-8601",
    "observation_span_days": 14,
    "statistical_basis": {
      "method": "frequency_analysis | distribution_comparison | sequence_mining | correlation | llm_only",
      "test_statistic": 0.0,
      "p_value": 0.0,
      "effect_size": 0.0
    }
  },

  "confidence": {
    "score": 0.72,
    "status": "emerging | developing | established | confirmed | fading | deprecated",
    "trend": "strengthening | stable | weakening",
    "last_recalculated": "ISO-8601"
  },

  "context": {
    "related_people": ["contact_id", "..."],
    "related_task_categories": ["string", "..."],
    "related_time_windows": [{"day": "friday", "start": "14:00", "end": "17:00"}],
    "related_pattern_ids": ["pattern_id", "..."],
    "tags": ["string", "..."]
  },

  "metadata": {
    "extraction_method": "statistical | llm | hybrid",
    "extraction_model": "opus-4.6",
    "extraction_date": "ISO-8601",
    "reinforcement_count": 5,
    "last_surfaced_to_user": "ISO-8601 | null",
    "user_feedback": "confirmed | dismissed | corrected | null"
  },

  "embedding": {
    "vector_id": "string (reference to Jina embedding in vector store)",
    "text_for_embedding": "Flattened text representation used for embedding generation"
  }
}
```

### 5.2 Storage Location

First-order patterns are stored in **Layer 2 — Memory Store** as semantic memory entries with `memory_type = 'first_order_pattern'`. They are also embedded via Jina AI (1024-dim) for similarity retrieval during reflection and morning session preparation.

On-device: CoreData entity `FirstOrderPattern` with all fields above.
Remote: Supabase `first_order_patterns` table, synced nightly after reflection completes.

### 5.3 Pattern Lifecycle

```
                    3+ observations,
                    5+ day span
                         │
                         ▼
 [not stored] ──► [emerging] ──► [developing] ──► [established] ──► [confirmed]
                      │               │                │                 │
                      │               │                │                 │
                      ▼               ▼                ▼                 ▼
                  [fading] ◄──── [fading] ◄────── [fading] ◄─────── [fading]
                      │
                      ▼
                 [deprecated]
```

**Promotion criteria:**
- `emerging` → `developing`: 5+ supporting observations, 7+ day span
- `developing` → `established`: 10+ supporting observations, 14+ day span, counter ratio < 0.3
- `established` → `confirmed`: 20+ supporting observations, 21+ day span, counter ratio < 0.2

**Demotion criteria:**
- Any status → `fading`: No new supporting observation in 14 days, OR counter ratio exceeds 0.5
- `fading` → `deprecated`: No new supporting observation in 30 days, OR explicitly contradicted by user feedback

**Deprecated patterns are never deleted.** They move to archival memory with a deprecation reason. This preserves the historical record and allows patterns to be resurrected if they re-emerge.

---

## 6. Confidence Calculation

### 6.1 Base Confidence

```
base_confidence = min(0.95, observation_weight * span_weight * consistency_weight)
```

Where:
- `observation_weight = min(1.0, supporting_count / 20)` — saturates at 20 observations
- `span_weight = min(1.0, observation_span_days / 28)` — saturates at 4 weeks
- `consistency_weight = supporting_count / (supporting_count + counter_count * 1.5)`

### 6.2 Recency Adjustment

Patterns with recent evidence are more confident than stale patterns.

```
recency_factor = exp(-days_since_last_observation / decay_constant)
```

Where `decay_constant = 21` (3 weeks half-life).

### 6.3 User Feedback Adjustment

If the user has interacted with a surfaced insight that cites this pattern:
- `confirmed`: confidence += 0.10 (capped at 0.95)
- `dismissed`: confidence -= 0.05 (floored at 0.10)
- `corrected`: confidence -= 0.15, pattern flagged for Opus re-evaluation

### 6.4 Final Confidence

```
final_confidence = base_confidence * recency_factor + feedback_adjustment
```

Clamped to [0.0, 0.95]. No pattern ever reaches 1.0 — human behaviour always has variance.

---

## 7. Examples

### Example 1: Temporal + Avoidance Compound

**Pattern title**: "Strategic documents opened but not edited before board meetings"

**Detail**: "In 9 of the last 14 days, at least one strategic document (board memo, strategy deck, or restructuring proposal) was opened in the document editor. In 7 of those 9 instances, the document was closed within 3 minutes with no edits saved. This behaviour clusters in the 48-96h window before scheduled Board meetings. Outside this window, strategic document engagement averages 34 minutes per session."

**Evidence**:
- Supporting: 7 episodic memories of open-close-no-edit sequences
- Counter: 2 instances where the document was edited for >15min in the same window
- Span: 14 days
- Statistical basis: frequency analysis flagged the cluster; Opus identified the board-meeting temporal anchor

**Confidence**: 0.68 (developing)
**Category**: avoidance / approach_retreat
**Related patterns**: ["post_board_meeting_latency", "decision_avoidance_restructuring"]

### Example 2: Relational

**Pattern title**: "Friday Board email response delay"

**Detail**: "Response time to Board member emails received on Fridays is 2.1x the Monday-Thursday average (median 6.2h vs 2.9h). This effect is specific to Board members — response time to direct reports shows no Friday effect. 11 of 14 Board emails received on Fridays were not responded to until Monday morning."

**Evidence**:
- Supporting: 11 Friday Board emails with >5h response time
- Counter: 3 Friday Board emails with <3h response time
- Span: 21 days
- Statistical basis: distribution comparison flagged Board Friday latency as >2 sigma from Board weekday mean

**Confidence**: 0.74 (established)
**Category**: relational / response_priority
**Related patterns**: ["friday_afternoon_energy_decline", "board_communication_formality"]

### Example 3: Cognitive

**Pattern title**: "Afternoon decision reversals"

**Detail**: "Decisions communicated via email after 3:00pm are revised or reversed within 48 hours at a rate of 31%, compared to 12% for decisions communicated before 11:00am. Sample: 26 decision emails over 18 days. The effect is strongest for people-related decisions (reversal rate 44% after 3pm vs 8% before 11am)."

**Evidence**:
- Supporting: 8 post-3pm decisions reversed within 48h
- Counter: 18 post-3pm decisions not reversed
- Span: 18 days
- Statistical basis: correlation analysis between time-of-day and reversal-within-48h flag; Opus identified the people-decision amplification

**Confidence**: 0.61 (developing)
**Category**: cognitive / decision_quality_window
**Related patterns**: ["meeting_fatigue_afternoon", "people_decision_avoidance"]

---

## 8. Integration Points

### 8.1 Input: Layer 2 Memory Store

First-order extraction reads:
- All episodic memories from the past 24h (unfiltered)
- Summarised episodic memories from the past 7 days (time-bucketed)
- All existing first-order patterns (for reinforcement/contradiction)
- User semantic profile (for context — role, key contacts, current priorities)

### 8.2 Output: Layer 2 Memory Store

First-order extraction writes:
- New `FirstOrderPattern` entities
- Updated confidence scores on existing patterns
- Status transitions (emerging → developing, etc.)
- New episodic memory entries for the extraction event itself (meta-memory: "Reflection on 2026-04-02 identified 3 new patterns and reinforced 7 existing ones")

### 8.3 Output: Stage 3 (Second-Order Synthesis)

The complete set of `developing`, `established`, and `confirmed` first-order patterns is passed as input context to the second-order synthesis stage. `Emerging` patterns are excluded from second-order synthesis — they need more evidence before being combined into insights.

### 8.4 Output: Layer 4 Intelligence Delivery

First-order patterns are NOT directly surfaced to the user. They are raw material for second-order insights and named patterns delivered in the morning session. The only exception: a first-order pattern with `confirmed` status and `avoidance` category MAY be surfaced directly if no second-order insight has been generated from it within 7 days. Avoidance is too time-sensitive to wait for synthesis.

---

## 9. Performance Budgets

| Metric | Budget |
|--------|--------|
| Statistical pre-processing | < 30 seconds on-device (M-series Mac) |
| Context assembly | < 10 seconds |
| Opus extraction call | < 120 seconds API time, < 30K input tokens, < 8K output tokens |
| Pattern store update | < 5 seconds on-device |
| Total Stage 2 time | < 3 minutes |

The Opus extraction call is the primary cost. At ~30K input tokens + ~8K output tokens per night, this is approximately $0.50-0.80/night at current Opus pricing. No cost cap applies — intelligence quality is the constraint, not cost.

---

## 10. Quality Metrics

### 10.1 Extraction Quality

Measured monthly by sampling 20 random patterns and evaluating:
- **Precision**: What percentage of extracted patterns correspond to real regularities? Target: >85% at month 3.
- **Recall**: What percentage of human-identifiable regularities were captured? Target: >60% at month 3, >80% at month 6.
- **Specificity**: Are patterns specific enough to be actionable at the second-order stage? Reject patterns that are true but trivially obvious ("user checks email every day").

### 10.2 Compounding Indicator

Track monthly:
- Total pattern count by status tier
- Average confidence score across all active patterns
- Percentage of patterns with >3 months of evidence
- Number of cross-category pattern links (precursor to second-order synthesis)

Month 1: 15-30 emerging patterns, few developing. Month 3: 50-80 patterns across all statuses, first confirmed patterns appearing. Month 6: 100-150 patterns, robust confirmed set, interconnected pattern web enabling deep second-order synthesis.
