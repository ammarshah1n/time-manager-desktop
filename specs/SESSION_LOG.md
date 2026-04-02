# SESSION_LOG.md Template and Obsidian Knowledge Base Structure

> Timed v1 Intelligence Layer | Last updated: 2026-04-02

---

## Part 1: SESSION_LOG.md Template

This file lives at the repository root. It is the single chronological record of development activity. Claude Code reads the last entry at the start of every session and appends a new entry at the end.

### Template

```markdown
# Timed — Session Log

---

## Session [N] — [YYYY-MM-DD]

**Goal:** [One sentence: what was planned for this session]

**Phase:** [Phase 1/2/3/4/5/6] | **Layer focus:** [Layer 1/2/3/4/Cross-cutting]

**Skills active:** [plan-feature / checkpoint / debug-swift / memory-layer / reflect / none]

### What Was Built

- [Concrete deliverable 1 — e.g., "EpisodicMemoryRepository actor with CRUD operations"]
- [Concrete deliverable 2]
- [Concrete deliverable 3]

### Files Created

| File | Layer | Purpose |
|------|-------|---------|
| `Sources/Timed/Layer2/Repositories/EpisodicMemoryRepository.swift` | L2 | Episodic memory CRUD |
| `Tests/TimedTests/Layer2/EpisodicMemoryRepositoryTests.swift` | L2 | Unit tests for above |

### Files Modified

| File | What Changed |
|------|-------------|
| `Sources/Timed/Protocols/MemoryStoring.swift` | Added `saveEpisodic()` method |
| `Sources/Timed/Models/Timed.xcdatamodeld` | Added EpisodicMemory entity |

### Commits

| Hash | Message |
|------|---------|
| `abc1234` | feat(layer2): add episodic memory entity to CoreData model |
| `def5678` | feat(layer2): implement EpisodicMemoryRepository with CRUD |
| `ghi9012` | test(layer2): add episodic memory repository tests |

### Tests

- **Added:** 8 new tests in `EpisodicMemoryRepositoryTests`
- **Total passing:** 57/57
- **Coverage delta:** +3% on Layer 2

### Decisions Made

- [Decision 1 — e.g., "Used background context for all writes, main context read-only"]
- [Decision 2 — e.g., "Chose to store embeddings as Data blob on entity rather than separate table"]

### Blockers Encountered

- [Blocker 1 — e.g., "CoreData binary attribute has 16MB limit — need to verify 1024-dim Float array fits (it does: 4KB)"]
- [Blocker 2 — or "None"]

### What Was Learned

- [Technical insight — e.g., "CoreData background context merge notifications must be observed on the main context, not the background one"]
- [Pattern — e.g., "Actor-based repositories simplify threading but require all methods to be async"]

### Next Session Priorities

1. [Priority 1 — e.g., "Build SemanticMemoryRepository"]
2. [Priority 2 — e.g., "Add confidence decay to semantic memory"]
3. [Priority 3 — e.g., "Start on retrieval engine scoring"]

### Open Questions

- [Question 1 — e.g., "Should semantic memory decay be linear or exponential? Spec says -0.01/week but exponential might be more natural."]
- [Question 2 — or "None"]

### Compounding Note

> [One insight that will make future sessions better. This is the development equivalent of what the reflection engine does for the executive.]
> 
> Example: "Writing the CoreData entity first, then the repository actor, then the tests is the fastest sequence. Starting with tests (TDD) for CoreData code is slower because the entity shape changes as you discover constraints."

---
```

### Auto-Population Guide

Claude Code can auto-populate most fields from git and test output:

| Field | Auto-populated from |
|-------|-------------------|
| Session number | Increment from last entry |
| Date | System date |
| Commits | `git log --oneline --since="[session start time]"` |
| Files created | `git diff --name-only --diff-filter=A [start hash]..HEAD` |
| Files modified | `git diff --name-only --diff-filter=M [start hash]..HEAD` |
| Tests passing | `swift test 2>&1 \| tail -5` |
| Build status | `swift build 2>&1 \| tail -3` |

Fields that require human input: Goal, Decisions Made, What Was Learned, Open Questions, Compounding Note. These are the valuable parts -- don't skip them.

### Time Budget

Filling out the session log should take **under 5 minutes**. Claude Code auto-fills the mechanical parts (commits, files, test counts). The developer provides the 5 insight fields (Goal, Decisions, Learnings, Questions, Compounding Note) -- these can be single sentences.

If the log takes more than 5 minutes, the template is too heavy. Trim it.

---

## Part 2: Obsidian Knowledge Base Structure

The Obsidian vault is where knowledge extracted from session logs becomes permanent, searchable, and linked. Located at `~/timed-knowledge/` (or wherever the developer keeps Obsidian vaults).

### Vault Structure

```
timed-knowledge/
├── sessions/              # Session logs (copied or linked from repo)
│   ├── session-001.md
│   ├── session-002.md
│   └── ...
├── specs/                 # Spec documents (reference copies)
│   ├── data-models.md
│   ├── architecture.md
│   ├── episodic-memory.md
│   └── ...
├── decisions/             # Architecture Decision Records
│   ├── adr-001-coredata-vs-swiftdata.md
│   ├── adr-002-on-device-voice.md
│   └── ...
├── research/              # Research findings and references
│   ├── stanford-generative-agents.md
│   ├── memgpt-architecture.md
│   ├── circadian-performance.md
│   └── ...
├── patterns/              # Development process patterns
│   ├── coredata-background-context.md
│   ├── actor-repository-pattern.md
│   ├── prompt-engineering-iteration.md
│   └── ...
├── bugs/                  # Bug postmortems
│   ├── bug-001-coredata-merge-conflict.md
│   └── ...
├── prompts/               # Prompt engineering notes
│   ├── reflection-stage3-v1.md
│   ├── reflection-stage3-v2.md
│   ├── email-classification-v1.md
│   └── ...
└── retrospectives/        # Phase and weekly retrospectives
    ├── retro-phase-1.md
    ├── retro-week-01.md
    └── ...
```

### Folder Details

#### sessions/
- **What goes here:** One file per session, copied from or linking to `SESSION_LOG.md` entries.
- **Naming:** `session-NNN.md` (zero-padded to 3 digits).
- **Purpose:** Chronological record. Searchable by date, layer, phase.

#### specs/
- **What goes here:** Reference copies of spec documents from `~/timed-docs/docs/`. These are read-only in the vault -- the source of truth is the docs directory.
- **Naming:** Match the spec doc name.
- **Purpose:** Obsidian links from sessions/decisions/patterns to specific spec sections.

#### decisions/
- **What goes here:** Architecture Decision Records. Created when a significant design choice is made during a session.
- **Naming:** `adr-NNN-short-description.md`
- **Template:**

```markdown
---
tags: [decision, layer2, active]
date: YYYY-MM-DD
status: accepted
session: session-NNN
---

# ADR-NNN: [Decision Title]

## Context
[Why this decision matters. What problem does it solve. What constraints apply.]

## Options Considered

### Option A: [Name]
- Pros: ...
- Cons: ...

### Option B: [Name]
- Pros: ...
- Cons: ...

### Option C: [Name]
- Pros: ...
- Cons: ...

## Decision
[Which option and why.]

## Consequences
- [What this enables]
- [What this costs]
- [What risks remain]

## Reversal Cost
[Low / Medium / High / Catastrophic]

## Related
- [[session-NNN]] — session where this was decided
- [[spec-doc-name]] — relevant spec
```

#### research/
- **What goes here:** Summaries of research findings, paper notes, competitive analysis. NOT raw Perplexity output -- distilled findings with implications for Timed.
- **Naming:** `topic-name.md`
- **Template:**

```markdown
---
tags: [research, memory, reflection]
date: YYYY-MM-DD
source: [paper/url/perplexity]
---

# [Research Topic]

## Key Findings
- [Finding 1 with citation]
- [Finding 2 with citation]

## Implications for Timed
- [How this affects our architecture]
- [How this affects our approach]

## Open Questions
- [What we still don't know]

## Related
- [[adr-NNN]] — decision influenced by this research
- [[spec-name]] — spec this research informs
```

#### patterns/
- **What goes here:** Recurring development patterns discovered during implementation. The development equivalent of the executive's procedural memory. Sourced from "Compounding Notes" in session logs.
- **Naming:** `pattern-name.md`
- **Template:**

```markdown
---
tags: [pattern, coredata, layer2]
date: YYYY-MM-DD
discovered_in: session-NNN
---

# [Pattern Name]

## When to Use
[The situation where this pattern applies]

## The Pattern
[Step-by-step description]

## Why It Works
[Explanation]

## Example
[Code snippet or reference to a file where this pattern is implemented]

## Anti-Pattern
[What NOT to do -- the thing this pattern replaces]

## Sessions Where This Applied
- [[session-NNN]]
- [[session-NNN]]
```

#### bugs/
- **What goes here:** Postmortems for non-trivial bugs. Not every bug -- only the ones where the root cause was surprising or the fix taught something.
- **Naming:** `bug-NNN-short-description.md`
- **Template:**

```markdown
---
tags: [bug, layer1, fixed]
date: YYYY-MM-DD
session: session-NNN
severity: [minor/major/critical]
time_to_fix: [Xm/Xh]
---

# Bug NNN: [Short Description]

## Symptom
[What was observed]

## Root Cause
[What was actually wrong]

## Fix
[What was changed, with file references]

## How to Prevent Recurrence
[Rule or convention that should be added]

## Related
- [[session-NNN]] — session where this was found and fixed
```

#### prompts/
- **What goes here:** Prompt engineering notes for every significant prompt template (reflection stages, email classification, morning director). Iteration history showing how prompts evolved.
- **Naming:** `purpose-vN.md`
- **Template:**

```markdown
---
tags: [prompt, opus, layer3, reflection]
date: YYYY-MM-DD
model: opus/sonnet/haiku
version: N
status: active/deprecated/testing
---

# [Prompt Purpose] — Version N

## Model
[Haiku 3.5 / Sonnet / Opus 4.6]

## System Prompt
```
[The system prompt text]
```

## User Prompt Template
```
[The user prompt with interpolation points marked as {variable}]
```

## Expected Output Schema
```json
{schema}
```

## Example Input -> Output
[One concrete example]

## Quality Assessment
- Tested on [N] synthetic scenarios
- Pattern detection rate: [X]%
- False positive rate: [X]%
- Average output tokens: [N]

## Iteration Notes
- v1: [what was tried, what happened]
- v2: [what changed, why, result]

## Related
- [[reflection-stage3-v(N-1)]] — previous version
- [[docs/reflection-engine-prompt-templates]] — spec reference
```

#### retrospectives/
- **What goes here:** Weekly and phase-level retrospectives. Weekly retros review the last 5-7 sessions. Phase retros review an entire build phase.
- **Naming:** `retro-week-NN.md` or `retro-phase-N.md`
- **Weekly retro template:**

```markdown
---
tags: [retrospective, weekly]
date: YYYY-MM-DD
sessions: [NNN-NNN]
phase: N
---

# Week [N] Retrospective

## Sessions Covered
[[session-NNN]] through [[session-NNN]]

## What Was Planned
- [Planned item 1]
- [Planned item 2]

## What Was Delivered
- [Delivered item 1]
- [Delivered item 2]

## Velocity
- Sessions this week: [N]
- Commits: [N]
- Tests added: [N]
- Components completed: [N]

## What Went Well
- [Thing 1]
- [Thing 2]

## What Went Poorly
- [Thing 1]
- [Thing 2]

## Patterns Emerging
- [Development process pattern observed]

## Adjustments for Next Week
- [Change 1]
- [Change 2]
```

---

## Part 3: Tag Taxonomy

Controlled vocabulary for cross-cutting search and Obsidian dataview queries.

### Layer Tags
- `#layer1` — Signal Ingestion
- `#layer2` — Memory Store
- `#layer3` — Reflection Engine
- `#layer4` — Intelligence Delivery
- `#cross-cutting` — Auth, infra, distribution

### Type Tags
- `#session` — Session log
- `#decision` — Architecture Decision Record
- `#research` — Research finding
- `#pattern` — Development process pattern
- `#bug` — Bug postmortem
- `#prompt` — Prompt engineering note
- `#retrospective` — Weekly or phase retro
- `#spec` — Specification document

### Status Tags
- `#active` — Currently relevant
- `#done` — Completed
- `#blocked` — Waiting on something
- `#superseded` — Replaced by a newer decision/approach
- `#deprecated` — No longer used
- `#testing` — Being evaluated

### Component Tags
- `#signal-bus` — Signal queue
- `#email-agent` — Email signal agent
- `#calendar-agent` — Calendar signal agent
- `#app-focus-agent` — App focus observer
- `#voice-agent` — Voice capture agent
- `#task-agent` — Task signal agent
- `#episodic-memory` — Episodic memory repository
- `#semantic-memory` — Semantic memory repository
- `#procedural-memory` — Procedural memory repository
- `#core-memory` — Core memory manager
- `#retrieval-engine` — Memory retrieval engine
- `#consolidation` — Memory consolidation
- `#reflection-engine` — Nightly reflection orchestrator
- `#pattern-extraction` — First/second order pattern work
- `#rule-generation` — Procedural rule generation
- `#morning-session` — Morning intelligence session
- `#menu-bar` — Menu bar widget
- `#alerts` — Proactive alert system
- `#focus-timer` — Focus timer
- `#query-interface` — Natural language query
- `#day-plan` — Day plan generation
- `#auth` — Microsoft OAuth / Supabase Auth
- `#coredata` — CoreData model and migrations
- `#embeddings` — Jina embedding pipeline
- `#privacy` — Privacy abstraction pipeline

### Quality Tags
- `#needs-review` — Awaiting review
- `#validated` — Reviewed and confirmed
- `#experimental` — Trying something, not committed

### Task Type Tags
- `#feature` — New capability
- `#bug` — Bug fix
- `#refactor` — Code restructuring
- `#test` — Test addition/modification
- `#docs` — Documentation
- `#infra` — Infrastructure/tooling

---

## Part 4: How Session Logs Feed the Knowledge Base

After every session, extract permanent knowledge from the session log into the vault:

### Extraction Rules

| Session Log Field | Extract To | When |
|-------------------|-----------|------|
| Decisions Made | `decisions/adr-NNN.md` | Every non-trivial design decision |
| Blockers Encountered (bugs) | `bugs/bug-NNN.md` | When the root cause was non-obvious |
| What Was Learned (technical) | `patterns/pattern-name.md` | When the insight is reusable across sessions |
| What Was Learned (research) | `research/topic.md` | When new external knowledge was gained |
| Compounding Note | Append to `patterns/development-patterns.md` | Every session (aggregated running list) |
| Prompt changes | `prompts/purpose-vN.md` | Every prompt template modification |

### Extraction Process

**Semi-automated.** At session end, Claude Code suggests extractions:

```
Session complete. Suggested knowledge extractions:

1. DECISION: "Store embeddings as Data blob on entity" -> Create decisions/adr-007-embedding-storage.md? [y/n]
2. PATTERN: "Background context for writes, main for reads" -> Create patterns/coredata-context-rule.md? [y/n]
3. BUG: "Merge conflict when both contexts write same entity" -> Create bugs/bug-003-merge-conflict.md? [y/n]

[Developer approves/rejects each]
```

Claude Code creates the approved notes with the correct template and tags. Developer can edit later in Obsidian.

### Development Reflection Cycle

Weekly (every 5-7 sessions): Claude Code generates a weekly retrospective by reading the last 5-7 session logs and producing `retrospectives/retro-week-NN.md`. This mirrors the product's nightly reflection:

1. Read all session logs for the week.
2. Extract: what was planned vs delivered, velocity trend, recurring blockers, emerging patterns.
3. Identify: which layers took longest, which bugs recurred, where velocity is increasing/decreasing.
4. Recommend: adjustments for next week (e.g., "Layer 2 memory tests are taking 40% of session time -- consider writing a test helper to reduce boilerplate").

---

## Part 5: How Claude Code Uses the Knowledge Base

### Session Start Context Loading

Claude Code reads (in order):
1. `CLAUDE.md` (always)
2. `SESSION_LOG.md` — last entry only (what happened last, what's next)
3. Relevant spec doc(s) for today's task
4. Any ADR tagged with the current layer (e.g., all `#layer2 #decision` notes if working on Layer 2)
5. Any active bug notes for the current layer

**Total context:** ~6,000-10,000 tokens. Fits comfortably in working memory.

### What NOT to Load at Session Start

- All session logs (too much, use search instead)
- All research notes (irrelevant unless working on a related feature)
- Retrospectives (useful for planning, not for coding)
- Deprecated/superseded notes

### Retrieval Strategy

When Claude Code needs knowledge mid-session:
1. **Specific question:** Search Obsidian vault by tag + keyword (e.g., "How did we handle CoreData merge conflicts?" -> search `#bug #coredata`).
2. **Architectural context:** Read the relevant ADR.
3. **Previous approach:** Search session logs for when a similar component was built.
4. **Research reference:** Search `research/` folder for the topic.

### CLAUDE.md Reference to Knowledge Base

Add to CLAUDE.md:

```markdown
## Knowledge Base
Obsidian vault at ~/timed-knowledge/. When you need context beyond the current session:
- Architecture decisions: decisions/ folder, tagged by layer
- Bug history: bugs/ folder, search by component tag
- Development patterns: patterns/ folder
- Prompt history: prompts/ folder, versioned
- Do NOT load the entire vault. Search by tag and keyword.
```

---

## Part 6: Useful Obsidian Dataview Queries

For developers using the Obsidian Dataview plugin, these queries surface useful cross-cutting information:

### All Active Decisions for a Layer

```dataview
TABLE status, date, session
FROM "decisions"
WHERE contains(tags, "layer2") AND status = "accepted"
SORT date DESC
```

### Recent Bugs by Severity

```dataview
TABLE severity, time_to_fix, session
FROM "bugs"
WHERE status != "deprecated"
SORT date DESC
LIMIT 10
```

### Velocity Trend (Sessions per Week)

```dataview
TABLE length(rows) AS "Sessions"
FROM "sessions"
GROUP BY dateformat(date, "yyyy-'W'WW") AS Week
SORT Week DESC
LIMIT 8
```

### Active Prompt Versions

```dataview
TABLE model, version, status
FROM "prompts"
WHERE status = "active"
SORT model, date DESC
```

### Development Patterns by Frequency

```dataview
TABLE length(sessions_applied) AS "Times Used"
FROM "patterns"
SORT length(sessions_applied) DESC
```
