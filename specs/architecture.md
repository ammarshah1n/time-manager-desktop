# Timed — System Architecture Overview

> Definitive architecture specification. Protocols, data flow, concurrency model, AI routing, privacy, and extension points. Implementation-ready.

**Last updated:** 2026-04-02
**Target:** macOS 14+ (Sonoma), Swift 5.9+

---

## Foundational Principles

1. **Observation only.** Timed never acts on the world. It never sends emails, modifies calendars, creates meetings, or takes any action. The human always decides and executes. This is enforced architecturally, not by convention.
2. **Four strict layers.** Signal Ingestion → Memory Store → Reflection Engine → Intelligence Delivery. No cross-layer coupling. Each layer communicates through defined protocols.
3. **Intelligence compounds.** Month 6 must be qualitatively smarter than month 1. This requires persistent memory, periodic deep reflection, and a feedback loop that strengthens with use.
4. **No cost cap on intelligence.** Opus 4.6 at maximum effort for reflection and morning briefing. Cheaper models for real-time classification only.

---

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    macOS Application Process                         │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  LAYER 4: Intelligence Delivery                                 │ │
│  │  Morning Session │ Menu Bar │ Proactive Alerts │ Command Palette│ │
│  │                      ▲                                          │ │
│  │  Consumes: MemoryReadPort, PatternQueryPort, UserProfilePort    │ │
│  └──────────────────────┼──────────────────────────────────────────┘ │
│                         │                                            │
│  ┌──────────────────────┼──────────────────────────────────────────┐ │
│  │  LAYER 3: Reflection Engine                                     │ │
│  │  NightlyReflection │ TriggeredReflection │ WeeklyConsolidation  │ │
│  │                      ▲ ▼                                        │ │
│  │  Reads: EpisodicMemoryPort │ Writes: SemanticPort, PatternPort  │ │
│  └──────────────────────┼──────────────────────────────────────────┘ │
│                         │                                            │
│  ┌──────────────────────┼──────────────────────────────────────────┐ │
│  │  LAYER 2: Memory Store                                          │ │
│  │  Episodic │ Semantic │ Procedural │ Core │ Archival (pgvector)  │ │
│  │                      ▲ ▼                                        │ │
│  │  Implements: MemoryWritePort, MemoryReadPort, EmbeddingPort     │ │
│  └──────────────────────┼──────────────────────────────────────────┘ │
│                         │                                            │
│  ┌──────────────────────┼──────────────────────────────────────────┐ │
│  │  LAYER 1: Signal Ingestion                                      │ │
│  │  EmailAgent │ CalendarAgent │ VoiceAgent │ AppFocusAgent        │ │
│  │                                                                  │ │
│  │  Writes to: SignalWritePort → triggers EpisodicMemory creation   │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │  INFRASTRUCTURE                                                  │ │
│  │  CoreData Stack │ Supabase Client │ Graph Client │ AI Router     │ │
│  │  Embedding Service │ Auth Service │ Logger │ Scheduler           │ │
│  └──────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Layer Protocol Definitions

### Layer 1: Signal Ingestion

```swift
/// Port for writing raw signals into the system.
/// Implemented by Layer 2's SignalStore.
/// Called by Layer 1 agents when they observe something.
protocol SignalWritePort: Sendable {
    /// Records a raw signal and creates an EpisodicMemory from it.
    /// Returns the created EpisodicMemory ID.
    func recordSignal(_ signal: SignalInput) async throws -> UUID

    /// Batch-record signals (for email delta sync with 50+ messages).
    func recordSignals(_ signals: [SignalInput]) async throws -> [UUID]
}

/// Input type for signal recording. Decoupled from CoreData.
struct SignalInput: Sendable {
    let source: SignalSource
    let modalityTag: ModalityTag
    let timestamp: Date
    let content: String                    // human-readable summary
    let importanceScore: Float             // 0.0–1.0, set by Layer 1 classifier
    let rawPayloadRef: String?             // file path for large payloads
    let metadata: [String: AnySendable]?   // source-specific key-value pairs
    let embeddingText: String?             // text to embed (may differ from content)
}
```

```swift
/// Contract for a background signal agent.
/// Each agent observes one domain and produces signals.
protocol SignalAgent: Actor {
    /// Unique identifier for this agent type.
    var agentId: String { get }

    /// Start observing. Called once at app launch.
    func startObserving() async throws

    /// Stop observing. Called at app termination.
    func stopObserving() async

    /// Current agent health status.
    var isHealthy: Bool { get }

    /// Last time this agent produced a signal.
    var lastSignalAt: Date? { get }
}
```

```swift
/// Classifies signal importance. Haiku-tier.
protocol ImportanceClassifier: Sendable {
    /// Returns an importance score (0.0–1.0) for a raw signal.
    func classify(_ content: String, source: SignalSource) async throws -> Float
}
```

---

### Layer 2: Memory Store

```swift
/// Read access to episodic memories.
/// Used by Layer 3 (Reflection Engine) and Layer 4 (Intelligence Delivery).
protocol EpisodicMemoryReadPort: Sendable {
    /// Retrieve memories by time range.
    func memories(from: Date, to: Date) async throws -> [EpisodicMemoryDTO]

    /// Retrieve unconsolidated memories (for nightly reflection).
    func unconsolidatedMemories(since: Date) async throws -> [EpisodicMemoryDTO]

    /// Retrieval-scored query: recency × importance × relevance.
    /// Uses embedding similarity for relevance component.
    func retrieveRelevant(
        queryEmbedding: [Float],
        limit: Int,
        recencyWeight: Float,
        importanceWeight: Float,
        relevanceWeight: Float
    ) async throws -> [ScoredMemory]

    /// Count of total episodic memories (for compounding metrics).
    func totalCount() async throws -> Int
}

/// Write access to all memory tiers.
/// Used by Layer 1 (signal recording) and Layer 3 (consolidation).
protocol MemoryWritePort: Sendable {
    // Episodic
    func createEpisodicMemory(_ input: EpisodicMemoryInput) async throws -> UUID
    func markConsolidated(_ ids: [UUID]) async throws

    // Semantic
    func upsertSemanticMemory(_ input: SemanticMemoryInput) async throws -> UUID
    func reinforceSemanticMemory(id: UUID) async throws
    func contradictSemanticMemory(id: UUID) async throws

    // Procedural
    func createProceduralMemory(_ input: ProceduralMemoryInput) async throws -> UUID
    func activateProceduralMemory(id: UUID) async throws
    func addException(ruleId: UUID, exception: String) async throws

    // Core
    func upsertCoreMemory(_ input: CoreMemoryInput) async throws
    func evictLowestPriorityCoreMemory() async throws -> CoreMemoryInput? // returns evicted entry
}

/// Embedding generation service.
protocol EmbeddingPort: Sendable {
    /// Generate a 1024-dim embedding vector for the given text.
    func embed(_ text: String) async throws -> [Float]

    /// Batch embed (more efficient for nightly processing).
    func embedBatch(_ texts: [String]) async throws -> [[Float]]

    /// Cosine similarity between two vectors.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float
}
```

```swift
/// Read access for patterns and rules.
/// Used by Layer 4 (Morning Session, PlanningEngine).
protocol PatternQueryPort: Sendable {
    /// All confirmed patterns, sorted by confidence descending.
    func confirmedPatterns() async throws -> [PatternDTO]

    /// Patterns observed in the last N days.
    func recentPatterns(days: Int) async throws -> [PatternDTO]

    /// Active procedural rules for the planning engine.
    func activeRules() async throws -> [ProceduralRuleDTO]

    /// Rules matching a specific type (e.g., all "timing" rules).
    func rules(ofType: ProceduralRuleType) async throws -> [ProceduralRuleDTO]
}

/// Read access for user profile.
protocol UserProfilePort: Sendable {
    func currentProfile() async throws -> UserProfileDTO
    func coreMemoryBuffer() async throws -> [CoreMemoryEntryDTO]
    func energyCurve() async throws -> [Float]   // 24 hourly weights
}
```

---

### Layer 3: Reflection Engine

```swift
/// The nightly reflection engine contract.
/// Implemented by a single class that orchestrates Opus calls.
protocol ReflectionEngine: Actor {
    /// Run a full nightly reflection cycle.
    /// 1. Retrieve today's unconsolidated episodic memories
    /// 2. Send to Opus for recursive reflection
    /// 3. Extract patterns, update semantic memories, generate rules
    /// 4. Update core memory buffer
    /// 5. Log the run in ReflectionRun
    func runNightlyReflection() async throws -> ReflectionRunResult

    /// Run a triggered reflection (e.g., after a high-importance event).
    func runTriggeredReflection(trigger: ReflectionTrigger) async throws -> ReflectionRunResult

    /// Weekly consolidation: prune, merge, archive.
    func runWeeklyConsolidation() async throws -> ConsolidationResult

    /// Status of the last reflection run.
    var lastRunResult: ReflectionRunResult? { get }
}

/// What triggers a non-scheduled reflection.
enum ReflectionTrigger: Sendable {
    case highImportanceSignal(signalId: UUID, importance: Float)
    case userCorrection(entityType: String, entityId: UUID, correction: String)
    case patternContradiction(patternId: UUID, contradictingSignalId: UUID)
    case manual
}
```

---

### Layer 4: Intelligence Delivery

```swift
/// Morning intelligence session generator.
protocol MorningDirector: Sendable {
    /// Generate the morning cognitive briefing.
    /// Uses: full core memory buffer, recent patterns, today's calendar,
    /// pending tasks, yesterday's reflection output.
    func generateBriefing(
        voiceTranscript: String?,     // user's morning voice input (nil if skipped)
        calendar: [CalendarEventDTO],
        tasks: [TaskDTO],
        patterns: [PatternDTO],
        coreMemory: [CoreMemoryEntryDTO],
        profile: UserProfileDTO
    ) async throws -> MorningBriefing
}

struct MorningBriefing: Sendable {
    let openingInsight: String          // the named pattern or observation to lead with
    let todayPlan: [PlanItem]           // scored and ordered tasks
    let namedPatterns: [String]         // patterns to surface explicitly
    let avoidanceWarning: String?       // "You've deferred X three times..."
    let energyGuidance: String          // "Your peak analytical window is 9-11am today"
    let proactiveAlerts: [String]       // deadline risks, relationship maintenance, etc.
    let questionForUser: String?        // active preference elicitation
    let aiModelUsed: AIModelTier
    let generatedAt: Date
}

/// Proactive alert system.
protocol AlertEngine: Sendable {
    /// Evaluate current state and return any alerts that should fire.
    func evaluateAlerts(
        currentTime: Date,
        calendar: [CalendarEventDTO],
        tasks: [TaskDTO],
        patterns: [PatternDTO],
        profile: UserProfileDTO
    ) async throws -> [ProactiveAlert]
}

struct ProactiveAlert: Sendable, Identifiable {
    let id: UUID
    let alertType: AlertType
    let message: String
    let urgency: AlertUrgency
    let actionSuggestion: String?       // what to do about it — never an action Timed takes
    let generatedAt: Date

    enum AlertType: String, Sendable {
        case deadlineRisk
        case energyWarning
        case meetingOverload
        case avoidanceTrigger
        case relationshipMaintenance
        case scheduleConflict
        case focusProtection
    }

    enum AlertUrgency: String, Sendable {
        case low        // menu bar only
        case medium     // menu bar + badge
        case high       // notification
    }
}
```

---

## Observation-Only Enforcement

The "never acts" constraint is enforced at three levels:

### 1. Protocol-Level (Compile Time)
No protocol in the system exposes a write method for external services. There is no `sendEmail()`, `createCalendarEvent()`, `acceptMeeting()`, or equivalent anywhere in the protocol definitions. The Graph Client exposes only read scopes.

### 2. OAuth Scope (Runtime)
The MSAL configuration requests only:
- `Mail.Read` (not `Mail.ReadWrite` or `Mail.Send`)
- `Calendars.Read` (not `Calendars.ReadWrite`)
- `offline_access`

Even if code somehow attempted a write operation, the token lacks permission.

### 3. Architecture Review Rule
Any PR that adds a write method to GraphClient, SupabaseClient (for user-facing data), or any external service is automatically flagged. The CLAUDE.md project brain enforces this during development.

---

## Data Flow

### Primary Loop (Daily Cycle)

```
06:00  ──── Scheduled agents wake ────────────────────────────────
              │
              ├── EmailAgent: delta sync from Graph → new EmailSignals
              ├── CalendarAgent: sync today's events → CalendarEvents
              └── AppFocusAgent: resume NSWorkspace observation
              │
              ▼
07:00  ──── Morning Voice Session ────────────────────────────────
              │
              ├── VoiceAgent: Apple Speech → transcript
              ├── Haiku: classify importance of transcript
              ├── SignalWritePort: record voice signal + episodic memory
              └── MorningDirector (Opus): generate briefing
                  ├── Reads: core memory buffer (50 entries)
                  ├── Reads: last night's reflection output
                  ├── Reads: today's calendar
                  ├── Reads: pending tasks + patterns
                  └── Outputs: MorningBriefing → UI
              │
              ▼
09:00–18:00 ── Continuous Observation ────────────────────────────
              │
              ├── EmailAgent: delta sync every 5 min
              │   └── Each new email: Haiku classifies → SignalWritePort
              ├── CalendarAgent: poll every 15 min for changes
              ├── AppFocusAgent: NSWorkspace notifications → app switches
              ├── FocusTimer: records sessions → CompletionRecords
              └── PlanningEngine: re-scores on new signals (no AI call)
              │
              ▼
02:00  ──── Nightly Reflection ───────────────────────────────────
              │
              ├── ReflectionEngine gathers all today's episodic memories
              ├── Opus 6-stage recursive reflection:
              │   ├── Stage 1: Episodic summarisation
              │   ├── Stage 2: First-order pattern extraction
              │   ├── Stage 3: Second-order synthesis
              │   ├── Stage 4: Rule generation
              │   ├── Stage 5: Memory updates (deterministic)
              │   └── Stage 6: Morning session preparation
              ├── Pattern store updates (new/reinforced/fading)
              ├── Core memory buffer update (evict/insert)
              └── ReflectionRun audit log saved
              │
              ▼
04:00  ──── Sync to Supabase ─────────────────────────────────────
              │
              └── Push: episodic, semantic, procedural, patterns, profile
```

### Real-Time Path (Sub-Second)

For signals that need immediate reflection in the UI:

```
Email arrives → Graph delta sync (5s poll)
    → Haiku classifies importance + bucket (200ms)
    → SignalWritePort records (local CoreData, <10ms)
    → If importance > 0.8: UI badge updates, menu bar refreshes
    → If importance > 0.9: proactive alert fires
    → NO Opus call — intelligence delivery uses cached patterns
```

### Nightly Path (Deep Intelligence)

```
Trigger: 02:00 local time OR user manually triggers
    → Gather: all unconsolidated episodic memories (typically 50–200/day)
    → Prepare: core memory buffer + existing patterns + profile
    → 6-stage Opus pipeline (see reflection-architecture.md):
        Stage 1: Episodic summarisation (~5K-15K in, ~2K-4K out)
        Stage 2: First-order pattern extraction (~10K-25K in, ~3K-6K out)
        Stage 3: Second-order synthesis (~15K-40K in, ~4K-8K out)
        Stage 4: Rule generation (~5K-10K in, ~1K-3K out)
        Stage 5: Memory updates (deterministic, no LLM call)
        Stage 6: Morning session preparation (~10K-20K in, ~3K-6K out)
    → Write: SemanticMemory upserts, Pattern updates, ProceduralMemory creates
    → Write: CoreMemory buffer adjustments
    → Log: ReflectionRun with token counts, duration, outputs
    
    Estimated nightly cost: $1.50–$5.00 depending on day's signal volume
    No cost cap applies — intelligence quality is the priority
```

### Weekly Consolidation Path

```
Trigger: Sunday 03:00 OR user manually triggers
    → Scan: semantic memories with contradictions
    → Scan: patterns in "fading" status
    → Scan: episodic memories older than 90 days with 0 access
    → Opus call: "Review this week's learning. What should be archived?"
    → Archive: old episodic → Supabase pgvector (keep embedding, drop CoreData)
    → Merge: overlapping semantic memories
    → Retire: rules with high exception rates
    → Recalculate: core memory priority ranks
```

---

## Compounding Intelligence Loop

### Week 1 (Cold Start)
- Archetype picker at onboarding pre-loads scoring weights
- Calendar history bootstrap: 90-day Outlook history → infer meeting patterns
- Voice sessions: morning sessions build initial profile
- EMA: no data yet, uses default bucket estimates
- Thompson sampling: uniform priors (alpha=1, beta=1)
- Core memory: 5–10 entries from onboarding + calendar analysis
- **Intelligence quality: generic — better than nothing**

### Month 1
- ~600 episodic memories accumulated
- ~30 nightly reflection runs completed
- ~20 semantic memories extracted (work style, energy patterns, key relationships)
- ~5 procedural rules active (ordering preferences, timing preferences)
- Thompson sampling: ~100 observations per bucket, posteriors stabilizing
- EMA: 30 completion records, estimates improving
- Energy curve: 4 weeks of app focus data → first chronotype inference
- **Intelligence quality: noticeably personalized — correct ~60% of the time**

### Month 3
- ~1,800 episodic memories, ~500 consolidated to semantic
- ~50+ semantic memories with high confidence
- ~15 procedural rules active, 5 retired
- Named patterns detected: "Monday morning avoidance", "post-lunch email binge", "Thursday deadline rush"
- Relationship map: top 20 contacts scored by interaction frequency and sentiment
- Thompson sampling: strong posteriors, sampling adds ~5% accuracy over fixed scores
- **Intelligence quality: genuinely insightful — surfaces patterns the user hasn't consciously noticed**

### Month 6
- ~3,600 episodic memories, ~300 in archival (pgvector)
- ~100+ semantic memories forming a rich user model
- ~25 active rules, some with exceptions refined over time
- Core memory buffer: stable, high-quality, 50 entries
- Cross-pattern synthesis: "Your avoidance of people decisions correlates with high meeting density days"
- Predictive capability: can anticipate procrastination, burnout risk, deadline misses
- Morning sessions open with insights, not just plans
- **Intelligence quality: transformative — the system understands the executive better than their coach**

---

## Concurrency Model

### Actors and Contexts

```
Main Actor (UI thread)
    ├── All SwiftUI views
    ├── VoiceCaptureService (@MainActor for AVAudioEngine)
    └── Published state for menu bar + command palette

DataStore Actor (background)
    ├── JSON file I/O (current implementation)
    └── Will transition to CoreData background context

CoreData Stack
    ├── viewContext (Main Actor) — for UI reads via @FetchRequest
    ├── backgroundContext (background queue) — for Layer 1 signal writes
    └── reflectionContext (background queue) — for Layer 3 nightly processing
    Note: Each background context is a child of the persistent container.
    Merges propagate via NSManagedObjectContextDidSave notification.

Agent Actors (each agent is its own actor)
    ├── EmailSignalAgent: polls Graph API, writes via backgroundContext
    ├── CalendarSignalAgent: polls Graph API, writes via backgroundContext
    ├── AppFocusSignalAgent: observes NSWorkspace, writes via backgroundContext
    └── FocusSessionAgent: tracks timer state, writes via backgroundContext

ReflectionActor (background, long-running)
    ├── Runs on its own context (reflectionContext)
    ├── Reads episodic memories, writes semantic/procedural/patterns
    └── Heavy AI calls (Opus) — can run 30s–2min per nightly cycle

AIRouter Actor (serialized AI calls)
    ├── Manages rate limiting across all AI model calls
    ├── Routes to Haiku/Sonnet/Opus based on request type
    └── Handles retries, backoff, and fallback
```

### CoreData Context Rules

1. **Never pass `NSManagedObject` across contexts.** Always convert to DTOs (plain structs) at the boundary.
2. **Background writes use `perform { }` blocks.** Never write on the main context.
3. **View reads use `@FetchRequest` or `viewContext.fetch()`.** Never read from a background context in UI code.
4. **Merge policy: `NSMergeByPropertyObjectTrumpMergePolicy`.** Background writes win over stale view context data.
5. **Save propagation:** Background context saves automatically merge into view context via notification observer.

```swift
/// CoreData stack setup.
final class TimedPersistenceController {
    static let shared = TimedPersistenceController()

    let container: NSPersistentContainer

    /// Main-thread context for UI reads.
    var viewContext: NSManagedObjectContext { container.viewContext }

    /// Background context for signal ingestion (Layer 1).
    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.automaticallyMergesChangesFromParent = true
        return ctx
    }

    private init() {
        // Register value transformers before loading the store
        EmbeddingVectorTransformer.register()

        container = NSPersistentContainer(name: "TimedModel")
        container.loadPersistentStores { description, error in
            if let error {
                TimedLogger.persistence.critical("Failed to load CoreData: \(error.localizedDescription)")
                fatalError("CoreData load failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
```

---

## Supabase Integration

### Role

Supabase is NOT the primary data store. CoreData on-device is the source of truth. Supabase provides:

1. **Edge Functions** — Serverless compute for AI model calls (keeps API keys off-device)
2. **pgvector** — Archival embedding storage and similarity search
3. **Backup** — Nightly sync of all memory tiers
4. **Graph Webhooks** — Microsoft Graph subscription renewal and webhook receiver
5. **Future: Cross-Device Sync** — If the executive uses multiple Macs

### Edge Functions

| Function | Purpose | AI Model | Trigger |
|----------|---------|----------|---------|
| `classify-email` | Triage bucket + importance | Haiku 3.5 | On new email signal |
| `detect-reply` | Detect if email is a reply in thread | None (heuristic) | On new email signal |
| `estimate-time` | Estimate task duration | Sonnet 4 | On task creation |
| `generate-daily-plan` | Full morning briefing | Opus 4.6 | Morning session |
| `generate-profile-card` | User profile summary | Opus 4.6 | Weekly / on-demand |
| `graph-webhook` | Receive Graph change notifications | None | Microsoft Graph |
| `parse-voice-capture` | Extract tasks from transcript | Sonnet 4 | After voice session |
| `renew-graph-subscriptions` | Keep Graph subscriptions alive | None | Cron (every 2 days) |
| `run-nightly-reflection` | Deep reflection cycle | Opus 4.6 | Cron (02:00 daily) |

### Sync Protocol

```swift
/// Supabase sync contract.
protocol SyncPort: Sendable {
    /// Push local changes to Supabase. Called nightly after reflection.
    func pushMemoryState(
        episodic: [EpisodicMemoryDTO],
        semantic: [SemanticMemoryDTO],
        procedural: [ProceduralRuleDTO],
        patterns: [PatternDTO],
        profile: UserProfileDTO
    ) async throws

    /// Pull any server-side changes (e.g., email classifications from Edge Functions).
    func pullPendingUpdates() async throws -> [RemoteUpdate]

    /// Archive episodic memories to pgvector (embeddings only).
    func archiveToVector(_ memories: [EpisodicMemoryDTO]) async throws
}
```

---

## AI Model Routing

### Router Decision Matrix

| Request Type | Model | Max Tokens | Latency Target | Fallback |
|-------------|-------|------------|----------------|----------|
| Email importance classification | Haiku 3.5 | 100 | <500ms | Heuristic (sender + subject keyword match) |
| Email triage bucket | Haiku 3.5 | 50 | <500ms | Default: "action" |
| Task time estimation | Sonnet 4 | 200 | <2s | EMA estimate from history |
| Voice transcript parsing | Sonnet 4 | 500 | <3s | Regex-based TranscriptParser |
| Nightly reflection | Opus 4.6 | 4096 | <120s | Never falls back — retry 3x then log failure |
| Morning briefing | Opus 4.6 | 2048 | <30s | Cached yesterday's briefing + local plan |
| Profile card generation | Opus 4.6 | 1024 | <15s | Cached last profile card |
| Triggered reflection | Opus 4.6 | 2048 | <60s | Defer to nightly |

### Router Protocol

```swift
/// Routes AI requests to the appropriate model tier.
protocol AIRouter: Actor {
    /// Route a request to the appropriate model.
    func route(_ request: AIRequest) async throws -> AIResponse

    /// Check if a specific model tier is available (rate limits, network).
    func isAvailable(_ tier: AIModelTier) async -> Bool

    /// Current rate limit state per model.
    func rateLimitState() async -> [AIModelTier: RateLimitInfo]
}

struct AIRequest: Sendable {
    let requestType: AIRequestType
    let systemPrompt: String
    let userPrompt: String
    let maxTokens: Int
    let temperature: Float              // 0.0 for classification, 0.7 for reflection
    let preferredModel: AIModelTier
    let fallbackModel: AIModelTier?
    let includesCoreMemory: Bool        // inject core memory buffer into system prompt
}

enum AIRequestType: String, Sendable {
    case emailClassification
    case emailTriage
    case timeEstimation
    case voiceParsing
    case nightlyReflection
    case morningBriefing
    case profileGeneration
    case triggeredReflection
}

struct AIResponse: Sendable {
    let content: String
    let modelUsed: AIModelTier
    let inputTokens: Int
    let outputTokens: Int
    let latencyMs: Int
    let wasFallback: Bool
}
```

---

## Privacy Architecture

### Data Classification

| Data Type | Sensitivity | Storage | Encryption |
|-----------|-------------|---------|------------|
| Email body text | HIGH | On-device CoreData only | FileVault (OS-level) |
| Email metadata (sender, subject, timestamps) | MEDIUM | On-device + Supabase (encrypted at rest) |
| Calendar events | MEDIUM | On-device + Supabase |
| Voice transcripts | HIGH | On-device CoreData only |
| App focus (bundle IDs) | LOW | On-device + Supabase |
| App focus (window titles) | HIGH | On-device only, user opt-in |
| Semantic memories | MEDIUM | On-device + Supabase |
| Core memory buffer | HIGH | On-device only (contains synthesized profile) |
| Embedding vectors | LOW | On-device + Supabase pgvector |

### Privacy Controls (User-Facing)

```swift
/// User-configurable privacy settings.
struct PrivacySettings: Codable, Sendable {
    var captureWindowTitles: Bool = false       // default OFF
    var captureEmailBodies: Bool = true         // needed for NLP, user can disable
    var syncToCloud: Bool = true                // disable for fully on-device mode
    var retentionDaysEpisodic: Int = 90         // auto-archive after N days
    var retentionDaysSemantic: Int = 365        // semantic memories persist longer
    var excludedAppBundleIds: Set<String> = []  // apps to never track
    var excludedEmailDomains: Set<String> = []  // domains to never process
    var allowVoiceProsodyAnalysis: Bool = true  // emotional inference from voice
}
```

### What Never Leaves the Device

1. Raw email body text (only metadata + embeddings sync to Supabase)
2. Voice recordings (only transcripts are stored; audio is never persisted)
3. Window titles (if captured at all)
4. Core memory buffer (synthesized profile stays local)
5. Full user profile (only anonymized aggregate metrics sync)

### AI API Privacy

When sending content to Claude API (via Supabase Edge Functions):
- Email bodies are sent for classification — the API has a zero-retention policy
- Core memory is injected into system prompts — this is the user's own data processed for their benefit
- No training: Anthropic API usage is not used for model training
- All API calls route through the user's own Supabase project (no shared infrastructure)

---

## Error Handling Strategy

### Typed Errors

```swift
/// All Timed errors implement this protocol.
protocol TimedError: Error, Sendable {
    var layer: ArchitectureLayer { get }
    var isRecoverable: Bool { get }
    var userMessage: String { get }
    var logMessage: String { get }
}

enum ArchitectureLayer: String, Sendable {
    case signalIngestion
    case memoryStore
    case reflectionEngine
    case intelligenceDelivery
    case infrastructure
}

/// Layer 1 errors.
enum SignalError: TimedError {
    case graphAPIUnavailable(underlying: Error)
    case graphAuthExpired
    case graphRateLimited(retryAfterSeconds: Int)
    case speechRecognitionDenied
    case speechRecognitionUnavailable
    case signalWriteFailed(underlying: Error)

    var layer: ArchitectureLayer { .signalIngestion }
    var isRecoverable: Bool {
        switch self {
        case .graphAPIUnavailable, .graphRateLimited: return true
        case .graphAuthExpired: return true // re-auth flow
        case .speechRecognitionDenied: return false
        case .speechRecognitionUnavailable: return true
        case .signalWriteFailed: return true
        }
    }
    // ... userMessage, logMessage implementations
}

/// Layer 2 errors.
enum MemoryError: TimedError {
    case coreDataSaveFailed(underlying: Error)
    case embeddingGenerationFailed(underlying: Error)
    case memoryNotFound(id: UUID)
    case coreMemoryBufferFull
    case migrationRequired(from: String, to: String)

    var layer: ArchitectureLayer { .memoryStore }
    // ...
}

/// Layer 3 errors.
enum ReflectionError: TimedError {
    case opusUnavailable(underlying: Error)
    case opusRateLimited(retryAfterSeconds: Int)
    case reflectionTimeout
    case malformedReflectionOutput(rawOutput: String)
    case insufficientMemories(count: Int, minimum: Int)

    var layer: ArchitectureLayer { .reflectionEngine }
    // ...
}

/// Layer 4 errors.
enum DeliveryError: TimedError {
    case briefingGenerationFailed(underlying: Error)
    case noPlanDataAvailable
    case staleProfileData(lastUpdated: Date)

    var layer: ArchitectureLayer { .intelligenceDelivery }
    // ...
}
```

### Error Recovery Strategy

| Error | Recovery | User Impact |
|-------|----------|-------------|
| Graph API down | Retry with exponential backoff (5s, 15s, 45s). After 3 failures, use cached data. | "Email sync paused" in menu bar |
| Graph auth expired | Trigger MSAL silent token refresh. If fails, prompt interactive sign-in. | Sign-in sheet appears |
| Opus unavailable | Retry 3x with 30s backoff. If fails, skip nightly reflection, log, retry tomorrow. | Morning session uses yesterday's intelligence |
| CoreData save fails | Retry once. If fails, queue the write and retry on next app foreground. | No visible impact (writes are background) |
| Embedding API fails | Retry 2x. If fails, store memory without embedding, backfill on next successful call. | Slightly degraded retrieval relevance |
| Speech recognition denied | Show permission prompt. Cannot proceed with voice features. | Voice features disabled, text input fallback |

---

## Extension Points

### Adding a New Signal Source

1. Create a new entity in the CoreData model (e.g., `CDSlackMessage`)
2. Add a case to `SignalSource` enum
3. Implement `SignalAgent` protocol for the new source
4. Register the agent in `AgentCoordinator`
5. No changes needed to Layer 2, 3, or 4 — they consume signals generically

### Adding a New Memory Type

1. Add the entity to the CoreData model
2. Extend `MemoryWritePort` with new write methods
3. Update the reflection engine prompts to include the new type
4. No changes to Layer 1 or Layer 4

### Adding a New Delivery Channel

1. Implement the delivery logic (e.g., a widget, a Shortcuts action)
2. Consume existing `PatternQueryPort`, `UserProfilePort` protocols
3. No changes to Layers 1, 2, or 3

### Replacing the AI Provider

1. Implement `AIRouter` with the new provider's API
2. Update Edge Functions to call the new API
3. No changes to Layer 1, 2, or 4 — they interact through `AIRouter`

---

## File Structure

```
Sources/
├── Core/
│   ├── Models/            # CoreData NSManagedObject subclasses + DTOs
│   │   ├── CDSignal.swift
│   │   ├── CDEmailSignal.swift
│   │   ├── CDCalendarEvent.swift
│   │   ├── CDVoiceSession.swift
│   │   ├── CDAppFocusSession.swift
│   │   ├── CDEpisodicMemory.swift
│   │   ├── CDSemanticMemory.swift
│   │   ├── CDProceduralMemory.swift
│   │   ├── CDCoreMemoryEntry.swift
│   │   ├── CDPattern.swift
│   │   ├── CDRule.swift
│   │   ├── CDTask.swift
│   │   ├── CDFocusSession.swift
│   │   ├── CDCompletionRecord.swift
│   │   ├── CDUserProfile.swift
│   │   ├── CDMLModelState.swift
│   │   ├── CDReflectionRun.swift
│   │   ├── Enums.swift
│   │   └── DTOs/          # Plain struct DTOs for cross-layer communication
│   │       ├── EpisodicMemoryDTO.swift
│   │       ├── SemanticMemoryDTO.swift
│   │       └── ...
│   ├── Ports/             # Protocol definitions (layer boundaries)
│   │   ├── SignalWritePort.swift
│   │   ├── EpisodicMemoryReadPort.swift
│   │   ├── MemoryWritePort.swift
│   │   ├── EmbeddingPort.swift
│   │   ├── PatternQueryPort.swift
│   │   ├── UserProfilePort.swift
│   │   ├── ReflectionEngine.swift
│   │   ├── MorningDirector.swift
│   │   ├── AlertEngine.swift
│   │   ├── AIRouter.swift
│   │   └── SyncPort.swift
│   ├── Clients/           # External service clients
│   │   ├── GraphClient.swift
│   │   ├── SupabaseClient.swift
│   │   └── JinaEmbeddingClient.swift
│   ├── Services/          # Implementations
│   │   ├── Agents/
│   │   │   ├── EmailSignalAgent.swift
│   │   │   ├── CalendarSignalAgent.swift
│   │   │   ├── AppFocusSignalAgent.swift
│   │   │   └── AgentCoordinator.swift
│   │   ├── Memory/
│   │   │   ├── EpisodicMemoryStore.swift
│   │   │   ├── SemanticMemoryStore.swift
│   │   │   ├── ProceduralMemoryStore.swift
│   │   │   ├── CoreMemoryManager.swift
│   │   │   └── MemoryConsolidator.swift
│   │   ├── Reflection/
│   │   │   ├── NightlyReflectionEngine.swift
│   │   │   ├── WeeklyConsolidationEngine.swift
│   │   │   └── ReflectionPromptBuilder.swift
│   │   ├── Intelligence/
│   │   │   ├── MorningDirectorService.swift
│   │   │   ├── ProactiveAlertService.swift
│   │   │   └── PatternAnalyzer.swift
│   │   ├── PlanningEngine.swift
│   │   ├── TimeSlotAllocator.swift
│   │   ├── DataStore.swift
│   │   ├── AuthService.swift
│   │   ├── VoiceCaptureService.swift
│   │   └── TimedScheduler.swift
│   ├── Design/
│   │   ├── TimedColors.swift
│   │   └── TimedMotion.swift
│   ├── Persistence/
│   │   ├── TimedModel.xcdatamodeld/
│   │   ├── TimedPersistenceController.swift
│   │   └── EmbeddingVectorTransformer.swift
│   └── Infrastructure/
│       ├── TimedLogger.swift
│       ├── AIModelRouter.swift
│       └── NetworkMonitor.swift
├── Features/              # SwiftUI views, grouped by screen
│   ├── Today/
│   ├── MorningInterview/
│   ├── Focus/
│   ├── Tasks/
│   ├── Calendar/
│   ├── Triage/
│   ├── Capture/
│   ├── MenuBar/
│   ├── CommandPalette/
│   ├── Onboarding/
│   ├── Prefs/
│   └── TimedRootView.swift
├── Resources/
│   ├── Assets.xcassets/
│   └── Sounds/
└── Legacy/                # Old code pending migration
```
