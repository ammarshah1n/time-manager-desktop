# Timed — Master Data Models

> Implementation-ready specification. Every entity, attribute, relationship, enum, and constraint the system needs. A developer opens Xcode and builds from this document.

**Last updated:** 2026-04-02
**Target:** macOS 14+ (Sonoma), Swift 5.9+

---

## Storage Engine Decision: CoreData

**Recommendation: CoreData with NSPersistentContainer, not SwiftData.**

Rationale:
1. **Background processing** — Timed runs continuous background agents and a nightly reflection engine. CoreData's `newBackgroundContext()` and `performBackgroundTask` are battle-tested for multi-context concurrent writes. SwiftData's `ModelActor` is functional but less mature for heavy background pipelines.
2. **Complex queries** — Memory retrieval requires compound predicates (recency x importance x relevance scoring). CoreData's `NSFetchRequest` with `NSCompoundPredicate` and `NSSortDescriptor` chains handle this natively. SwiftData's `#Predicate` macro has limitations with complex expressions.
3. **Migration control** — The data model will evolve aggressively as new signal sources and memory types are added. CoreData's lightweight migration handles additive changes automatically; heavyweight migration with mapping models gives full control. SwiftData migration is still limited.
4. **Embedding storage** — 1024-dim float vectors stored as `Transformable` with a custom `ValueTransformer` for `[Float]` → `Data` conversion. SwiftData has no equivalent to `Transformable`.
5. **Relationship cascade rules** — Fine-grained delete rules (cascade, nullify, deny) per relationship. SwiftData supports `@Relationship(deleteRule:)` but CoreData's `.xcdatamodeld` editor gives visual control.

**SwiftData migration path:** If macOS 16+ drops CoreData improvements or SwiftData matures for background contexts, the `NSManagedObject` subclasses can be migrated to `@Model` classes. The repository pattern (see architecture.md) isolates storage from business logic, making this swap non-breaking.

---

## Entity Relationship Overview (Text Diagram)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        LAYER 1: SIGNAL INGESTION                     │
├─────────────────────────────────────────────────────────────────────┤
│  Signal ──1:1──► EpisodicMemory                                      │
│  EmailSignal ──1:M──► Signal                                         │
│  CalendarEvent ──1:M──► Signal                                       │
│  VoiceSession ──1:M──► Signal                                        │
│  AppFocusSession ──1:M──► Signal                                     │
├─────────────────────────────────────────────────────────────────────┤
│                        LAYER 2: MEMORY STORE                         │
├─────────────────────────────────────────────────────────────────────┤
│  EpisodicMemory ──M:M──► SemanticMemory (via EpisodicSemanticLink)  │
│  EpisodicMemory ──M:M──► Pattern (via PatternEpisodicLink)          │
│  SemanticMemory ──M:M──► ProceduralMemory (via SemanticProceduralLink)│
│  CoreMemoryEntry (standalone, fixed-size buffer)                     │
│  UserProfile ──1:1──► (singleton per workspace)                      │
├─────────────────────────────────────────────────────────────────────┤
│                        LAYER 3: REFLECTION ENGINE                    │
├─────────────────────────────────────────────────────────────────────┤
│  Pattern ──1:M──► Rule                                               │
│  ReflectionRun (audit log of each nightly/triggered run)             │
├─────────────────────────────────────────────────────────────────────┤
│                        LAYER 4: INTELLIGENCE DELIVERY                │
├─────────────────────────────────────────────────────────────────────┤
│  Task ──1:M──► FocusSession                                         │
│  Task ──1:M──► CompletionRecord                                     │
│  Task ──M:1──► CalendarEvent (optional scheduled slot)               │
│  MLModelState (singleton per model type)                             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Layer 1: Signal Ingestion Entities

### Signal

The universal signal envelope. Every external observation enters the system as a Signal. Lightweight — carries metadata and a reference to the raw payload, not the payload itself.

```swift
@objc(CDSignal)
final class CDSignal: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var timestamp: Date
    @NSManaged var source: String           // SignalSource.rawValue
    @NSManaged var modalityTag: String      // "text", "voice", "calendar", "behaviour", "system"
    @NSManaged var rawPayloadRef: String?   // file path or inline JSON key for large payloads
    @NSManaged var isProcessed: Bool
    @NSManaged var processedAt: Date?
    @NSManaged var layerOneMetadata: Data?  // JSON blob for source-specific metadata
    @NSManaged var createdAt: Date

    // Relationships
    @NSManaged var episodicMemory: CDEpisodicMemory?   // 1:1, created when signal is processed
    @NSManaged var emailSignal: CDEmailSignal?          // inverse: nullable
    @NSManaged var calendarEvent: CDCalendarEvent?      // inverse: nullable
    @NSManaged var voiceSession: CDVoiceSession?        // inverse: nullable
    @NSManaged var appFocusSession: CDAppFocusSession?  // inverse: nullable
}
```

**Constraints:**
- `id` is unique
- `source` must be a valid `SignalSource` raw value
- `timestamp` is required, defaults to creation time
- Cascade: deleting a Signal deletes its linked EpisodicMemory

---

### EmailSignal

Everything captured from Microsoft Graph for a single email message.

```swift
@objc(CDEmailSignal)
final class CDEmailSignal: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var graphMessageId: String       // Microsoft Graph message ID
    @NSManaged var conversationId: String?      // Graph conversation thread ID
    @NSManaged var internetMessageId: String?   // RFC 822 Message-ID header
    @NSManaged var subject: String
    @NSManaged var senderName: String?
    @NSManaged var senderAddress: String
    @NSManaged var recipientAddresses: Data     // JSON array of strings
    @NSManaged var ccAddresses: Data            // JSON array of strings
    @NSManaged var sentAt: Date?
    @NSManaged var receivedAt: Date
    @NSManaged var isRead: Bool
    @NSManaged var importanceFlag: String        // "low", "normal", "high"
    @NSManaged var isReply: Bool
    @NSManaged var bodyPreview: String?          // first ~255 chars
    @NSManaged var bodyText: String?             // full plain-text body for NLP (nil if privacy-restricted)
    @NSManaged var parentFolderId: String?       // Inbox, SentItems, etc.
    @NSManaged var hasAttachments: Bool
    @NSManaged var attachmentCount: Int16
    @NSManaged var responseLatencySeconds: Int32 // computed: time from received to user's reply (0 if no reply yet)
    @NSManaged var triageBucket: String?         // TaskBucket.rawValue after classification
    @NSManaged var triageConfidence: Float
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    // Relationships
    @NSManaged var signals: NSSet?              // 1:M → CDSignal (one email can generate multiple signals over time)
    @NSManaged var task: CDTask?                // nullable — only if email spawned a task
}
```

**Constraints:**
- `graphMessageId` is unique (upsert key for delta sync)
- `senderAddress` is required
- `receivedAt` is required
- Delete rule: nullify on signals, nullify on task

---

### CalendarEvent

Everything captured from Microsoft Graph for a calendar event.

```swift
@objc(CDCalendarEvent)
final class CDCalendarEvent: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var graphEventId: String         // Microsoft Graph event ID
    @NSManaged var subject: String
    @NSManaged var startTime: Date
    @NSManaged var endTime: Date
    @NSManaged var durationMinutes: Int16        // computed: endTime - startTime
    @NSManaged var location: String?
    @NSManaged var isAllDay: Bool
    @NSManaged var isRecurring: Bool
    @NSManaged var seriesMasterId: String?       // Graph series master for recurring events
    @NSManaged var attendeeCount: Int16
    @NSManaged var attendeeNames: Data?          // JSON array of strings
    @NSManaged var organiserName: String?
    @NSManaged var organiserAddress: String?
    @NSManaged var isOrganiser: Bool             // true if the user organised this meeting
    @NSManaged var responseStatus: String        // "accepted", "tentative", "declined", "none"
    @NSManaged var isCancelled: Bool
    @NSManaged var category: String              // BlockCategory.rawValue
    @NSManaged var onlineMeetingUrl: String?
    @NSManaged var actualEndTime: Date?          // set if meeting ran over/under — nil until observed
    @NSManaged var preEventActions: String?       // what the user did in the 15 min before (app focus data)
    @NSManaged var postEventActions: String?      // what the user did in the 15 min after
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    // Relationships
    @NSManaged var signals: NSSet?               // 1:M → CDSignal
    @NSManaged var scheduledTasks: NSSet?         // M:M → CDTask (tasks scheduled in this slot)
}
```

**Constraints:**
- `graphEventId` is unique (upsert key)
- `startTime` < `endTime`
- Delete rule: nullify on signals, nullify on scheduledTasks

---

### VoiceSession

A single voice interaction — morning session, ad-hoc capture, or focus debrief.

```swift
@objc(CDVoiceSession)
final class CDVoiceSession: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var sessionType: String          // VoiceSessionType.rawValue
    @NSManaged var startedAt: Date
    @NSManaged var endedAt: Date?
    @NSManaged var durationSeconds: Int32
    @NSManaged var transcriptText: String        // full transcript
    @NSManaged var wordCount: Int32
    @NSManaged var speakingPaceWPM: Float        // words per minute
    @NSManaged var detectedTopics: Data?         // JSON array of strings
    @NSManaged var sentimentScore: Float         // -1.0 (negative) to +1.0 (positive)
    @NSManaged var energyLevelInference: String? // EnergyLevel.rawValue, inferred from prosody
    @NSManaged var confidenceScore: Float        // speech recognition confidence average
    @NSManaged var aiResponseText: String?       // the AI's generated response/plan
    @NSManaged var aiModelUsed: String?          // "haiku-3.5", "sonnet-4", "opus-4"
    @NSManaged var createdAt: Date

    // Relationships
    @NSManaged var signals: NSSet?               // 1:M → CDSignal
    @NSManaged var extractedTasks: NSSet?         // 1:M → CDTask (tasks extracted from voice)
}
```

**Constraints:**
- `startedAt` is required
- `transcriptText` is required (can be empty string for failed sessions)
- Delete rule: nullify on signals, nullify on extractedTasks

---

### AppFocusSession

A continuous period of focus on a single application. Created when the user switches to an app, closed when they switch away.

```swift
@objc(CDAppFocusSession)
final class CDAppFocusSession: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var bundleId: String              // e.g., "com.apple.mail"
    @NSManaged var appName: String               // e.g., "Mail"
    @NSManaged var windowTitle: String?          // optional — privacy-controlled via user setting
    @NSManaged var startedAt: Date
    @NSManaged var endedAt: Date?
    @NSManaged var durationSeconds: Int32
    @NSManaged var classification: String        // AppWorkCategory.rawValue
    @NSManaged var contextSwitchCount: Int16     // times user switched away and back within this session
    @NSManaged var isPrivacyRedacted: Bool       // true if user has opted out of window title capture
    @NSManaged var createdAt: Date

    // Relationships
    @NSManaged var signals: NSSet?               // 1:M → CDSignal
}
```

**Constraints:**
- `bundleId` is required
- `startedAt` is required
- Delete rule: nullify on signals

---

## Layer 2: Memory Store Entities

### EpisodicMemory

Raw timestamped events from any signal source. The foundation of the memory system. Every signal that passes Layer 1 processing generates exactly one episodic memory.

```swift
@objc(CDEpisodicMemory)
final class CDEpisodicMemory: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var timestamp: Date               // when the event occurred (not when it was stored)
    @NSManaged var sourceModality: String         // SignalSource.rawValue
    @NSManaged var content: String                // human-readable summary of the event
    @NSManaged var rawContentRef: String?         // reference to full raw content if too large for content field
    @NSManaged var importanceScore: Float         // 0.0–1.0, set by Layer 1 classifier (Haiku)
    @NSManaged var accessCount: Int32             // incremented each time this memory is retrieved
    @NSManaged var lastAccessedAt: Date?
    @NSManaged var embeddingVector: Data?         // 1024-dim Jina embedding as [Float] → Data
    @NSManaged var embeddingModelVersion: String? // "jina-embeddings-v3" for future migration
    @NSManaged var metadataBlob: Data?            // JSON blob for source-specific metadata
    @NSManaged var isConsolidated: Bool           // true after this memory has been consolidated into semantic
    @NSManaged var consolidatedAt: Date?
    @NSManaged var createdAt: Date

    // Relationships
    @NSManaged var signal: CDSignal?                          // 1:1 inverse
    @NSManaged var semanticMemories: NSSet?                   // M:M → CDSemanticMemory via join entity
    @NSManaged var contributingPatterns: NSSet?               // M:M → CDPattern via join entity

    // MARK: - Retrieval Score (computed, not stored)

    /// Stanford Generative Agents retrieval score: recency x importance x relevance.
    /// `relevanceSimilarity` is the cosine similarity to the query embedding (0.0–1.0).
    func retrievalScore(now: Date, relevanceSimilarity: Float) -> Float {
        let hoursSinceAccess = Float(now.timeIntervalSince(lastAccessedAt ?? timestamp) / 3600)
        let recency = 1.0 / (1.0 + hoursSinceAccess * 0.01)  // decay factor
        return recency * importanceScore * relevanceSimilarity
    }
}
```

**Constraints:**
- `id` is unique
- `importanceScore` must be in 0.0...1.0
- `embeddingVector` is 4096 bytes when present (1024 floats x 4 bytes)
- Delete rule: cascade to join entities, nullify on signal

---

### SemanticMemory

Learned facts about the user. Extracted from patterns across multiple episodic memories. This is what Timed "knows" about the executive.

```swift
@objc(CDSemanticMemory)
final class CDSemanticMemory: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var key: String                   // human-readable key, e.g., "prefers_morning_deep_work"
    @NSManaged var value: String                 // the learned fact: "User consistently schedules deep work 9-11am"
    @NSManaged var category: String              // SemanticCategory.rawValue
    @NSManaged var confidenceScore: Float        // 0.0–1.0, increases with reinforcement
    @NSManaged var reinforcementCount: Int32     // how many episodic memories have confirmed this
    @NSManaged var contradictionCount: Int32     // how many have contradicted it
    @NSManaged var firstObservedAt: Date
    @NSManaged var lastReinforcedAt: Date
    @NSManaged var embeddingVector: Data?         // 1024-dim Jina embedding
    @NSManaged var isActive: Bool                // false if confidence dropped below threshold
    @NSManaged var supersededById: UUID?          // if this fact was replaced by a newer one
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    // Relationships
    @NSManaged var episodicMemories: NSSet?       // M:M → CDEpisodicMemory (contributing memories)
    @NSManaged var proceduralMemories: NSSet?     // M:M → CDProceduralMemory (rules derived from this fact)
}
```

**Constraints:**
- `key` is unique within active records
- `confidenceScore` must be in 0.0...1.0
- Deactivation threshold: confidence < 0.3 after contradictionCount >= 3
- Delete rule: nullify on join entities

---

### ProceduralMemory

Operating rules the system has learned from confirmed patterns. These are the "if X, then Y" rules that drive the planning engine and morning briefings.

```swift
@objc(CDProceduralMemory)
final class CDProceduralMemory: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var ruleText: String              // "When user has back-to-back meetings exceeding 2h, schedule 15m recovery before next task"
    @NSManaged var ruleKey: String               // machine-readable key: "post_meeting_recovery"
    @NSManaged var ruleType: String              // ProceduralRuleType.rawValue
    @NSManaged var conditionJson: Data?          // JSON: when this rule applies {"trigger": "meeting_block > 120min"}
    @NSManaged var actionJson: Data?             // JSON: what the rule recommends {"insert": "recovery_break", "duration": 15}
    @NSManaged var confidenceScore: Float        // 0.0–1.0
    @NSManaged var activationCount: Int32        // times this rule has been triggered
    @NSManaged var lastActivatedAt: Date?
    @NSManaged var exceptionNotes: String?       // known exceptions discovered over time
    @NSManaged var exceptionCount: Int16
    @NSManaged var status: String                // RuleStatus.rawValue
    @NSManaged var sourcePatternId: UUID?        // the Pattern that generated this rule
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    // Relationships
    @NSManaged var sourcePattern: CDPattern?      // M:1 → CDPattern
    @NSManaged var semanticMemories: NSSet?       // M:M → CDSemanticMemory
}
```

**Constraints:**
- `ruleKey` is unique
- `conditionJson` is required (rules without conditions are invalid)
- Delete rule: nullify on sourcePattern, nullify on semanticMemories

---

### CoreMemoryEntry (MemGPT-Style Fixed Buffer)

Always-in-context user profile facts. These are injected into every AI prompt's system message. Fixed-size buffer with a hard cap (default: 50 entries, ~4K tokens).

```swift
@objc(CDCoreMemoryEntry)
final class CDCoreMemoryEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var content: String               // "User is CEO of PFF Group. Manages 200+ staff across 6 entities."
    @NSManaged var section: String               // CoreMemorySection.rawValue
    @NSManaged var priorityRank: Int16           // 0 = highest priority, used for eviction
    @NSManaged var source: String                // how this was learned: "voice_session", "reflection", "manual"
    @NSManaged var lastUpdatedAt: Date
    @NSManaged var createdAt: Date
}
```

**Buffer management:**
- Hard cap: 50 entries
- When full: evict lowest-priority entry (highest `priorityRank`)
- Before eviction, demote to SemanticMemory (never lose information)
- Priority recalculation: run weekly during nightly reflection
- Sections organize the buffer: `identity`, `workStyle`, `relationships`, `currentContext`, `preferences`

**Constraints:**
- `content` max length: 500 characters
- `section` must be valid CoreMemorySection
- `priorityRank` unique within active entries

---

### Pattern

Named behavioural patterns discovered by the reflection engine. The bridge between raw observation and actionable intelligence.

```swift
@objc(CDPattern)
final class CDPattern: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String                  // "Monday morning avoidance"
    @NSManaged var patternDescription: String     // full description for morning briefing
    @NSManaged var patternType: String            // PatternType.rawValue
    @NSManaged var confidenceScore: Float         // 0.0–1.0
    @NSManaged var firstObservedAt: Date
    @NSManaged var lastObservedAt: Date
    @NSManaged var observationCount: Int32
    @NSManaged var status: String                 // PatternStatus.rawValue
    @NSManaged var trendDirection: String          // "strengthening", "stable", "weakening"
    @NSManaged var impactAssessment: String?       // how this pattern affects the executive's effectiveness
    @NSManaged var embeddingVector: Data?           // 1024-dim for similarity search
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    // Relationships
    @NSManaged var episodicMemories: NSSet?        // M:M → CDEpisodicMemory
    @NSManaged var rules: NSSet?                   // 1:M → CDProceduralMemory
}
```

**Constraints:**
- `name` is unique
- Status lifecycle: `emerging` → `confirmed` → `fading` → `archived`
  - `emerging`: observationCount < 3
  - `confirmed`: observationCount >= 3 AND confidenceScore >= 0.6
  - `fading`: not observed in 14+ days AND was confirmed
  - `archived`: not observed in 30+ days OR manually archived
- Delete rule: cascade to rules, nullify on episodicMemories join

---

### Rule (Reflection Engine Output)

Actionable rules generated from confirmed patterns. Consumed by PlanningEngine and morning session.

```swift
@objc(CDRule)
final class CDRule: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var ruleText: String
    @NSManaged var ruleKey: String
    @NSManaged var sourcePatternId: UUID?
    @NSManaged var confidenceScore: Float
    @NSManaged var activationCount: Int32
    @NSManaged var lastActivatedAt: Date?
    @NSManaged var status: String                 // RuleStatus.rawValue
    @NSManaged var createdAt: Date

    // Relationships
    @NSManaged var sourcePattern: CDPattern?
}
```

> **Note:** CDRule and CDProceduralMemory are closely related. CDRule is the simpler planning-engine-facing entity. CDProceduralMemory is the full memory-tier entity with conditions, actions, and exceptions. During reflection, Opus generates ProceduralMemories; a subset are promoted to Rules for the PlanningEngine.

---

## Layer 3: Reflection Engine Entities

### ReflectionRun

Audit log for each reflection cycle. Critical for debugging intelligence quality and tracking compounding progress.

```swift
@objc(CDReflectionRun)
final class CDReflectionRun: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var runType: String               // "nightly", "triggered", "weekly_consolidation"
    @NSManaged var startedAt: Date
    @NSManaged var completedAt: Date?
    @NSManaged var status: String                // "running", "completed", "failed", "partial"
    @NSManaged var episodicMemoriesProcessed: Int32
    @NSManaged var patternsDiscovered: Int16
    @NSManaged var patternsReinforced: Int16
    @NSManaged var semanticMemoriesCreated: Int16
    @NSManaged var semanticMemoriesUpdated: Int16
    @NSManaged var proceduralRulesGenerated: Int16
    @NSManaged var coreMemoryUpdates: Int16
    @NSManaged var aiModelUsed: String           // "opus-4"
    @NSManaged var inputTokenCount: Int32
    @NSManaged var outputTokenCount: Int32
    @NSManaged var totalCostUSD: Float           // for cost tracking (informational only)
    @NSManaged var rawOutputRef: String?          // file path to full AI response for audit
    @NSManaged var errorMessage: String?
    @NSManaged var createdAt: Date
}
```

---

## Layer 4: Intelligence Delivery Entities

### Task

The primary work unit. Extends the existing `TimedTask` struct with CoreData persistence and ML parameters.

```swift
@objc(CDTask)
final class CDTask: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var taskDescription: String?
    @NSManaged var sender: String?
    @NSManaged var bucket: String                // TaskBucket.rawValue
    @NSManaged var status: String                // TaskStatus.rawValue
    @NSManaged var estimatedMinutes: Int16
    @NSManaged var actualMinutes: Int16          // 0 until completed
    @NSManaged var estimateUncertainty: Int16    // EMA uncertainty in minutes
    @NSManaged var priority: Int16               // 0–5 scale
    @NSManaged var energyLevel: String           // EnergyLevel.rawValue
    @NSManaged var dueAt: Date?
    @NSManaged var completedAt: Date?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    // Planning flags
    @NSManaged var isDoFirst: Bool
    @NSManaged var isDailyUpdate: Bool
    @NSManaged var isFamilyEmail: Bool
    @NSManaged var isTransitSafe: Bool
    @NSManaged var deferredCount: Int16

    // Thompson sampling parameters (per-task posterior)
    @NSManaged var tsAlpha: Float               // Beta distribution alpha (successes + 1)
    @NSManaged var tsBeta: Float                // Beta distribution beta (failures + 1)

    // EMA parameters
    @NSManaged var emaEstimate: Float           // current EMA estimate in minutes
    @NSManaged var emaSampleCount: Int16        // number of observations
    @NSManaged var emaAlpha: Float              // smoothing factor (default 0.3)

    // Scheduling
    @NSManaged var scheduledStartTime: Date?
    @NSManaged var scheduledEndTime: Date?
    @NSManaged var planScore: Int32             // composite score from PlanningEngine

    // Source tracking
    @NSManaged var sourceType: String?          // "email", "voice", "manual", "calendar"
    @NSManaged var sourceEmailId: UUID?
    @NSManaged var sourceVoiceSessionId: UUID?

    // Relationships
    @NSManaged var focusSessions: NSSet?         // 1:M → CDFocusSession
    @NSManaged var completionRecords: NSSet?     // 1:M → CDCompletionRecord
    @NSManaged var sourceEmail: CDEmailSignal?   // M:1 optional
    @NSManaged var calendarSlot: CDCalendarEvent? // M:1 optional
    @NSManaged var replyMedium: String?          // ReplyMedium.rawValue, nil if not a reply task
    @NSManaged var waitingOn: String?
    @NSManaged var askedDate: Date?
    @NSManaged var expectedByDate: Date?
}
```

**Thompson Sampling Usage:**
- `tsAlpha` starts at 1.0 (prior: uniform)
- `tsBeta` starts at 1.0
- On completion: `tsAlpha += 1`
- On deferral: `tsBeta += 1`
- Sampling: draw from Beta(tsAlpha, tsBeta) via Gaussian approximation
- Score bump: sample × 250 (max Thompson bump)

**EMA Usage:**
- `emaEstimate` starts at `estimatedMinutes`
- On completion with actual time: `emaEstimate = emaAlpha * actual + (1 - emaAlpha) * emaEstimate`
- `emaSampleCount` incremented on each update
- After 5 samples, `emaAlpha` reduces from 0.3 to 0.15 (stabilization)

**Constraints:**
- `id` is unique
- `tsAlpha` >= 1.0, `tsBeta` >= 1.0
- `emaAlpha` in 0.0...1.0
- Delete rule: cascade to focusSessions and completionRecords, nullify on sourceEmail

---

### FocusSession

A timed focus period linked to a task. Feeds completion data back into the ML loop.

```swift
@objc(CDFocusSession)
final class CDFocusSession: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var startedAt: Date
    @NSManaged var pausedAt: Date?
    @NSManaged var endedAt: Date?
    @NSManaged var totalSeconds: Int32
    @NSManaged var plannedSeconds: Int32         // what the user set
    @NSManaged var pomodoroIndex: Int16          // 0-based index in a Pomodoro sequence
    @NSManaged var wasCompleted: Bool            // did the timer run to completion
    @NSManaged var outcome: String               // FocusOutcome.rawValue
    @NSManaged var interruptionCount: Int16
    @NSManaged var interruptionSources: Data?    // JSON array of interrupt sources (app bundle IDs, notifications)
    @NSManaged var flowStateScore: Float         // 0.0–1.0, inferred from interruption count + completion
    @NSManaged var postSessionReflection: String? // optional text from user
    @NSManaged var createdAt: Date

    // Relationships
    @NSManaged var task: CDTask?                  // M:1 → CDTask (nullable for unlinked focus sessions)
}
```

---

### CompletionRecord

Tracks actual vs estimated time for the learning loop.

```swift
@objc(CDCompletionRecord)
final class CDCompletionRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var taskId: UUID
    @NSManaged var bucket: String                // TaskBucket.rawValue
    @NSManaged var estimatedMinutes: Int16
    @NSManaged var actualMinutes: Int16          // 0 if not tracked
    @NSManaged var completedAt: Date
    @NSManaged var wasDeferred: Bool
    @NSManaged var deferredCount: Int16
    @NSManaged var hourOfDay: Int16              // 0–23, for Thompson sampling hour-range bucketing
    @NSManaged var dayOfWeek: Int16              // 1–7 (Sunday=1)
    @NSManaged var createdAt: Date

    // Relationships
    @NSManaged var task: CDTask?                  // M:1 → CDTask
}
```

---

### UserProfile

Singleton per workspace. The executive's learned profile — the core of what Timed knows.

```swift
@objc(CDUserProfile)
final class CDUserProfile: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var workspaceId: UUID

    // Identity
    @NSManaged var displayName: String?
    @NSManaged var emailAddress: String?
    @NSManaged var timezone: String              // e.g., "Australia/Adelaide"

    // Chronotype
    @NSManaged var chronotype: String            // Chronotype.rawValue: "morning", "evening", "variable"
    @NSManaged var chronotypeConfidence: Float
    @NSManaged var typicalWakeHour: Float        // e.g., 6.5 = 6:30am
    @NSManaged var typicalSleepHour: Float       // e.g., 22.5 = 10:30pm

    // Energy curve (24 hourly weights, 0.0–1.0)
    @NSManaged var energyCurve: Data             // [Float] of 24 values, JSON or raw Data

    // Work preferences
    @NSManaged var preferredWorkStartHour: Int16
    @NSManaged var preferredWorkEndHour: Int16
    @NSManaged var deepWorkMaxMinutes: Int16     // how long they can sustain deep work
    @NSManaged var meetingToleranceMinutes: Int16 // max consecutive meeting minutes before burnout
    @NSManaged var preferredDeepWorkWindows: Data? // JSON array of {start: Int, end: Int} hour pairs

    // Communication style
    @NSManaged var communicationStyleNotes: String? // learned from email/voice analysis
    @NSManaged var averageEmailResponseMinutes: Float
    @NSManaged var averageEmailLengthWords: Float

    // Relationships (JSON-serialized for flexibility)
    @NSManaged var relationshipMapJson: Data?     // [{contact: String, frequency: Int, sentiment: Float, lastContact: Date}]

    // Avoidance patterns (human-readable descriptions)
    @NSManaged var avoidancePatternsJson: Data?   // [{pattern: String, frequency: Int, examples: [String]}]

    // Decision style
    @NSManaged var decisionStyleNotes: String?    // e.g., "Delays people decisions, fast on financial"

    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
}
```

---

### MLModelState

Persists ML model parameters that must survive app restarts. One record per model type.

```swift
@objc(CDMLModelState)
final class CDMLModelState: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var modelType: String             // MLModelType.rawValue
    @NSManaged var parametersJson: Data           // model-specific state as JSON
    @NSManaged var version: Int32                 // incremented on each update
    @NSManaged var lastTrainedAt: Date
    @NSManaged var sampleCount: Int32
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
}
```

**Model types and their parameter structures:**

| modelType | parametersJson shape |
|-----------|---------------------|
| `thompson_sampling` | `{bucketType: {hourRange: {alpha: Float, beta: Float, samples: Int}}}` |
| `ema_time_estimation` | `{bucketType: {mean: Float, sampleCount: Int, alpha: Float}}` |
| `importance_classifier` | `{version: String, thresholds: {high: Float, medium: Float}}` |
| `energy_curve` | `{hourlyWeights: [Float], lastCalibrated: Date}` |

---

## Enums

```swift
// MARK: - Signal & Modality

enum SignalSource: String, Codable, CaseIterable, Sendable {
    case email
    case calendar
    case voice
    case appFocus = "app_focus"
    case task
    case system
    case focusSession = "focus_session"
}

enum ModalityTag: String, Codable, CaseIterable, Sendable {
    case text
    case voice
    case calendar
    case behaviour
    case system
}

// MARK: - Task

enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case inProgress = "in_progress"
    case done
    case deferred
    case cancelled
    case waitingOn = "waiting_on"
}

enum TaskBucket: String, Codable, CaseIterable, Sendable {
    case reply
    case action
    case calls
    case readToday = "Read Today"
    case readThisWeek = "Read This Week"
    case transit
    case waiting
    case ccFyi = "CC / FYI"
}

enum EnergyLevel: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case recovery
}

enum ReplyMedium: String, Codable, CaseIterable, Sendable {
    case email = "Email"
    case whatsApp = "WhatsApp"
    case other = "Other"
}

// MARK: - Calendar

enum BlockCategory: String, Codable, CaseIterable, Sendable {
    case focus
    case meeting
    case admin
    case `break`
    case transit
}

// MARK: - Memory

enum MemoryTier: String, Codable, CaseIterable, Sendable {
    case episodic
    case semantic
    case procedural
    case core
    case archival      // vector-only, no longer in active CoreData
}

enum SemanticCategory: String, Codable, CaseIterable, Sendable {
    case workStyle = "work_style"
    case preferences
    case relationships
    case avoidancePatterns = "avoidance_patterns"
    case decisionStyle = "decision_style"
    case communication
    case energy
    case chronotype
    case stressIndicators = "stress_indicators"
}

enum CoreMemorySection: String, Codable, CaseIterable, Sendable {
    case identity
    case workStyle = "work_style"
    case relationships
    case currentContext = "current_context"
    case preferences
}

// MARK: - Pattern & Rule

enum PatternType: String, Codable, CaseIterable, Sendable {
    case behavioural
    case temporal
    case relational
    case cognitive
    case avoidance
    case communication
    case energy
}

enum PatternStatus: String, Codable, CaseIterable, Sendable {
    case emerging
    case confirmed
    case fading
    case archived
}

enum ProceduralRuleType: String, Codable, CaseIterable, Sendable {
    case ordering       // "calls before email"
    case timing         // "deep work between 9-11am"
    case threshold      // "max 2h consecutive meetings"
    case categoryPref = "category_pref"  // "prefers action items first"
    case recovery       // "15m break after long meeting"
    case avoidance      // "tends to defer people decisions"
}

enum RuleStatus: String, Codable, CaseIterable, Sendable {
    case active
    case testing        // newly generated, being validated
    case suspended      // temporarily disabled by user correction
    case retired        // replaced by newer rule
}

// MARK: - Voice

enum VoiceSessionType: String, Codable, CaseIterable, Sendable {
    case morningSession = "morning_session"
    case adHocCapture = "ad_hoc_capture"
    case focusDebrief = "focus_debrief"
    case eveningReflection = "evening_reflection"
}

// MARK: - App Focus

enum AppWorkCategory: String, Codable, CaseIterable, Sendable {
    case deepWork = "deep_work"
    case shallowWork = "shallow_work"
    case communication
    case breakActivity = "break"
    case unknown
}

// MARK: - Focus

enum FocusOutcome: String, Codable, CaseIterable, Sendable {
    case completed
    case partial
    case abandoned
    case interrupted
}

// MARK: - AI Model

enum AIModelTier: String, Codable, CaseIterable, Sendable {
    case haiku = "haiku-3.5"
    case sonnet = "sonnet-4"
    case opus = "opus-4"
}

// MARK: - ML Model

enum MLModelType: String, Codable, CaseIterable, Sendable {
    case thompsonSampling = "thompson_sampling"
    case emaTimeEstimation = "ema_time_estimation"
    case importanceClassifier = "importance_classifier"
    case energyCurve = "energy_curve"
    case chronotypeDetector = "chronotype_detector"
}

// MARK: - Delivery

enum DeliveryChannel: String, Codable, CaseIterable, Sendable {
    case morningSession = "morning_session"
    case menuBar = "menu_bar"
    case proactiveAlert = "proactive_alert"
    case commandPalette = "command_palette"
}

// MARK: - Mood (PlanningEngine)

enum MoodContext: String, Codable, CaseIterable, Sendable {
    case easyWins = "easy_wins"
    case avoidance
    case deepFocus = "deep_focus"
}

// MARK: - Chronotype

enum Chronotype: String, Codable, CaseIterable, Sendable {
    case morning
    case evening
    case variable
}
```

---

## Memory Tier Promotion Logic

### Episodic → Semantic Consolidation

**Trigger:** Nightly reflection engine (Opus).

**Process:**
1. Retrieve all unconsolidated episodic memories from the last 24h
2. Cluster by topic using embedding similarity (cosine > 0.75)
3. For each cluster with 3+ memories: extract a semantic fact
4. Check if semantic fact already exists (embedding similarity > 0.85 to existing SemanticMemory)
   - If exists: increment `reinforcementCount`, update `confidenceScore`, update `lastReinforcedAt`
   - If new: create SemanticMemory with `confidenceScore = 0.5`, link contributing episodic memories
5. Mark processed episodic memories as `isConsolidated = true`

**Confidence scoring:**
```
confidence = min(1.0, baseConfidence + (reinforcementCount * 0.05) - (contradictionCount * 0.1))
```

### Semantic → Procedural Promotion

**Trigger:** Weekly consolidation (Opus).

**Process:**
1. Retrieve confirmed semantic memories with `reinforcementCount >= 5`
2. Opus analyzes for actionable patterns (if-then structure)
3. Generate procedural rule with `conditionJson` and `actionJson`
4. Set initial `confidenceScore = 0.6`
5. Status: `testing` until activated 3+ times without user correction

### Procedural → Core Memory Promotion

**Trigger:** Nightly reflection + weekly review.

**Process:**
1. Procedural rules with `activationCount >= 10` and `confidenceScore >= 0.8` are candidates
2. Opus summarizes the rule into a concise core memory entry (<500 chars)
3. If buffer is full (50 entries), evict lowest-priority entry to SemanticMemory
4. Insert with `priorityRank` calculated by: activation frequency × confidence × recency

### Archival / Vector-Only Demotion

**Trigger:** Monthly consolidation.

**Process:**
1. Episodic memories older than 90 days with `accessCount == 0`: move to archival
2. Archival = embedding preserved in Supabase pgvector, CoreData entity deleted
3. The embedding + metadata JSON are stored server-side for retrieval if needed
4. This keeps the local CoreData store bounded

---

## Supabase Schema Mapping

Local CoreData is the source of truth for the current device. Supabase serves as:
1. **Backup/sync** — nightly push of all memory tiers
2. **Vector search** — pgvector for archival embeddings (episodic memories older than 90 days)
3. **Edge Function state** — email classification results, voice parsing, reflection outputs
4. **Cross-device sync** (future) — if the executive uses multiple Macs

**Key Supabase tables:**

| CoreData Entity | Supabase Table | Sync Direction |
|-----------------|----------------|----------------|
| CDEpisodicMemory | `episodic_memories` | push (nightly) |
| CDSemanticMemory | `semantic_memories` | push (nightly) |
| CDProceduralMemory | `procedural_memories` | push (nightly) |
| CDCoreMemoryEntry | `core_memory` | push (on change) |
| CDPattern | `patterns` | push (nightly) |
| CDUserProfile | `user_profiles` | push (on change) |
| CDEmailSignal | `email_messages` | bidirectional (Graph webhook → Supabase → local) |
| CDReflectionRun | `reflection_runs` | push (after each run) |

---

## ValueTransformer for Embedding Vectors

```swift
@objc(EmbeddingVectorTransformer)
final class EmbeddingVectorTransformer: ValueTransformer {
    static let name = NSValueTransformerName(rawValue: "EmbeddingVectorTransformer")

    override class func transformedValueClass() -> AnyClass { NSData.self }
    override class func allowsReverseTransformation() -> Bool { true }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let floats = value as? [Float] else { return nil }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    static func register() {
        ValueTransformer.setValueTransformer(
            EmbeddingVectorTransformer(),
            forName: name
        )
    }
}
```

Register in `AppDelegate.applicationDidFinishLaunching` before loading the persistent container.

---

## Migration Strategy

### Lightweight Migration (default path)

CoreData lightweight migration handles automatically:
- Adding new entities
- Adding optional attributes to existing entities
- Adding relationships with nullify delete rule
- Renaming entities/attributes (with renaming ID in model editor)

**Rule: All new attributes MUST be optional or have default values.** This keeps lightweight migration viable for most changes.

### Heavyweight Migration (when needed)

Required for:
- Changing attribute types (e.g., `Int16` → `Int32`)
- Splitting or merging entities
- Complex data transformation during migration

**Process:**
1. Create new model version in `.xcdatamodeld`
2. Create `NSMappingModel` with custom `NSEntityMigrationPolicy` subclasses
3. Test migration with production-scale data before release
4. Ship as a Sparkle update — the app detects the old model version and migrates on launch

### Version Strategy

- Model versions named: `TimedModel_v1`, `TimedModel_v2`, etc.
- Each Sparkle release notes which model version it expects
- Migration tested in CI with synthetic data for each version transition
