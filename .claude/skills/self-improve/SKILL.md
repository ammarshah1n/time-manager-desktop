---
name: self-improve
description: >
  Extract lessons from the current session and route them to the correct
  knowledge layer. Scans for corrections, repeated guidance, failure modes,
  and skill-shaped knowledge. Routes to: existing skills, CLAUDE.md,
  Obsidian vault (00-Rules, 04-Errors), .learnings/ files, or new skills.
  Trigger: "self-improve", "learn from this", "update skills", "remember
  this pattern", "what did we learn", "extract lessons", "save learnings"
---

# Self-Improve

Review the current conversation to extract durable lessons and route each
one to the right knowledge layer.

## Step 1: Detect Available Destinations

Read these files to understand what already exists:

| Destination | Location | Purpose |
|-------------|----------|---------|
| Project CLAUDE.md | `./CLAUDE.md` | Architecture rules, File Oracle, conventions |
| Skills | `.claude/skills/*/SKILL.md` | Domain-specific instruction sets |
| Obsidian Rules | `~/Timed Vault/00 - Rules/` via MCP | Permanent mistake-prevention rules |
| Obsidian Errors | `~/Timed Vault/04 - Errors/` via MCP | Structured error registry |
| Obsidian Context | `~/Timed Vault/06 - Context/` via MCP | Project knowledge base |
| .learnings/ | `.learnings/LEARNINGS.md`, `ERRORS.md`, `FEATURE_REQUESTS.md` | Structured log with IDs |
| PLAN.md | `./PLAN.md` | Current sprint state |

Read CLAUDE.md and list all skill directories. Do NOT read skill files yet — Step 2 determines what to look for.

## Step 2: Scan for Lessons

Scan the full conversation in this priority order:

### Priority 1: Corrections (Highest Value)
- User interrupted, said "no", "actually", "stop", "not like that"
- User manually fixed something Claude did wrong
- User redirected approach mid-task

### Priority 2: Repeated Guidance
- Same instruction given 2+ times in the session
- Same feedback pattern across multiple files

### Priority 3: Skill-Shaped Knowledge
- Domain expertise needed repeatedly
- Tool/API integration details that had to be looked up
- Decision frameworks that emerged
- Multi-step workflows where ordering mattered

### Priority 4: New Workflows
- Novel multi-step procedures that worked and would need repeating
- Coordination patterns or automations worth capturing as skills

### Priority 5: Preferences
- Formatting, naming, style, or tool choices user expressed

### Priority 6: Failure Modes
- Approaches that failed, with what worked instead
- For tool/script failures: trace back to the source of bad info

### Priority 7: Domain Knowledge
- Facts or conventions Claude needed but didn't have

### Priority 8: Improvement Opportunities
- Out-of-scope improvements noticed during work
- Code that could be refactored, missing tests, performance issues
- Feature ideas intentionally skipped to stay focused

After scanning, NOW read all skill SKILL.md files for routing context.

## Step 3: Quality Filter

### Gate 1: Signal Quality (from autoskill)
For each candidate lesson, ask ALL FOUR:
1. Was this correction repeated, or stated as a general rule?
2. Would this apply to future sessions, or just this task?
3. Is it specific enough to be actionable?
4. Is this NEW information I wouldn't already know?

Only proceed with lessons that pass all four.

### Gate 2: What Counts as "New Information"

**Worth capturing:**
- Project-specific conventions ("we use TCA Reducers, not ObservableObject")
- Custom file locations ("all Graph API calls go through GraphClient.swift")
- Team preferences that differ from defaults
- Non-obvious architectural decisions
- API quirks specific to this stack (Graph, Supabase, MSAL)

**NOT worth capturing (already known):**
- General best practices (DRY, separation of concerns)
- Language/framework conventions (Swift naming, SwiftUI basics)
- Common library usage (standard Supabase patterns)
- Universal security practices
- Standard accessibility guidelines

**Rule: If I'd give the same advice to any project, it doesn't belong.**

### Gate 3: Not Already Documented
Check if the lesson already exists in:
- CLAUDE.md rules
- Any SKILL.md file
- `.learnings/LEARNINGS.md` (grep for keywords)
- Obsidian `00 - Rules/` via MCP

If already documented, discard.

### Gate 4: Still a Concern
- If a bug was found AND fixed this session, future sessions see the fix — no reminder needed
- EXCEPTION: successful workflows ARE skill candidates even though they "worked"

Discard anything session-specific, speculative, one-off, or already resolved.
If no lessons survive, tell the user and stop.

## Step 4: Route Each Lesson

### Mandatory Skill-First Rule
Before consulting the routing table: does this lesson correct, refine, or add a guardrail to ANY existing skill? If yes, route to that skill. Period. Do not route skill corrections to .learnings/ or CLAUDE.md.

### Routing Table

| Destination | Route Here When |
|-------------|-----------------|
| **Existing skill** | Lesson improves a skill's instructions, adds missing edge case, corrects workflow, or refines trigger conditions |
| **New skill** | Cohesive body of knowledge emerged that's too large for CLAUDE.md and should only load when relevant |
| **CLAUDE.md** | Intentional project decisions: conventions, architecture, stack choices, module boundaries |
| **Obsidian `00 - Rules/`** | Mistake-prevention rules that should persist across all sessions. Format: `RULE: [always/never do X] — learned [date] from [what happened]` |
| **Obsidian `04 - Errors/`** | Structured error log with pskoett format (see below) |
| **`.learnings/LEARNINGS.md`** | Discovered knowledge with no skill home: API quirks, debugging workarounds, tool pitfalls |
| **`.learnings/ERRORS.md`** | Command failures, exceptions, unexpected behaviour |
| **`.learnings/FEATURE_REQUESTS.md`** | Capabilities user wanted that don't exist yet |
| **No destination** | Doesn't clearly fit anywhere. Drop it. Routing a weak lesson is worse than losing it. |

### Tiebreakers (in priority order)
1. Skill correction → skill (HARD RULE, no exceptions)
2. Skill vs CLAUDE.md → always the skill (better scoped, loaded only when relevant)
3. Skill vs .learnings/ → always the skill
4. CLAUDE.md vs .learnings/ → intentional decisions go to CLAUDE.md, discovered knowledge goes to .learnings/
5. Lesson vs improvement → knowledge to remember = lesson; work to do later = improvement (can produce both)

### Obsidian Error Format (pskoett structure)

```markdown
## [ERR-YYYYMMDD-XXX] error_name
**Logged**: ISO-8601 timestamp
**Priority**: low | medium | high | critical
**Status**: pending | resolved | promoted
**Area**: frontend | backend | infra | tests | docs | config

### Summary
One-line description

### Error
Actual error message or output

### Context
- Command/operation attempted
- Input or parameters
- Environment details

### Fix Applied
What resolved it (if resolved)

### Metadata
- Reproducible: yes | no | unknown
- Related Files: path/to/file
- Pattern-Key: [stable key for dedup, e.g., graph.token.refresh_failed]
- Recurrence-Count: [N]
- First-Seen: [date]
- Last-Seen: [date]
- See Also: [related entry IDs]
```

### Learning Entry Format

```markdown
## [LRN-YYYYMMDD-XXX] category
**Logged**: ISO-8601 timestamp
**Priority**: low | medium | high | critical
**Status**: pending | resolved | promoted
**Area**: frontend | backend | infra | tests | docs | config

### Summary
One-line description

### Details
Full context: what happened, what was wrong, what's correct

### Suggested Action
Specific fix or improvement

### Metadata
- Source: conversation | error | user_feedback | simplify-and-harden
- Related Files: path/to/file
- Tags: tag1
- Pattern-Key: [stable dedup key]
- Recurrence-Count: [N]
- First-Seen: [date]
- Last-Seen: [date]
- See Also: [related entry IDs]
```

### Recurrence Detection

Before creating any new entry:

1. Search `.learnings/` for existing entries with similar keywords: `grep -r "keyword" .learnings/`
2. If a matching Pattern-Key exists:
   - Increment Recurrence-Count
   - Update Last-Seen
   - Add See Also link
   - If Recurrence-Count >= 3: AUTO-PROMOTE (see below)
3. If no match: create new entry with Recurrence-Count: 1

### Auto-Promotion Rule

When ALL of these are true, promote automatically:
- Recurrence-Count >= 3
- Seen across at least 2 distinct sessions or tasks
- Occurred within a 30-day window

Promotion means:
1. Distill into a concise, imperative rule
2. Write to Obsidian `00 - Rules/` via MCP
3. Also append to CLAUDE.md under the relevant section
4. Update original entry: `Status: promoted`, add `Promoted-To: [destination]`

Write promoted rules as short prevention rules (what to do), not incident write-ups.

Example:
- **Learning (verbose)**: "Graph delta token expired after 7 days of inactivity causing 401 errors. Had to re-auth and request fresh token. Third time this happened."
- **Rule (concise)**: `RULE: Graph delta tokens expire after 7 days idle. graphClient.ts must check token age and re-request if >6 days. — learned 2026-04-02 from ERR-20260402-001`

## Step 5: Present Routing Plan

Output a table BEFORE making any changes:

```
SELF-IMPROVE: Routing Plan
═══════════════════════════════════════════

| # | Lesson | Confidence | Destination | Action |
|---|--------|------------|-------------|--------|
| 1 | Always use delta queries... | HIGH | CLAUDE.md | Append to ## Architecture Rules |
| 2 | TCA Reducer must handle... | HIGH | .claude/skills/tca-patterns | Update Step 3 |
| 3 | Graph 401 on stale token | HIGH | .learnings/ERRORS.md | New entry ERR-YYYYMMDD-XXX |
| 4 | User prefers short commits | MEDIUM | .learnings/LEARNINGS.md | New entry LRN-YYYYMMDD-XXX |
| 5 | Refactor estimator.ts | — | Improvement | Note for backlog |

HIGH confidence: Apply? [y/n/selective]
MEDIUM confidence: Review individually? [y/n]
```

Present HIGH confidence changes first. Wait for explicit approval.

## Step 6: Execute

Apply approved changes in order:

### 1. Existing file updates
- Read the target file
- Find the right section
- Append or update in place
- Match the existing tone and format

### 2. Skill updates
- Read the skill's SKILL.md
- Apply minimal, focused change
- If git available: `git add .claude/skills/[name]/SKILL.md && git commit -m "chore(self-improve): update [skill] — [brief reason]"`

### 3. Obsidian writes (via MCP)
- For rules: write to `00 - Rules/[area]-rules.md`
  - If file exists, append under the relevant heading
  - If file doesn't exist, create with heading and first rule
  - Format: `- RULE: [imperative statement] — learned [date] from [source]`
- For errors: write to `04 - Errors/[YYYY-MM-DD]-[error-name].md`
  - Use full pskoett format from Step 4
- For context: write to `06 - Context/[topic].md`
  - Append discovered knowledge under relevant heading

### 4. .learnings/ entries
- Append to the appropriate file using the structured format
- Generate ID: `[TYPE]-[YYYYMMDD]-[XXX]`
  - TYPE: LRN (learning), ERR (error), FEAT (feature request)
  - XXX: sequential number (check last entry, increment)

### 5. New skills
- Create `.claude/skills/[name]/SKILL.md`
- Include: frontmatter (name, description, trigger), instructions, examples
- Add to CLAUDE.md skill activation table
- Commit: `feat(skills): create [name] skill — [reason]`

### 6. Improvements (backlog items)
Append to `.learnings/IMPROVEMENTS.md`:

```markdown
## [IMP-YYYYMMDD-XXX] description
**Logged**: ISO-8601
**Priority**: low | medium | high
**Area**: frontend | backend | infra
**Location**: path/to/file:line

### What Could Improve
[Description of the improvement]

### Why
[Impact: performance, readability, reliability, DX]

### Suggested Approach
[How to fix it]
```

## Step 7: Verify & Report

After all changes are applied:

- Run `grep -c "RULE:" ~/Timed\ Vault/00\ -\ Rules/*.md` to count total rules
- Run `grep -c "Status.*pending" .learnings/*.md` to count pending learnings
- Run `grep "Recurrence-Count: [3-9]" .learnings/*.md` to flag anything ready for promotion

Print summary:

```
SELF-IMPROVE COMPLETE
═══════════════════════════════════════════
Scanned:      [N] signals detected
Filtered:     [N] passed quality gates
Routed:       [N] lessons applied

  Skills updated:    [N] ([list names])
  CLAUDE.md:         [N] rules added
  Obsidian Rules:    [N] written to 00-Rules/
  Obsidian Errors:   [N] written to 04-Errors/
  .learnings/:       [N] new entries
  Improvements:      [N] logged to backlog
  New skills:        [N] created

Auto-promoted:  [N] (recurrence >= 3)
Total rules:    [N] across all 00-Rules/ files
Pending:        [N] unresolved learnings
Near promotion: [N] entries at recurrence 2 (one more = auto-promote)
═══════════════════════════════════════════
```

## Constraints

- NEVER delete existing rules or skill content without explicit user instruction
- Prefer additive changes over rewrites
- One concept per change (easy to revert individually)
- Preserve existing file structure and tone
- When uncertain between HIGH and MEDIUM confidence, downgrade to MEDIUM
- If a skill has been corrected 3+ times by self-improve, flag for human review:
  `"⚠️ Skill [name] has been corrected [N] times. Consider rewriting it."`
- Maximum 500 tokens per individual rule or learning entry — keep them concise
- Never include temporary state, in-progress work, or task-specific details in rules
- Keep rules generic — state the rule, not the instance that caused it
