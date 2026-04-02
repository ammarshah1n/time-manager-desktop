# Timed — CLAUDE.md (Project Brain)

> This file is the single source of truth for any AI assistant working on the Timed codebase. Read this before every task. Obey every rule without exception.

---

## What This Is

macOS application: the most intelligent executive operating system ever built. Builds a deep, compounding cognitive model of how a specific C-suite executive thinks, decides, avoids, prioritises, communicates, and operates — then uses that model to give them their cognitive bandwidth back, permanently.

**HARD CONSTRAINT: observation and intelligence only.** Never sends emails, modifies calendars, or takes any action on the world. The human always decides and executes. This boundary is enforced at the OAuth scope, protocol, and linter levels. Never negotiate it.

---

## Mission (Non-Negotiable — 6 Principles)

1. **No cost cap on intelligence.** Opus 4.6 at max effort for the reflection engine and morning briefing. Never suggest cheaper models for these. Never optimize intelligence quality for cost.
2. **Intelligence compounds over time.** Month 6 must be qualitatively smarter than month 1. Every architectural decision must support this.
3. **The nightly reflection engine is the heart.** Opus runs recursive reflection — not summaries. Raw observations → first-order patterns → second-order synthesis → semantic model updates → procedural rule generation.
4. **The morning session delivers intelligence, not a task list.** Opens with named patterns, interrogates avoidance, explains its own reasoning.
5. **Cognitive layer only.** Observe, reflect, recommend. Never act. Not even "helpful" actions.
6. **The user is a C-suite executive.** They have tried every tool. Impressed by depth, not features.

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.9+, strict concurrency |
| UI | SwiftUI, macOS 14+ (Sonoma) |
| State | `@State`, `@Binding`, `@StateObject` + TCA Dependencies for DI |
| Persistence (local) | CoreData with `NSPersistentContainer` |
| Persistence (remote) | Supabase Postgres (project: `fpmjuufefhtlwbfinxlx`) |
| External API | Microsoft Graph (Outlook, read-only via MSAL) |
| AI — classification | Claude Haiku 3.5 (via Supabase Edge Functions) |
| AI — estimation | Claude Sonnet 4 (via Supabase Edge Functions) |
| AI — reflection/briefing | Claude Opus 4.6 at max effort (via Supabase Edge Functions) |
| Embeddings | Jina AI jina-embeddings-v3, 1024 dimensions |
| Voice | Apple Speech framework (on-device only, never cloud) |
| Auth | MSAL OAuth — scopes: `Mail.Read`, `Calendars.Read`, `offline_access` |
| Distribution | Direct DMG + Sparkle auto-updates (not App Store) |
| Backend | 9 Supabase Edge Functions (TypeScript) |

---

## Architecture — Four Layers

| Layer | Purpose | Cadence | Key Protocols |
|-------|---------|---------|---------------|
| 1. Signal Ingestion | Reads external data (email, calendar, voice, app focus) | Continuous, passive | `SignalAgent`, `SignalWritePort`, `ImportanceClassifier` |
| 2. Memory Store | Three-tier persistence (episodic/semantic/procedural) + core buffer | Persistent | `EpisodicMemoryReadPort`, `MemoryWritePort`, `EmbeddingPort`, `PatternQueryPort` |
| 3. Reflection Engine | Pattern extraction, synthesis, rule generation | Nightly + triggered | `ReflectionEngine` |
| 4. Intelligence Delivery | Morning session, menu bar, proactive alerts | On-demand + scheduled | `MorningDirector`, `AlertEngine`, `UserProfilePort` |

**Critical rule:** These four layers communicate ONLY through their defined protocol boundaries. No direct access to another layer's internals. No importing a Layer 2 CoreData entity in a Layer 4 view — use the DTO.

---

## File Structure

```
Sources/
├── Core/
│   ├── Models/              # CoreData NSManagedObject subclasses + DTOs
│   │   └── DTOs/            # Plain structs for cross-layer communication
│   ├── Ports/               # Protocol definitions (layer boundaries)
│   ├── Clients/             # External service clients (GraphClient, SupabaseClient, JinaClient)
│   ├── Services/            # Implementation code
│   │   ├── Agents/          # Layer 1 signal agents
│   │   ├── Memory/          # Layer 2 memory stores
│   │   ├── Reflection/      # Layer 3 reflection engine
│   │   └── Intelligence/    # Layer 4 delivery services
│   ├── Design/              # Colors, motion, sounds
│   ├── Persistence/         # CoreData stack, model, transformers
│   └── Infrastructure/      # Logger, network monitor, AI router
├── Features/                # SwiftUI views, one directory per screen
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
└── Legacy/                  # Old code awaiting migration — do NOT add new code here
```

---

## Naming Conventions

### Files

| Category | Pattern | Example |
|----------|---------|---------|
| CoreData entity | `CD[EntityName].swift` | `CDEpisodicMemory.swift` |
| DTO | `[EntityName]DTO.swift` | `EpisodicMemoryDTO.swift` |
| Protocol (port) | `[Name]Port.swift` or `[Name]Protocol.swift` | `SignalWritePort.swift` |
| Signal agent | `[Source]SignalAgent.swift` | `EmailSignalAgent.swift` |
| Memory store | `[Tier]MemoryStore.swift` | `SemanticMemoryStore.swift` |
| Service | `[Name]Service.swift` | `VoiceCaptureService.swift` |
| View | `[Feature]View.swift` | `MorningInterviewView.swift` |
| View model | `[Feature]ViewModel.swift` (if needed) | `TodayViewModel.swift` |

### Swift

| Element | Convention | Example |
|---------|-----------|---------|
| Protocols | Noun or adjective phrase | `SignalWritePort`, `ReflectionEngine` |
| Actors | `[Name]Actor` or class name | `AIModelRouter`, `DataStore` |
| Enums | Singular, PascalCase | `SignalSource`, `PatternStatus` |
| Enum cases | camelCase | `.morningSession`, `.deepWork` |
| Struct fields | camelCase, no abbreviations | `receivedAt`, `importanceScore` |
| CoreData attributes | camelCase (matches Swift property names) | `triageBucket`, `embeddingVector` |

---

## Coding Standards

### Concurrency

```swift
// ALWAYS use async/await. Never use completion handlers for new code.
func fetchEmails() async throws -> [EmailSignalDTO]   // correct
func fetchEmails(completion: @escaping (Result<...>) -> Void)  // WRONG — never write this

// Stores are actors. Not classes with DispatchQueue.
actor EpisodicMemoryStore { ... }   // correct
class EpisodicMemoryStore { ... }   // WRONG

// CoreData background work uses perform { }
context.perform {
    let entity = CDEpisodicMemory(context: context)
    // ...
    try context.save()
}
```

### Repository Pattern

Every data access goes through a protocol (port). No view or service directly accesses CoreData or Supabase.

```swift
// CORRECT: view calls a port
let memories = try await episodicMemoryPort.unconsolidatedMemories(since: yesterday)

// WRONG: view imports CoreData and fetches directly
let request = CDEpisodicMemory.fetchRequest()
let results = try viewContext.fetch(request)
```

### Error Handling

```swift
// All errors are typed. No generic Error throws.
enum MemoryError: TimedError {
    case coreDataSaveFailed(underlying: Error)
    // ...
}

// Errors carry layer information for logging.
catch let error as TimedError {
    TimedLogger.log(error.layer, error.logMessage, level: .error)
}
```

### Logging

```swift
// Use TimedLogger subsystems. Never print().
TimedLogger.planning.info("Plan generated: \(items.count) tasks")
TimedLogger.memory.debug("Episodic memory created: \(id)")
TimedLogger.reflection.error("Opus call failed: \(error)")

// NEVER: print("something happened")
// NEVER: NSLog("something happened")
```

### Data Transfer Objects

```swift
// All cross-layer communication uses DTOs, not CoreData entities.
struct EpisodicMemoryDTO: Sendable {
    let id: UUID
    let timestamp: Date
    let content: String
    let importanceScore: Float
    // ... no NSManagedObject references
}

// Conversion at the boundary:
extension CDEpisodicMemory {
    func toDTO() -> EpisodicMemoryDTO {
        EpisodicMemoryDTO(id: id, timestamp: timestamp, content: content, importanceScore: importanceScore)
    }
}
```

### SwiftUI Views

```swift
// Views are thin. No business logic in views.
// Business logic lives in services/stores, consumed via dependency injection.

// CORRECT:
struct TodayView: View {
    @Dependency(\.planningEngine) var planningEngine
    // ...
}

// WRONG: computing scores, filtering data, or calling AI in a view body
```

---

## Testing Rules

1. **Unit test all ML components.** Thompson sampling, EMA estimation, scoring algorithms — these must have tests.
2. **Unit test all memory promotion logic.** Episodic → semantic thresholds, semantic → procedural thresholds.
3. **Unit test PlanningEngine.** Score computation is deterministic (except Thompson sampling, which must be seeded for tests).
4. **Integration test CoreData operations.** Use in-memory persistent stores (`NSInMemoryStoreType`).
5. **No tests for SwiftUI views.** Views are thin wrappers; test the services they depend on.
6. **Test framework:** swift-testing (`import Testing`, `@Test`, `#expect`). Not XCTest for new tests.
7. **Test file location:** `Tests/` directory, mirroring `Sources/` structure.
8. **Mock external services.** GraphClient, SupabaseClient, and AI Router must be mockable via protocol conformance + TCA Dependencies.

```swift
// Test example using swift-testing
import Testing
@testable import Timed

@Test func thompsonSamplingBumpWithSufficientData() {
    let stats = [BucketCompletionStat(bucketType: "action", hourRange: "06-12", completions: 15, deferrals: 5)]
    let bump = PlanningEngine.thompsonBump(bucketType: "action", currentHour: 9, stats: stats)
    #expect(bump > 0)
    #expect(bump <= 250)
}
```

---

## AI Assistant Rules

### MUST

- Read `BUILD_STATE.md` before starting any task
- Follow the four-layer architecture — never bypass layer boundaries
- Use DTOs for all cross-layer data transfer
- Use async/await for all asynchronous code
- Use actors for all shared mutable state
- Log all memory read/write operations via TimedLogger
- Use typed errors that implement `TimedError`
- Write unit tests for any new ML/scoring/memory logic
- Put domain models in `Sources/Core/Models/`, not in view files
- Use CoreData background contexts for all write operations
- Register new signal sources in `AgentCoordinator`

### MUST NOT

- Add write methods to `GraphClient` (read-only OAuth scopes enforced)
- Add write methods to any external service client for user-facing data
- Use `UserDefaults` for anything beyond UI preferences
- Use completion handlers (use async/await)
- Use `DispatchQueue` for concurrency (use actors + structured concurrency)
- Put business logic in SwiftUI views
- Import CoreData entities in Layer 4 (use DTOs)
- Skip the embedding step when creating episodic memories
- Modify the core memory buffer without going through `CoreMemoryManager`
- Use `print()` or `NSLog()` — use `TimedLogger`

### NEVER

- Add code that sends emails, creates calendar events, or performs any external write action
- Suggest cheaper models for the reflection engine or morning briefing (Opus only, no cost cap)
- Store API keys in the Swift codebase (keys live in Supabase Edge Function secrets)
- Add new code to the `Legacy/` directory
- Use `force unwrap` (`!`) except in tests or `fatalError` for programmer errors
- Bypass the protocol layer to access another layer's internals
- Hard-code user data or assumptions about the executive's identity
- Use SwiftData — CoreData is the chosen persistence layer (see ADR-001)

---

## Build Commands

```bash
# Build the project
swift build

# Run tests
swift test

# Run tests with verbose output
swift test --verbose

# Build for release (optimized)
swift build -c release

# Clean build artifacts
swift package clean

# Resolve dependencies
swift package resolve

# Open in Xcode (if needed)
open Package.swift
```

---

## Environment Setup

### Prerequisites

1. **macOS 14+** (Sonoma)
2. **Xcode 15.2+** (for Swift 5.9+)
3. **Supabase CLI** — `brew install supabase/tap/supabase`
4. **gh CLI** — `brew install gh` (authenticated as `pffteam`)

### First-Time Setup

```bash
# Clone
git clone git@github.com:ammarshah1n/time-manager-desktop.git
cd time-manager-desktop

# Resolve Swift packages
swift package resolve

# Verify build
swift build

# Run tests
swift test
```

### Supabase

- Project ref: `fpmjuufefhtlwbfinxlx`
- Edge Functions: managed via `supabase functions deploy`
- Secrets: managed via `supabase secrets set` (API keys for Claude, Jina, Azure)
- DB migrations: `supabase/migrations/` directory

### Azure App Registration

- Client ID + Tenant ID + Secret stored in Supabase Edge Function secrets
- MSAL configuration in `AuthService.swift`
- OAuth scopes: `Mail.Read`, `Calendars.Read`, `offline_access`
- Redirect URI: `msauth.com.timed.app://auth`

### Key Files (Read Before Every Session)

| File | Purpose |
|------|---------|
| `CLAUDE.md` | This file — architecture rules, coding standards |
| `BUILD_STATE.md` | What's done, what's not, dependencies |
| `CHANGELOG.md` | What changed in each session (read latest entry) |
| `Sources/Core/Services/PlanningEngine.swift` | Scoring algorithm — understand before touching task logic |
| `Sources/Core/Services/TimeSlotAllocator.swift` | Calendar-aware scheduling |
| `Sources/Features/PreviewData.swift` | All current model types + sample data |
| `Sources/Core/Services/DataStore.swift` | Current local persistence (JSON, pre-CoreData) |

---

## Session Protocol

### Starting a Session

1. Read `CLAUDE.md` (this file)
2. Read `BUILD_STATE.md` — know what's done and what's next
3. Read latest `CHANGELOG.md` entry — know what changed last
4. Verify infra: `supabase functions list`, `supabase secrets list`
5. Verify build: `swift build`
6. Only then begin the task

### Ending a Session

1. Update `BUILD_STATE.md` with any state changes
2. Add a `CHANGELOG.md` entry with what was done
3. Commit all changes
4. Note any unfinished work or known issues

---

## Common Anti-Patterns (Do Not Repeat)

1. **Cost optimization framing.** Timed is not a SaaS margin problem. Intelligence quality is the only metric. Do not suggest cheaper models, reduced API calls, or "good enough" alternatives for the core intelligence loop.

2. **Feature-first thinking.** The executive is not impressed by features. They are impressed by a system that understands them. Do not propose new features without explaining how they deepen the compounding intelligence model.

3. **Action-layer creep.** "What if Timed could auto-accept meetings?" NO. It observes. It reflects. It recommends. The human acts. This is non-negotiable.

4. **Mixing legacy and new code.** The `Legacy/` directory exists for historical code. New functionality goes in `Sources/Core/` or `Sources/Features/`. Never import from Legacy in new code.

5. **God objects.** `PreviewData.swift` currently holds all model definitions. These are being migrated to `Sources/Core/Models/`. Do not add new types to PreviewData — create proper model files.
