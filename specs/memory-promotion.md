# Memory Tier Promotion — Implementation Spec

> Timed v1 Intelligence Layer | Last updated: 2026-04-02

---

## 1. Purpose

Timed's memory store has three tiers reflecting cognitive science's model of human memory:

- **Episodic** — Raw events. "Met with Sarah at 2pm about Q3 pipeline. She expressed concern about the Asia deal."
- **Semantic** — Learned facts. "Sarah is cautious about international expansion. The executive tends to override her concerns."
- **Procedural** — Operating rules. "WHEN Sarah raises concerns about international deals, surface them prominently — the executive's override rate on her concerns correlates with 60% negative outcome rate."

This spec defines how memories promote between tiers, how duplicates merge, how conflicts resolve, and how consolidation prevents important memories from being lost.

---

## 2. Promotion Pathways

```
Episodic ──────────► Semantic ──────────► Procedural
  (events)    frequency/     (facts)    reflection/      (rules)
              reflection                 pattern detection
```

There is no demotion. Episodic memories are never deleted by promotion — they persist as evidence. Semantic memories persist when procedural rules are generated from them. The tiers are additive, not replacement.

---

## 3. Episodic → Semantic Promotion

### 3.1 Trigger Conditions

An episodic memory (or cluster of episodic memories) promotes to a semantic fact when **any** of these conditions are met:

**Condition A — Frequency Threshold:**
The same pattern appears in ≥3 episodic memories within a 30-day window.

- "Pattern" is defined by semantic similarity: if 3+ episodic memories have pairwise cosine similarity > 0.75 (Jina v3, 1024-dim embeddings) and share a common theme, they constitute a recurring pattern.
- Detection method: The nightly reflection engine clusters the day's new episodic memories against the existing episodic store. Clusters with ≥3 members that don't already have a corresponding semantic memory trigger promotion.

**Condition B — Reflection Engine Output:**
The nightly Opus reflection engine explicitly identifies a fact about the executive during its reflection pass.

- The reflection engine's output includes structured extractions: `<semantic_fact>` tags wrapping new facts it has synthesised from the day's observations.
- Each extracted fact is checked against existing semantic memories (cosine similarity > 0.85) to avoid duplicates.
- This is the primary promotion pathway — the reflection engine IS the consolidation mechanism.

**Condition C — High-Confidence Single Event:**
A single episodic memory with importance ≥ 0.8 that contains an explicit, unambiguous fact about the executive.

- Example: The executive says in the morning interview "I've decided to leave all hiring decisions to Maria from now on." This is a single event but directly states a procedural change — it promotes immediately.
- Requires importance ≥ 0.8 AND the writing agent flags it as `contains_explicit_declaration: true`.

### 3.2 Semantic Fact Generation

When promotion triggers, the system generates the semantic memory:

**Generator:** Haiku 3.5 (cost-efficient for structured extraction; Opus is reserved for the reflection engine itself).

**Prompt template:**

```
You are extracting a learned fact about an executive from observed events.

Source episodic memories:
{episodic_memories}

Write a single, concise semantic fact that captures what these events reveal 
about the executive. The fact should be:
- About the PERSON, not the events (who they are, how they operate, what they prefer)
- Stated as a present-tense generalisation
- Specific enough to be actionable
- 1-2 sentences maximum

Also rate your confidence in this fact from 0.0 to 1.0.

Format:
FACT: [the semantic fact]
CONFIDENCE: [0.0-1.0]
EVIDENCE_COUNT: [number of supporting episodic memories]
```

### 3.3 Confidence Threshold

A semantic fact must have confidence ≥ 0.6 to be stored. Below that threshold, the fact is logged as a `candidate_semantic` memory with a `pending` flag. It will be re-evaluated at the next nightly reflection with any new supporting evidence.

### 3.4 Evidence Linking

Every semantic memory maintains a `evidence_ids: [UUID]` field linking back to the episodic memories that supported its creation. This serves three purposes:
1. **Explainability** — "I believe this because of these 4 events..."
2. **Conflict resolution** — When challenged, the system can present evidence.
3. **Confidence updates** — As more supporting evidence arrives, confidence increases.

---

## 4. Semantic → Procedural Promotion

### 4.1 What Procedural Memories Are

Procedural memories are IF-THEN rules that guide the system's behaviour. They are not passive facts — they are operational directives.

```
Format: IF [condition] THEN [action/recommendation]

Examples:
- IF meeting_count_today > 5 THEN flag_cognitive_overload AND suggest_cancellation
- IF email_from(Sarah) AND topic(international_expansion) THEN importance += 2
- IF time > 15:00 AND task_type(people_decision) THEN warn_decision_quality_risk
- IF days_since_contact(board_member) > 14 THEN surface_relationship_maintenance_alert
```

### 4.2 Trigger: Reflection Engine Pattern Detection

Procedural rules are generated **only** by the nightly Opus reflection engine. They are never auto-generated from frequency alone — because rules have operational consequences, they require the highest-quality reasoning.

**The reflection engine's procedural generation prompt includes:**

```
Review the executive's semantic facts and recent episodic evidence.

Identify any patterns that can be formalised into IF-THEN operating rules. A valid 
rule must:
1. Be grounded in at least 2 semantic facts or 5 episodic events
2. Have a clear trigger condition that is observable by the system
3. Have a clear action that the system can take (surface, alert, adjust score, flag)
4. Not duplicate an existing procedural rule (existing rules provided below)

For each proposed rule:
RULE: IF [condition] THEN [action]
GROUNDING: [list of semantic fact IDs and/or episodic memory IDs that support this]
CONFIDENCE: [0.0-1.0]
REVERSIBLE: [yes/no — can the system undo this action if the rule is wrong?]
```

### 4.3 Confidence and Activation

- **Confidence ≥ 0.7:** Rule is stored as `active` — immediately operational.
- **Confidence 0.5-0.7:** Rule is stored as `candidate` — logged but not operational. Re-evaluated weekly with new evidence.
- **Confidence < 0.5:** Rule is discarded. The underlying semantic facts remain for future re-evaluation.

### 4.4 Rule Versioning

Procedural rules are versioned. When a rule is updated (modified conditions or actions), the previous version is archived with a `superseded_by` reference. This allows:
- Rollback if a new rule performs worse
- Historical analysis of how the executive's operating patterns have evolved
- The reflection engine to detect oscillation (rule keeps flipping between two states)

---

## 5. Merge Logic for Duplicate/Overlapping Semantic Facts

### 5.1 Detection

Before writing any new semantic memory, check for duplicates:

```
existing = retrieve(query: new_fact.content, tiers: [.semantic], limit: 5, minScore: 0.0)
duplicates = existing.filter { $0.relevanceScore > 0.85 }
```

If `duplicates` is non-empty, this is a merge candidate, not a new memory.

### 5.2 Merge Strategy

**Case 1: Near-identical (relevance > 0.92)**
The new fact is essentially the same as the existing one. Do not create a new memory. Instead:
- Append the new evidence IDs to the existing semantic memory's `evidence_ids`
- Update confidence: `new_confidence = min(1.0, old_confidence + 0.05 * new_evidence_count)`
- Update `last_accessed_at` to now

**Case 2: Overlapping but distinct (relevance 0.85-0.92)**
The facts are related but contain different information. Use Haiku to merge:

```
Existing fact: {existing_fact}
New fact: {new_fact}

These facts overlap. Merge them into a single, more complete semantic fact that 
preserves all information from both. If they contain contradictory information, 
note the contradiction explicitly.

MERGED_FACT: [merged text]
CONTAINS_CONTRADICTION: [yes/no]
```

If no contradiction: replace existing with merged version, combine evidence IDs.
If contradiction: trigger conflict resolution (Section 6).

**Case 3: Below threshold (relevance < 0.85)**
Not a duplicate. Store as a new semantic memory.

### 5.3 Merge Logging

Every merge is logged to a `memory_merge_log` table:

```swift
struct MergeLogEntry {
    let id: UUID
    let timestamp: Date
    let survivingMemoryId: UUID
    let mergedMemoryId: UUID?          // nil if evidence-append only
    let mergeType: MergeType           // .evidenceAppend | .contentMerge | .conflictDetected
    let previousContent: String        // Snapshot of pre-merge state
    let newContent: String
    let confidenceBefore: Float
    let confidenceAfter: Float
}
```

---

## 6. Conflict Resolution

### 6.1 What Constitutes a Conflict

A conflict exists when new evidence contradicts an existing semantic fact.

**Examples:**
- Existing: "The executive always delegates Asia decisions to Sarah."
- New evidence: Three recent episodic memories show the executive handling Asia decisions directly.

**Detection methods:**
1. **Merge-time detection:** The merge process (Section 5.2, Case 2) identifies a contradiction.
2. **Reflection engine detection:** The nightly reflection engine notices episodic evidence that contradicts a semantic fact.
3. **User correction:** The executive explicitly tells the system something it believes is wrong.

### 6.2 Resolution Protocol

**Step 1 — Evidence Audit**
Retrieve all episodic memories linked to the conflicting semantic fact. Also retrieve recent episodic memories that support the new, contradictory information.

**Step 2 — Temporal Analysis**
Split evidence into temporal buckets:
- Old evidence (>30 days): supports the existing fact
- Recent evidence (<30 days): supports the new information

If the pattern clearly shifts over time, this is not a conflict — it's a **behaviour change**. The existing fact should be updated, not defended.

**Step 3 — Resolution Decision (Opus)**

```
A conflict has been detected in the executive's cognitive model.

Existing belief: {existing_semantic_fact}
Supported by: {old_evidence_summary} ({n} events, most recent {days_ago} days ago)

Contradicting evidence: {new_evidence_summary} ({m} events, most recent {days_ago} days ago)

Determine:
1. Is this a genuine behaviour change (the executive has changed)?
2. Is this a contextual exception (different situation, same person)?
3. Is the existing belief wrong (insufficient evidence originally)?

RESOLUTION: [UPDATE | SPLIT | INVALIDATE]
- UPDATE: Modify the existing fact to reflect the new reality
- SPLIT: Create two context-specific facts (e.g., "delegates Asia to Sarah EXCEPT for deals > $10M")
- INVALIDATE: The original fact was wrong. Replace entirely.

NEW_FACT: [the updated/new semantic fact]
CONFIDENCE: [0.0-1.0]
```

**Step 4 — Execute Resolution**
- `UPDATE`: Edit existing semantic memory in place, update evidence links, log the change.
- `SPLIT`: Archive existing memory, create two new context-specific semantic memories.
- `INVALIDATE`: Archive existing memory (don't delete — it's evidence of what we once believed), create replacement.

### 6.3 User Corrections Are Highest Priority

When the executive explicitly corrects the system ("No, that's not why I delayed that decision"), the correction:
- Creates an episodic memory with importance=0.9 and `source_type: .user_correction`
- Immediately triggers conflict resolution against any related semantic facts
- User corrections bypass the confidence threshold — they are treated as ground truth

---

## 7. Consolidation Scheduling

### 7.1 Nightly Consolidation (Primary)

**Trigger:** Runs as part of the nightly reflection engine, every night at 2:00 AM local time (or when the Mac wakes from sleep after 2 AM).

**Process:**
1. Retrieve all episodic memories created today.
2. Cluster by semantic similarity (cosine > 0.75 threshold, single-linkage clustering).
3. For each cluster with ≥2 members: check against existing semantic facts for merge or promotion.
4. Run the full reflection engine (Opus) on the day's events — generates new semantic facts and procedural rules.
5. Run merge logic on all newly generated semantic facts.
6. Run conflict detection on all updated facts.

**Budget:** The nightly consolidation is Opus at maximum effort. No token budget cap. This is the heart of the system.

### 7.2 Weekly Consolidation

**Trigger:** Sunday night, after the nightly consolidation.

**Additional processes:**
1. Re-cluster all episodic memories from the past 7 days — catches patterns that only emerge across a full week.
2. Review all `candidate` semantic facts (confidence 0.5-0.6) — re-evaluate with a week of evidence.
3. Review all `candidate` procedural rules (confidence 0.5-0.7) — activate or discard.
4. Run the procedural rule audit (Section 7.4).

### 7.3 Monthly Consolidation

**Trigger:** First Sunday of each month.

**Additional processes:**
1. Full semantic memory audit — retrieve all semantic facts, check each against the last 30 days of episodic evidence. Flag any fact with zero supporting evidence in the last 30 days as `stale`.
2. Stale facts are not deleted — they are marked `stale` and deprioritised in retrieval (importance multiplied by 0.5).
3. Procedural rule audit with longer time horizon (Section 7.4 with 90-day lookback).
4. Generate a "model evolution report" — what has the system learned this month? What beliefs changed? Stored as a special semantic memory for the executive's review.

### 7.4 Procedural Rule Audit

**Purpose:** Prevent stale rules from persisting. Rules that no longer reflect reality must be identified and deactivated.

**Process:**
1. For each active procedural rule:
   a. Retrieve episodic memories from the last N days (7 for weekly, 90 for monthly) where the rule's trigger condition was met.
   b. Check if the rule's predicted action/outcome matches what actually happened.
   c. If the rule was triggered ≥3 times and the match rate is <50%, flag for review.
   d. If the rule was never triggered in the audit window, check if the trigger condition is still possible (e.g., maybe the executive no longer has meetings with that person).

2. Flagged rules are presented to the reflection engine (Opus) with the evidence:

```
This procedural rule has been flagged for review:
RULE: {rule_content}
Created: {created_at}
Match rate over last {N} days: {match_rate}% ({matches}/{triggers})

Contradicting evidence: {evidence_summary}

Should this rule be: KEPT | MODIFIED | DEACTIVATED
If MODIFIED, provide the updated rule.
```

3. Deactivated rules are archived, not deleted.

---

## 8. Preventing Memory Loss During Consolidation

### 8.1 The Risk

Consolidation (merging, updating, invalidating) creates opportunities to lose information. A merge that over-generalises, an update that drops a nuance, an invalidation that was wrong.

### 8.2 Safeguards

**Safeguard 1 — Episodic memories are immutable.**
Episodic memories are never modified, merged, or deleted by the consolidation process. They are the ground truth. Even if all semantic and procedural memories were lost, the system could rebuild from episodic records.

**Safeguard 2 — Archive, never delete.**
When semantic or procedural memories are superseded, they are archived (flagged `archived: true, archived_at: Date, superseded_by: UUID`) but retained. The archive is excluded from normal retrieval but accessible for audits and rollbacks.

**Safeguard 3 — Pre-consolidation snapshot.**
Before each nightly consolidation run, capture a snapshot of all semantic and procedural memories that will be affected. Store in a `consolidation_snapshots` table with the consolidation run ID. Retention: 30 days of snapshots.

**Safeguard 4 — Merge preserves source content.**
When two semantic facts are merged, the original text of both is stored in the merge log (Section 5.3). The merged text can be regenerated from source if the merge was lossy.

**Safeguard 5 — Importance floor.**
Any memory with importance ≥ 0.8 requires explicit reflection engine approval before it can be merged, updated, or invalidated. The system cannot silently consolidate high-importance memories — Opus must confirm.

**Safeguard 6 — Evidence count floor.**
A semantic fact with ≥10 supporting episodic memories cannot be invalidated by a single contradicting event. It requires ≥3 contradicting events to trigger conflict resolution for well-evidenced facts.

---

## 9. Data Model Additions

Beyond the base `MemoryRecord` from the retrieval spec, promotion requires:

```swift
// Additions to MemoryRecord for promotion tracking
extension MemoryRecord {
    var confidence: Float              // 0.0-1.0, updatable
    var status: PromotionStatus         // .active | .candidate | .stale | .archived
    var evidenceIds: [UUID]            // Episodic memories supporting this fact/rule
    var promotedFrom: [UUID]?          // Memory IDs this was promoted from
    var supersededBy: UUID?            // If archived, the replacement memory
    var version: Int                   // Incremented on every content update
    var containsContradiction: Bool    // Flagged during merge
    var lastAuditedAt: Date?           // Last time the procedural audit checked this
    var triggerCount: Int              // Procedural rules: how many times triggered
    var matchCount: Int                // Procedural rules: how many times prediction matched
}

/// Cross-tier promotion tracking status. Distinct from per-tier status enums:
/// - FactStatus (semantic-memory.md): active, weakened, contradicted, deprecated
/// - RuleStatus (procedural-memory.md): proposed, active, suspended, deprecated
/// - PatternStatus (data-models.md): emerging, confirmed, fading, archived
/// PromotionStatus tracks a memory's position in the promotion pipeline.
enum PromotionStatus: String {
    case active        // Normal operation
    case candidate     // Below confidence threshold, pending more evidence
    case stale         // No supporting evidence in audit window
    case archived      // Superseded or invalidated, retained for history
}
```

**Supabase columns to add to `memories` table:**

```sql
alter table memories add column confidence float default 1.0;
alter table memories add column status text default 'active' 
    check (status in ('active', 'candidate', 'stale', 'archived'));
alter table memories add column evidence_ids uuid[] default '{}';
alter table memories add column promoted_from uuid[];
alter table memories add column superseded_by uuid;
alter table memories add column version int default 1;
alter table memories add column contains_contradiction boolean default false;
alter table memories add column last_audited_at timestamptz;
alter table memories add column trigger_count int default 0;
alter table memories add column match_count int default 0;
```

---

## 10. Metrics and Observability

Track these to validate that promotion is working correctly:

| Metric | Target | Alert if |
|--------|--------|----------|
| Episodic → semantic promotion rate | 5-15% of episodic memories produce semantic facts within 30 days | < 2% (system not learning) or > 30% (over-generalising) |
| Semantic → procedural promotion rate | 5-10% of semantic facts produce rules within 60 days | < 1% (no rules being generated) or > 20% (too many rules) |
| Conflict detection rate | 2-8% of new semantic facts conflict with existing | > 15% (model is unstable) |
| Merge rate | 10-20% of new semantic facts merge with existing | > 40% (generating too many duplicates) |
| Stale fact rate (monthly audit) | < 20% of semantic facts flagged stale | > 40% (model not tracking reality) |
| Procedural rule match rate | > 65% for active rules | < 50% (rules not predictive) |
| User correction frequency | Decreasing month-over-month | Increasing (system not learning from corrections) |
| Archive rate | < 10% of total memories archived per month | > 25% (too much churn in the model) |

---

## 11. Testing Strategy

- **Promotion trigger tests:** Synthetic episodic memories at exact threshold boundaries (2 vs 3 occurrences, 0.74 vs 0.76 cosine similarity) — verify promotion fires/doesn't fire correctly.
- **Merge idempotency:** Run the same evidence through merge logic twice — second run should be a no-op.
- **Conflict resolution paths:** Create deliberate contradictions, verify each resolution type (UPDATE, SPLIT, INVALIDATE) produces correct results.
- **Consolidation safety:** Run consolidation on a known memory set, verify no episodic memories are modified, verify all changes are logged.
- **Rollback test:** Perform a merge, then verify the pre-merge state can be reconstructed from the merge log and snapshots.
- **Evidence floor test:** Attempt to invalidate a high-evidence semantic fact with a single contradiction — verify it is rejected.
