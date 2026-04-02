# Claude Code Project Configuration Spec

> Timed v1 Intelligence Layer | Last updated: 2026-04-02

---

## Overview

Three configuration files control how Claude Code operates on the Timed project. Together they form the AI development environment: CLAUDE.md is the project brain, settings.json controls permissions, and mcp.json connects external tools.

---

## File 1: CLAUDE.md (Project Root)

This file lives at the repository root. Claude Code reads it at the start of every session. It is the single source of truth for architecture rules, code conventions, and session workflow.

### Complete Content

```markdown
# CLAUDE.md — Timed Project

## What Is Timed

Timed is a macOS cognitive intelligence layer for C-suite executives. It builds a compounding model of how a specific person thinks, decides, avoids, and operates -- then uses that model to return cognitive bandwidth. Observation and intelligence only. It never acts on the world.

## Hard Constraints (NEVER violate)

1. **Observation only.** Never generate code that sends emails, modifies calendars, writes files outside the app sandbox, or takes any action on the user's behalf. If you catch yourself writing a POST/PUT/PATCH/DELETE to any external API that modifies state, STOP.
2. **No cross-layer coupling.** Layer 1 code must not import Layer 2 types. Layer 2 code must not import Layer 3 types. Layers communicate through protocols defined in `Sources/Timed/Protocols/`. If you need a type from another layer, you are doing it wrong.
3. **Privacy abstraction pipeline.** Every string sent to an external LLM API (Claude, Jina) must first pass through `PrivacyAbstractor.sanitise()`. No raw user data leaves the device without sanitisation. No exceptions.
4. **No force unwraps.** Never use `!` for unwrapping. Use `guard let`, `if let`, or nil-coalescing. Never use `try!`. Use `do/catch` or `try?` with explicit fallback.
5. **No dependencies without approval.** Do not add Swift Package Manager dependencies without explicit approval. The current approved list: MSAL, Sparkle, Supabase Swift SDK. Everything else, ask first.

## Architecture

```
Layer 1: Signal Ingestion (continuous, passive)
    |  writes Signal records
    v
Layer 2: Memory Store (persistent, tiered)
    |  provides memories via MemoryQuerying protocol
    v
Layer 3: Reflection Engine (periodic, nightly)
    |  writes patterns/rules back to Layer 2
    |  produces MorningBrief payloads
    v
Layer 4: Intelligence Delivery (on-demand + scheduled)
    |  user interactions become signals -> Layer 1
    v
    (loop)
```

### Layer Boundaries

| Boundary | Protocol | Data Direction |
|----------|----------|----------------|
| L1 -> L2 | `SignalWritePort` | Signal value types (structs, not managed objects) |
| L2 -> L3 | `MemoryQuerying` | Memory DTOs with scores |
| L3 -> L2 | `MemoryWriting` | New semantic facts, procedural rules, patterns |
| L3 -> L4 | `IntelligencePayload` | MorningBrief, alerts, pattern summaries |
| L4 -> L1 | `UserInteractionSignal` | Dismissals, corrections, queries |

### No cross-layer violations -- examples

BAD: `import Layer2` inside a Layer 1 file.
BAD: Layer 3 calling `EpisodicMemoryRepository.save()` directly instead of through `MemoryWriting` protocol.
BAD: Layer 4 SwiftUI view importing `ReflectionOrchestrator`.
GOOD: Layer 1 agent calls `signalBus.emit(Signal(...))`.
GOOD: Layer 3 calls `memoryWriter.writeSemanticFact(...)` through the protocol.

## Directory Structure

```
Sources/Timed/
  Core/                  # Shared utilities, logging, error types
    Clients/             # ClaudeClient, EmbeddingService, SupabaseClient, GraphClient
    Privacy/             # PrivacyAbstractor, sanitisation rules
    Extensions/          # Swift extensions
  Models/                # CoreData model, managed object subclasses, enums
  Protocols/             # ALL inter-layer protocols live here (shared, no layer owns them)
  Layer1/                # Signal Ingestion
    Agents/              # EmailAgent, CalendarAgent, AppFocusAgent, VoiceAgent, TaskAgent
    SignalBus/           # SignalBus actor, signal queue
  Layer2/                # Memory Store
    Repositories/        # EpisodicMemoryRepository, SemanticMemoryRepository, ProceduralMemoryRepository
    CoreMemory/          # CoreMemoryManager
    Retrieval/           # MemoryRetrievalEngine, vector search
    Consolidation/       # MemoryConsolidationEngine
  Layer3/                # Reflection Engine
    Orchestrator/        # ReflectionOrchestrator
    Stages/              # Stage1Summariser, Stage2PatternExtractor, Stage3Synthesiser, Stage4RuleGenerator, Stage5ModelUpdater, Stage6BriefPreparer
    Prompts/             # ReflectionPrompts.swift (all prompt templates)
    Patterns/            # PatternLifecycleManager
  Layer4/                # Intelligence Delivery
    MorningSession/      # MorningSessionView, MorningSessionViewModel
    MenuBar/             # MenuBarView, MenuBarManager
    Alerts/              # ProactiveAlertManager
    FocusTimer/          # FocusTimerView, FocusTimerViewModel
    Query/               # QueryInterfaceView, QueryRouter
    DayPlan/             # DayPlanGenerator, DayPlanView
  App/                   # TimedApp.swift, AppDelegate, entry point

Tests/TimedTests/
  Layer1/
  Layer2/
  Layer3/
  Layer4/
  Core/
  Integration/           # Cross-layer integration tests
```

## Code Conventions

### Swift Style

- **Actors for all services.** Every repository, manager, client, and agent is an actor. No class-based services.
- **@Observable for ViewModels.** All view models use the Observation framework, not Combine.
- **Structured concurrency.** Use `async/await`, `TaskGroup`, `AsyncStream`. No completion handlers. No `DispatchQueue` unless interfacing with a non-async API (mark with `// BRIDGE: non-async API`).
- **One type per file.** File name matches type name. `EmailAgent.swift` contains `actor EmailAgent`.
- **Naming:** PascalCase for types. camelCase for properties/functions. Agent files: `*Agent.swift`. Memory types: `*Memory.swift` or `*MemoryRepository.swift`. Views: `*View.swift`. ViewModels: `*ViewModel.swift`.

### CoreData

- **Background contexts for writes.** All write operations use `container.newBackgroundContext()`.
- **Main context for reads only.** SwiftUI views read from `container.viewContext`.
- **Merge policy:** `NSMergeByPropertyObjectTrumpMergePolicy`.
- **No managed objects cross context boundaries.** Pass value-type DTOs between contexts.
- **Every schema change gets a migration test.**

### Error Handling

```swift
enum TimedError: Error {
    case signal(SignalError)
    case memory(MemoryError)
    case reflection(ReflectionError)
    case delivery(DeliveryError)
    case api(APIError)
    case auth(AuthError)
}
```

Each sub-enum has specific cases. Never use a generic `.unknown` without a debug message.

### API Calls

Every call to Claude or Jina:
1. `PrivacyAbstractor.sanitise(input)` -- strips PII
2. `ClaudeClient.send(sanitisedInput)` -- makes the call
3. `PrivacyAbstractor.restore(output)` -- re-inserts PII tokens

Never skip step 1. Never send raw user content to an external API.

### Logging

```swift
import OSLog

extension Logger {
    static let layer1 = Logger(subsystem: "com.timed.app", category: "Layer1")
    static let layer2 = Logger(subsystem: "com.timed.app", category: "Layer2")
    static let layer3 = Logger(subsystem: "com.timed.app", category: "Layer3")
    static let layer4 = Logger(subsystem: "com.timed.app", category: "Layer4")
    static let auth   = Logger(subsystem: "com.timed.app", category: "Auth")
    static let api    = Logger(subsystem: "com.timed.app", category: "API")
    static let data   = Logger(subsystem: "com.timed.app", category: "CoreData")
}
```

Use `.debug` for verbose tracing, `.info` for normal operations, `.error` for failures, `.fault` for unrecoverable issues.

## Testing Rules

- **Framework:** Swift Testing (`import Testing`), NOT XCTest.
- Every public protocol method has at least one test.
- Agent tests verify: (1) signal emission for valid input, (2) no emission for invalid input, (3) error handling for API failures.
- Memory tests verify: CRUD, decay, lifecycle transitions, concurrent access safety.
- Reflection tests verify: output structure, pattern quality (not just "it ran"), contradiction detection.
- Integration tests in `Tests/TimedTests/Integration/` test cross-layer flows.
- Run `swift test` before and after every change.

## Commit Rules

- Commit after EVERY single logical change. Not batched.
- Format: `type(scope): description`
  - `feat(layer2): add episodic memory repository`
  - `fix(layer1): handle Graph API 429 rate limit`
  - `refactor(core): extract privacy abstraction to separate module`
  - `test(layer3): add reflection stage 2 pattern quality tests`
  - `docs: update build sequence with Phase 3 completion`
- Never commit: secrets, API keys, user data, `.env` files, CoreData store files.

## Session Workflow

1. Read this CLAUDE.md.
2. Read the last SESSION_LOG.md entry (what happened last time, what's next).
3. Read the relevant spec doc for today's task (from `docs/`).
4. Run `swift build` -- confirm clean baseline.
5. Run `swift test` -- confirm all tests pass.
6. Work on the task. Commit after each logical change.
7. Run `swift test` after every change.
8. Update SESSION_LOG.md before ending.

## What Claude Must NOT Do

- Generate code that acts on the world (sends emails, modifies calendars, writes external files).
- Skip the privacy abstraction pipeline on ANY external API call.
- Add SPM dependencies without explicit approval.
- Modify layer boundary protocols without discussion.
- Use SwiftUI previews that require real API calls.
- Use `try!`, `!` (force unwrap), or `fatalError()` in production code.
- Batch commits across multiple logical changes.
- Create files outside the defined directory structure.

## AI Model Usage

| Model | Use For | Token Budget |
|-------|---------|--------------|
| Haiku 3.5 | Signal classification, importance scoring, quick categorisation | ~500 tokens per call |
| Sonnet | Time estimation, day-level summarisation, medium-complexity analysis | ~2,000 tokens per call |
| Opus 4.6 | Nightly reflection (Stages 3-4), morning director, deep pattern analysis | No cap -- quality is the priority |

## Key Specs (read when working on specific layers)

| Layer | Spec Files |
|-------|------------|
| Layer 1 | `docs/signal-email.md`, `docs/signal-calendar.md`, `docs/signal-app-focus.md`, `docs/signal-voice.md`, `docs/signal-task-interaction.md` |
| Layer 2 | `docs/episodic-memory.md`, `docs/semantic-memory.md`, `docs/procedural-memory.md`, `docs/memory-retrieval.md`, `docs/memory-tier-promotion.md`, `docs/memgpt-context-management.md` |
| Layer 3 | `docs/reflection-engine-architecture.md`, `docs/first-order-pattern-extraction.md`, `docs/second-order-insight-synthesis.md`, `docs/rule-generation.md`, `docs/reflection-engine-prompt-templates.md`, `docs/named-pattern-library.md` |
| Layer 4 | `docs/morning-intelligence-session.md`, `docs/morning-session-voice.md`, `docs/menu-bar-presence.md`, `docs/proactive-alert.md`, `docs/focus-timer.md`, `docs/day-plan-generation.md`, `docs/query-interface.md` |
| Cross-cutting | `docs/data-models.md`, `docs/architecture.md`, `docs/background-agent-architecture.md`, `docs/privacy-data-handling.md`, `docs/microsoft-graph-integration.md` |
```

---

## File 2: .claude/settings.json

This file lives at `.claude/settings.json` in the repository. It controls which tools and commands Claude Code can execute without asking for confirmation.

### Complete Content

```json
{
  "permissions": {
    "allow": [
      "Bash(swift build)",
      "Bash(swift test)",
      "Bash(swift test --filter *)",
      "Bash(swift package resolve)",
      "Bash(swift package update)",
      "Bash(git status)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git log *)",
      "Bash(git diff *)",
      "Bash(git branch *)",
      "Bash(git checkout *)",
      "Bash(git stash *)",
      "Bash(git push *)",
      "Bash(ls *)",
      "Bash(mkdir *)",
      "Bash(cat *)",
      "Bash(wc *)",
      "Bash(xcrun notarytool *)",
      "Bash(codesign *)",
      "Bash(hdiutil *)",
      "Bash(supabase *)",
      "Read",
      "Write",
      "Edit",
      "Glob",
      "Grep",
      "mcp__comet__*"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(curl * -X POST *)",
      "Bash(curl * -X PUT *)",
      "Bash(curl * -X DELETE *)",
      "Bash(sudo *)",
      "Bash(defaults write *)",
      "Bash(open *)",
      "Bash(osascript *)",
      "Bash(security *)"
    ]
  },
  "model": {
    "default": "claude-opus-4-6"
  }
}
```

### Permission Rationale

**Auto-allowed:**
- `swift build`, `swift test` -- these run constantly during development. Confirming each one would destroy flow.
- All `git` commands -- Claude commits after every change. Must be frictionless.
- `ls`, `mkdir`, `cat`, `wc` -- basic filesystem inspection.
- `supabase` -- CLI for checking edge function status, running migrations.
- `xcrun notarytool`, `codesign`, `hdiutil` -- DMG packaging pipeline.
- All file tools (`Read`, `Write`, `Edit`, `Glob`, `Grep`) -- core development operations.
- `mcp__comet__*` -- Comet browser automation for testing OAuth flows and inspecting Supabase dashboard.

**Denied:**
- `rm -rf` -- prevent accidental deletion of the project or system files.
- `curl` with mutating HTTP methods -- prevent accidental writes to external APIs (observation-only constraint extends to the dev environment).
- `sudo` -- no privilege escalation.
- `defaults write` -- no system preference changes.
- `open` -- no opening arbitrary applications or URLs (Comet handles browser interaction).
- `osascript` -- no AppleScript execution (powerful but unpredictable).
- `security` -- no Keychain manipulation outside the app.

### Commands That Require Confirmation

Anything not in `allow` or `deny` will prompt for confirmation. This includes:
- `npm`, `pip`, `brew` -- dependency installation must be intentional.
- `curl -X GET` -- reading external APIs is fine but should be visible.
- `swift package init` -- creating new packages should be deliberate.

---

## File 3: .claude/mcp.json

This file configures MCP (Model Context Protocol) servers that give Claude Code access to external tools.

### Complete Content

```json
{
  "mcpServers": {
    "comet": {
      "command": "npx",
      "args": ["-y", "@anthropic/comet-mcp-server"],
      "description": "Browser automation for testing OAuth flows, inspecting Supabase dashboard, and verifying web-based integrations.",
      "env": {}
    }
  }
}
```

### Comet MCP Usage Scenarios

| Scenario | How |
|----------|-----|
| Test Microsoft OAuth flow | `comet_connect` to `login.microsoftonline.com`, walk through consent screen, verify token receipt |
| Inspect Supabase dashboard | `comet_connect` to project dashboard, verify edge function status, check RLS policies |
| Verify Sparkle appcast | `comet_connect` to appcast URL, verify XML structure and version info |
| Test Graph API in browser | `comet_connect` to Graph Explorer, verify query results match app behaviour |

### Future MCP Servers (add when needed)

| Server | When | Purpose |
|--------|------|---------|
| `supabase-mcp` | Phase 1 (if available) | Direct Supabase operations without browser |
| `obsidian-mcp` | Phase 1 | Read/write Obsidian vault notes from Claude Code |

---

## How Sessions Start

1. Claude Code launches and reads `CLAUDE.md` from the project root. This loads the full architecture context, rules, and conventions.
2. Claude reads the last entry in `SESSION_LOG.md` to understand: what was done last, what's next, any blockers.
3. Claude reads the spec doc(s) relevant to the current task (listed in `CLAUDE.md` key specs table).
4. Claude runs `swift build` and `swift test` to confirm a clean baseline.
5. If either fails, Claude fixes the issue before starting new work.

**Total context loaded at session start:** CLAUDE.md (~3,000 tokens) + last session log (~500 tokens) + relevant spec (~2,000-5,000 tokens) = ~5,500-8,500 tokens of project context. Well within budget.

---

## How Subagents Are Used

Claude Code's Agent tool dispatches subagents for parallelisable work. The dispatch rules (from CLAUDE.md global context) apply:

### Fire Subagents When

- 3+ files need editing simultaneously (e.g., adding a new entity to CoreData model + repository + tests).
- Writing or modifying tests (test writing is well-specified boilerplate).
- Generating >150 lines of new code (e.g., a new agent scaffold).
- Same operation on multiple files (e.g., adding OSLog to all 5 agents).
- Bulk edits (e.g., renaming a type across all files).

### Keep In Main Context When

- Architecture decisions (which approach for a layer boundary).
- Debugging cross-layer issues (needs full system context).
- Prompt engineering for the reflection engine (iterative, needs quality judgment).
- Reviewing code quality across a phase.

### Subagent Prompt Template

When dispatching a subagent, include:

```
You are working on the Timed project, a macOS cognitive intelligence layer.

**Read first:** CLAUDE.md (project root)
**Layer:** [Layer 1/2/3/4]
**Task:** [specific task]
**Files to create/modify:** [list]
**Constraints:**
- Follow all CLAUDE.md rules (especially observation-only, no cross-layer imports, privacy pipeline)
- Use Swift Testing, not XCTest
- Commit format: type(scope): description
- Run swift build + swift test after changes

**Acceptance criteria:** [specific, testable]
```

---

## How Configuration Evolves

### CLAUDE.md Growth Strategy

As the project grows, CLAUDE.md will accumulate rules. To keep it manageable:

1. **Phase 1-3:** Everything in one CLAUDE.md. It will be ~3,000-5,000 tokens. Fine.
2. **Phase 4+:** If CLAUDE.md exceeds 6,000 tokens, split layer-specific rules into:
   - `docs/layer1-conventions.md`
   - `docs/layer2-conventions.md`
   - `docs/layer3-conventions.md`
   - `docs/layer4-conventions.md`
   
   CLAUDE.md retains: hard constraints, architecture overview, directory structure, commit rules, session workflow. Layer files are loaded on-demand based on the task.

3. **New rules:** When a bug or mistake reveals a missing convention, add the rule to CLAUDE.md immediately. Format:
   ```
   ## Rule: [name]
   **Added:** [date]
   **Trigger:** [what happened that required this rule]
   **Rule:** [the rule]
   ```

### settings.json Growth

- Add new `allow` entries as new tools are adopted.
- Never expand `deny` list to `allow` without explicit discussion.
- If a new MCP server is added, its tools get `allow` entries.

### mcp.json Growth

- Add servers only when a concrete use case demands it.
- Each server gets a `description` field explaining why it exists.
- Remove servers that haven't been used in 2+ weeks.

---

## Layer-Specific Conventions

### Layer 1 (Signal Ingestion)

- Every agent is an actor conforming to `SignalWritePort`.
- Agents MUST NOT classify signals themselves -- they emit raw signals to the `SignalBus`. Haiku classification happens in a separate classification step after emission.
- Exception: App focus agent classifies locally (bundle ID -> category mapping, no API call needed).
- Polling intervals are configurable via `AgentConfiguration` struct (not hardcoded).
- Every agent implements `health() -> AgentHealth` for monitoring.

### Layer 2 (Memory Store)

- Every repository is an actor.
- All CoreData writes happen on background contexts.
- Every memory write generates an embedding via `EmbeddingService` (async, non-blocking).
- Retrieval always goes through `MemoryRetrievalEngine` -- never query CoreData directly from outside Layer 2.
- Value-type DTOs cross the layer boundary, never managed objects.

### Layer 3 (Reflection Engine)

- All prompts live in `ReflectionPrompts.swift` as static string constants with interpolation points.
- Every prompt includes the core memory buffer in the system message.
- Every prompt output must be structured JSON that parses into a Swift type.
- Never modify Layer 2 directly -- use the `MemoryWriting` protocol.
- Log every prompt + response for debugging (local only, never sent externally).

### Layer 4 (Intelligence Delivery)

- Views are pure SwiftUI. No business logic in views.
- ViewModels are `@Observable` actors that query Layer 2 and format data for display.
- No direct access to Layer 3 -- all intelligence comes through pre-computed payloads or Layer 2 queries.
- User interactions (dismissals, corrections, queries) are emitted as signals back to Layer 1.
