# Rule Generation Spec

> Timed — Layer 3 Reflection Engine, Stage 4
> Version: 1.0 | 2026-04-02
> Dependency: Second-Order Synthesis (Stage 3), Memory Store (Layer 2)
> Runs: Nightly, after second-order synthesis completes
> Model: Claude Opus 4.6 at maximum reasoning effort

---

## 1. Purpose

Rules are the procedural memory of Timed. They encode learned operating principles about the user into executable IF-THEN structures that the system can apply in real time without waiting for nightly reflection.

A rule is the final compression of intelligence: observations → patterns → insights → rules.

Rules allow Timed to act on its intelligence during the day (via morning session recommendations, proactive alerts, and scheduling guidance) without needing to re-derive every conclusion from raw data each time.

Rules are what make Month 6 feel fundamentally different from Month 1. By Month 6, the system has accumulated a set of operating rules specific to this executive — essentially a codified understanding of how they work best, when they fail, and what conditions produce their best outcomes.

---

## 2. Rule Schema

### 2.1 Core Structure

Every rule follows the form:

```
IF [trigger_condition]
AND [context_conditions]
THEN [recommendation]
WITH confidence [score]
BECAUSE [evidence_summary]
```

### 2.2 Full Schema

```json
{
  "rule_id": "uuid-v4",
  "created_at": "ISO-8601",
  "updated_at": "ISO-8601",

  "definition": {
    "trigger": {
      "type": "event | time | threshold | compound",
      "description": "Human-readable trigger description",
      "conditions": [
        {
          "field": "string (e.g., 'calendar.event_type')",
          "operator": "equals | greater_than | less_than | within_hours | contains | matches",
          "value": "string | number | array",
          "temporal_modifier": "within_Xh | after_Xh | before_Xh | null"
        }
      ],
      "compound_logic": "AND | OR (only for compound type)"
    },
    "context": {
      "description": "Additional conditions that must be true for the rule to apply",
      "conditions": [
        {
          "field": "string",
          "operator": "string",
          "value": "any"
        }
      ]
    },
    "recommendation": {
      "action_type": "avoid | prefer | protect | alert | suggest | reframe",
      "description": "Human-readable recommendation",
      "specificity": "general | time_specific | person_specific | task_specific",
      "urgency": "proactive | at_trigger | within_24h"
    }
  },

  "confidence": {
    "score": 0.82,
    "trend": "strengthening | stable | weakening",
    "last_recalculated": "ISO-8601"
  },

  "provenance": {
    "source_insight_id": "uuid",
    "source_insight_title": "Post-Board Fatigue Cycle",
    "contributing_pattern_ids": ["uuid", "uuid", "uuid"],
    "total_supporting_episodic_memories": 23,
    "evidence_span_days": 42,
    "evidence_summary": "3 board meeting cycles observed over 42 days. Strategic output drops 64% in 72h post-board window."
  },

  "lifecycle": {
    "status": "candidate | active | suspended | deprecated",
    "activated_at": "ISO-8601 | null",
    "suspended_at": "ISO-8601 | null",
    "deprecated_at": "ISO-8601 | null",
    "deprecation_reason": "string | null"
  },

  "effectiveness": {
    "times_triggered": 0,
    "times_followed": 0,
    "times_ignored": 0,
    "times_overridden": 0,
    "outcome_when_followed": {
      "positive": 0,
      "neutral": 0,
      "negative": 0
    },
    "outcome_when_ignored": {
      "positive": 0,
      "neutral": 0,
      "negative": 0
    },
    "net_effectiveness_score": 0.0,
    "last_evaluated": "ISO-8601"
  },

  "surface": {
    "morning_session_text": "Your board meeting is Thursday. Based on 6 weeks of data, your strategic output drops significantly for about 72 hours after board meetings. I'd suggest keeping Friday and Monday light on strategic commitments.",
    "alert_text": "Post-board recovery window — strategic work is better deferred to Tuesday.",
    "menu_bar_text": "Post-board window: light strategic load recommended"
  },

  "metadata": {
    "generation_model": "opus-4.6",
    "generation_date": "ISO-8601",
    "version": 1,
    "supersedes_rule_id": "uuid | null",
    "conflict_group": "string | null"
  },

  "embedding": {
    "vector_id": "string",
    "text_for_embedding": "IF post-board-meeting within 72h THEN avoid strategic work scheduling — post-board fatigue reduces strategic output 64%"
  }
}
```

---

## 3. Rule Types

### 3.1 By Action Type

| Action type | Description | Example |
|-------------|------------|---------|
| `avoid` | Recommends against a specific action in a specific context | "Avoid scheduling strategic work within 72h of board meetings" |
| `prefer` | Recommends a positive action | "Prefer Monday 9-11:30am for strategic document work" |
| `protect` | Recommends protecting a time window or resource | "Protect Tuesday morning from meetings — highest focus session quality" |
| `alert` | Triggers a notification when a condition is met | "Alert when people-decision backlog exceeds 3 items for >7 days" |
| `suggest` | Offers a recommendation when a specific moment arrives | "Before 1:1 with CFO, surface pending financial decisions for discussion" |
| `reframe` | Provides context that changes how the user sees a situation | "You're about to make a people decision at 4:30pm — your reversal rate for afternoon people decisions is 44%" |

### 3.2 By Trigger Type

| Trigger type | Description | Example |
|--------------|------------|---------|
| `event` | Triggered by a specific calendar or system event | "Board meeting concluded" |
| `time` | Triggered by clock time or calendar position | "Monday 8:45am (before strategic window)" |
| `threshold` | Triggered when a metric exceeds a value | "Pending people decisions > 3 for > 7 days" |
| `compound` | Multiple conditions that must co-occur | "Post-board-meeting AND strategic work scheduled AND within 72h" |

---

## 4. Rule Lifecycle

### 4.1 States

```
                    Generated by
                    synthesis stage
                         │
                         ▼
                    [candidate]
                         │
               ┌─────────┴──────────┐
               │                    │
          Opus approves        Opus rejects
          + no conflicts       or conflicts
               │                    │
               ▼                    ▼
           [active]            [rejected]
               │                (logged, not
               │                 deleted)
          ┌────┴────┐
          │         │
     effective   ineffective
     (keep)     or contradicted
          │         │
          │         ▼
          │    [suspended]
          │         │
          │    ┌────┴────┐
          │    │         │
          │  recovers   stays
          │  evidence   ineffective
          │    │         │
          │    ▼         ▼
          │  [active]  [deprecated]
          │
          └──► (continues operating)
```

### 4.2 Candidate → Active Promotion

The nightly Rule Generation stage evaluates each candidate rule:

1. **Confidence check**: Source insight confidence >= 0.60
2. **Conflict check**: No existing active rule contradicts this candidate (see Section 6)
3. **Specificity check**: Trigger conditions are precise enough to be evaluated programmatically
4. **Measurability check**: The expected outcome can be tracked with available signals
5. **Opus evaluation**: Opus reviews the candidate in context of the full rule set and user profile, assessing whether it represents genuine intelligence or is an artifact of data noise

If all checks pass, the rule is promoted to `active`. If any check fails, the rule remains `candidate` with a note on what needs to change. Rules rejected by Opus are marked `rejected` with a reason.

### 4.3 Active → Suspended

A rule is suspended when:
- Its effectiveness score drops below 0.0 (net negative outcomes when followed vs ignored) for 2+ evaluation cycles
- The source insight's confidence drops below 0.50
- The user explicitly overrides the rule 3+ consecutive times
- A conflicting rule with higher confidence is activated

Suspension is reversible. The rule continues to be evaluated but stops being surfaced to the user.

### 4.4 Suspended → Deprecated

A rule is deprecated when:
- It has been suspended for 30+ days with no recovery
- The source insight is dissolved or archived
- The user explicitly requests its removal
- New evidence directly contradicts the rule's premise

**Deprecated rules are never deleted.** They move to archival procedural memory with full provenance. This allows:
- Historical record of what the system has learned and unlearned
- Prevention of re-generating the same rule if the evidence base hasn't changed
- Potential resurrection if conditions change (e.g., seasonal patterns)

---

## 5. Effectiveness Tracking

### 5.1 Tracking Mechanism

Every time a rule's trigger condition is met:

1. **Log the trigger event**: Record timestamp, context, what was recommended
2. **Track the response**: Did the user follow the recommendation, ignore it, or explicitly override it?
3. **Measure the outcome**: After a rule-specific evaluation window (24h-7d depending on the rule), assess whether the outcome was positive, neutral, or negative

### 5.2 Outcome Measurement

Outcomes are measured against the rule's stated expected outcome using available signals:

| Rule type | Outcome signal | Positive | Negative |
|-----------|---------------|----------|----------|
| "Avoid strategic work post-board" | Strategic document creation volume and quality in 72h window | Output maintained at baseline | Output dropped despite avoidance (rule is wrong about mechanism) |
| "Protect Monday morning" | Focus session duration, document output | Longest uninterrupted session of the week | Session disrupted, no output advantage |
| "Alert on people-decision backlog" | Decision resolution time after alert | Decisions addressed within 48h of alert | No action taken (alert ineffective) |

### 5.3 Net Effectiveness Score

```
NES = (positive_when_followed - negative_when_followed) / total_triggers
    - (positive_when_ignored - negative_when_ignored) / total_triggers
```

NES ranges from -1.0 to 1.0:
- Positive NES: Following the rule produces better outcomes than ignoring it
- Zero NES: The rule has no measurable effect
- Negative NES: Ignoring the rule actually produces better outcomes (the rule is wrong)

A rule with NES < 0.0 for 2 consecutive evaluation cycles (14 days) is suspended.

### 5.4 Confidence Update from Effectiveness

Rule confidence is updated based on effectiveness data:

```
updated_confidence = base_confidence * (0.7 + 0.3 * sigmoid(NES * 5))
```

This means:
- NES of 0.0 → confidence reduced to 85% of base (slight penalty for no demonstrated effect)
- NES of 0.5 → confidence increased to ~98% of base
- NES of -0.5 → confidence reduced to ~72% of base
- NES of -1.0 → confidence reduced to ~70% of base (triggers suspension)

---

## 6. Conflict Resolution

### 6.1 Conflict Types

| Conflict type | Description | Example |
|---------------|------------|---------|
| **Direct contradiction** | Two rules recommend opposite actions for the same trigger | Rule A: "Protect Monday morning from meetings." Rule B: "Schedule weekly team sync Monday 10am for best attendance." |
| **Resource competition** | Two rules compete for the same time/attention resource | Rule A: "Strategic work best Monday 9-11:30." Rule B: "Deep financial review best Monday 9-11." |
| **Conditional overlap** | Rules apply in overlapping but not identical conditions, with different recommendations | Rule A: "Post-board, avoid strategic work." Rule B: "End-of-quarter, prioritise strategic planning." What happens when a board meeting falls in the last week of the quarter? |

### 6.2 Resolution Protocol

When a conflict is detected (by the nightly Opus evaluation or by the real-time rule engine):

1. **Compare confidence scores**: Higher confidence rule takes precedence if the gap is > 0.15
2. **Compare effectiveness scores**: If confidence is close (gap < 0.15), the rule with higher NES takes precedence
3. **Compare specificity**: More specific rules override more general rules (e.g., "post-board + end-of-quarter" overrides both "post-board" and "end-of-quarter" individually)
4. **Temporal recency**: If all else is equal, the more recently confirmed rule takes precedence
5. **Opus arbitration**: If the conflict cannot be resolved mechanically, Opus evaluates the specific situation in the next nightly cycle and either:
   - Creates a new compound rule that handles the overlap case
   - Suspends one of the conflicting rules
   - Adds an exception to one of the rules

### 6.3 Conflict Groups

Rules that share trigger conditions are assigned to the same `conflict_group`. The rule engine checks for conflicts within groups before activating any rule. This prevents contradictory recommendations from reaching the user.

---

## 7. Rule Generation Process

### 7.1 Nightly Pipeline

```
┌──────────────────────────────────────────────────────────────┐
│                  NIGHTLY RULE GENERATION                      │
│                                                              │
│  INPUT:                                                      │
│  ├── Candidate rules from synthesis stage                    │
│  ├── Existing active rules (for conflict checking)           │
│  ├── Effectiveness data from past 24h                        │
│  ├── User feedback on rule-driven recommendations            │
│  └── User semantic profile                                   │
│                                                              │
│  STEP 1: Candidate Evaluation                                │
│  ├── Confidence check (>= 0.60)                              │
│  ├── Specificity check (trigger is programmatic)             │
│  ├── Measurability check (outcome is trackable)              │
│  └── Pass qualifying candidates to Opus                      │
│                                                              │
│  STEP 2: Opus Rule Review (API call)                         │
│  ├── Evaluate each candidate against:                        │
│  │   ├── Full rule set (conflict detection)                  │
│  │   ├── User profile (is this relevant to this person?)     │
│  │   ├── Counter-evidence (are there exceptions?)            │
│  │   └── Phrasing (is the recommendation clear and useful?)  │
│  ├── Promote approved candidates to active                   │
│  ├── Reject candidates with reasons                          │
│  ├── Create compound rules for overlap cases                 │
│  └── Add exceptions to existing rules where needed           │
│                                                              │
│  STEP 3: Effectiveness Review                                │
│  ├── Calculate NES for all active rules with new data        │
│  ├── Update confidence scores                                │
│  ├── Suspend rules with NES < 0.0 for 2+ cycles             │
│  ├── Deprecate rules suspended 30+ days                      │
│  └── Log all state transitions                               │
│                                                              │
│  STEP 4: Surface Text Generation                             │
│  ├── Generate morning_session_text for all active rules      │
│  │   that are triggered by tomorrow's context                │
│  ├── Generate alert_text for threshold-based rules           │
│  └── Generate menu_bar_text for always-visible rules         │
│                                                              │
│  OUTPUT:                                                     │
│  ├── Updated rule store                                      │
│  ├── Tomorrow's applicable rules (for morning session)       │
│  └── Active alert thresholds (for real-time monitoring)      │
└──────────────────────────────────────────────────────────────┘
```

---

## 8. Rule Examples

### 8.1 Time-Based Protection Rule

```json
{
  "definition": {
    "trigger": {
      "type": "time",
      "description": "Monday morning strategic window",
      "conditions": [
        {"field": "day_of_week", "operator": "equals", "value": "monday"},
        {"field": "time", "operator": "within_range", "value": ["09:00", "11:30"]}
      ]
    },
    "context": {
      "description": "No existing immovable commitment in the window",
      "conditions": [
        {"field": "calendar.has_immovable_event", "operator": "equals", "value": false}
      ]
    },
    "recommendation": {
      "action_type": "protect",
      "description": "Protect this window from meetings. Schedule strategic work here. This is your highest-output slot of the week.",
      "specificity": "time_specific",
      "urgency": "proactive"
    }
  },
  "confidence": {"score": 0.79},
  "provenance": {
    "source_insight_title": "Monday Morning Strategic Clarity Window",
    "evidence_summary": "8 weeks of data: Monday 9-11:30 produces 2.3x longer focus sessions and highest document output quality of any weekly slot."
  }
}
```

### 8.2 Event-Triggered Avoidance Rule

```json
{
  "definition": {
    "trigger": {
      "type": "event",
      "description": "Board meeting concluded",
      "conditions": [
        {"field": "calendar.event_category", "operator": "equals", "value": "board_meeting"},
        {"field": "calendar.event_status", "operator": "equals", "value": "concluded"}
      ]
    },
    "context": {
      "description": "Within 72 hours of board meeting conclusion",
      "conditions": [
        {"field": "hours_since_trigger", "operator": "less_than", "value": 72}
      ]
    },
    "recommendation": {
      "action_type": "avoid",
      "description": "Avoid scheduling strategic work (document creation, strategy sessions, long-form writing) in this window. Schedule operational tasks, 1:1s, or email processing instead.",
      "specificity": "time_specific",
      "urgency": "at_trigger"
    }
  },
  "confidence": {"score": 0.82},
  "provenance": {
    "source_insight_title": "Post-Board Fatigue Cycle",
    "evidence_summary": "3 board cycles over 42 days. Strategic output drops 64%, email latency spikes 2.1x, optional meeting acceptance rises 40% in 72h post-board."
  }
}
```

### 8.3 Threshold-Based Alert Rule

```json
{
  "definition": {
    "trigger": {
      "type": "threshold",
      "description": "People-decision backlog exceeds safe level",
      "conditions": [
        {"field": "tasks.category_people.pending_count", "operator": "greater_than", "value": 3},
        {"field": "tasks.category_people.oldest_pending_days", "operator": "greater_than", "value": 7}
      ]
    },
    "context": {
      "description": "Not in a period of known external constraint (travel, off-site, holiday)",
      "conditions": [
        {"field": "calendar.user_available", "operator": "equals", "value": true}
      ]
    },
    "recommendation": {
      "action_type": "alert",
      "description": "Your people-decision backlog is growing. You currently have 4 pending people decisions, oldest is 11 days. Your historical pattern shows deferred people decisions take 3x longer to resolve per week of delay. Consider scheduling a decision-making block this week.",
      "specificity": "task_specific",
      "urgency": "within_24h"
    }
  },
  "confidence": {"score": 0.71},
  "provenance": {
    "source_insight_title": "End-of-Quarter People Decision Bottleneck",
    "evidence_summary": "2 quarters of data. People decisions deferred at 3.4x rate of operational. Resolution time increases proportionally to deferral duration."
  }
}
```

### 8.4 Decision Quality Reframe Rule

```json
{
  "definition": {
    "trigger": {
      "type": "compound",
      "description": "People decision being made in afternoon low-quality window",
      "conditions": [
        {"field": "current_activity.type", "operator": "equals", "value": "people_decision"},
        {"field": "time", "operator": "greater_than", "value": "15:00"}
      ],
      "compound_logic": "AND"
    },
    "context": {
      "description": "Decision appears to be nearing commitment (email draft, meeting scheduled)",
      "conditions": [
        {"field": "activity.engagement_signal", "operator": "equals", "value": "commitment_approaching"}
      ]
    },
    "recommendation": {
      "action_type": "reframe",
      "description": "You're about to commit to a people decision at [time]. Your afternoon people decisions are reversed 44% of the time — compared to 8% for those made before 11am. Consider sleeping on it.",
      "specificity": "time_specific",
      "urgency": "at_trigger"
    }
  },
  "confidence": {"score": 0.65},
  "provenance": {
    "source_insight_title": "Afternoon Decision Quality Degradation",
    "evidence_summary": "18 days of data. Post-3pm people decisions reversed 44% vs 8% pre-11am. Effect strongest for people decisions, weaker for operational."
  }
}
```

---

## 9. Rule Store Architecture

### 9.1 On-Device

CoreData entity `ProceduralRule` with all schema fields. Rules are loaded into memory at app launch for real-time trigger evaluation.

The real-time rule engine runs as a background service that:
1. Monitors incoming signals against all active rule trigger conditions
2. When a trigger fires, evaluates context conditions
3. If all conditions are met, queues the recommendation for delivery via the appropriate channel (morning session, alert, menu bar)
4. Logs the trigger event for effectiveness tracking

### 9.2 Remote

Supabase `procedural_rules` table, synced nightly after the rule generation stage completes. Remote storage serves as backup and enables future cross-device sync.

### 9.3 Rule Set Size Expectations

| Timeframe | Expected active rules | Expected total rules (all statuses) |
|-----------|----------------------|-------------------------------------|
| Month 1 | 0-3 | 0-5 candidates |
| Month 3 | 5-12 | 15-25 (including candidates and rejected) |
| Month 6 | 12-25 | 40-60 |
| Month 12 | 20-40 | 80-120 |

The rule set should not grow unboundedly. Deprecated rules are archived. The active set should stabilise at 20-40 rules for most executives — this represents the core operating principles of a person, which are finite.

---

## 10. Performance Budgets

| Metric | Budget |
|--------|--------|
| Candidate evaluation (on-device) | < 5 seconds |
| Opus rule review call | < 90 seconds API time, < 20K input tokens, < 5K output tokens |
| Effectiveness calculation | < 10 seconds on-device |
| Surface text generation | Included in Opus call |
| Total Stage 4 time | < 2 minutes |

Rule generation is the lightest stage of the nightly pipeline (smallest context, most constrained output). Approximately $0.30-0.50/night.

---

## 11. Total Nightly Pipeline Summary

| Stage | Purpose | Opus cost/night | Time budget |
|-------|---------|----------------|-------------|
| Stage 1: Episodic Summarisation | Compress 24h of raw memories | $0.30-0.50 | 2 min |
| Stage 2: First-Order Extraction | Find patterns in raw data | $0.50-0.80 | 3 min |
| Stage 3: Second-Order Synthesis | Combine patterns into insights | $0.80-1.20 | 4 min |
| Stage 4: Rule Generation | Convert insights to operating rules | $0.30-0.50 | 2 min |
| Stage 5: Model Update | Update semantic memory + morning prep | $0.40-0.60 | 2 min |
| **Total** | | **$2.30-3.60** | **~13 min** |

This is approximately $70-110/month per user. Per the design principle: no cost cap on intelligence quality. This cost IS the product.
