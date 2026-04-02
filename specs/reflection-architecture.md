# Reflection Engine Architecture Spec

**System:** Timed — Cognitive Intelligence Layer for C-Suite Executives
**Layer:** The Core — processes all other layers, generates all intelligence
**Model:** Claude Opus 4.6 at maximum effort. No cost cap. No model substitution. This IS the product.
**Stack:** Swift 5.9+, CoreData, Supabase, Claude API
**Inspiration:** Stanford Generative Agents (Park et al., 2023) — recursive reflection producing emergent behaviour
**Status:** Implementation-ready

---

## 1. Purpose

The nightly reflection engine is the heart of Timed. Every other component — chronotype detection, avoidance analysis, cognitive load measurement, relationship scoring — is a signal collector. The reflection engine is where those signals become intelligence.

Every night, Opus processes the day's raw observations, extracts patterns, synthesises higher-order insights, generates operational rules, updates the executive's cognitive model, and prepares the morning briefing. It is not summarisation. It is genuine intelligence: a frontier model spending unconstrained compute to understand one specific human being more deeply than any system has attempted.

The compounding effect is the moat. Day 1, the system knows nothing. Day 30, it knows the executive's rhythms. Day 90, it knows their avoidance patterns. Day 180, it predicts their decisions before they make them. No other product achieves this because no other product invests Opus-tier compute nightly in recursive personal reflection.

---

## 2. Scientific Foundation: Generative Agents Architecture

### 2.1 Stanford Generative Agents (Park et al., 2023)

The paper demonstrated that LLM agents with three memory types and a reflection mechanism exhibit emergent social behaviour — planning, forming relationships, and making decisions that observers rated as "more human" than actual human scripted behaviour.

**Key architecture from the paper, adapted for Timed:**

| Generative Agents Concept | Timed Adaptation |
|--------------------------|------------------|
| **Observation** — agents perceive events in their environment | Haiku swarm continuously logs events (emails, tasks, meetings, behaviours) as episodic memories |
| **Reflection** — periodically synthesise observations into higher-level insights | Nightly Opus pipeline runs recursive synthesis: observations → first-order patterns → second-order insights → rules |
| **Planning** — use reflections to make decisions and plans | Morning Opus Director uses the updated model to deliver cognitive briefing and schedule recommendations |
| **Memory retrieval** — recency × importance × relevance scoring | Timed uses the same scoring for deciding which memories to include in the reflection context window |

### 2.2 Key Adaptation: Deeper Recursion

The original paper used single-pass reflection. Timed goes deeper:

1. **First-order reflection:** "What happened today?" → episodic summary
2. **Second-order reflection:** "What patterns appear across today and recent history?" → pattern extraction
3. **Third-order reflection:** "What do these patterns reveal about how this person fundamentally operates?" → semantic model update
4. **Meta-reflection:** "Which of my previous rules or patterns need revision based on new evidence?" → procedural rule validation

This multi-pass approach is computationally expensive and the reason Opus at max effort is non-negotiable. Haiku or Sonnet cannot perform second-order synthesis with the depth required.

---

## 3. Trigger Conditions

### 3.1 Primary Trigger: Scheduled Nightly Run

**Default time:** 2:00 AM local time (configurable in settings).

**Why 2am:**
- Well after the executive's cognitive stop time (typically 10pm-midnight for C-suite)
- Before the morning session window (typically 6-8am)
- Allows 3-5 hours for processing even in edge cases
- Mimics sleep consolidation: the system processes the day's memories while the executive sleeps

**Configuration:**
```swift
struct ReflectionSchedule {
    var scheduledTime: DateComponents = DateComponents(hour: 2, minute: 0) // 2:00 AM
    var minimumDataThreshold: Int = 10  // Minimum episodic memories to trigger reflection
    var skipWeekends: Bool = false       // Run even on weekends (executives work weekends)
    var skipHolidays: Bool = true        // Skip if calendar has all-day "holiday" event
}
```

### 3.2 Secondary Trigger: Manual

The executive can trigger reflection at any time via command palette: "Reflect on today so far."

This runs the same pipeline on partial day data. Useful for:
- Before a critical afternoon meeting ("What should I know going into this?")
- After a particularly intense morning
- On demand when the executive wants the system to "think"

### 3.3 Skip Conditions

Do NOT run reflection if:
- Fewer than `minimumDataThreshold` episodic memories for the day (nothing meaningful to reflect on)
- The system is offline / cannot reach the Claude API
- A previous reflection run is still in progress (should never happen with a 3-5 hour window, but guard against it)

---

## 4. Inputs

### 4.1 Day's Episodic Memories

Every event the Haiku swarm logs throughout the day:

```swift
struct EpisodicMemory {
    let id: UUID
    let timestamp: Date
    let source: SignalSource        // .email, .calendar, .task, .appFocus, .voice, .system, .userCorrection
    let eventType: String          // "email_sent", "task_completed", "meeting_attended", etc.
    let summary: String            // Haiku-generated one-line summary
    let details: Data              // JSON: source-specific structured data
    let importance: Float          // 0.0-1.0, computed at creation time
    let embeddingVector: [Float]   // 1024-dim Jina embedding for retrieval
    let relatedEntities: [UUID]    // Contact IDs, task IDs, project IDs
}
```

**Typical daily volume:** 50-200 episodic memories for a C-suite executive.

**Importance scoring at creation time (Haiku):**
- 0.1-0.3: Routine events (email read, app opened, routine meeting attended)
- 0.4-0.6: Notable events (task completed, substantive email sent, 1:1 had, focus session completed)
- 0.7-0.9: Significant events (deadline met/missed, important decision made, conflict in email, pattern anomaly)
- 0.9-1.0: Critical events (executive correction of the system, major calendar change, emotional signal detected)

### 4.2 Existing Semantic Model

The current state of what Timed has learned about the executive:

```swift
struct SemanticModel {
    let facts: [SemanticFact]           // "Avoids people decisions", "Peaks analytically 9-11am"
    let patterns: [NamedPattern]         // "The People Freeze", "Monday Overload"
    let relationships: [RelationshipScore] // Per-contact health scores
    let chronotype: ChronotypeModel      // Performance curves
    let loadProfile: [LoadPattern]       // Structural load patterns
    let preferences: [Preference]        // Learned preferences ("Likes email before 9am")
    let modelVersion: Int
    let lastUpdated: Date
}

struct SemanticFact {
    let id: UUID
    let category: String          // "cognitive", "behavioural", "relational", "preference"
    let fact: String              // Natural language: "Tends to underestimate time for creative tasks by ~40%"
    let confidence: Float         // 0.0-1.0
    let evidenceCount: Int        // Number of observations supporting this fact
    let firstObserved: Date
    let lastConfirmed: Date
    let contradictionCount: Int   // Times evidence contradicted this fact
}
```

### 4.3 Active Procedural Rules

Rules the system has generated from previous reflections:

```swift
struct ProceduralRule {
    let id: UUID
    let ruleType: String          // "scheduling", "avoidance", "alerting", "interaction"
    let condition: String         // "When a people-decision task is deferred twice"
    let action: String            // "Flag prominently in next morning session"
    let confidence: Float
    let timesApplied: Int
    let timesSuccessful: Int      // Times the action led to positive outcome
    let createdBy: String         // "reflection_v12"
    let createdAt: Date
    let lastApplied: Date?
    let supersededBy: UUID?       // If a newer rule replaced this one
}
```

---

## 5. Pipeline Stages

### 5.1 Stage 1: Episodic Summarisation

**Model:** Opus
**Input:** All episodic memories from the day, sorted chronologically
**Output:** Structured day narrative with significance annotations

**Opus prompt:**
```
You are the reflection engine for [executive name]'s cognitive intelligence system.

Today is [date]. Here are today's episodic memories, in chronological order:

[Array of EpisodicMemory objects — summary + details for each]

Your task: produce a structured summary of today. This is NOT a simple recap — extract the narrative arc of the day. What was attempted? What was accomplished? What was avoided? What surprised the system?

Output format:
{
    "day_narrative": "One paragraph capturing the shape of the day",
    "significant_events": [
        {
            "event_summary": "...",
            "significance": "why this matters for understanding the executive",
            "memory_ids": ["..."]
        }
    ],
    "anomalies": [
        {
            "description": "anything that deviated from expected patterns",
            "deviation_type": "positive_surprise | negative_deviation | unexplained"
        }
    ],
    "emotional_arc": "inferred emotional trajectory of the day based on behavioural signals",
    "unresolved_threads": ["items started but not completed, conversations left hanging"]
}
```

**Token budget:** ~5,000-15,000 input tokens (day's memories) + ~2,000-4,000 output tokens.

### 5.2 Stage 2: First-Order Pattern Extraction

**Model:** Opus
**Input:** Today's structured summary + last 7 days of structured summaries + active observations from subsystems (chronotype, avoidance, load, relationship signals)
**Output:** Patterns observable in the recent data

**Opus prompt:**
```
You are performing first-order pattern extraction.

Today's summary:
[Stage 1 output]

Previous 6 days' summaries:
[Last 6 days of Stage 1 outputs — abridged to key points]

Active subsystem observations:
- Chronotype: [ChronotypeModel summary — peaks, troughs, drift status]
- Avoidance: [Active AvoidanceAssessments with composite_score > 0.3]
- Cognitive Load: [Today's load curve summary, any structural patterns]
- Relationships: [Contacts with trend changes in last 7 days]

Your task: extract PATTERNS — regularities, recurrences, correlations that appear across the data. These are first-order patterns: directly observable in the data, not yet interpreted.

Output format:
{
    "recurring_patterns": [
        {
            "pattern": "description of the recurrence",
            "evidence": ["specific instances from the data"],
            "frequency": "daily | several_times_weekly | weekly | emerging",
            "confidence": 0.0-1.0
        }
    ],
    "new_observations": [
        {
            "observation": "something new that hasn't been seen before",
            "significance": "why it might matter"
        }
    ],
    "subsystem_validations": [
        {
            "subsystem": "chronotype | avoidance | load | relationship",
            "finding": "does today's data confirm or contradict the subsystem's model?"
        }
    ],
    "cross_cutting_patterns": [
        {
            "pattern": "pattern that spans multiple signal sources",
            "sources": ["email", "calendar", "task", ...]
        }
    ]
}
```

**Token budget:** ~10,000-25,000 input tokens + ~3,000-6,000 output tokens.

### 5.3 Stage 3: Second-Order Synthesis

**Model:** Opus (maximum effort)
**Input:** Stage 2 output + existing semantic model + the executive's full history of named patterns
**Output:** Higher-order insights about WHO this person is and HOW they operate

This is the stage that produces the intelligence that makes Timed unique. It asks: "Given what I've observed, what does this tell me about this human being that goes beyond the raw patterns?"

**Opus prompt:**
```
You are performing second-order synthesis — the deepest analysis in the reflection pipeline.

First-order patterns extracted tonight:
[Stage 2 output]

Current semantic model of [executive name]:
[Full SemanticModel — all facts, patterns, preferences]

Historical named patterns (all time):
[All NamedPattern objects, with creation dates and confidence scores]

Your task: synthesise. Move beyond "what patterns exist" to "what do these patterns REVEAL about how this person thinks, decides, avoids, and operates."

Think about:
1. Are any first-order patterns actually manifestations of a deeper trait? (e.g., "defers people decisions" + "shortens emails to direct reports when stressed" + "cancels 1:1s after board meetings" might all be manifestations of "conflict aversion that intensifies under pressure")
2. Are any existing semantic facts contradicted by new evidence? If so, which should be revised?
3. Are any named patterns strengthening, weakening, or evolving?
4. What PREDICTIONS can you now make about tomorrow's behaviour based on the model?
5. What is the single most important thing the executive should know about themselves that they probably don't?

Output format:
{
    "second_order_insights": [
        {
            "insight": "the synthesised understanding",
            "supporting_patterns": ["first-order patterns that support this"],
            "depth": "trait_level | behavioural_level | situational_level",
            "confidence": 0.0-1.0,
            "novelty": "new | refined | confirmed"
        }
    ],
    "model_revisions": [
        {
            "fact_id": "uuid of existing fact to revise, or null for new",
            "old_value": "previous understanding (if revision)",
            "new_value": "updated understanding",
            "evidence": "what triggered the revision"
        }
    ],
    "predictions": [
        {
            "prediction": "what the model expects to happen tomorrow",
            "basis": "which model elements support this prediction",
            "confidence": 0.0-1.0
        }
    ],
    "key_question": "The single most important question the morning session should pose to the executive"
}
```

**Token budget:** ~15,000-40,000 input tokens + ~4,000-8,000 output tokens. This is the most expensive stage. Intentionally.

### 5.4 Stage 4: Rule Generation

**Model:** Opus
**Input:** Stage 3 output + existing procedural rules
**Output:** New rules, updated rules, deprecated rules

**Opus prompt:**
```
You are generating and updating procedural rules based on tonight's synthesis.

Second-order insights:
[Stage 3 output]

Current procedural rules:
[All active ProceduralRule objects]

Your task: translate insights into actionable rules for the system. Rules should be:
- Specific (triggerable by observable conditions)
- Falsifiable (can be measured as successful or not)
- Minimal (one rule per insight, not redundant with existing rules)

For each existing rule, assess: does tonight's evidence confirm, weaken, or invalidate it?

Output format:
{
    "new_rules": [
        {
            "condition": "when/if condition (must be observable)",
            "action": "what the system should do",
            "justification": "which insight supports this rule",
            "confidence": 0.0-1.0
        }
    ],
    "updated_rules": [
        {
            "rule_id": "uuid",
            "change": "what changed and why",
            "new_confidence": 0.0-1.0
        }
    ],
    "deprecated_rules": [
        {
            "rule_id": "uuid",
            "reason": "why this rule is no longer valid"
        }
    ]
}
```

**Token budget:** ~5,000-10,000 input tokens + ~1,000-3,000 output tokens.

### 5.5 Stage 5: Memory Updates

**Model:** None (deterministic processing of Stage 3 and Stage 4 outputs)

Apply all changes to the persistent model:

```swift
func applyMemoryUpdates(synthesisOutput: SynthesisOutput, ruleOutput: RuleOutput) {
    // 1. Update semantic facts
    for revision in synthesisOutput.modelRevisions {
        if let existingId = revision.factId {
            updateSemanticFact(id: existingId, newValue: revision.newValue)
        } else {
            createSemanticFact(value: revision.newValue, confidence: revision.confidence)
        }
    }
    
    // 2. Create/update named patterns
    for insight in synthesisOutput.secondOrderInsights where insight.depth == .traitLevel {
        createOrUpdateNamedPattern(from: insight)
    }
    
    // 3. Apply rule changes
    for newRule in ruleOutput.newRules {
        createProceduralRule(condition: newRule.condition, action: newRule.action, confidence: newRule.confidence)
    }
    for update in ruleOutput.updatedRules {
        updateProceduralRule(id: update.ruleId, confidence: update.newConfidence)
    }
    for deprecation in ruleOutput.deprecatedRules {
        deprecateProceduralRule(id: deprecation.ruleId, reason: deprecation.reason)
    }
    
    // 4. Increment model version
    semanticModel.modelVersion += 1
    semanticModel.lastUpdated = Date()
    
    // 5. Store model snapshot for audit trail
    storeModelSnapshot(version: semanticModel.modelVersion)
}
```

### 5.6 Stage 6: Morning Session Preparation

**Model:** Opus
**Input:** Updated semantic model + Stage 3 insights + tomorrow's calendar + active alerts from all subsystems
**Output:** Complete morning session context document

**Opus prompt:**
```
You are preparing tomorrow's morning session for [executive name].

Updated cognitive model:
[SemanticModel — post-update]

Tonight's key insights:
[Stage 3 second_order_insights + key_question]

Tomorrow's predictions:
[Stage 3 predictions]

Tomorrow's calendar:
[Calendar events for tomorrow]

Active alerts:
- Avoidance: [active avoidance assessments at surfacing level 2+]
- Relationships: [relationship alerts]
- Load prediction: [predicted load based on calendar]
- Chronotype: [peak windows for tomorrow]

Your task: compose the morning session context. This will be loaded into the Morning Director's system prompt. It should contain:

1. Opening insight — the single most important thing to surface
2. Avoidance confrontation — any items the executive needs to face (use the escalation ladder)
3. Relationship intelligence — only if actionable (declining or dormant)
4. Schedule intelligence — chronotype-aligned recommendations for tomorrow
5. Predictions to test — what the model expects to happen, framed as questions
6. Evolving patterns — any patterns that changed confidence tonight

Tone: intelligent, direct, respectful. Like a brilliant chief of staff who has spent the night thinking about how to make tomorrow better.

Output format:
{
    "morning_context": {
        "opening_insight": "...",
        "avoidance_items": [...],
        "relationship_alerts": [...],
        "schedule_recommendations": [...],
        "predictions": [...],
        "pattern_updates": [...]
    },
    "morning_question": "The opening question for the voice session",
    "context_document": "Full natural-language document for the Morning Director system prompt"
}
```

**Token budget:** ~10,000-20,000 input tokens + ~3,000-6,000 output tokens.

---

## 6. Total Token Budget Per Nightly Run

| Stage | Input Tokens | Output Tokens | Model |
|-------|-------------|---------------|-------|
| Stage 1: Episodic Summary | 5,000-15,000 | 2,000-4,000 | Opus |
| Stage 2: First-Order Patterns | 10,000-25,000 | 3,000-6,000 | Opus |
| Stage 3: Second-Order Synthesis | 15,000-40,000 | 4,000-8,000 | Opus |
| Stage 4: Rule Generation | 5,000-10,000 | 1,000-3,000 | Opus |
| Stage 5: Memory Updates | 0 (deterministic) | 0 | N/A |
| Stage 6: Morning Prep | 10,000-20,000 | 3,000-6,000 | Opus |
| **Total** | **45,000-110,000** | **13,000-27,000** | **Opus** |

**Estimated cost per night:** $1.50-$5.00 at Opus pricing (varies with context size as the model matures and the semantic model grows).

**Monthly cost:** $45-$150 for the nightly engine alone. This is the product's core expenditure and it is correct. The intelligence quality IS the product.

---

## 7. Error Handling

### 7.1 Failure Modes and Recovery

| Failure | Detection | Recovery |
|---------|-----------|----------|
| **API timeout on Stage 1** | HTTP timeout / 5xx | Retry with exponential backoff (3 attempts, 30s/60s/120s). If all fail, skip tonight's reflection. Log failure. Morning session says: "Reflection didn't complete last night — I'm working from yesterday's model." |
| **API timeout on Stage 2-4** | Same | If Stage 1 completed, cache Stage 1 output and retry Stages 2-4 in 1 hour. If still failing, use Stage 1 summary as a degraded morning context. |
| **Malformed output from Opus** | JSON parse failure | Retry the specific stage once with explicit JSON formatting instructions appended. If second attempt fails, use the raw text output and extract what's parseable. Log the malformation for debugging. |
| **Stage 3 contradicts Stage 2** | Consistency check | Normal — Stage 3 is supposed to reinterpret Stage 2. Only flag if Stage 3 directly contradicts data (e.g., claims an event happened that didn't). In that case, re-run Stage 3 with the contradiction highlighted. |
| **Memory update conflict** | CoreData save fails, Supabase conflict | CoreData is authoritative. If Supabase sync fails, queue for retry. Never let a Supabase failure block local model updates. |
| **Model regression** | Validation checks (see 8.3) | If the updated model fails quality checks, roll back to the previous model snapshot. Flag the regression in the morning session: "Tonight's reflection produced results that seem inconsistent with recent patterns. I've reverted to last night's model and will try again tonight with additional validation." |
| **Mac asleep at trigger time** | macOS power assertion / wake schedule | Schedule a `NSBackgroundActivityScheduler` task. If the Mac wakes late, run reflection on wake. If the Mac was off all night, run on first morning launch (before the morning session). |

### 7.2 Graceful Degradation Hierarchy

If the full pipeline cannot complete, deliver what's available:

1. **Full pipeline** — all 6 stages complete → optimal morning session
2. **Stages 1-3 only** — synthesis complete but no rule updates → morning session uses insights without rule changes
3. **Stage 1 only** — day summary complete → morning session based on summary + yesterday's model
4. **No reflection** — pipeline didn't run → morning session uses existing model only, notes that reflection didn't complete
5. **No API access** — fully offline → morning session generated locally from cached model + calendar data, no new intelligence

---

## 8. Quality Measurement

### 8.1 Internal Quality Metrics

Computed after each reflection run:

```swift
struct ReflectionQualityMetrics {
    let runId: UUID
    let timestamp: Date
    
    // Completeness
    let stagesCompleted: Int           // Out of 6
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let durationSeconds: Double
    
    // Content quality
    let newFactsGenerated: Int
    let factsRevised: Int
    let rulesCreated: Int
    let rulesDeprecated: Int
    let patternsDetected: Int
    let predictionsGenerated: Int
    
    // Consistency
    let contradictionsWithExistingModel: Int  // Should be low
    let evidenceDensity: Float         // Ratio of cited evidence to claims
    
    // Evolution
    let modelVersionDelta: Int         // Should be 1
    let semanticModelSize: Int         // Total facts in model
    let proceduralRuleCount: Int       // Total active rules
}
```

### 8.2 Longitudinal Quality Tracking

Track across weeks:
- **Prediction accuracy:** Compare Stage 3 predictions to next day's actual events. Log hit rate.
- **Rule utility:** Track which procedural rules are applied and which lead to positive outcomes. Prune rules that fire but never help.
- **Insight novelty:** Are reflections still generating new insights or just confirming known patterns? If novelty drops to zero, the model may have saturated for the current behaviour set (which is expected and fine — new insights emerge when behaviour changes).
- **Morning session engagement:** Does the executive engage with the morning session's insights? (Measured by: session duration, follow-up questions, tasks created from recommendations.)

### 8.3 Regression Detection

After each reflection run, validate the updated model:

```swift
func validateModelUpdate(oldModel: SemanticModel, newModel: SemanticModel) -> ValidationResult {
    // 1. No facts should be deleted without explicit deprecation
    let deletedFacts = oldModel.facts.filter { old in
        !newModel.facts.contains { $0.id == old.id }
    }
    if !deletedFacts.isEmpty { return .regression("Facts deleted without deprecation") }
    
    // 2. High-confidence facts shouldn't flip without strong evidence
    for fact in newModel.facts {
        if let oldFact = oldModel.facts.first(where: { $0.id == fact.id }) {
            if oldFact.confidence > 0.8 && abs(oldFact.confidence - fact.confidence) > 0.3 {
                return .warning("High-confidence fact changed dramatically: \(fact.fact)")
            }
        }
    }
    
    // 3. Model size shouldn't shrink by more than 10% in a single run
    let shrinkage = Float(oldModel.facts.count - newModel.facts.count) / Float(oldModel.facts.count)
    if shrinkage > 0.1 { return .regression("Model shrunk by \(shrinkage * 100)%") }
    
    // 4. Procedural rules shouldn't all be deprecated at once
    if newModel.proceduralRules.filter({ $0.supersededBy != nil }).count > oldModel.proceduralRules.count / 2 {
        return .regression("More than half of rules deprecated in single run")
    }
    
    return .passed
}
```

---

## 9. Data Model (CoreData)

```swift
@Model
class ReflectionRun {
    var id: UUID
    var triggeredAt: Date
    var completedAt: Date?
    var triggerType: String           // "scheduled", "manual"
    var status: String                // "running", "completed", "partial", "failed"
    var stagesCompleted: Int
    var inputTokens: Int
    var outputTokens: Int
    var durationSeconds: Double?
    var modelVersionBefore: Int
    var modelVersionAfter: Int?
    var qualityMetrics: Data?         // JSON: ReflectionQualityMetrics
    var errorLog: String?
}

@Model
class ReflectionStageOutput {
    var id: UUID
    var runId: UUID                   // Parent ReflectionRun
    var stageNumber: Int              // 1-6
    var stageName: String             // "episodic_summary", "first_order", etc.
    var startedAt: Date
    var completedAt: Date?
    var inputTokens: Int
    var outputTokens: Int
    var rawOutput: Data               // JSON: full stage output
    var status: String                // "completed", "failed", "retried"
    var retryCount: Int
}

@Model
class SemanticFact {
    var id: UUID
    var category: String
    var fact: String
    var confidence: Float
    var evidenceCount: Int
    var firstObserved: Date
    var lastConfirmed: Date
    var contradictionCount: Int
    var createdByRunId: UUID
    var deprecated: Bool
    var deprecatedReason: String?
}

@Model
class NamedPattern {
    var id: UUID
    var name: String                  // "The People Freeze", "Monday Overload"
    var domain: String                // "avoidance", "chronotype", "load", "relationship"
    var description: String
    var confidence: Float
    var instanceCount: Int
    var lastTriggered: Date
    var isActive: Bool
    var createdByRunId: UUID
}

@Model
class ProceduralRule {
    var id: UUID
    var ruleType: String
    var condition: String
    var action: String
    var confidence: Float
    var timesApplied: Int
    var timesSuccessful: Int
    var createdByRunId: UUID
    var createdAt: Date
    var lastApplied: Date?
    var supersededBy: UUID?
}

@Model
class ModelSnapshot {
    var id: UUID
    var modelVersion: Int
    var snapshotDate: Date
    var factCount: Int
    var patternCount: Int
    var ruleCount: Int
    var fullSnapshot: Data            // JSON: complete SemanticModel serialisation
    var createdByRunId: UUID
}

@Model
class MorningSessionContext {
    var id: UUID
    var preparedByRunId: UUID
    var forDate: Date                 // The date this context is for
    var contextDocument: String       // Natural language context for Morning Director
    var openingInsight: String
    var morningQuestion: String
    var structuredData: Data          // JSON: full morning_context object
    var used: Bool                    // Whether the morning session consumed this
}
```

### Supabase Schema

```sql
create table reflection_runs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    triggered_at timestamptz not null,
    completed_at timestamptz,
    trigger_type text not null,
    status text not null default 'running',
    stages_completed integer not null default 0,
    input_tokens integer not null default 0,
    output_tokens integer not null default 0,
    duration_seconds double precision,
    model_version_before integer not null,
    model_version_after integer,
    quality_metrics jsonb,
    error_log text,
    created_at timestamptz not null default now()
);

create table reflection_stage_outputs (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references reflection_runs(id) not null,
    stage_number smallint not null,
    stage_name text not null,
    started_at timestamptz not null,
    completed_at timestamptz,
    input_tokens integer not null default 0,
    output_tokens integer not null default 0,
    raw_output jsonb not null,
    status text not null default 'running',
    retry_count integer not null default 0
);

create table semantic_facts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    category text not null,
    fact text not null,
    confidence real not null,
    evidence_count integer not null default 1,
    first_observed timestamptz not null default now(),
    last_confirmed timestamptz not null default now(),
    contradiction_count integer not null default 0,
    created_by_run_id uuid references reflection_runs(id),
    deprecated boolean not null default false,
    deprecated_reason text
);

create table named_patterns (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    name text not null,
    domain text not null,
    description text not null,
    confidence real not null,
    instance_count integer not null default 0,
    last_triggered timestamptz,
    is_active boolean not null default true,
    created_by_run_id uuid references reflection_runs(id),
    created_at timestamptz not null default now()
);

create table procedural_rules (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    workspace_id uuid references workspaces(id) not null,
    rule_type text not null,
    condition text not null,
    action text not null,
    confidence real not null,
    times_applied integer not null default 0,
    times_successful integer not null default 0,
    created_by_run_id uuid references reflection_runs(id),
    created_at timestamptz not null default now(),
    last_applied timestamptz,
    superseded_by uuid references procedural_rules(id)
);

create table model_snapshots (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    model_version integer not null,
    snapshot_date timestamptz not null default now(),
    fact_count integer not null,
    pattern_count integer not null,
    rule_count integer not null,
    full_snapshot jsonb not null,
    created_by_run_id uuid references reflection_runs(id)
);

-- Keep last 90 snapshots, archive older ones
create index idx_snapshots_version on model_snapshots(user_id, model_version desc);

create table morning_session_contexts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    prepared_by_run_id uuid references reflection_runs(id),
    for_date date not null,
    context_document text not null,
    opening_insight text not null,
    morning_question text not null,
    structured_data jsonb not null,
    used boolean not null default false,
    created_at timestamptz not null default now(),
    unique(user_id, for_date)
);

-- RLS
alter table reflection_runs enable row level security;
alter table reflection_stage_outputs enable row level security;
alter table semantic_facts enable row level security;
alter table named_patterns enable row level security;
alter table procedural_rules enable row level security;
alter table model_snapshots enable row level security;
alter table morning_session_contexts enable row level security;

create policy "own_data" on reflection_runs for all using (auth.uid() = user_id);
create policy "own_data" on reflection_stage_outputs for all 
    using (exists (select 1 from reflection_runs r where r.id = run_id and r.user_id = auth.uid()));
create policy "own_data" on semantic_facts for all using (auth.uid() = user_id);
create policy "own_data" on named_patterns for all using (auth.uid() = user_id);
create policy "own_data" on procedural_rules for all using (auth.uid() = user_id);
create policy "own_data" on model_snapshots for all using (auth.uid() = user_id);
create policy "own_data" on morning_session_contexts for all using (auth.uid() = user_id);
```

---

## 10. Resource Requirements

### 10.1 Compute

| Resource | Requirement |
|----------|-------------|
| **Claude API** | Opus 4.6 at max effort. 4-6 sequential API calls per run. Total latency: 3-8 minutes for the full pipeline (Opus is not fast — this is expected and acceptable for overnight processing). |
| **Local CPU** | Negligible — Stage 5 (memory updates) is the only local compute. JSON parsing + CoreData writes. |
| **Local storage** | ~500KB-2MB per nightly run (stage outputs + model snapshot). ~60-180MB per year. Manageable. |
| **Network** | ~200KB-500KB upload per run (prompts). ~50KB-150KB download per run (responses). Works on any connection. |

### 10.2 Scheduling

```swift
class ReflectionScheduler {
    private let scheduler = NSBackgroundActivityScheduler(identifier: "com.timed.reflection")
    
    func schedule() {
        scheduler.repeats = true
        scheduler.interval = 24 * 60 * 60 // Daily
        scheduler.qualityOfService = .utility
        scheduler.tolerance = 60 * 60 // 1 hour tolerance (2am-3am window)
        
        scheduler.schedule { [weak self] completion in
            guard let self = self else {
                completion(.finished)
                return
            }
            
            Task {
                do {
                    try await self.runReflection()
                    completion(.finished)
                } catch {
                    Logger.reflection.error("Reflection failed: \(error)")
                    completion(.deferred) // Try again later
                }
            }
        }
    }
}
```

---

## 11. Model Version Snapshots

Every reflection run increments the model version and stores a complete snapshot. This enables:

1. **Rollback:** If a reflection produces a bad model update, revert to the previous snapshot.
2. **Audit trail:** See how the model evolved over time. "What did the system believe about you on March 15th?"
3. **Quality measurement:** Compare model-at-week-4 to model-at-week-12 to verify compounding.
4. **Debugging:** When a morning session delivers a bad recommendation, trace back through the model versions to find where the bad belief was introduced.

**Retention policy:**
- Last 90 snapshots: full detail
- Older than 90: keep monthly snapshots only
- Delete stage outputs after 30 days (they're diagnostic, not needed long-term)

---

## 12. Implementation Sequence

1. **EpisodicMemory entity and Haiku logging** — event handlers for all signal sources writing structured episodic memories
2. **SemanticFact, NamedPattern, ProceduralRule entities** — CoreData models for the semantic model
3. **ReflectionRun orchestrator** — `ReflectionEngine` class that sequences the 6 stages
4. **Stage 1: Episodic Summarisation** — Opus prompt, JSON parsing, output storage
5. **Stage 2: First-Order Pattern Extraction** — pull 7-day history, subsystem signals, Opus prompt
6. **Stage 3: Second-Order Synthesis** — full semantic model loading, Opus prompt at max effort
7. **Stage 4: Rule Generation** — procedural rule CRUD from Opus output
8. **Stage 5: Memory Updates** — deterministic application of Stage 3/4 outputs to CoreData
9. **Stage 6: Morning Session Preparation** — calendar integration, alert aggregation, Opus prompt
10. **ModelSnapshot storage and rollback** — snapshot on every version, rollback on regression
11. **NSBackgroundActivityScheduler integration** — reliable 2am trigger, wake-from-sleep handling
12. **Quality metrics and validation** — post-run validation, regression detection, longitudinal tracking
13. **Graceful degradation** — partial pipeline results, offline fallback, API failure handling
14. **Supabase sync** — all entities synced with RLS, stage outputs for debugging
15. **Manual trigger via command palette** — "Reflect on today so far" runs the pipeline on partial data
