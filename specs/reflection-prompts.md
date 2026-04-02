# Reflection Engine Prompt Templates Spec

> Timed — Layer 3 Reflection Engine, LLM Prompt Architecture
> Version: 1.0 | 2026-04-02
> Model: Claude Opus 4.6 at maximum reasoning effort
> Runs: Nightly, 6-stage pipeline
> Total estimated token budget: ~150K input + ~40K output per nightly cycle

---

## 1. Purpose

This document defines the exact LLM prompt structures for each stage of the nightly reflection pipeline. These are the prompts that produce Timed's intelligence. They are the single most important technical artifact in the system — the quality of these prompts directly determines the quality of the product.

Each template specifies:
- System prompt structure
- Memory injection format (what context is loaded)
- Output JSON schema (what the model must produce)
- Few-shot examples (what good output looks like)
- Quality evaluation criteria (how to assess output quality)

---

## 2. Prompt Versioning Strategy

### 2.1 Version Format

```
{stage_name}-v{major}.{minor}.{patch}
```

Example: `first-order-extraction-v1.2.0`

- **Major**: Structural change to the prompt (new sections, removed sections, fundamentally different approach)
- **Minor**: Significant content change (new detection categories, changed confidence thresholds, new few-shot examples)
- **Patch**: Wording refinements, formatting changes, typo fixes

### 2.2 Version Storage

Prompt templates are stored as versioned JSON documents in the `prompt_templates` Supabase table:

```json
{
  "template_id": "uuid",
  "stage": "episodic_summarisation | first_order_extraction | second_order_synthesis | rule_generation | model_update | morning_session_script",
  "version": "1.0.0",
  "is_active": true,
  "system_prompt": "string",
  "memory_injection_schema": {},
  "output_schema": {},
  "few_shot_examples": [],
  "created_at": "ISO-8601",
  "performance_metrics": {}
}
```

Only one version per stage is `is_active = true` at any time. The nightly pipeline loads the active version for each stage.

### 2.3 A/B Testing

For prompt improvements, both the old and new version can be run on the same nightly data. Outputs are compared by the quality evaluation criteria (Section 9). If the new version scores higher on 3 consecutive nights, it is promoted to active.

---

## 3. Stage 1: Episodic Summarisation

**Purpose**: Compress the raw episodic memories from the past 24 hours into a structured daily summary that fits within the context window for subsequent stages.

**Version**: `episodic-summarisation-v1.0.0`

### 3.1 System Prompt

```
You are the memory consolidation system for Timed, a cognitive intelligence layer for a C-suite executive. Your role is to compress one day of raw episodic observations into a structured daily summary.

You are NOT generating insights or patterns. You are creating a faithful, compressed representation of what happened today — preserving all details that could be relevant for pattern detection, while removing noise and redundancy.

Principles:
- Preserve timestamps, durations, and quantities exactly. Never round or approximate.
- Preserve the identity of people involved in every interaction.
- Preserve emotional/tonal signals (email tone, voice energy, communication shifts).
- Preserve absence signals — what did NOT happen that was expected? (Skipped routines, unanswered emails, cancelled meetings.)
- Preserve sequence — the order of events matters for pattern detection.
- Compress repetitive low-signal events (e.g., 47 routine emails can become "47 routine emails processed between 7:15-7:45am and 5:30-6:10pm").
- Never interpret. Never explain why something happened. Record WHAT happened.

Output format: Structured JSON conforming to the schema below.
```

### 3.2 Memory Injection Format

```json
{
  "date": "2026-04-02",
  "user_profile_summary": "Brief semantic memory summary — role, key contacts, current priorities",
  "episodic_memories": [
    {
      "memory_id": "uuid",
      "timestamp": "ISO-8601",
      "source": "email | calendar | task | focus | voice | app_usage | system",
      "raw_content": "The full episodic memory content",
      "importance_score": 0.0,
      "metadata": {}
    }
  ],
  "expected_events_that_did_not_occur": [
    "Description of expected but absent events (e.g., 'Weekly 1:1 with Head of Product was on calendar but was cancelled at 11:15am')"
  ],
  "previous_day_summary": "Yesterday's daily summary (for continuity)"
}
```

### 3.3 Output JSON Schema

```json
{
  "daily_summary": {
    "date": "2026-04-02",
    "day_of_week": "Wednesday",

    "timeline": [
      {
        "time_window": "07:10-07:48",
        "category": "email_triage",
        "description": "Processed 34 emails. Replied to 8 (avg 45 words). Flagged 3 for follow-up. Deferred CFO email re: Q3 budget (opened, read, no reply).",
        "notable_signals": ["CFO email deferred", "reply volume below 10-day average"],
        "people_involved": ["CFO", "Head of Ops", "PA"],
        "duration_minutes": 38
      }
    ],

    "meetings": [
      {
        "time": "10:00-11:30",
        "title": "Board Committee - Governance",
        "attendees": 8,
        "key_attendees": ["Board Chair", "CFO", "General Counsel"],
        "duration_minutes": 90,
        "post_meeting_latency_minutes": 52,
        "post_meeting_first_action": "Opened email, did not compose"
      }
    ],

    "tasks": {
      "planned": ["Restructuring proposal", "Vendor contract review", "Q3 budget response", "Team sync prep"],
      "completed": ["Team sync prep", "3 email follow-ups"],
      "deferred": ["Restructuring proposal (3rd consecutive deferral)", "Vendor contract review"],
      "new": ["Board follow-up action items (2)"]
    },

    "focus_sessions": [
      {
        "start": "14:15",
        "planned_duration_minutes": 45,
        "actual_duration_minutes": 18,
        "task": "Restructuring proposal",
        "interruptions": 2,
        "outcome": "Abandoned — switched to email after 18 minutes"
      }
    ],

    "communication_signals": {
      "total_emails_sent": 12,
      "total_emails_received": 67,
      "avg_response_time_minutes": 142,
      "notable_non_responses": ["CFO Q3 budget email (8h, still pending)", "Legal compliance thread (3rd day unresponded)"],
      "tone_shifts": ["Emails to COO noticeably shorter than last week (avg 34 words vs 89)"]
    },

    "absence_signals": [
      "No work on restructuring proposal (planned, 3rd consecutive day)",
      "Weekly 1:1 with Head of Product cancelled (2nd in 3 weeks)",
      "No strategic document creation today"
    ],

    "voice_session": {
      "occurred": true,
      "duration_seconds": 87,
      "energy_level": "moderate",
      "key_topics": ["board prep", "team capacity concern"],
      "notable_statements": ["'I need to get to the restructuring thing but there's never a good time'"]
    },

    "day_level_signals": {
      "total_productive_hours": 5.2,
      "meeting_hours": 3.5,
      "strategic_time_hours": 0.3,
      "operational_time_hours": 4.1,
      "app_switches": 147,
      "avg_focus_session_minutes": 22
    }
  }
}
```

### 3.4 Few-Shot Example

*One complete input-output pair is stored with the template. Abbreviated here:*

**Input snippet**: 127 raw episodic memories from a sample day
**Output snippet**: The JSON structure above, demonstrating proper compression (127 memories → structured summary with ~30 meaningful entries)

### 3.5 Token Budget

- Input: ~25K tokens (user profile + raw episodic memories + previous day summary)
- Output: ~4K tokens (daily summary JSON)
- Total: ~29K tokens per nightly run

---

## 4. Stage 2: First-Order Pattern Extraction

**Purpose**: Identify regularities in the raw data — temporal, behavioural, relational, cognitive, and avoidance patterns.

**Version**: `first-order-extraction-v1.0.0`

### 4.1 System Prompt

```
You are the pattern detection system for Timed, a cognitive intelligence layer for a C-suite executive. Your role is to identify first-order patterns — regularities in behaviour, timing, communication, cognition, and avoidance — from observed data.

A first-order pattern is a statement about observed regularity with statistical backing. It is NOT an interpretation, recommendation, or insight. You describe WHAT is happening, not WHY.

Pattern taxonomy (classify every pattern into exactly one):
- TEMPORAL: Time-based regularities (clock_regularity, day_of_week_effect, calendar_relative, post_event_latency, cyclic_drift)
- BEHAVIOURAL: Action patterns (action_sequence, duration_regularity, completion_pattern, substitution, batch_preference)
- RELATIONAL: Communication patterns (response_priority, communication_frequency_shift, sentiment_trend, selective_non_response, channel_switching)
- COGNITIVE: Decision/thinking patterns (decision_latency, decision_quality_window, information_seeking, revision_intensity, cognitive_throughput)
- AVOIDANCE: Resistance patterns (task_avoidance, conversation_avoidance, decision_avoidance, category_avoidance, approach_retreat)

Evidence thresholds:
- Minimum 3 supporting observations to report a pattern
- Minimum 5-day span for temporal/behavioural patterns
- Minimum 7-day span for relational/cognitive/avoidance patterns
- Always count counter-evidence. A pattern with 5 supporting and 4 counter observations is weak — report it but flag the weakness.

For each pattern, provide:
- Exact observation counts and timeframes
- Specific numbers, dates, and names — never vague language
- Statistical basis where applicable (mean, median, standard deviation, comparison to baseline)
- Counter-evidence count and description
- Confidence score (0.30-0.95, using the formula: observation_weight * span_weight * consistency_weight)

You are processing the STATISTICAL CANDIDATES from the pre-processing stage plus the raw daily summaries. Some candidates will be real patterns. Some will be noise. Some real patterns will not appear in the candidates — find them.

CRITICAL: Prioritise avoidance patterns. They are the highest-value intelligence Timed produces. Look specifically for: repeated deferrals, opened-but-not-edited documents, selective non-responses, substitution behaviour, and approach-retreat cycles.
```

### 4.2 Memory Injection Format

```json
{
  "current_date": "2026-04-02",
  "user_profile": {
    "role": "CEO",
    "key_contacts": ["Board Chair", "CFO", "COO", "Head of Product", "Head of Ops", "PA"],
    "stated_priorities": ["Product strategy", "Board governance reform", "Asia expansion"],
    "known_tendencies": ["Defers people decisions", "High operational throughput preference"]
  },

  "statistical_candidates": [
    {
      "candidate_id": "uuid",
      "description": "Friday Board email response latency 2.1x weekday average",
      "method": "distribution_comparison",
      "supporting_data_points": 11,
      "counter_data_points": 3,
      "span_days": 21,
      "p_value": 0.003
    }
  ],

  "daily_summaries": {
    "today": { "...full Stage 1 output..." },
    "past_7_days": [ "...abbreviated daily summaries..." ]
  },

  "existing_patterns": [
    {
      "pattern_id": "uuid",
      "title": "Monday morning focus window",
      "category": "temporal",
      "subtype": "clock_regularity",
      "confidence": 0.74,
      "last_observed": "2026-03-31",
      "supporting_count": 9,
      "counter_count": 2
    }
  ]
}
```

### 4.3 Output JSON Schema

```json
{
  "extraction_date": "2026-04-02",
  "new_patterns": [
    {
      "title": "Strategic document approach-retreat on restructuring proposal",
      "category": "avoidance",
      "subtype": "approach_retreat",
      "summary": "Restructuring proposal opened 7 times in 14 days, average session 2.4 minutes, no meaningful edits saved in any session.",
      "detail": "Between 2026-03-19 and 2026-04-02, the restructuring proposal document was opened 7 times. Session durations: 1.5min, 3.2min, 2.1min, 4.0min, 1.8min, 2.5min, 1.7min. No session produced saved changes. 5 of 7 sessions occurred in the first 30 minutes of a planned focus block, followed by switching to email.",
      "supporting_observations": ["mem_001", "mem_015", "mem_023", "mem_041", "mem_058", "mem_072", "mem_089"],
      "counter_observations": [],
      "supporting_count": 7,
      "counter_count": 0,
      "first_observed": "2026-03-19",
      "last_observed": "2026-04-02",
      "observation_span_days": 14,
      "statistical_basis": {
        "method": "llm_only",
        "notes": "Not detected by statistical pre-processing — requires understanding that short sessions with no saves on the same document constitute a pattern"
      },
      "confidence_score": 0.72,
      "confidence_calculation": "observation_weight(min(1,7/20)=0.35) * span_weight(min(1,14/28)=0.50) * consistency_weight(7/(7+0*1.5)=1.0) = 0.175 — adjusted upward to 0.72 because zero counter-evidence and strong behavioural signal (approach-retreat with substitution)"
    }
  ],

  "reinforced_patterns": [
    {
      "pattern_id": "uuid (existing pattern)",
      "new_supporting_observations": ["mem_044"],
      "new_counter_observations": [],
      "updated_confidence": 0.77,
      "notes": "Monday morning focus window confirmed again — 52-minute uninterrupted session today"
    }
  ],

  "contradicted_patterns": [
    {
      "pattern_id": "uuid",
      "contradiction_evidence": ["mem_067"],
      "updated_confidence": 0.58,
      "notes": "Thursday strategic output was unexpectedly high — may need to revisit the Thursday-Friday operational bias pattern"
    }
  ],

  "meta_observations": [
    "The avoidance cluster around the restructuring proposal is deepening. Three separate avoidance signals now converge: approach-retreat on the document, selective non-response to the COO's restructuring emails, and 1:1 cancellation with Head of Product (who owns the implementation). This may warrant second-order synthesis."
  ]
}
```

### 4.4 Token Budget

- Input: ~35K tokens (user profile + statistical candidates + daily summaries + existing patterns)
- Output: ~8K tokens (new/reinforced/contradicted patterns + meta observations)
- Total: ~43K tokens

---

## 5. Stage 3: Second-Order Synthesis

**Purpose**: Combine first-order patterns across domains into named insights with explanatory narratives.

**Version**: `second-order-synthesis-v1.0.0`

### 5.1 System Prompt

```
You are the insight synthesis engine for Timed, a cognitive intelligence layer for a C-suite executive. Your role is to find MEANING in patterns — to connect regularities across different domains into named insights that explain behaviour, predict outcomes, and suggest actionable changes.

First-order patterns tell you WHAT is happening. Your job is to explain WHAT IT MEANS when multiple patterns are considered together.

Rules:
1. Every insight must draw from at least 2 first-order patterns from at least 2 different domains (calendar, email, task, focus, voice, behaviour).
2. Correlation is not causation. Always consider alternative explanations. If you can't distinguish the insight from coincidence, say so and score confidence accordingly.
3. Temporal alignment is required. The contributing patterns must co-occur, follow a consistent sequence, or show inverse cycling. Patterns with no temporal relationship don't combine into insights.
4. Name insights using specific, human-readable titles under 60 characters. Include the relevant context (person, time, topic). Never use generic labels.
5. For each insight, draft the morning session surface text — the exact words the system would use to communicate this to the executive. The text must be:
   - Specific (names, numbers, dates — never "sometimes" or "often")
   - Evidence-based (cite observation counts and timeframes)
   - Non-judgmental (describe behaviour, don't evaluate character)
   - Actionable when possible (what could the executive do differently?)
   - Respectful of the executive's intelligence (no patronising, no motivational language)
6. Score actionability: can this insight produce a concrete IF-THEN rule? If yes, draft the candidate rule.
7. Check existing insights for reinforcement, contradiction, or merger opportunities.

CRITICAL: The morning session text is what the user sees. It must sound like a brilliant, discreet chief of staff — not a therapist, not a productivity coach, not a chatbot. Direct. Specific. Intelligent. Brief.
```

### 5.2 Memory Injection Format

```json
{
  "current_date": "2026-04-02",
  "user_profile": { "...full semantic memory profile..." },

  "first_order_patterns": [
    {
      "pattern_id": "uuid",
      "title": "string",
      "category": "string",
      "subtype": "string",
      "confidence": 0.0,
      "summary": "string",
      "detail": "string",
      "supporting_count": 0,
      "counter_count": 0,
      "first_observed": "ISO-8601",
      "last_observed": "ISO-8601",
      "observation_span_days": 0,
      "domain": "calendar | email | task | focus | voice | behaviour"
    }
  ],

  "cross_domain_pairs": [
    {
      "pair_id": "uuid",
      "pattern_a": "uuid",
      "pattern_b": "uuid",
      "domain_a": "string",
      "domain_b": "string",
      "temporal_alignment": "co_occurrence | sequential | inverse_cycle | none",
      "correlation_score": 0.0
    }
  ],

  "existing_insights": [
    {
      "insight_id": "uuid",
      "title": "string",
      "status": "string",
      "confidence": 0.0,
      "contributing_pattern_ids": ["uuid"],
      "morning_session_text": "string",
      "last_updated": "ISO-8601"
    }
  ],

  "calendar_lookahead_7d": [
    {
      "date": "2026-04-03",
      "events": ["Board Committee 10:00-12:00", "1:1 CFO 14:00-14:30", "Team Sync 16:00-16:45"]
    }
  ],

  "recent_user_feedback": [
    {
      "insight_id": "uuid",
      "feedback": "confirmed | dismissed | corrected",
      "correction_text": "string | null",
      "date": "ISO-8601"
    }
  ]
}
```

### 5.3 Output JSON Schema

```json
{
  "synthesis_date": "2026-04-02",

  "new_insights": [
    {
      "title": "Post-Board Fatigue Cycle",
      "one_liner": "Board meetings trigger a 72-hour cognitive recovery period that suppresses strategic output",
      "contributing_patterns": [
        {"pattern_id": "uuid", "role": "Primary signal"},
        {"pattern_id": "uuid", "role": "Corroborating signal"},
        {"pattern_id": "uuid", "role": "Compensatory behaviour"}
      ],
      "cross_domain_count": 3,
      "temporal_relationship": "sequential",
      "temporal_detail": "0-72 hours after board meeting conclusion",
      "narrative": "After your last three board meetings, strategic output dropped 64% for about 72 hours. Email response latency doubled. You filled the time with optional meetings and email processing. The pattern is consistent across all 3 observed cycles.",
      "alternative_explanations": "Possible confound: two of the three board meetings fell on Thursdays, and Thursday-Friday operational bias is a separate pattern. However, the third board meeting was on a Tuesday and showed the same recovery pattern, suggesting the board meeting — not the day of week — is the driver.",
      "morning_session_text": "Your board committee meeting is Thursday. Over the past 6 weeks, your strategic output has dropped significantly in the 72 hours after each board meeting — you shift to email and optional meetings instead. The pattern has held across all 3 cycles. I'd suggest keeping Friday and Monday light on strategic commitments.",
      "confidence": 0.68,
      "confidence_calculation": "geometric_mean(0.74, 0.71, 0.62) = 0.69 * alignment_factor(0.85) * evidence_depth(1.0) = 0.59 — adjusted to 0.68 because zero counter-evidence across 3 full cycles",
      "actionability_score": 0.82,
      "candidate_rule": {
        "trigger": "Board meeting concluded within past 72 hours",
        "recommendation": "Avoid scheduling strategic work. Prefer operational tasks, 1:1s, and email processing.",
        "expected_outcome": "Strategic output quality maintained by respecting recovery window"
      }
    }
  ],

  "updated_insights": [
    {
      "insight_id": "uuid",
      "update_type": "reinforced | weakened | revised | merged",
      "new_confidence": 0.0,
      "update_notes": "string"
    }
  ],

  "model_corrections": [
    {
      "correction_type": "semantic_memory_update | pattern_reclassification | insight_dissolution",
      "description": "string",
      "evidence": "string"
    }
  ],

  "morning_session_candidates": [
    {
      "insight_id": "uuid",
      "priority": 1,
      "reason_for_inclusion": "Proactive — board meeting is in 2 days, this insight is directly relevant",
      "surface_text": "string"
    }
  ]
}
```

### 5.4 Token Budget

- Input: ~50K tokens (full pattern inventory + existing insights + calendar lookahead + user profile)
- Output: ~12K tokens (new insights + updates + morning candidates)
- Total: ~62K tokens

---

## 6. Stage 4: Rule Generation

**Purpose**: Convert actionable insights into IF-THEN procedural rules.

**Version**: `rule-generation-v1.0.0`

### 6.1 System Prompt

```
You are the rule generation engine for Timed, a cognitive intelligence layer for a C-suite executive. Your role is to convert actionable insights into precise, testable IF-THEN rules that the system can evaluate in real time.

A rule encodes a learned operating principle about this specific executive. It is the highest compression of intelligence: months of observation → patterns → insights → a single executable rule.

Rules must be:
1. PRECISE: Trigger conditions must be evaluable programmatically. "When stressed" is not a valid trigger. "When cognitive_load_score > 0.8 AND hours_since_last_break > 3" is.
2. TESTABLE: The recommendation must have a measurable outcome. "Be more strategic" is not testable. "Strategic document output volume in the recommended window" is.
3. SPECIFIC TO THIS PERSON: Rules come from this executive's data, not generic productivity advice. "Take breaks" is generic. "After meetings exceeding 90 minutes, you need 45 minutes before productive output — schedule accordingly" is personal.
4. CONSERVATIVE: Only generate rules when confidence is >= 0.60. A wrong rule is worse than no rule. Err on the side of fewer, stronger rules.
5. CONFLICT-AWARE: Check every new rule against the existing rule set. Flag conflicts. Propose resolution.

For each rule, generate three surface texts:
- morning_session_text: Full context, used when the rule is relevant to tomorrow's schedule
- alert_text: Brief, used for real-time notifications when a trigger fires
- menu_bar_text: Ultra-brief, used for glanceable display

Rule action types: avoid, prefer, protect, alert, suggest, reframe.
```

### 6.2 Output JSON Schema

```json
{
  "generation_date": "2026-04-02",

  "new_rules": [
    {
      "source_insight_id": "uuid",
      "source_insight_title": "Post-Board Fatigue Cycle",
      "definition": {
        "trigger": {
          "type": "event",
          "conditions": [
            {"field": "calendar.event_category", "operator": "equals", "value": "board_meeting"},
            {"field": "calendar.event_status", "operator": "equals", "value": "concluded"}
          ]
        },
        "context": {
          "conditions": [
            {"field": "hours_since_trigger", "operator": "less_than", "value": 72}
          ]
        },
        "recommendation": {
          "action_type": "avoid",
          "description": "Avoid scheduling strategic work. Prefer operational tasks, 1:1s, and email processing.",
          "specificity": "time_specific",
          "urgency": "at_trigger"
        }
      },
      "confidence": 0.82,
      "conflicts_with": [],
      "surface": {
        "morning_session_text": "Your board meeting is Thursday. Your strategic output drops significantly for about 72 hours post-board. I'd suggest keeping Friday and Monday light on strategic commitments.",
        "alert_text": "Post-board recovery window active — strategic work deferred to Tuesday.",
        "menu_bar_text": "Post-board: light strategic load"
      }
    }
  ],

  "rule_effectiveness_updates": [
    {
      "rule_id": "uuid",
      "new_nes": 0.34,
      "new_confidence": 0.85,
      "status_change": "none | suspended | deprecated",
      "notes": "Rule followed 3 times, positive outcome each time"
    }
  ],

  "conflict_resolutions": [
    {
      "rule_a_id": "uuid",
      "rule_b_id": "uuid",
      "conflict_type": "direct_contradiction | resource_competition | conditional_overlap",
      "resolution": "Rule A takes precedence (higher confidence: 0.82 vs 0.61)",
      "compound_rule_created": false
    }
  ],

  "tomorrow_applicable_rules": [
    {
      "rule_id": "uuid",
      "trigger_context": "Board committee meeting at 10:00 tomorrow",
      "recommendation_summary": "Protect Friday and Monday from strategic work"
    }
  ]
}
```

### 6.3 Token Budget

- Input: ~20K tokens (candidate rules + existing rule set + effectiveness data + user profile)
- Output: ~5K tokens (new rules + updates + tomorrow's applicable rules)
- Total: ~25K tokens

---

## 7. Stage 5: Model Update

**Purpose**: Update the user's semantic memory with confirmed facts, reinforce or weaken existing semantic memories, and prepare the morning session context.

**Version**: `model-update-v1.0.0`

### 7.1 System Prompt

```
You are the memory consolidation system for Timed. Your role is to update the executive's long-term semantic model based on tonight's reflection outputs.

Semantic memories are FACTS about the executive — stable characteristics, confirmed tendencies, relationship dynamics, and cognitive patterns that have been validated through repeated observation.

Your tasks:
1. PROMOTE: Identify insights and patterns that have reached sufficient confidence to become permanent semantic memories. A pattern observed for 30+ days with confidence > 0.80 should be encoded as a fact about this person.
2. REINFORCE: Update confidence and recency scores on existing semantic memories that were supported by tonight's data.
3. WEAKEN: Reduce confidence on semantic memories that were contradicted by tonight's data.
4. CORRECT: When tonight's synthesis identified a model correction, apply it. Explain what changed and why.
5. PRUNE: Flag semantic memories that haven't been reinforced in 60+ days for review. Don't delete — flag.
6. MORNING PREP: Assemble the context package for tomorrow's morning session. Select the most relevant semantic memories, active insights, and applicable rules for the Morning Director.

The semantic model is the system's understanding of who this person IS. It should be getting more accurate over time. Every update should make the model slightly truer.
```

### 7.2 Output JSON Schema

```json
{
  "update_date": "2026-04-02",

  "new_semantic_memories": [
    {
      "content": "This executive requires approximately 72 hours of cognitive recovery after board meetings, during which strategic output is significantly reduced.",
      "category": "energy_pattern",
      "confidence": 0.82,
      "source_pattern_ids": ["uuid", "uuid"],
      "source_insight_id": "uuid"
    }
  ],

  "reinforced_memories": [
    {
      "memory_id": "uuid",
      "previous_confidence": 0.74,
      "new_confidence": 0.77,
      "reinforcement_evidence": "Monday morning focus window confirmed for 10th time"
    }
  ],

  "weakened_memories": [
    {
      "memory_id": "uuid",
      "previous_confidence": 0.68,
      "new_confidence": 0.61,
      "weakening_evidence": "Thursday strategic output was unexpectedly high, contradicting the 'Thursday is purely operational' model"
    }
  ],

  "corrections": [
    {
      "memory_id": "uuid",
      "previous_content": "This executive's best decision-making window is Thursday morning",
      "corrected_content": "This executive's best decision-making window is Tuesday morning. Thursday's apparent quality was an artifact of operational decision volume, not strategic decision quality.",
      "evidence": "Decision reversal analysis across 30 days shows Tuesday morning decisions reversed at 6% vs Thursday morning at 19%"
    }
  ],

  "flagged_for_review": [
    {
      "memory_id": "uuid",
      "content": "This executive prefers written communication for all financial discussions",
      "last_reinforced": "2026-02-01",
      "days_since_reinforcement": 60,
      "recommendation": "Review — may have been based on insufficient early data"
    }
  ],

  "morning_context_package": {
    "top_semantic_memories": ["memory_id_1", "memory_id_2", "..."],
    "active_insights_for_tomorrow": ["insight_id_1", "insight_id_2", "..."],
    "applicable_rules_for_tomorrow": ["rule_id_1", "rule_id_2", "..."],
    "proactive_alerts": ["Board meeting Thursday — post-board recovery window applies"],
    "calendar_summary_tomorrow": "4 meetings (2 optional), strategic block at 9am, 1:1 with CFO at 2pm"
  }
}
```

### 7.3 Token Budget

- Input: ~25K tokens (all stage outputs + existing semantic memory + calendar)
- Output: ~6K tokens (memory updates + morning context package)
- Total: ~31K tokens

---

## 8. Stage 6: Morning Session Script Generation

**Purpose**: Generate the script for tomorrow's morning intelligence session — the primary user-facing output of the entire system.

**Version**: `morning-session-script-v1.0.0`

### 8.1 System Prompt

```
You are the Morning Director for Timed. You are about to brief a C-suite executive on what their cognitive intelligence system has observed, learned, and recommends.

This is NOT a task list. This is NOT a productivity summary. This is a cognitive briefing from a system that has spent the night thinking about this person.

Structure (strict order):
1. OPENING OBSERVATION — One sentence that demonstrates the system understands the executive. Reference a specific pattern, insight, or observation. This must feel personal and intelligent. Never generic.
2. TODAY'S LANDSCAPE — What the day looks like: schedule density, meeting load, energy forecast based on their model, any rules that apply today.
3. NAMED PATTERNS (1-2 max) — The most relevant active insight(s) for today's context. Full evidence, specific numbers. These are the core intelligence deliverables.
4. AVOIDANCE CHECK (if applicable) — Direct, specific, evidence-based. What are they avoiding? How long? What's the cost of continued avoidance? This is the hardest thing to say — say it clearly and respectfully.
5. DECISION QUALITY NOTE (if applicable) — If a major decision is on today's agenda, surface the conditions for their best decisions and flag any risk factors (time of day, prior meeting load, fatigue).
6. ONE QUESTION — End with exactly one question that invites reflection. Not a rhetorical question. A genuine question that the system wants the answer to because it will improve the model.

Tone: A brilliant, discreet chief of staff. Direct. Specific. Intelligent. Brief. No filler. No motivation. No "Great morning!" No emojis. No bullet points — this is spoken, not read.

Word count: 200-350 words. The executive has 90 seconds.
```

### 8.2 Memory Injection Format

```json
{
  "morning_context_package": "...from Stage 5 output...",
  "user_semantic_profile": "...full profile...",
  "today_calendar": ["...full day schedule..."],
  "yesterday_summary": "...from Stage 1...",
  "active_insights_with_surface_text": ["...relevant insight texts..."],
  "applicable_rules_with_surface_text": ["...relevant rule texts..."],
  "pending_avoidance_patterns": ["...any active avoidance patterns..."],
  "pending_user_questions": ["...questions from previous sessions the user hasn't answered..."],
  "previous_morning_sessions": ["...last 3 session scripts for continuity..."]
}
```

### 8.3 Output JSON Schema

```json
{
  "session_date": "2026-04-03",
  "script": {
    "opening_observation": "The restructuring proposal has been on your radar for 18 days now. You've opened the document 7 times without making changes. That pattern is worth naming.",
    "todays_landscape": "Today: 4 meetings totalling 3.5 hours, including the board committee at 10. Your model says your best output window is 8:00-9:45 before the board session. After the board meeting, expect about 90 minutes of recovery before productive work resumes. Your afternoon is lighter — two optional meetings you could decline.",
    "named_patterns": "Post-board recovery is something your data shows clearly. After each of your last three board meetings, strategic output dropped for about 72 hours. You compensated with email and optional meetings — productive, but not high-leverage. Tomorrow and Monday will be in that window. I'd suggest protecting Tuesday morning for the strategic items you're pushing to this week.",
    "avoidance_check": "The restructuring proposal. 18 days, 7 opened sessions averaging 2.4 minutes each, zero saved changes. The COO has 3 unanswered emails about the timeline. The Head of Product 1:1 — where implementation would be discussed — has been cancelled twice. These are three separate avoidance signals pointing at the same decision. The cost of deferral is compounding — your team is waiting.",
    "decision_quality_note": null,
    "closing_question": "What specifically about the restructuring proposal is creating resistance — is it the decision itself, or how it needs to be communicated?"
  },
  "word_count": 247,
  "insights_referenced": ["insight_id_1", "insight_id_2"],
  "rules_applied": ["rule_id_1"],
  "avoidance_patterns_surfaced": ["pattern_id_1"],
  "model_question_purpose": "Understanding the specific blocker will help the system distinguish between decision avoidance and communication avoidance for this executive"
}
```

### 8.4 Few-Shot Example

**Weak output** (what to avoid):
> "Good morning! You have a busy day ahead. Here's your schedule... Remember to take breaks and stay hydrated! You've got this!"

**Strong output** (the standard):
> "The restructuring proposal has been on your radar for 18 days now. You've opened the document 7 times without making changes. That pattern is worth naming.
>
> Today: board committee at 10, then a lighter afternoon. Your sharpest window is the next 90 minutes before the board session. After it ends, expect about 90 minutes of cognitive recovery before you're producing quality output again.
>
> Your post-board pattern is consistent — strategic work drops for about 72 hours while you shift to email and optional meetings. Tomorrow and Monday will be in that window. Protect Tuesday morning for the work that matters most this week.
>
> On the restructuring — the COO has 3 unanswered emails about the timeline, the Head of Product 1:1 has been cancelled twice, and the document itself has been opened 7 times with zero changes saved. That's three separate signals pointing at the same thing. Your team is in a holding pattern.
>
> What specifically about the restructuring is creating the resistance — the decision itself, or how it needs to be communicated?"

### 8.5 Token Budget

- Input: ~20K tokens (morning context package + user profile + calendar + previous sessions)
- Output: ~2K tokens (session script)
- Total: ~22K tokens

---

## 9. Quality Evaluation Criteria

### 9.1 Per-Stage Criteria

| Stage | Primary quality metric | Secondary metrics |
|-------|----------------------|-------------------|
| Stage 1: Episodic Summarisation | Information preservation — did the summary lose any detail that later stages would need? | Compression ratio, structural completeness, absence signal capture |
| Stage 2: First-Order Extraction | Precision × Recall — are the patterns real and did we catch them all? | Confidence calibration, counter-evidence handling, avoidance detection rate |
| Stage 3: Second-Order Synthesis | Explanatory power — does the insight explain more than any single pattern? | Cross-domain requirement met, temporal alignment verified, alternative explanations considered |
| Stage 4: Rule Generation | Testability — can the rule be evaluated programmatically? | Conflict detection accuracy, effectiveness prediction, surface text quality |
| Stage 5: Model Update | Accuracy — is the updated model more true than before? | Memory promotion accuracy, correction quality, morning context relevance |
| Stage 6: Morning Session | User resonance — does the executive confirm the intelligence is accurate and useful? | Specificity, actionability, tone, brevity, avoidance surfacing quality |

### 9.2 System-Level Metrics

Tracked weekly:
- **Intelligence depth**: Average number of contributing patterns per active insight (should increase over time)
- **Prediction accuracy**: When the system predicts behaviour (e.g., "you'll defer this"), how often is it correct?
- **User confirmation rate**: Percentage of surfaced insights the executive confirms vs dismisses
- **Rule effectiveness**: Average NES across active rules
- **Morning session engagement**: Does the executive respond to the closing question? (indicates the session was valuable enough to engage with)
- **Novel insight rate**: Percentage of insights that tell the user something they didn't already know (self-reported)

### 9.3 Prompt Quality Red Flags

Monitor for these failure modes:
- **Generic output**: Insights that could apply to any executive ("You're busy this week"). Trigger: lack of specific names, numbers, dates.
- **Hallucinated evidence**: Pattern claims citing observations that don't exist in the memory store. Trigger: cross-reference output against input memories.
- **Judgmental tone**: Language that evaluates character rather than describing behaviour. Trigger: sentiment analysis on surface texts.
- **Confirmation bias**: System only finding evidence for existing patterns and never discovering new ones. Trigger: new pattern rate < 1 per week after month 2.
- **Avoidance avoidance**: The system itself avoiding surfacing uncomfortable truths. Trigger: avoidance pattern surfacing rate drops despite stable avoidance signal input.

---

## 10. Total Nightly Pipeline Token Budget

| Stage | Input tokens | Output tokens | Estimated cost |
|-------|-------------|---------------|----------------|
| Stage 1: Episodic Summarisation | ~25K | ~4K | $0.35-0.50 |
| Stage 2: First-Order Extraction | ~35K | ~8K | $0.50-0.80 |
| Stage 3: Second-Order Synthesis | ~50K | ~12K | $0.80-1.20 |
| Stage 4: Rule Generation | ~20K | ~5K | $0.30-0.50 |
| Stage 5: Model Update | ~25K | ~6K | $0.40-0.60 |
| Stage 6: Morning Session Script | ~20K | ~2K | $0.25-0.35 |
| **Total** | **~175K** | **~37K** | **$2.60-3.95** |

Monthly cost: approximately $80-120 per user. This is the cost of intelligence. It is the product.
