---
name: session-handoff
description: >
  Session start/close handoff protocol. On start: loads vault context + HANDOFF.md.
  On close (/wrap-up): writes HANDOFF.md to vault root with structured state.
  Trigger: automatic on session start, or manual via /session-handoff
---

# Session Handoff Protocol

## On Session Start (Read Protocol)

Execute this read sequence before any work begins. This is not optional.

### Step 1: Identify the active vault

| Project | Vault Root |
|---------|-----------|
| time-manager-desktop | `~/Timed-Brain/` |
| PFF-DD-V3 | `~/Documents/PFF-Brain/` |
| facilitated / sw2 | No vault — skip to Step 4 |

### Step 2: Read vault state (in order)

1. `{vault_root}/VAULT-INDEX.md` — understand vault structure
2. `{vault_root}/HANDOFF.md` — understand where last session left off
3. `{vault_root}/Working-Context/timed-brain-state.md` — understand current state

**Note:** For non-Timed projects, substitute the correct state file name (e.g. `pff-brain-state.md` for PFF).

If HANDOFF.md does not exist, note this and proceed — the project has no prior handoff.

### Step 3: Read project state

1. `{project_root}/CLAUDE.md`
2. `{project_root}/BUILD_STATE.md` (if exists)
3. `{project_root}/MASTER-PLAN.md` (if exists) — read STATUS section only (first ~150 lines)

### Step 4: Announce readiness

Print a one-line summary:
```
Session loaded. Last handoff: [date]. Next action: [from HANDOFF.md "Next" field]
```

---

## On Session Close (Write Protocol)

Execute before ending the session. Called automatically by `/wrap-up` Phase 4.

### Step 1: Write HANDOFF.md

Write to `{vault_root}/HANDOFF.md` (overwrite, not append):

```markdown
# HANDOFF.md — [Project Name]

Last updated: [YYYY-MM-DD HH:MM]

## Done
- [Bullet list: what was completed THIS session — concrete deliverables, not activities]

## Open Decisions
- [Framed as QUESTIONS, not tasks — questions create a gate, tasks create bias toward action]
- [Only include genuine open decisions, not deferred work]

## Deferred
- [What was explicitly parked, and why]

## Next
- [Single most important next action — one line only]
```

<important>
Frame "Open Decisions" as QUESTIONS, not statements. AI agents bias toward action — questions create deliberation gates.

Bad: "Need to decide on embedding provider"
Good: "Should Tier 0 embeddings use voyage-context-3 or text-embedding-3-small given the volume/quality tradeoff?"
</important>

### Step 2: Update Working-Context state file

Update `{vault_root}/Working-Context/timed-brain-state.md` with (substitute correct filename for non-Timed projects):
- Current build phase and step
- Any state changes from this session
- Files created or significantly modified

### Step 3: Update MASTER-PLAN.md STATUS (if applicable)

If any plan deliverables were completed this session:
- Mark them `[x]` in the STATUS section
- Update "Last updated" date
- Update total counts at bottom

### Step 4: Extract architectural decisions

If any architectural decisions were made this session:
- Write to `{vault_root}/06 - Context/` as permanent notes
- Use typed links: `implements::`, `supersedes::`, `caused-by::`
