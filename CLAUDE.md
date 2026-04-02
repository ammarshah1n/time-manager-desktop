# Timed — Project Brain

## What This Is
macOS application: the most intelligent executive operating system ever built.
Builds a deep, compounding cognitive model of how a specific C-suite executive
thinks, decides, avoids, prioritises, communicates, and operates — then uses
that model to give them their cognitive bandwidth back, permanently.

**HARD CONSTRAINT: observation and intelligence only.** Never sends emails,
modifies calendars, or takes any action on the world. The human always decides
and executes. Never negotiate this boundary.

## Mission (non-negotiable)
1. No cost cap on intelligence — Opus 4.6 at max effort for the reflection engine
2. Intelligence compounds over time — month 6 incomparably smarter than month 1
3. The reflection engine is the heart — recursive reflection, not summaries
4. Morning session delivers intelligence, not a task list
5. Cognitive layer only — observe, reflect, recommend. Never act.
6. The user is a C-suite executive — impressed by depth, not features

## Tech Stack
- Language: Swift 6.1, SwiftUI, macOS 14+, StrictConcurrency enabled
- State: Vanilla SwiftUI (@State, @Binding, @StateObject) + TCA Dependencies for DI
- Storage: Local JSON (DataStore actor) + Supabase Postgres (remote)
- API: Microsoft Graph (Outlook email + calendar, read-only via MSAL)
- AI: Claude Opus 4.6 (reflection engine), Haiku 3.5 (classification), Sonnet (estimation)
- Embeddings: Jina AI jina-embeddings-v3 (1024-dim)
- Voice: Apple Speech framework (local, on-device, no cloud)
- Backend: Supabase (ref: fpmjuufefhtlwbfinxlx), 9 Edge Functions (TypeScript)

## Architecture — Four Layers
See docs/01-architecture.md for full definitions.

| Layer | Purpose | Cadence |
|-------|---------|---------|
| Signal Ingestion | Reads external data (email, calendar, voice, behaviour) | Continuous, passive |
| Memory Store | Three-tier persistence (episodic/semantic/procedural) | Persistent |
| Reflection Engine | Pattern extraction, synthesis, rule generation | Periodic (nightly + triggered) |
| Delivery | Morning session, menu bar, proactive alerts | On-demand + scheduled |

**Key rule:** These four layers have defined interfaces. Do not couple them.

## Coding Conventions
- Swift strict concurrency (async/await, actors for stores)
- Unit tests for all ML model components and memory operations
- Log all memory read/write operations via TimedLogger
- NEVER use UserDefaults for anything beyond UI preferences
- File naming: [Layer][Component].swift (e.g., MemoryEpisodicStore.swift)
- Domain models belong in Sources/Core/Models/, not PreviewData.swift

## Current Build State
See BUILD_STATE.md — read this before every task.

## Key Decisions
See docs/08-decisions-log.md for why specific choices were made.

## Repo
- Owner: ammarshah1n/time-manager-desktop
- Branch: ui/apple-v1-restore
- Backend: Supabase project fpmjuufefhtlwbfinxlx
- Azure: App Registration for Microsoft OAuth

## Commands
- /new-session — runs session orientation protocol
- /handoff — creates session handoff doc before ending
- /sync-docs — updates BUILD_STATE.md from current conversation
