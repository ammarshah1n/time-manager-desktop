# Longitudinal Model Versioning Spec

**Status:** Implementation-ready
**Layer:** 2 (Memory Store) + Layer 3 (Reflection Engine)
**Owner:** ModelVersioningService
**Depends on:** UserIntelligenceStore, ReflectionEngine, CoreData

---

## 1. Purpose

The cognitive model of the executive evolves every night as the reflection engine processes new observations, detects patterns, and updates rules. This evolution is the product's core value — but it also creates risk. A bad reflection cycle could corrupt the model. Gradual drift could go unnoticed. And the executive (and the system itself) needs the ability to look back and understand how the model has changed.

This spec defines:
- How model snapshots are captured and stored
- How diffs between snapshots are computed
- How model drift is distinguished from genuine person change
- How rollback works when a reflection produces a bad update
- How versioning enables longitudinal comparison ("Month 6 vs Month 1")

---

## 2. Model Snapshot Definition

A model snapshot is a complete, serialisable representation of the system's understanding of the executive at a specific point in time.

### 2.1 Snapshot Contents

```swift
struct ModelSnapshot: Codable, Identifiable {
    let id: UUID
    let version: Int                     // monotonically increasing
    let createdAt: Date
    let trigger: SnapshotTrigger         // .weekly, .preReflection, .manual, .milestone
    
    // Semantic Memory State
    let semanticFacts: [SemanticFact]
    let factCount: Int
    let averageConfidence: Float
    let confidenceDistribution: ConfidenceDistribution
    
    // Procedural Memory State
    let activeRules: [ProceduralRule]
    let ruleCount: Int
    let averageRuleConfidence: Float
    let ruleEffectivenessRate: Float     // % of rules that improved outcomes when applied
    
    // Pattern Inventory
    let confirmedPatterns: [PatternSummary]
    let emergingPatterns: [PatternSummary]
    let fadingPatterns: [PatternSummary]
    let archivedPatterns: [PatternSummary]
    let firstOrderPatternCount: Int
    let secondOrderPatternCount: Int
    
    // Performance Curve
    let chronotypeWeights: [Float]       // 48 half-hour weights
    let chronotypeConfidence: Float
    
    // Scoring Parameters
    let thompsonParameters: [TaskCategoryScores]  // alpha/beta per category
    let emaCoefficients: [CategoryEMA]   // EMA state per task category
    
    // Cognitive Load Baseline
    let baselineCognitiveLoad: Float
    let loadTrend: TrendDirection        // .increasing, .stable, .decreasing
    
    // Relationship Map Summary
    let trackedRelationships: Int
    let relationshipHealthScores: [RelationshipScore]
    
    // Model Metadata
    let totalEpisodicMemories: Int
    let totalSemanticFacts: Int
    let totalProceduralRules: Int
    let totalPatternsEverDetected: Int
    let daysSinceInstall: Int
    let reflectionCyclesCompleted: Int
    let sizeBytes: Int                   // serialised size
}

enum SnapshotTrigger: String, Codable {
    case weekly            // automatic, every Sunday 03:00
    case preReflection     // taken before every nightly reflection (safety net)
    case postReflection    // taken after every nightly reflection (for diff)
    case manual            // executive requests via UI
    case milestone         // system-triggered at day 7, 30, 60, 90, 180
}

struct ConfidenceDistribution: Codable {
    let below30: Int       // facts with confidence < 0.3
    let range30to60: Int   // 0.3–0.6
    let range60to80: Int   // 0.6–0.8
    let above80: Int       // > 0.8
}

struct SemanticFact: Codable, Identifiable {
    let id: UUID
    let content: String
    let category: String
    let confidence: Float
    let firstObserved: Date
    let lastReinforced: Date
    let reinforcementCount: Int
    let sourceEpisodicIDs: [UUID]
}

struct ProceduralRule: Codable, Identifiable {
    let id: UUID
    let ruleText: String
    let confidence: Float
    let activationCount: Int
    let lastActivated: Date
    let effectivenessScore: Float?  // nil until enough data
    let sourcePatternIDs: [UUID]
    let status: RuleStatus
}

enum RuleStatus: String, Codable {
    case active
    case suspended       // temporarily disabled after bad outcome
    case retired         // replaced by a better rule
}

struct PatternSummary: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: String             // behavioural, temporal, relational, cognitive, avoidance
    let confidence: Float
    let firstObserved: Date
    let lastObserved: Date
    let observationCount: Int
    let order: Int               // 1 = first-order, 2 = second-order (pattern about patterns)
    let status: String           // emerging, confirmed, fading, archived
}

struct RelationshipScore: Codable {
    let contactName: String
    let healthScore: Float       // 0.0–1.0
    let interactionFrequency: String  // daily, weekly, monthly, quarterly
    let sentimentTrend: TrendDirection
}

enum TrendDirection: String, Codable {
    case increasing
    case stable
    case decreasing
}
```

### 2.2 Snapshot Size

A typical snapshot at month 3:
- ~200 semantic facts × ~100 bytes each = ~20 KB
- ~50 procedural rules × ~150 bytes each = ~7.5 KB
- ~80 patterns × ~120 bytes each = ~9.6 KB
- Performance curve + scoring parameters + metadata = ~5 KB
- **Total: ~42 KB compressed**

At this size, storing 52 weekly snapshots per year = ~2.2 MB. Storage is not a constraint.

---

## 3. Snapshot Schedule

| Trigger | Frequency | Retention |
|---|---|---|
| Pre-reflection | Nightly (before each Opus reflection) | Keep 7 days rolling, then merge into weekly |
| Post-reflection | Nightly (after each Opus reflection) | Keep 7 days rolling, then merge into weekly |
| Weekly | Every Sunday 03:00 | Keep all (permanent archive) |
| Milestone | Day 7, 30, 60, 90, 180, 365 | Keep all (permanent, never delete) |
| Manual | On-demand via UI | Keep all |

**Pre/post reflection pairs** are critical. They allow the system to diff "what the model was before tonight's reflection" vs "what it became after." If the post-reflection model is worse (by any quality metric), rollback is trivial — restore the pre-reflection snapshot.

---

## 4. Diff Capability

### 4.1 Model Diff Structure

```swift
struct ModelDiff: Codable {
    let fromVersion: Int
    let toVersion: Int
    let fromDate: Date
    let toDate: Date
    let periodDays: Int
    
    // Semantic changes
    let factsAdded: [SemanticFact]
    let factsRemoved: [SemanticFact]         // dropped below confidence threshold
    let factsStrengthened: [FactChange]      // confidence increased
    let factsWeakened: [FactChange]          // confidence decreased
    let factsCorrected: [FactCorrection]     // content changed
    let netFactChange: Int
    
    // Rule changes
    let rulesAdded: [ProceduralRule]
    let rulesRetired: [ProceduralRule]
    let rulesSuspended: [ProceduralRule]
    let rulesReactivated: [ProceduralRule]
    let netRuleChange: Int
    
    // Pattern changes
    let patternsNewlyConfirmed: [PatternSummary]
    let patternsStartedFading: [PatternSummary]
    let patternsArchived: [PatternSummary]
    let patternsNewlyEmerging: [PatternSummary]
    let firstOrderDelta: Int
    let secondOrderDelta: Int
    
    // Performance curve shift
    let chronotypeShift: Float               // magnitude of curve change (L2 norm)
    let peakWindowShifted: Bool
    let peakWindowOld: String?               // e.g., "09:00–11:00"
    let peakWindowNew: String?
    
    // Overall model quality
    let averageConfidenceDelta: Float
    let modelSpecificityDelta: Float         // fact count + avg confidence composite
    
    // Classification
    let changeType: ModelChangeType
    let changeMagnitude: ChangeMagnitude
    let summary: String                      // human-readable summary of what changed
}

struct FactChange: Codable {
    let fact: SemanticFact
    let oldConfidence: Float
    let newConfidence: Float
    let delta: Float
}

struct FactCorrection: Codable {
    let factID: UUID
    let oldContent: String
    let newContent: String
    let reason: String                       // what evidence triggered the correction
}

enum ModelChangeType: String, Codable {
    case growth          // model is expanding — new facts, patterns, rules
    case refinement      // model is sharpening — same scope, higher confidence
    case correction      // model is fixing errors — facts changing, rules retiring
    case drift           // model is shifting without clear cause
    case regression      // model quality metrics declined
    case stable          // minimal change
}

enum ChangeMagnitude: String, Codable {
    case negligible      // < 2% of model changed
    case minor           // 2–10%
    case moderate        // 10–25%
    case major           // 25–50%
    case transformative  // > 50% (rare — indicates life change or model correction event)
}
```

### 4.2 Diff Computation

Diffs are computed by the ModelVersioningService on demand (not pre-computed). The algorithm:

1. Load both snapshots from CoreData
2. For semantic facts: match by `id`, compare `confidence` and `content`
3. For procedural rules: match by `id`, compare `confidence`, `status`, and `ruleText`
4. For patterns: match by `id`, compare `status`, `confidence`, and `observationCount`
5. For performance curve: compute L2 distance between the two 48-element weight vectors
6. Classify the change type based on the balance of additions, removals, and confidence shifts
7. Generate a human-readable summary

### 4.3 Diff Queries

The executive can query diffs through the query interface:

- "What has changed about my model this month?" → Compute diff between current snapshot and 4-weeks-ago weekly snapshot
- "How was my model different 3 months ago?" → Load the milestone or nearest weekly snapshot and compute diff
- "What new patterns have you detected recently?" → Filter the last 4 weekly diffs for `patternsNewlyConfirmed`

---

## 5. Detecting Model Drift vs Genuine Person Change

This is the hardest problem in model versioning. When the model shifts, is it because:

**(A) The reflection engine made a bad inference** — model drift, should be corrected
**(B) The executive actually changed** — genuine person change, the model should adapt

### 5.1 Drift Detection Heuristics

| Signal | Suggests Drift (Bad) | Suggests Genuine Change |
|---|---|---|
| Multiple semantic facts change in the same direction overnight | Yes — single reflection overcorrecting | Unlikely |
| Change contradicts 10+ episodic memories | Yes — inference error | No |
| Performance curve shifts > 0.15 in one cycle | Yes — insufficient data for that magnitude | Possible only with major life event |
| Rule retired + replaced by contradictory rule in same cycle | Yes — oscillation | Unlikely |
| Change aligns with a known life event (new role, new quarter, travel) | No | Yes — contextual change |
| Change develops gradually over 3+ weekly snapshots | No | Yes — genuine evolution |
| Executive explicitly confirms the change | No | Definitive yes |

### 5.2 Drift Detection Algorithm

After each nightly reflection, the ModelVersioningService runs:

```
1. Compute diff between pre-reflection and post-reflection snapshots
2. If changeMagnitude >= .moderate:
   a. Flag the reflection for review
   b. Check each changed fact/rule against the episodic evidence base:
      - Count supporting episodic memories (created in last 30 days)
      - Count contradicting episodic memories (created in last 90 days)
      - If contradicting > supporting: classify as DRIFT
      - If supporting > contradicting: classify as GENUINE CHANGE
      - If ambiguous: classify as UNCERTAIN, do not commit the change
   c. For DRIFT: revert the specific facts/rules to pre-reflection state
   d. For GENUINE CHANGE: commit and log the change reason
   e. For UNCERTAIN: hold in a staging area; present to the executive in the next morning session:
      "I noticed something shift in your patterns — [description]. Is this a real change, or was this week unusual?"
```

### 5.3 Gradual Drift Detection

Beyond single-night analysis, the service runs a monthly drift scan:

1. Compare the current weekly snapshot to 4-weeks-ago, 8-weeks-ago, and 12-weeks-ago
2. For each semantic fact and procedural rule, compute a confidence trajectory (linear regression on confidence over time)
3. If a trajectory shows steady decline without corresponding episodic evidence of change: flag as gradual drift
4. Gradual drift is reported in the monthly intelligence report (see intelligence-report.md)

---

## 6. Storage: CoreData Entities

```swift
@objc(CDModelSnapshot)
class CDModelSnapshot: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var version: Int32
    @NSManaged var createdAt: Date
    @NSManaged var trigger: String           // maps to SnapshotTrigger
    @NSManaged var snapshotData: Data        // JSON-encoded ModelSnapshot
    @NSManaged var sizeBytes: Int32
    @NSManaged var factCount: Int16
    @NSManaged var ruleCount: Int16
    @NSManaged var patternCount: Int16
    @NSManaged var averageConfidence: Float
    @NSManaged var modelSpecificity: Float   // composite quality metric
    @NSManaged var isMilestone: Bool
    @NSManaged var isRollbackTarget: Bool    // flagged if this was used as a rollback source
    @NSManaged var pairedSnapshotID: UUID?   // links pre-reflection to post-reflection
}

@objc(CDModelDiffCache)
class CDModelDiffCache: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var fromVersion: Int32
    @NSManaged var toVersion: Int32
    @NSManaged var computedAt: Date
    @NSManaged var diffData: Data            // JSON-encoded ModelDiff
    @NSManaged var changeType: String
    @NSManaged var changeMagnitude: String
    @NSManaged var summary: String
}
```

**Indexes:**
- `CDModelSnapshot`: composite index on `(trigger, createdAt)` for efficient weekly/milestone lookups
- `CDModelSnapshot`: index on `version` for sequential access
- `CDModelDiffCache`: composite index on `(fromVersion, toVersion)` for diff lookup

---

## 7. Rollback Capability

### 7.1 When Rollback is Triggered

Rollback occurs when the system or the executive determines that a reflection cycle produced a worse model.

**Automatic rollback triggers:**
- Drift detection classifies > 3 fact changes as DRIFT in a single cycle
- Model specificity score (fact count * average confidence) drops > 10% in one cycle
- A procedural rule causes 3 consecutive negative outcomes after its creation

**Manual rollback:**
- Executive says "That advice was wrong — go back to how you were" (detected via correction protocol)
- Executive explicitly requests rollback via settings: "Restore model from [date]"

### 7.2 Rollback Process

```
1. Identify the rollback target snapshot (pre-reflection snapshot from the problematic night)
2. Load the target snapshot's semantic facts and procedural rules
3. For each fact in the current model:
   a. If the fact exists in the target snapshot: restore the target version (confidence, content)
   b. If the fact does NOT exist in the target (it was added by the bad reflection): delete it
   c. If a fact exists in the target but not in current (it was deleted by the bad reflection): restore it
4. Same process for procedural rules
5. Patterns: restore pattern statuses from target snapshot
6. Performance curve: restore the target curve if it was modified
7. Mark the rolled-back reflection cycle as "reverted" in the reflection log
8. Create a new post-rollback snapshot
9. Log the rollback as a high-importance episodic memory:
   "Model rolled back to version [X] from [date]. Reason: [reason]. Changes reverted: [count]."
```

### 7.3 Rollback Scope

Rollback can be:
- **Full:** Restore the entire model to a previous snapshot. Used for catastrophic reflection failures.
- **Partial:** Revert only specific facts or rules. Used when the reflection was mostly good but made a few bad inferences. The executive or the drift detector specifies which items to revert.

### 7.4 Rollback Limitations

- Rollback restores the model state, NOT the episodic memory store. Raw observations are never deleted or modified by rollback. This means the next reflection cycle will re-process the same observations — the system needs a "reflection blacklist" to prevent re-generating the same bad inference.
- The reflection blacklist stores: `(episodicMemoryIDs: [UUID], badInference: String, blacklistedAt: Date)`. The reflection engine checks this before generating inferences.

---

## 8. Longitudinal Comparison ("Month 6 vs Month 1")

### 8.1 Comparison Capability

The system supports arbitrary snapshot comparison. Common comparisons:

| Comparison | Source | Target |
|---|---|---|
| "How has my model changed this month?" | 4 weeks ago (weekly snapshot) | Current |
| "Month 6 vs Month 1" | Day-30 milestone | Day-180 milestone |
| "Before and after the reorg" | Nearest weekly snapshot before event | Current |
| "Show me the trend" | All weekly snapshots | Trend analysis |

### 8.2 Comparison Output

```swift
struct LongitudinalComparison {
    let fromSnapshot: ModelSnapshot
    let toSnapshot: ModelSnapshot
    let diff: ModelDiff
    let narrative: String            // human-readable story of the evolution
    let highlights: [ComparisonHighlight]
}

struct ComparisonHighlight {
    let category: String             // "Patterns", "Rules", "Confidence", "Performance"
    let description: String
    let significance: Float          // 0.0–1.0
}
```

**Narrative example (Month 6 vs Month 1):**

"In month 1, I knew 23 facts about you with an average confidence of 0.41. Today I know 187 facts with an average confidence of 0.74. I've confirmed 34 behavioural patterns — 8 of which are second-order patterns (patterns about your patterns). Your performance curve has stabilised and I can now predict your energy level for any given hour with 78% accuracy. The biggest evolution: in month 1, I treated your hiring decisions as individual events. By month 4, I detected a consistent avoidance pattern — you defer people decisions until they become crises. This pattern has been confirmed 6 times."

### 8.3 Trend Visualisation Data

The system produces time-series data for trend charts (rendered by the UI layer):

```swift
struct ModelTrend {
    let metric: TrendMetric
    let dataPoints: [(date: Date, value: Float)]
}

enum TrendMetric {
    case factCount
    case averageConfidence
    case ruleCount
    case ruleEffectiveness
    case firstOrderPatterns
    case secondOrderPatterns
    case modelSpecificity      // composite: factCount * avgConfidence
    case predictionAccuracy    // tracked from day plan outcomes
    case chronotypeStability   // how much the curve changes week-to-week
}
```

---

## 9. Retention and Cleanup

| Snapshot Type | Retention Policy |
|---|---|
| Pre/post-reflection (nightly) | 7 days rolling. After 7 days, only the post-reflection snapshot is kept, merged into the weekly. |
| Weekly | Permanent. Never deleted. |
| Milestone | Permanent. Never deleted. |
| Manual | Permanent unless manually deleted by executive. |
| Diff caches | 90 days. Re-computed on demand if needed beyond this. |

**Estimated storage at 1 year:**
- 52 weekly snapshots × ~42 KB = ~2.2 MB
- 6 milestone snapshots × ~42 KB = ~252 KB
- 7 rolling nightly × 2 (pre/post) × ~42 KB = ~588 KB
- **Total: ~3 MB/year** — negligible.

---

## 10. API Surface

```swift
protocol ModelVersioningService {
    /// Take a snapshot now with the given trigger
    func captureSnapshot(trigger: SnapshotTrigger) async throws -> ModelSnapshot
    
    /// Get a specific snapshot by version number
    func getSnapshot(version: Int) async throws -> ModelSnapshot?
    
    /// Get the most recent snapshot
    func latestSnapshot() async throws -> ModelSnapshot
    
    /// Get all milestone snapshots
    func milestoneSnapshots() async throws -> [ModelSnapshot]
    
    /// Compute diff between two versions
    func diff(from: Int, to: Int) async throws -> ModelDiff
    
    /// Run drift detection on the latest reflection cycle
    func detectDrift(preVersion: Int, postVersion: Int) async throws -> DriftReport
    
    /// Rollback to a specific version (full)
    func rollback(toVersion: Int) async throws -> RollbackResult
    
    /// Rollback specific items only (partial)
    func rollbackPartial(toVersion: Int, factIDs: [UUID], ruleIDs: [UUID]) async throws -> RollbackResult
    
    /// Get trend data for a metric
    func trend(metric: TrendMetric, from: Date, to: Date) async throws -> ModelTrend
    
    /// Generate a longitudinal comparison
    func compare(fromVersion: Int, toVersion: Int) async throws -> LongitudinalComparison
}

struct DriftReport {
    let driftDetected: Bool
    let driftItems: [DriftItem]
    let recommendation: DriftRecommendation  // .noAction, .partialRollback, .fullRollback, .askUser
}

struct DriftItem {
    let itemType: DriftItemType   // .fact, .rule, .pattern
    let itemID: UUID
    let description: String
    let supportingEvidence: Int
    let contradictingEvidence: Int
    let classification: DriftClassification  // .drift, .genuineChange, .uncertain
}

struct RollbackResult {
    let success: Bool
    let factsReverted: Int
    let rulesReverted: Int
    let patternsReverted: Int
    let newSnapshotVersion: Int
}
```

---

## 11. Integration with Reflection Engine

The reflection engine interacts with versioning at these points:

1. **Before reflection:** `captureSnapshot(trigger: .preReflection)`
2. **During reflection:** The reflection engine has read access to the last 4 weekly snapshots so it can reference its own trajectory ("Last week I learned X — this week's data reinforces/contradicts it")
3. **After reflection:** `captureSnapshot(trigger: .postReflection)` then `detectDrift(preVersion:, postVersion:)`
4. **On drift detection:** If drift is detected, the versioning service can autonomously revert specific changes before the morning session
5. **Morning session context:** The morning director receives the latest diff summary so it can narrate what changed: "Overnight, I updated my understanding of your Thursday patterns based on yesterday's data."

---

## 12. Edge Cases

| Scenario | Behaviour |
|---|---|
| First-ever snapshot (day 1) | Create with `trigger: .milestone`. All metrics will be low — this is the baseline. |
| Reflection fails mid-cycle (API timeout) | Pre-reflection snapshot exists, post-reflection does not. The model is unchanged. Log the failure. Retry next night. |
| Two rollbacks in 48 hours | After second rollback, pause automatic reflection for 48 hours and surface: "I've had trouble updating your model reliably. I'm pausing overnight analysis for 2 days and will try again with a more conservative approach." The next reflection runs with a reduced update rate (max 5 fact changes per cycle). |
| Executive changes role (CEO → board member) | Detected by calendar/email pattern shift. The system captures a milestone snapshot, flags the model as entering a "transition period," and reduces confidence on all role-specific semantic facts by 30%. |
| Snapshot storage corruption | Each snapshot is JSON-encoded with a SHA-256 checksum. On load, verify checksum. If corrupt, fall back to previous valid snapshot and log the corruption. |
