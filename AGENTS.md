# AGENTS.md — Timed (time-manager-desktop)

> Per-project AGENTS.md for Codex. Inherits global rules from `~/.codex/AGENTS.md`. Stack-specific overrides below.

## Stack
- Swift 5.9 / SwiftUI / SwiftData / Swift Testing
- macOS 15+ desktop (no iOS-only code outside Platforms/iOS/, no UIKit, no Combine, no deprecated APIs)
- Backend: Supabase project `fpmjuufefhtlwbfinxlx`, 29 Edge Functions all active
- Auth: Microsoft OAuth + Supabase Auth (`AuthService.swift` implemented, UI bridge pending)

## Branch Discipline
- **Always work on `unified`.** First action of any session: `git checkout unified && git pull`.
- Do NOT branch off `ui/apple-v1-restore`, `ui/apple-v1-local-monochrome`, `ui/apple-v1-wired`, or `ios/port-bootstrap`.

## Memory & State
- **basic-memory project:** `timed-brain` (1198+ notes). For AIF questions: also search `aif-vault`.
- **Vault state:** `~/Timed-Brain/Working-Context/timed-brain-state.md` — read at session start.
- **Vault index:** `~/Timed-Brain/VAULT-INDEX.md` → `HANDOFF.md` → `Working-Context/timed-brain-state.md`.
- **Search:** `qmd search "term" -c timed-brain` (BM25), `qmd query "question" -c timed-brain` (hybrid).

## Read Order on Session Start
1. `docs/UNIFIED-BRANCH.md`
2. `HANDOFF.md`
3. `BUILD_STATE.md`
4. `CLAUDE.md` (canonical) / this file
5. `MASTER-PLAN.md` STATUS section

## Build Commands
- Build: `swift build`
- Test: `swift test`
- Build release: `swift build -c release`
- Mac xcodebuild: `xcodegen generate` then `xcodebuild -skipMacroValidation -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES ...`
- DMG: `bash scripts/package_app.sh && bash scripts/create_dmg.sh` → `dist.noindex/Timed.dmg`

## Architecture Rules (NEVER violate)
- No external Swift dependencies beyond `supabase-swift` + `MSAL`.
- All AI calls go through Edge Functions via Supabase client. No direct Anthropic API calls in Swift.
- All persistence goes through Supabase PostgREST. No local JSON files (the `DataStore` is being deprecated).
- All Microsoft Graph calls go through `GraphClient.swift`. No inline Graph API calls anywhere else.
- All ranking logic lives in `PlanningEngine`. No scoring in views or stores.
- New Swift files: `Sources/TimedKit/Features/<area>/` or `Sources/TimedKit/Core/<area>/`. Mac-only wraps in `#if os(macOS)`.

## Anti-Patterns (HARD STOPS)
- NEVER suggest cheaper models for the core intelligence engine. Intelligence quality IS the product.
- NEVER have Timed act on the world (no sending email, no booking, no scheduling). Timed observes, reflects, recommends — never acts.
- NEVER treat `DataStore` as source of truth. Supabase is the source of truth once Auth lands.
- NEVER apply web or Next.js patterns. macOS desktop only.
- NEVER skip the read order. Verify infra state with CLI before trusting docs.
- NEVER ship third-party API keys to the client. Anthropic/ElevenLabs/Deepgram/OpenAI keys live in Supabase Edge Function secrets only.

## Test Loop
1. Modify Swift file
2. `swift test --filter TestName`
3. Fix immediately on structured failure
4. Repeat until green
- Framework: `import Testing` (Swift Testing). Naming: `{TypeName}Tests.swift`.

## Commit Format
`feat(timed): description` / `fix(timed): description` / `chore(timed): description` — subject under 70 chars. One commit per change.

## Build & Test Tools
- XcodeBuildMCP: `build_sim` / `test_sim` / `debug_attach_sim` — structured JSON errors, prefer over raw `xcodebuild`.
- `xcrun mcpbridge`: `DocumentationSearch` for Apple API questions, `ExecuteSnippet` to verify Swift API behaviour.
- Supabase MCP: deploy edge functions, fetch logs. Service-role bypasses RLS — never `always_allow` destructive ops.

## Circuit Breaker
3 attempts at the same operation with the same error → STOP. Write error to `PLAN.md` under BLOCKED. Exit cleanly.

## Acceptance Criteria (do not stop until all pass)
1. `swift build` exits 0
2. `swift test` exits 0 — all tests pass
3. `BUILD_STATE.md` updated with what was built and what comes next
