---
name: code-review-objective-aligned
description: Timed-specific code review skill aligned to Ammar's hard objectives. Drives a structured review of a diff produced by any worker (JCode subagent, CC subagent, Codex exec, manual edit). Checks architectural pillars (no client-side AI keys, GraphClient/SupabaseClient boundaries, RLS, no Timed-acts violations), cognitive-load UI rules, type safety, Swift 6 concurrency, and dispatches sub-reviewers per file type. Used by the CC-plans-JCode-executes workflow's Phase-4 automated review block. Default reviewer model GPT-5.5 (xhigh) for first pass; Opus 4.7 final double-check. NO DEFERRALS — gaps either get filled by a follow-up worker dispatch or surfaced as explicit human blockers.
---

# Code Review — Objective-Aligned (Timed)

Use when reviewing a diff against Ammar's hard Timed objectives. Drives a structured pass through architectural pillars, fans out to specialist reviewers per file type, and ends with a binary verdict (APPROVE / REQUEST_CHANGES / BLOCKED_ON_HUMAN).

## Inputs (provided by the dispatching CC parent)
- **Diff** — `git diff <base>..<worktree-branch>` from the worker's branch
- **Brief** — the original step-N.md the worker received (acceptance criteria + scope)
- **Summary** — the worker's step-N-summary.md (decisions made, NOT the verdict)
- **Plan** — the original `.exec/<feature>/plan.md` (so reviewer knows the broader feature context)

## Checklist — run in order

### 1. Hard architectural constraints (auto-FAIL on any violation)
- No third-party API keys in client code. Grep diff for `sk-ant-`, `sk-`, `xi-api-key`, `Bearer eyJ`, etc.
- All Microsoft Graph calls go through `GraphClient.swift`. No direct `https://graph.microsoft.com` URLs in feature code.
- All Google/Gmail calls go through `GoogleClient.swift` / `GmailClient.swift`.
- No `DataStore` writes. Persistence goes through Supabase PostgREST.
- No `setTimeout` / `setInterval` / cron-in-app-code. Background work goes through Supabase Edge Functions or Trigger.dev.
- Schema changes ONLY via `supabase/migrations/`. No raw SQL execution against cloud.
- RLS enabled on every new table. Policies present and named.
- No "Timed acts on the world" violations: no email-send, no calendar-create, no message-send, no booking, no contacting anyone. Timed observes/reflects/recommends only.

### 2. Cognitive load pillar (Timed UI rules 14-15)
For any SwiftUI views in the diff:
- No empty rows. If a field has no value, the row is HIDDEN, not rendered as `—` or `(none)` placeholder.
- No decorative chrome that doesn't earn its weight.
- If a section is informational-only and rare, it's folded into another section.

### 3. Type safety
- No `as!` force-casts.
- No `as? Any`.
- No `Any` in function signatures (use generics or protocols).
- No commented-out code (delete it).

### 4. Concurrency (Swift 6+)
- `@MainActor` on UI-touching functions.
- `Sendable` conformances on shared state.
- No data races (no shared mutable state without protection).
- Async functions use `await`, not callback-based legacy.

### 5. Sub-reviewer dispatch (run in parallel where the dep graph allows)
Based on file types in the diff:
- `Sources/TimedKit/Features/**/*.swift` → invoke `swiftui-pro` (UI patterns) + `swift-concurrency` (race / actor isolation)
- `Sources/TimedKit/Core/**/*.swift` → invoke `tca-patterns` (TCA invariants) + `swift-concurrency`
- `Tests/**/*.swift` → invoke `swift-testing-pro` (Swift Testing framework, not XCTest; verify mocks don't fake the wrong layer)
- `supabase/migrations/*.sql` → invoke `supabase-postgres-best-practices` (RLS, indexes, FKs, EXPLAIN-friendly query patterns, no SECURITY DEFINER without justification)
- `supabase/functions/*/index.ts` → review for: untrusted-input `<untrusted_*>` fences, model allowlist, max_tokens cap, no upstream-error echoing, service-role auth check vs user JWT
- `**/*.tsx` / `**/*.ts` (Next.js) → general TypeScript review for type safety, no `any`

### 6. Acceptance criteria verification
For each criterion in the brief's `Acceptance criteria` section:
- Explicitly verified by the diff or the actual test output, or just claimed by the worker?
- If unverified: dispatch a follow-up step. NO DEFERRALS.

### 7. Plan-completion reassessment (NO DEFERRALS)
Compare the original `.exec/<feature>/plan.md` to what was shipped:
- Did everything the plan said get done?
- If NOT: is the gap fillable by another worker dispatch right now? If yes, dispatch it.
- If the gap is a HUMAN BLOCKER (needs Apple Developer cert, OAuth grant, Yasser's confirmation, etc.): surface it explicitly with the exact action Ammar must take. Don't defer it silently. Don't ignore it.

### 8. Test thoroughness
- Targeted tests passed? Worker self-reports the verbatim output — independently re-run by CC verifying gate.
- Full test suite for the touched module passes? CC re-runs `swift test` for the relevant target (not just `--filter`) before approving.
- No regressions in adjacent tests? Compare test count + duration vs baseline.

## Output schema

Structured report:

```
## Architectural pillars
- [PASS/FAIL per pillar with verbatim diff quote on any FAIL]

## Cognitive load
- [PASS/FAIL with affected views]

## Type safety
- [PASS/FAIL with violations cited line:col]

## Concurrency
- [PASS/FAIL]

## Sub-reviewer outputs
- swiftui-pro: <verdict + notes>
- swift-concurrency: <verdict + notes>
- swift-testing-pro: <verdict + notes>
- (etc per file type)

## Acceptance criteria
- [PASS/FAIL per criterion with evidence]

## Plan completion
- [Items shipped]
- [Items NOT shipped — fillable now / human blocker / dropped per justification]

## Test thoroughness
- targeted: [tests + result]
- module suite: [tests + result]
- regressions: [count]

## Final verdict
- APPROVE / REQUEST_CHANGES / BLOCKED_ON_HUMAN
- If REQUEST_CHANGES: dispatch fix step <fix-spec>
- If BLOCKED_ON_HUMAN: action Ammar must take is <exact action>
```

## Reviewer routing
1. **First pass — GPT-5.5 (xhigh)** via `jcode -C <worktree> --provider openai --model gpt-5.5 --reasoning xhigh run "$(cat review-brief.md)"`. Fast, broad, catches obvious things, cheap.
2. **Final pass — Opus 4.7** via `jcode -C <worktree> --provider claude --model claude-opus-4-7 run "$(cat review-brief.md)"`. Deeper reasoning, catches subtle architectural drift. Only if first pass returned APPROVE; if first returned REQUEST_CHANGES, fix first then re-run from scratch.
3. **Conflict resolution:** if GPT-5.5 says APPROVE but Opus says REQUEST_CHANGES, trust Opus. If Opus says APPROVE but GPT-5.5 found a violation in §1 hard pillar, trust GPT-5.5 — hard pillars are objective, not judgment.

## Invocation
This skill is dispatched automatically by the CC-plans-JCode-executes workflow's Phase 4 review block. Do NOT invoke during planning. Do NOT invoke during execution. Only after a worker completes and the CC verification gate has passed.

## Lineage
Aligned with: `~/Timed-Brain/06 - Context/Workflow — CC plans JCode executes worktree-isolated.md` (Phase 4 review block). Uses sibling skills: `swiftui-pro`, `swift-concurrency`, `swift-testing-pro`, `tca-patterns`, `supabase-postgres-best-practices`. Per saved planning principle: NO DEFERRALS.
