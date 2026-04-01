---
name: wrap-up
description: >
  End-of-session lifecycle skill. Commits code, audits file placement,
  extracts lessons, updates PLAN.md, writes Obsidian walkthrough.
  Trigger: "wrap up", "end session", "session done", "that's it", "/wrap-up"
---

# Session Wrap-Up

Run all 4 phases sequentially. No approval prompts between phases.
All phases execute automatically, culminating in a summary report.

## Phase 1: Ship

### Commit
1. Run `git status` in each repo modified during session
2. If uncommitted changes exist, commit with: `feat(FR-XX): [what was built]` or `fix: [what was fixed]`
3. Push if on a feature branch (never push directly to main)

### File Placement Audit
4. Check every file created or modified this session:
   - Does it follow the File Oracle paths in CLAUDE.md?
   - Is it in the correct feature directory under `Sources/`?
   - Are types in `Sources/TimedCore/Types/`?
   - Are migrations in `supabase/migrations/`?
5. Auto-relocate any misplaced files. Rename if naming conventions are wrong.
6. Move any `.md` files created at workspace root to `docs/` (unless they are CLAUDE.md, PLAN.md, AGENTS.md, README.md, or Package.swift)

### Task Cleanup
7. Run `taskflow status` if taskflow is available
8. Mark completed tasks as done: `taskflow complete [id]`
9. Flag any orphaned or stale tasks

## Phase 2: Remember

Reflect on what was learned. Route each piece of knowledge to the correct layer.

### Memory Placement Decision Tree
For each piece of knowledge, ask in order:

1. Does it correct or refine an existing skill? → Update that SKILL.md
2. Is it a permanent project rule or convention? → CLAUDE.md
3. Is it a rule scoped to certain file types? → `.claude/rules/[area].md`
4. Is it a pattern or quirk Claude discovered? → `.learnings/LEARNINGS.md`
5. Is it personal/temporary/local? → CLAUDE.local.md
6. Would it duplicate content from another file? → Use @import reference instead

### What to Look For
- New API behaviour discovered (e.g., "Graph delta tokens expire after 7 days")
- A workaround for a bug or limitation
- A pattern that worked well and should be reused
- A configuration that took multiple attempts
- Project-specific conventions not yet documented

Document each piece of knowledge in the appropriate location.

## Phase 3: Review & Apply (Self-Improvement Engine)

Examine the conversation for actionable improvement insights.
If the session was brief or routine, state "Nothing to improve" and move to Phase 4.

### Scan for Signals (Priority Order)
1. **Corrections** — User said "no", "actually", "stop", "not like that", or manually fixed something
2. **Repeated guidance** — Same instruction given 2+ times
3. **Skill gaps** — Claude struggled, made mistakes, needed multiple attempts
4. **Friction** — Repetitive manual tasks user had to request explicitly
5. **Failure modes** — Approaches that failed, with what worked instead

### Quality Gate (ALL must pass before creating a rule)
From autoskill's 4-gate filter:
1. Was this correction repeated, or stated as a general rule?
2. Would this apply to future sessions, or just this task?
3. Is it specific enough to be actionable?
4. Is this NEW information Claude wouldn't already know?

If I'd give the same advice to any project, it doesn't belong in a rule.

### Action Types
For each signal that passes the quality gate:

| Signal Type | Route To |
|-------------|----------|
| Skill correction | Update the relevant SKILL.md |
| Project convention | Append to CLAUDE.md |
| Scoped rule | Create/update `.claude/rules/[area].md` |
| API quirk or workaround | `.learnings/LEARNINGS.md` |
| New automation opportunity | Note for future skill creation |

### Apply Changes
Automatically implement all actionable insights. Commit them. Summarise what changed.

Format applied changes:
```
Findings (applied):

✅ Skill gap: [description]
   → [CLAUDE.md] Added [what]
✅ Friction: [description]
   → [Rules] Created [what]

No action needed:

ℹ️ Knowledge: [description]
   → Already documented in [where]
```

## Phase 4: Update State Files

### Update PLAN.md
1. Mark completed tasks as `[x]`
2. Update "What's In Progress" with current state
3. Update "Files Touched This Session" with every file created/modified
4. Update "Decisions Made This Session" with any architectural choices
5. Write "Notes for Next Session" — what the next Claude session needs to know immediately

### Write Obsidian Walkthrough
Write a walkthrough note to the Obsidian vault via MCP:

**Path**: `01 - Walkthroughs/[YYYY-MM-DD]-[feature-name].md`

**Template**:
```markdown
---
date: [ISO-8601]
feature: [FR-XX name]
duration: [estimated session time]
tags: [walkthrough, FR-XX]
---

## What Was Built
[1-3 sentences]

## How Data Flows
[Describe the data flow through the new code]

## Files Created/Modified
| File | Change |
|------|--------|
| path/to/file | Created — [purpose] |

## Decisions Made
- [Decision]: [Why]

## Rules Extracted
- [Any new rules added to 00-Rules/ this session]

## Notes for Next Session
- [What the next session needs to know]
```

### Write Obsidian Error Logs (if any errors occurred)
For each error encountered during the session, write to:

**Path**: `04 - Errors/[YYYY-MM-DD]-[error-name].md`

Using pskoett format:
```markdown
## [ERR-YYYYMMDD-XXX] error_name
**Logged**: [ISO-8601]
**Priority**: [low|medium|high|critical]
**Status**: [pending|resolved]
**Area**: [frontend|backend|infra|tests|docs|config]

### Summary
[One line]

### Error
[Actual error output]

### Context
- Command attempted
- Input/parameters
- Environment details

### Fix Applied
[What resolved it]

### Rule Created
[If this error generated a new rule, link to it]
```

## Output Summary

At the end, print:
```
SESSION WRAP-UP
═══════════════════════════════════════════
Committed:   [hash] — [message]
Files moved: [N] files relocated to correct paths
Learned:     [N] new things saved
Rules:       [N] new rules added
             - [list each rule]
Errors:      [N] logged to Obsidian 04-Errors/
PLAN.md:     Updated ✓
Walkthrough: Written to 01-Walkthroughs/[filename]
Taskflow:    [N] tasks completed, [N] remaining
Next task:   [taskflow next output or "run taskflow next"]
═══════════════════════════════════════════
```
