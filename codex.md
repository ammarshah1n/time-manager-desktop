# Timed — Codex Context

> Read AGENTS.md and CLAUDE.md for full context. This file is a quick-start for sandboxed agents.

## Build
```
swift build
swift test
```

## File Placement
```
Sources/Core/Models/       → Codable structs, one per file
Sources/Core/Services/     → Protocol + implementation pairs
Sources/Core/Clients/      → GraphClient, SupabaseClient singletons
Sources/Core/Utilities/    → Pure helpers
Sources/Features/{FR}/     → Feature-specific code
Tests/                     → Mirror Sources/ structure, {TypeName}Tests.swift
docs/specs/                → FR specs with acceptance criteria
docs/rules/                → Architecture rules (mirrored from vault)
docs/decisions/            → ADRs
tools/taskflow/            → Task orchestration
```

## Rules
1. Protocol-first: define protocol, then implement
2. No business logic in route handlers or entry points
3. All models Codable + Sendable
4. One type per file, filename = type name
5. Update PLAN.md after every task
6. Update FILE ORACLE in CLAUDE.md after creating any .swift file
7. All Graph API calls through GraphClient.swift only
8. All Supabase access through SupabaseClient.swift only

## Test Framework
`import Testing` (Swift Testing). NOT XCTest.
`@testable import time_manager_desktop`

If `swift test` fails with `no such module 'Testing'`, uncomment the swift-testing
dependency in Package.swift (requires network to fetch the package).

## No External Access
You have no internet, no MCP, no Obsidian vault. Everything you need is in this repo.
