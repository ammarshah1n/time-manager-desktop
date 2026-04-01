# AGENTS.md — Timed (Timed) Autonomous Agent Rules

## You are building Timed. Read CLAUDE.md fully before starting.

## Task Execution Protocol (taskflow)
Tasks are managed via `taskflow` (`tools/taskflow/taskflow.sh`).

**If launched by taskflow autopilot:**
1. You receive focused context with task description, acceptance criteria, FR spec, and completed dependencies
2. Implement against the acceptance criteria provided
3. Run `swift build` and `swift test` to verify
4. When ALL criteria met and tests pass, output: `TASK_COMPLETE`
5. If stuck after 3 attempts on same error, output: `TASK_BLOCKED`

**If working manually:**
1. Run `taskflow next` to find what to work on
2. Run `taskflow start <id>` to get focused context
3. Implement against the acceptance criteria
4. Run `swift build` and `swift test`
5. Run `taskflow complete <id>` when done (writes walkthrough + updates PLAN.md)

**Never:**
- Work on a task not assigned via `taskflow start`
- Skip acceptance criteria checks
- Mark complete without `swift build` passing

## Build Commands
- Build: `swift build`
- Test: `swift test`
- Build release: `swift build -c release`

## Test Patterns
Framework: `import Testing` (Swift Testing). Requires Xcode or swift-testing SPM package.
Import: `@testable import time_manager_desktop`

**Environment note:** If `swift test` fails with `no such module 'Testing'`, uncomment the
swift-testing dependency in Package.swift. This happens with Command Line Tools only (no Xcode).

Example:
```swift
import Testing
@testable import time_manager_desktop

@Suite("EmailMessage Tests")
struct EmailMessageTests {
    @Test("Codable roundtrip preserves all fields")
    func codableRoundtrip() throws {
        let original = EmailMessage(
            id: UUID(),
            subject: "Test",
            sender: "test@example.com",
            receivedAt: Date(),
            body: "Hello",
            isRead: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EmailMessage.self, from: data)
        #expect(original.id == decoded.id)
        #expect(original.subject == decoded.subject)
    }
}
```

Naming: `{TypeName}Tests.swift`, methods describe behaviour not implementation.

## Architecture Rules
- No external Swift dependencies beyond supabase-swift + MSAL. Pure SwiftUI + Foundation + EventKit.
- All AI calls go through Edge Functions via Supabase client. No direct Claude API calls in Swift.
- All persistence goes through Supabase PostgREST. No local JSON files.
- All Microsoft Graph calls go through a single GraphClient module. No inline Graph API calls.
- All ranking logic lives in PlanningEngine. No scoring in views or stores.
- NEVER apply web or Next.js patterns. This is macOS 15 desktop only.

## Hard Stops (stop immediately, don't attempt to fix)
- Swift compiler errors in files you didn't create
- Missing environment variables (GRAPH_CLIENT_ID, SUPABASE_URL, etc.)
- Azure OAuth errors (require human config)
- Any database migration conflicts
- Supabase Edge Function deployment failures

## Never Do
- Write raw SQL against cloud database
- Import Supabase SDK directly (use the app's SupabaseClient singleton)
- Call Microsoft Graph outside GraphClient module
- Create files outside Sources/, Tests/, supabase/, docs/, or tools/
- Use setTimeout/Timer for job scheduling (Edge Functions + pg_cron only)

## Agent Teams (experimental — use after FR-01 hooks are battle-tested)

For cross-layer FRs (e.g. "build FR-01 end-to-end"), use Agent Teams instead of manual worktrees:
- Shift+Up/Down to select teammates, Ctrl+T for shared task list
- Teammates can message each other directly — no round-trip through you
- Use for FRs that touch shared interfaces (GraphClient ↔ classifier ↔ Supabase)
- Keep worktrees for truly independent FRs with zero shared interfaces
- **Do NOT use Agent Teams until FR-01 is complete and all hooks have been validated on real work**

## Circuit Breaker
If you've attempted the same operation 3 times with the same error: STOP.
Write the error to PLAN.md under BLOCKED. Exit cleanly.

---

## ACCEPTANCE CRITERIA — DO NOT STOP UNTIL THESE ALL PASS

1. `swift build` exits 0 with no errors
2. `swift test` exits 0 — all tests pass
3. PLAN.md updated with what was built and what comes next
