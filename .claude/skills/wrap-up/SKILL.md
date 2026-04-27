---
name: wrap-up
description: >
  Timed-specific wrap-up. Inherits the 11-phase fire-and-forget pipeline from
  the global wrap-up at ~/.claude/skills/wrap-up/SKILL.md, then adds two Timed-
  specific phases (Obsidian walkthrough + Obsidian error log) and pre-fills the
  basic-memory project (`timed-brain`) and TickTick project (`Timed`) defaults.
  Trigger: "wrap up", "end session", "session done", "that's it", "/wrap-up"
---

# Session Wrap-Up — Timed (extends global v2)

This skill **runs the global v2 wrap-up at `~/.claude/skills/wrap-up/SKILL.md`** for Phases 0–10 and inserts two Timed-specific phases between Phase 7 (TickTick) and Phase 8 (NEXT.md).

Read the global skill first. The instructions below describe ONLY the Timed-specific overrides and additions.

## Defaults (pre-filled for Timed)

When the global skill asks "which basic-memory project?" / "which TickTick project?" / "which vault?", use:

| Surface | Default for Timed |
|---------|-------------------|
| Repo root | `~/time-manager-desktop/` |
| Active branch trunk | `unified` (per `CLAUDE.md` mandatory rule #1) |
| basic-memory project | `timed-brain` |
| Vault root | `~/Timed-Brain/` |
| Vault state file | `~/Timed-Brain/Working-Context/timed-brain-state.md` |
| Repo state files | `~/time-manager-desktop/{HANDOFF.md, BUILD_STATE.md, SESSION_LOG.md}` |
| Vault HANDOFF.md | `~/Timed-Brain/HANDOFF.md` (kept as a pointer to the repo HANDOFF — match its existing shape) |
| TickTick project | `Timed` |
| AIF folder | `~/aif-vault/AIF/03 Timed/` |
| claude-mem corpora to refresh on canonical-doc edits | `yasser-profile-brain`, `intelligence-core-brain` |

## Timed-specific extensions

### Phase 7.5 — Obsidian walkthrough (AFTER Phase 7 TickTick, BEFORE Phase 8 NEXT.md)

**Trigger:** Only if this session built or substantially modified a feature (FR-XX).
Skip if the session was pure docs, infra, or memory-system work — those are captured by Phase 4 basic-memory writes.

**Write to:** `~/Timed-Brain/01 - Walkthroughs/YYYY-MM-DD-<feature-slug>.md`

**Template:**

```markdown
---
type: walkthrough
date: <YYYY-MM-DD>
feature: <FR-XX or feature name>
session-state: <SHIPPED | PARKED | INTERRUPTED>
duration-minutes: <int>
summary: One sentence, retrieval-tuned, ending in a period.
tags: [walkthrough, FR-XX, <area>]
---

## What was built
<1–3 sentences>

## How data flows
<the data flow through the new code — diagram in prose if useful>

## Files created / modified
| File | Change | Why |
|------|--------|-----|
| `Sources/.../Foo.swift` | Created | … |

## Decisions made (with the why)
- <decision>: <why>

## Rules extracted
- <new rule added to 00-Rules/ or .claude/rules/ this session>

## Notes for next session
- <what next session needs to know — short>

## Related
- basic-memory: `<permalink>` (the canonical doc this walks through)
- AIF: `<D-XXX>` (if logged)
```

After writing, also call `mcp__basic-memory__write_note` with the walkthrough content so it's retrievable from `timed-brain` (Phase 4 of the global skill should have already covered the canonical-doc write; this is the walkthrough-specific write).

### Phase 7.6 — Obsidian error log (AFTER Phase 7.5)

**Trigger:** Only if errors occurred during the session that took >2 attempts to resolve OR remain unresolved.

**Write to:** `~/Timed-Brain/04 - Errors/YYYY-MM-DD-<error-slug>.md`

**Template:**

```markdown
---
type: error-log
id: ERR-YYYYMMDD-XXX
logged: <ISO-8601>
priority: <low | medium | high | critical>
status: <pending | resolved>
area: <frontend | backend | infra | tests | docs | config>
summary: One sentence, retrieval-tuned, ending in a period.
tags: [error, <area>]
---

## Error
<actual output / message>

## Context
- Command: `<exact command>`
- Input: <…>
- Environment: <…>

## What was tried (and didn't work)
- <attempt 1>
- <attempt 2>

## Fix applied
<what resolved it — concrete, citable>

## Rule created (if any)
<link to the rule in `.claude/rules/` or `00 - Rules/never-do.md`-style location>

## Related
- basic-memory: `<permalink>`
- Commit: `<hash>` (if the fix was committed)
```

After writing, call `mcp__basic-memory__write_note` to make it retrievable.

## Phase 9 (Verify) Timed-specific overrides

The global Phase 9 spawns a subagent that tests the handoff. For Timed sessions, also include this question in the subagent prompt:

> Question C: Open `~/time-manager-desktop/HANDOFF.md` and confirm the trunk branch is `unified` (per `CLAUDE.md` mandatory rule #1) and that the three unblock chains (DMG to Yasser / Wave 2 nightly engine / Apple Developer enrollment) are listed with their current state. PASS if all three present and current; FAIL if any missing or stale.

The Timed wrap-up cannot pass verify if the unified-branch invariant or the three-chain structure is broken in the HANDOFF.

## Phase 10 (Stop signal) Timed-specific additions

Add these lines to the global stop-signal summary block:

```
Timed-specific:
  Walkthrough:    <path or "skipped: no feature work">
  Error logs:     <N> entries written to 04-Errors/
  AIF entries:    <N> D-XXX rows added to ~/aif-vault/AIF/07 Decision Log/
  Corpora:        yasser-profile-brain | intelligence-core-brain — <rebuilt | unchanged>
```

## Read order for the global skill

When this Timed wrap-up fires, the agent should:
1. Read this file (Timed-specific defaults + extensions).
2. Read `~/.claude/skills/wrap-up/SKILL.md` (global v2 — Phases 0–10).
3. Execute Phases 0–7 from global, using Timed defaults from this file.
4. Execute Phases 7.5 and 7.6 from this file.
5. Execute Phases 8–10 from global, using Timed defaults from this file.
6. Apply the Timed-specific Phase 9 override (Question C) and Phase 10 additions.

## Anti-patterns

- Do NOT branch off `ui/apple-v1-restore`, `ui/apple-v1-local-monochrome`, `ui/apple-v1-wired`, or `ios/port-bootstrap` — those are superseded backups (per `CLAUDE.md` mandatory rule #1). The wrap-up commit must be on `unified`.
- Do NOT push to `main`. Push to `unified` is fine on this project.
- Do NOT write Edge Function deployment instructions in NEXT.md — those go in `HANDOFF.md` Chain B.
- Do NOT overwrite `Working-Context/timed-brain-state.md` blindly — it has a "carried forward" landmines list. Append/update sections, don't replace the file.
