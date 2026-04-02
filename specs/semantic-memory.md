# PRD: Semantic Memory Store

> Layer: Memory Store (Tier 2 of 3)
> Status: Implementation-ready
> Dependencies: Episodic Memory, Reflection Engine, Jina Embeddings, Supabase
> Swift target: 5.9+ / macOS 14+
> Reference: Park et al. 2023, cognitive science literature on semantic memory consolidation

---

## 1. Purpose

Semantic memory is the system's understanding of who the executive IS. Not what they did today (that is episodic memory), but what the system has learned about them over time: their work style, preferences, relationship patterns, avoidance behaviours, decision tendencies, energy rhythms, and cognitive fingerprints.

Every fact in semantic memory was extracted from episodic records by the reflection engine. Every fact carries an evidence chain back to the episodes that produced it and a confidence score that strengthens with reinforcement and decays without it.

This is the layer that makes month 6 incomparably smarter than month 1. The reflection engine writes here nightly. The morning director reads here to deliver intelligence.

---

## 2. Schema

### 2.1 Semantic Fact Record

```swift
struct SemanticFact: Identifiable, Codable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let factType: FactType
    let category: FactCategory
    let subject: String                   // what the fact is about: "HR tasks", "John Chen", "Monday mornings"
    let content: String                   // the fact itself, natural language
    let confidence: Float                 // 0.0 to 1.0
    let evidenceChain: [UUID]             // episodic episode IDs that support this fact
    let evidenceCount: Int                // total episodes that have reinforced this fact
    let firstObserved: Date               // when the pattern was first detected
    let lastReinforced: Date              // when the most recent supporting episode occurred
    let reinforcementCount: Int           // how many times the reflection engine has confirmed this fact
    let contradictionCount: Int           // how many episodes have contradicted this fact
    let embedding: [Float]?               // 1024-dim Jina embedding for retrieval
    let status: FactStatus                // active, weakened, contradicted, deprecated
    let supersededBy: UUID?               // if this fact was replaced by a newer understanding
    let createdAt: Date
    let updatedAt: Date
}
```

### 2.2 Fact Types

```swift
enum FactType: String, Codable, Sendable {
    case observation     // directly observed pattern: "Defers HR tasks on Mondays"
    case inference       // derived from multiple observations: "Avoids people-management decisions under time pressure"
    case preference      // stated or revealed preference: "Prefers deep work before 11am"
    case relationship    // about a person in the executive's network: "John Chen is a trusted advisor"
    case selfModel       // the system's model of the executive's self-perception vs behaviour
}
```

### 2.3 Fact Categories

```swift
enum FactCategory: String, Codable, Sendable {
    // Work patterns
    case workStyle           // "Batches email processing into 2 sessions/day"
    case energyPattern       // "Peak analytical performance between 9-11am"
    case avoidance           // "Chronically defers financial reviews"
    case decisionPattern     // "Makes people decisions slowly, technical decisions fast"
    case communicationStyle  // "Writes longer emails to direct reports, terse emails to board"
    
    // Preferences
    case schedulingPref      // "Prefers no meetings before 10am"
    case toolPref            // "Uses voice capture for urgent items, manual entry for planned items"
    case priorityPref        // "Consistently prioritises client-facing work over internal ops"
    
    // Relationships
    case relationship        // "Sarah Kim: reports to the executive, high communication frequency"
    case stakeholder         // "Board chair: low frequency but high-importance interactions"
    
    // Cognitive
    case blindSpot           // "Underestimates time for legal review tasks by ~40%"
    case strength            // "Exceptional at rapid context-switching between operational domains"
    case trigger             // "Back-to-back meetings > 3hrs correlates with poor afternoon decisions"
    
    // Meta
    case selfAwareness       // "Believes they are a morning person — data confirms this"
    case growthArea          // "Delegation has improved: defer-then-delete rate dropped 30% over 2 months"
}

enum FactStatus: String, Codable, Sendable {
    case active              // currently believed to be true, sufficient confidence
    case weakened            // confidence has decayed below threshold, needs reinforcement
    case contradicted        // recent evidence conflicts — under review by reflection engine
    case deprecated          // explicitly replaced by a newer fact (supersededBy populated)
}
```

### 2.4 Supabase Table

```sql
CREATE TABLE semantic_facts (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id          UUID NOT NULL REFERENCES workspaces(id),
    profile_id            UUID NOT NULL REFERENCES profiles(id),
    fact_type             TEXT NOT NULL,
    category              TEXT NOT NULL,
    subject               TEXT NOT NULL,
    content               TEXT NOT NULL,
    confidence            REAL NOT NULL DEFAULT 0.5,
    evidence_chain        UUID[] NOT NULL DEFAULT '{}',
    evidence_count        INT NOT NULL DEFAULT 0,
    first_observed        TIMESTAMPTZ NOT NULL,
    last_reinforced       TIMESTAMPTZ NOT NULL,
    reinforcement_count   INT NOT NULL DEFAULT 1,
    contradiction_count   INT NOT NULL DEFAULT 0,
    embedding             vector(1024),
    status                TEXT NOT NULL DEFAULT 'active',
    superseded_by         UUID REFERENCES semantic_facts(id),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_semantic_facts_profile_status ON semantic_facts(profile_id, status);
CREATE INDEX idx_semantic_facts_category ON semantic_facts(profile_id, category);
CREATE INDEX idx_semantic_facts_confidence ON semantic_facts(profile_id, confidence DESC);
CREATE INDEX idx_semantic_facts_subject ON semantic_facts(profile_id, subject);
CREATE INDEX idx_semantic_facts_embedding ON semantic_facts USING ivfflat (embedding vector_cosine_ops) WITH (lists = 50);
```

**RLS:** `profile_id = auth.uid()` for SELECT. INSERT and UPDATE restricted to service role (reflection engine only). The client app reads semantic memory but never writes to it directly.

---

## 3. How Facts Are Extracted

### 3.1 Extraction Pipeline

The reflection engine is the sole writer of semantic memory. It runs nightly (or on significant event triggers) and follows this pipeline:

```
1. Read unprocessed episodes from episodic memory (today's events)
2. Read existing semantic facts for this profile (the current model)
3. For each cluster of related episodes:
   a. Check: does an existing fact already describe this pattern?
      ├─ YES → Reinforce (Section 4.1)
      └─ NO → Is this a new pattern with sufficient evidence?
           ├─ YES → Create new fact (Section 4.2)
           └─ NO → Do nothing (not enough signal yet)
4. For each existing fact:
   a. Check: do today's episodes contradict this fact?
      ├─ YES → Handle contradiction (Section 5)
      └─ NO → Apply confidence decay if no reinforcement (Section 4.3)
5. Mark processed episodes
```

### 3.2 Evidence Threshold for New Facts

A new semantic fact requires a minimum evidence threshold before creation:

| Fact type | Minimum episodes | Minimum time span | Rationale |
|-----------|-----------------|-------------------|-----------|
| `observation` | 3 | 3 days | Repeated behaviour over multiple days, not a one-off |
| `inference` | 5 | 7 days | Higher bar for derived conclusions |
| `preference` | 2 | 1 day | Preferences can be established quickly (2 consistent signals) |
| `relationship` | 5 | 7 days | Need sustained interaction pattern |
| `selfModel` | 10 | 14 days | Highest bar — modelling self-perception requires substantial data |

### 3.3 Fact Content Generation

Fact content is generated by the reflection engine (Opus at max effort) as natural language. The reflection prompt includes:
- The cluster of supporting episodes (summaries)
- Existing semantic facts in the same category (to avoid redundancy)
- Instructions to be specific, evidence-grounded, and non-judgmental

Example output:
```
"Defers HR-related action items an average of 4.2 times before completion. 
Deferrals cluster on Monday mornings (60% of HR deferrals). Pattern is 
specific to HR — other action items average 1.1 deferrals."
```

NOT acceptable:
```
"Tends to procrastinate on some tasks."  // too vague
"Is bad at HR work."                     // judgmental, not evidence-based
```

---

## 4. Update Logic

### 4.1 Reinforcement (New Observation Supports Existing Fact)

When the reflection engine finds new episodes that support an existing fact:

```swift
func reinforce(factId: UUID, newEpisodeIds: [UUID]) {
    // 1. Append new episode IDs to evidence chain
    fact.evidenceChain.append(contentsOf: newEpisodeIds)
    
    // 2. Increment counters
    fact.evidenceCount += newEpisodeIds.count
    fact.reinforcementCount += 1
    fact.lastReinforced = Date()
    
    // 3. Boost confidence (diminishing returns)
    let boost = 0.05 * (1.0 / Float(fact.reinforcementCount))  // decreasing boost
    fact.confidence = min(fact.confidence + boost, 0.99)        // never reaches 1.0
    
    // 4. If fact was weakened, restore to active
    if fact.status == .weakened {
        fact.status = .active
    }
    
    fact.updatedAt = Date()
}
```

### 4.2 New Fact Creation

```swift
func createFact(
    profileId: UUID,
    factType: FactType,
    category: FactCategory,
    subject: String,
    content: String,
    episodeIds: [UUID]
) -> SemanticFact {
    SemanticFact(
        id: UUID(),
        workspaceId: workspaceId,
        profileId: profileId,
        factType: factType,
        category: category,
        subject: subject,
        content: content,
        confidence: initialConfidence(for: factType, evidenceCount: episodeIds.count),
        evidenceChain: episodeIds,
        evidenceCount: episodeIds.count,
        firstObserved: Date(),
        lastReinforced: Date(),
        reinforcementCount: 1,
        contradictionCount: 0,
        embedding: nil,  // generated asynchronously
        status: .active,
        supersededBy: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
}

func initialConfidence(for factType: FactType, evidenceCount: Int) -> Float {
    let base: Float = switch factType {
        case .observation:  0.50
        case .inference:    0.40
        case .preference:   0.55
        case .relationship: 0.45
        case .selfModel:    0.35
    }
    // Slight boost for more evidence at creation time
    let evidenceBoost = Float(min(evidenceCount - 1, 5)) * 0.03
    return min(base + evidenceBoost, 0.75)  // cap initial confidence
}
```

### 4.3 Confidence Decay

Facts that are not reinforced gradually lose confidence. This ensures the model reflects the executive's current behaviour, not outdated patterns.

```swift
func applyDecay(fact: inout SemanticFact, currentDate: Date) {
    let daysSinceReinforcement = currentDate.timeIntervalSince(fact.lastReinforced) / 86400
    
    // No decay for first 14 days (grace period for intermittent patterns)
    guard daysSinceReinforcement > 14 else { return }
    
    // Decay rate depends on fact type
    let dailyDecay: Float = switch fact.factType {
        case .observation:  0.003   // ~50% confidence after 230 days without reinforcement
        case .inference:    0.005   // ~50% after 140 days
        case .preference:   0.002   // preferences are stable, decay slowly
        case .relationship: 0.004   // relationships can change
        case .selfModel:    0.002   // self-model is slow to change
    }
    
    let decayDays = Float(daysSinceReinforcement - 14)  // days past grace period
    let decayAmount = dailyDecay * decayDays
    
    fact.confidence = max(fact.confidence - decayAmount, 0.05)  // floor at 0.05
    
    // Transition to weakened status
    if fact.confidence < 0.25 && fact.status == .active {
        fact.status = .weakened
    }
}
```

### 4.4 When New Observation Updates vs Replaces

**Update (reinforce):** The new evidence is consistent with the existing fact. The fact's content still accurately describes the pattern. Only counters and confidence change.

**Replace (supersede):** The new evidence shows the pattern has fundamentally changed. The old fact is deprecated, a new fact is created, and `supersededBy` links them.

**Decision criteria (used by reflection engine):**

```
IF the new evidence cluster describes the SAME pattern with the SAME conclusion:
  → Reinforce
  
IF the new evidence cluster describes the SAME subject but a DIFFERENT pattern:
  IF old fact confidence > 0.6 AND contradiction count < 3:
    → Record contradiction, don't replace yet (could be an anomaly)
  IF old fact confidence <= 0.6 OR contradiction count >= 3:
    → Supersede: deprecate old fact, create new fact
    
IF the new evidence cluster is about a DIFFERENT subject:
  → Create new fact (no relationship to existing)
```

---

## 5. Contradiction Handling

### 5.1 What Counts as a Contradiction

A contradiction occurs when new episodic evidence directly opposes an existing semantic fact. Examples:

| Existing fact | Contradicting evidence | Contradiction? |
|--------------|----------------------|----------------|
| "Defers HR tasks on Mondays" | Completed 3 HR tasks on Monday without deferral | Yes |
| "Peak performance 9-11am" | Completed deep work at 3pm successfully | No (one instance is not a pattern change) |
| "Prefers no meetings before 10am" | Scheduled a meeting at 8am | Weak — could be forced by external constraint |

### 5.2 Contradiction Processing

```swift
func handleContradiction(fact: inout SemanticFact, contradictingEpisodeIds: [UUID]) {
    fact.contradictionCount += 1
    fact.updatedAt = Date()
    
    // Track contradicting evidence separately (don't add to evidence chain)
    // Stored in a contradiction_evidence JSONB column (not shown in main schema for clarity)
    
    switch fact.contradictionCount {
    case 1:
        // Single contradiction — could be noise. Log it, don't change status.
        // The reflection engine notes it for next cycle.
        break
        
    case 2:
        // Second contradiction — flag for attention.
        // The morning briefing can mention: "Your pattern of X may be changing — I've seen 2 exceptions recently."
        break
        
    case 3...:
        // Pattern is genuinely changing.
        if fact.confidence > 0.5 {
            fact.status = .contradicted
            // Reflection engine will create a replacement fact in the next cycle
            // with updated content reflecting the new pattern
        } else {
            // Low confidence + contradictions = deprecate
            fact.status = .deprecated
        }
    }
}
```

### 5.3 Contradiction Resolution

When a fact enters `.contradicted` status, the reflection engine in its next cycle:
1. Reads the original evidence chain AND the contradicting evidence
2. Determines what the updated pattern is (if any)
3. Creates a new fact with the updated understanding
4. Sets `supersededBy` on the old fact pointing to the new one
5. The old fact moves to `.deprecated`

This creates a clear audit trail: "I used to think X (deprecated), now I think Y (active), because of these episodes."

---

## 6. Query Interface

### 6.1 Full Profile Load (Morning Director)

```swift
func loadActiveProfile(profileId: UUID) async throws -> [SemanticFact]
```

Returns all facts where `status == .active` and `confidence >= 0.25`, ordered by `category` then `confidence DESC`. This is the complete model of the executive that gets loaded into the morning director's system prompt.

Expected size at maturity (6+ months): 50-200 active facts. At ~100 tokens per fact content, this is 5,000-20,000 tokens — within Opus's context window with room to spare.

### 6.2 Category Query

```swift
func loadFacts(
    profileId: UUID,
    category: FactCategory,
    minConfidence: Float = 0.25,
    status: FactStatus = .active
) async throws -> [SemanticFact]
```

Returns facts in a specific category. Used by:
- PlanningEngine: queries `schedulingPref`, `energyPattern`, `avoidance` to parameterise scoring
- Morning director: queries `blindSpot`, `trigger` to generate warnings
- Alert engine: queries `trigger` for proactive intervention criteria

### 6.3 Semantic Search

```swift
func searchFacts(
    profileId: UUID,
    queryEmbedding: [Float],
    topK: Int = 10,
    minConfidence: Float = 0.25
) async throws -> [SemanticFactSearchResult]
```

Finds facts semantically similar to a query. Used when the morning interview mentions a topic and the system needs to retrieve relevant known facts about the executive's relationship to that topic.

### 6.4 Evidence Trace

```swift
func traceEvidence(factId: UUID) async throws -> EvidenceTrace
```

Returns the fact + all source episodes from the evidence chain. Used for explainability: "Why does Timed think this about me?"

```swift
struct EvidenceTrace: Sendable {
    let fact: SemanticFact
    let sourceEpisodes: [Episode]       // from evidence chain
    let contradictingEpisodes: [Episode] // episodes that contradicted this fact
    let supersedes: SemanticFact?        // the fact this one replaced (if any)
    let supersededBy: SemanticFact?      // the fact that replaced this one (if any)
}
```

---

## 7. Supabase RPC Functions

```sql
-- Load full active profile for morning director
CREATE OR REPLACE FUNCTION load_semantic_profile(p_profile_id UUID)
RETURNS SETOF semantic_facts AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM semantic_facts
    WHERE profile_id = p_profile_id
      AND status = 'active'
      AND confidence >= 0.25
    ORDER BY category, confidence DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Semantic search on facts
CREATE OR REPLACE FUNCTION match_semantic_facts(
    p_profile_id UUID,
    p_query_embedding vector(1024),
    p_top_k INT DEFAULT 10,
    p_min_confidence REAL DEFAULT 0.25
) RETURNS TABLE (
    id UUID,
    fact_type TEXT,
    category TEXT,
    subject TEXT,
    content TEXT,
    confidence REAL,
    cosine_similarity REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sf.id,
        sf.fact_type,
        sf.category,
        sf.subject,
        sf.content,
        sf.confidence,
        1 - (sf.embedding <=> p_query_embedding) AS cosine_similarity
    FROM semantic_facts sf
    WHERE sf.profile_id = p_profile_id
      AND sf.status = 'active'
      AND sf.confidence >= p_min_confidence
      AND sf.embedding IS NOT NULL
    ORDER BY sf.embedding <=> p_query_embedding
    LIMIT p_top_k;
END;
$$ LANGUAGE plpgsql STABLE;
```

---

## 8. Integration with Other Layers

### 8.1 Reads From Semantic Memory

| Consumer | What it reads | How it uses it |
|----------|--------------|----------------|
| **Morning Director (Opus)** | Full active profile | System prompt: "Here is everything you know about this executive." Delivers intelligence briefing. |
| **PlanningEngine** | `energyPattern`, `schedulingPref`, `avoidance` | Parameterises scoring: boost/penalise task types at specific times based on learned patterns |
| **Alert Engine** | `trigger`, `blindSpot` | Fires proactive alerts: "You've been in meetings for 3hrs — your data shows decision quality drops after 2.5hrs" |
| **Morning Interview** | `avoidance`, `growthArea` | Asks targeted questions: "You've been deferring the board prep — what's blocking you?" |
| **Profile Card (Opus)** | Full active profile | Generates the user-facing "Here's what I know about you" view |

### 8.2 Writes To Semantic Memory

Only the reflection engine writes to semantic memory. No other component. This is a hard architectural boundary.

### 8.3 Relationship to Procedural Memory

Semantic memory stores WHAT the system knows about the executive. Procedural memory stores WHAT TO DO about it.

Example:
- Semantic fact: "Defers HR tasks on Monday mornings (confidence: 0.85)"
- Procedural rule: "IF task.category == HR AND day == Monday THEN schedule for Tuesday 10am slot"

The procedural rule is derived from the semantic fact. If the semantic fact is deprecated, the procedural rule should be reviewed.

---

## 9. Acceptance Criteria

1. **Facts are created with correct evidence** — Run reflection on 5 episodes of the same pattern (e.g., 5 Monday HR deferrals). A semantic fact is created with `factType == .observation`, `category == .avoidance`, all 5 episode IDs in `evidenceChain`, and `confidence` in the 0.50-0.65 range.

2. **Reinforcement works** — After the initial fact is created, add 3 more supporting episodes. Run reflection. The fact's `reinforcementCount` increases, `confidence` increases (but with diminishing returns), and `lastReinforced` updates.

3. **Decay works** — Create a fact. Advance time by 30 days without reinforcement. Run decay. Confidence has decreased. Advance to 60 days. Fact status transitions to `weakened`.

4. **Contradiction handling works** — Create a fact with confidence 0.7. Submit 3 contradicting episodes across 3 reflection cycles. After the 3rd, the fact's status is `contradicted`. Next reflection cycle creates a replacement fact with `supersededBy` link.

5. **Evidence trace is complete** — Query `traceEvidence` for a fact. Returns the fact, all source episodes, all contradicting episodes, and supersession chain. No broken references.

6. **Morning director receives full profile** — Call `loadActiveProfile`. Returns all active facts with confidence >= 0.25, correctly ordered. Total token count of all fact contents is within budget (< 30,000 tokens).

7. **Semantic search returns relevant facts** — Insert 50 facts across categories. Search with an embedding related to "email habits." Top results are facts in the `communicationStyle` and `workStyle` categories related to email.

8. **No direct client writes** — The Swift client has no public method to create or update semantic facts. Only read methods are exposed. RLS enforces this on the Supabase side.

9. **Supersession chain is navigable** — Deprecate a fact (A), create its replacement (B). `A.supersededBy == B.id`. `A.status == .deprecated`. `B.status == .active`. Query the history of a subject and see the evolution: A → B.

10. **Initial confidence is calibrated** — New observations start at ~0.50, new inferences at ~0.40, new preferences at ~0.55. No fact is ever created with confidence > 0.75 regardless of evidence count. Confidence of 0.99 requires many reinforcement cycles over weeks.
