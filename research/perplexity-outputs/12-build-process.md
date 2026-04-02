# Timed — The Impeccable Build Process
### How to doc, context-engineer, and orchestrate Claude so it builds this right

***

## Overview

This is the master guide for building Timed with Claude Max 20x + Cursor + Comet MCP + Perplexity. It covers the complete documentation architecture, how Claude remembers across sessions, when to open new terminals, which skills and MCPs to install, and the exact workflow discipline that separates a clean build from an entropy spiral. Read this before you write a single line of code.

The core principle: **Claude is not a tool you prompt — it is a collaborator you context-engineer.** The quality of what it builds is directly proportional to the quality of the information system you build around it. For a project this ambitious (multi-layer memory system, ML scoring, SwiftUI macOS app, Microsoft Graph integration, reflection engine), poor documentation hygiene will compound into catastrophic drift by week three.

***

## Part 1: The Documentation Architecture

### The Document Hierarchy

Every file in your documentation system serves a different purpose and is read at a different frequency. Get this structure right before you start.

```
timed/
├── CLAUDE.md                          ← always loaded, project brain
├── .claude/
│   ├── settings.json                  ← permissions, tool config
│   ├── skills/                        ← reusable skill definitions
│   │   ├── reflect/SKILL.md           ← memory layer reasoning
│   │   ├── plan-feature/SKILL.md      ← feature planning mode
│   │   └── checkpoint/SKILL.md        ← session handoff protocol
│   └── commands/                      ← slash command shortcuts
│       ├── new-session.md
│       ├── sync-docs.md
│       └── handoff.md
├── docs/
│   ├── 00-project-overview.md         ← product vision (from Research Pack 01)
│   ├── 01-architecture.md             ← system architecture, layer definitions
│   ├── 02-memory-system.md            ← three-layer memory spec
│   ├── 03-ml-models.md                ← Thompson sampling, time estimation
│   ├── 04-integrations.md             ← Microsoft Graph, Outlook Calendar
│   ├── 05-reflection-engine.md        ← reflection loop spec
│   ├── 06-morning-session.md          ← delivery layer design
│   ├── 07-data-models.md              ← all Swift data types and persistence
│   └── 08-decisions-log.md            ← architectural decisions and why
├── BUILD_STATE.md                     ← current build state (updated every session)
└── SESSION_LOG.md                     ← what was done, what broke, what's next
```

### CLAUDE.md — The Project Brain

This is the single most important file in the entire project. Claude reads it automatically at the start of every session. It must be concise, imperative, and living — updated after every significant session.[^1][^2][^3]

**What goes in CLAUDE.md:**

```markdown
# Timed — Project Memory

## What This Is
macOS application: cognitive intelligence layer for C-suite executives.
HARD CONSTRAINT: observation and intelligence only. Never sends emails,
modifies calendars, or takes action. Never negotiate this.

## Tech Stack
- Language: Swift 5.9+, SwiftUI, macOS 14+
- ML: CreateML, CoreML (Thompson sampling, time estimation EMA)
- Storage: CoreData (episodic/semantic/procedural memory tiers)
- API: Microsoft Graph (Outlook email + calendar, read-only)
- Voice: AVFoundation + SpeechFramework (local, no cloud)
- Architecture: MVVM + clean separation of intelligence layers

## Project Structure
See docs/01-architecture.md for full layer definitions.
Key rule: Signal ingestion, memory, reflection engine, and delivery are
SEPARATE layers with defined interfaces. Do not couple them.

## Coding Conventions
- MUST use Swift strict concurrency (async/await, actors for memory store)
- MUST write unit tests for all ML model components
- MUST log all memory read/write operations for debug
- NEVER use UserDefaults for anything beyond app preferences
- File naming: [Layer][Component].swift (e.g. MemoryEpisodicStore.swift)

## Current Build State
See BUILD_STATE.md — read this before every task.

## Key Architectural Decisions
See docs/08-decisions-log.md for why specific choices were made.

## Commands
- /new-session → runs session orientation protocol
- /handoff → creates session handoff doc before ending
- /sync-docs → updates BUILD_STATE.md from current conversation
```

Keep CLAUDE.md under 150 lines. If it grows beyond that, move content to a referenced doc and put a pointer in CLAUDE.md instead. Long CLAUDE.md files fill the context window with noise; short ones fill it with signal.[^4][^5]

### BUILD_STATE.md — Living Truth

This is the document that makes or breaks long-build continuity. It is the single source of truth about where the project currently stands. Claude must update it at the end of every session.[^2]

```markdown
# BUILD_STATE.md — Last updated: [date/session]

## What Exists and Works
- [x] Menu bar presence — basic NSStatusItem
- [x] CoreData schema — episodic memory model v1
- [ ] Microsoft Graph OAuth flow — in progress

## What Is In Progress
- Microsoft Graph OAuth: client ID set up, callback handler missing
- Thompson sampling model: data model done, scoring function not yet

## What Is NOT Started
- Voice session (morning briefing)
- Reflection engine
- Semantic memory layer

## Known Issues / Landmines
- CoreData migration not set up — do NOT change schema without a migration
- Microsoft Graph scope requires user consent on first launch

## Last Decision Made
Chose CoreData over SQLite directly because NSPersistentCloudKitContainer
gives future iCloud sync for free. See docs/08-decisions-log.md #004.

## Next Planned Task
Implement Microsoft Graph token refresh flow.
File to edit: Services/GraphAuthManager.swift
```

### docs/ — The Deep Reference Layer

These files are not loaded automatically. Claude reads them when you ask it to, or when a skill loads them. They are the specification, not the operating instructions.[^6]

**docs/01-architecture.md** must define the four layers (signal ingestion, memory store, reflection engine, delivery) with their interfaces — what data flows in, what flows out, what each layer is allowed to know about the others.

**docs/08-decisions-log.md** is critical for avoiding architectural regression. Every non-obvious decision gets an entry:

```markdown
## Decision #004 — CoreData over SQLite direct
**Date**: [date]  
**Decision**: Using NSPersistentContainer (CoreData) for all memory storage  
**Why**: Native Swift integration, CloudKit sync path, built-in migration tools  
**Trade-off**: More abstraction overhead, harder raw queries  
**Do NOT reverse unless**: Performance profiling shows CoreData is a bottleneck  
```

***

## Part 2: How Claude Remembers — The Full Picture

### What Claude Retains and What It Doesn't

Claude Max has a 200,000-token context window. Within a single session, it remembers everything in that window with near-perfect fidelity. Across sessions, it does **not** automatically remember previous conversations — but it does support opt-in cross-chat memory and project-level memory summaries.[^7][^8]

Here is the full memory architecture for Timed's build process:

| Memory Type | How It Works | Your Mechanism |
|---|---|---|
| In-session context | Everything in the active window | Keep sessions focused; use `/compact` when nearing limit |
| Cross-session project memory | Claude learns from your project files | CLAUDE.md + BUILD_STATE.md |
| Claude.ai project memory | Claude auto-summarises within a project | Create a dedicated "Timed" project in claude.ai |
| Long-term architectural memory | Docs that persist across sessions | docs/ folder, referenced explicitly |
| Decision memory | Why choices were made | docs/08-decisions-log.md |
| Error/pattern memory | What broke and what fixed it | SESSION_LOG.md + Obsidian rules/ |

### The Session Protocol

The most important workflow discipline is treating each build session as a bounded unit with a defined start and end.[^9][^2]

**Starting a session:**
```
Run: /new-session
This skill does:
1. Reads CLAUDE.md
2. Reads BUILD_STATE.md
3. Reads the last 3 entries in SESSION_LOG.md
4. Summarises current project state in one paragraph
5. Asks: "What are we building today?"
```

**Ending a session:**
```
Run: /handoff
This skill does:
1. Summarises what was accomplished
2. Lists any new landmines or gotchas discovered
3. Updates BUILD_STATE.md (what now works, what's in progress)
4. Appends a new entry to SESSION_LOG.md
5. Identifies the exact next task with the file and function to start from
```

This is the compounding system for your build process, analogous to the reflection engine in Timed itself. Each session builds on the last with maximum fidelity.[^9]

### Context Compaction — Managing the 200K Window

A complex macOS build session with multiple file reads, code generations, and back-and-forth iterations can approach context limits faster than expected. Anthropic tightened limits in March 2026, and heavy agentic sessions — especially those involving plan mode exploration agents — can exhaust the 5-hour window on Max 20x in three to four large prompts.[^10][^11][^12][^13]

Rules for managing context:

- **Never paste entire files into the conversation.** Use `@filename` to reference them; Claude reads them without filling the chat.
- **Use `/compact` mid-session** when you feel the context filling up. It summarises the history and continues from the summary.[^14]
- **Use subagents for research-heavy tasks** (reading through multiple files, analysing patterns). Each subagent gets its own 200K context and returns only the distilled result — the noise never enters your main conversation.[^15][^16]
- **Split large features across sessions.** One session per major component. Never try to build the reflection engine and the voice session in the same session.

***

## Part 3: When to Open a New Terminal

This is one of the highest-leverage tactical decisions in the build process. The rule is simple: **open a new terminal (new session) when the current context has accumulated enough intermediate noise that it will degrade future responses**.

### Open a New Terminal When:

1. **You've finished a complete component.** The CoreData schema is done and tested. Start fresh for the Graph OAuth layer.

2. **You've hit a dead end and need fresh reasoning.** If Claude has been going back and forth on a bug for more than 4 turns without resolution, the context is likely polluted with failed attempts. New session with a clean summary of the problem.

3. **You're switching architectural layers.** Don't build the reflection engine in the same session where you were debugging the memory store. The context contamination will cause layer coupling.

4. **After `/compact` has run once.** A compacted session is already compressed; a second compaction further degrades fidelity. Start fresh.

5. **When you're starting a new feature from the docs.** Beginning a new feature from scratch is most powerful with a clean context window loaded with just CLAUDE.md, BUILD_STATE.md, and the relevant spec doc.

6. **After any major architectural decision.** If you've just decided to change the CoreData schema, start a new session with an updated BUILD_STATE.md so Claude's first action is reading the new state, not the old reasoning.

### Do NOT Open a New Terminal When:

- You're mid-way through building a component — context continuity is the value here
- You're iterating on a design decision that requires the full history of reasoning
- You're debugging a specific function where the error + code + attempts all need to be in-window

### The "Token Budget" Mental Model

Think of each session as a token budget — roughly 200K tokens total, but practically about 100–150K before response quality degrades. A well-structured session spends roughly:[^8][^11]
- 20K on CLAUDE.md + BUILD_STATE.md + spec doc (your starting context)
- 80–100K on the actual build work
- 20–30K buffer for iterations and debugging

When you've spent the budget, close and start fresh with a handoff document.

***

## Part 4: Skills, MCPs, and the Toolchain

### Essential MCPs to Install

These MCPs are the difference between Claude working on Timed in isolation and Claude operating as an embedded engineer with access to your actual environment.[^17][^18]

**1. Perplexity MCP (Web Research)**
```bash
# Install via Claude Code MCP
claude mcp add perplexity --transport http https://mcp.perplexity.ai/anthropic
# Or via npm
npx @modelcontextprotocol/server-perplexity
```
Purpose: When building the ML components or integrations, Claude can search for Swift API documentation, CoreML patterns, or Microsoft Graph endpoints in real time without leaving the session.[^19][^20]

**2. Comet MCP (Browser Automation)**
As you built it yourself: Comet handles browser-based interactions — logging into dev consoles, checking Microsoft Graph Explorer, inspecting API responses — while Claude maintains oversight and gets text reports back. This is critical for the Outlook OAuth setup.[^21]

**3. GitHub MCP**
```bash
claude mcp add github --transport http https://api.githubcopilot.com/mcp/
```
Purpose: Claude can read your PR diffs, create branches, and commit code directly without leaving Cursor. Critical for the checkpoint workflow.[^18][^17]

**4. Filesystem MCP (local)**
Already built into Claude Code's default toolset. Ensure it has read access to the entire Timed project directory and write access to docs/ and CLAUDE.md.

**5. (Optional) Supabase MCP**
If you end up adding a cloud sync layer or an analytics backend for the ML models later, Supabase MCP eliminates manual configuration entirely.[^22]

### MCP Configuration Location

For project-scoped MCPs (only available in the Timed project):
```json
// .cursor/mcp.json or .claude/mcp.json
{
  "mcpServers": {
    "perplexity": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-perplexity"],
      "env": { "PERPLEXITY_API_KEY": "your-key" }
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_TOKEN": "your-token" }
    }
  }
}
```
For global MCPs available across all projects, put the same config at `~/.cursor/mcp.json`.[^17]

### Skills to Install

Skills are the automation layer above MCPs — they define how Claude should behave for recurring task types.[^16][^23]

**Install these skills in `.claude/skills/`:**

```
.claude/skills/
├── plan-feature/
│   └── SKILL.md      ← invoked when starting any new feature
├── checkpoint/
│   └── SKILL.md      ← session handoff protocol
├── debug-swift/
│   └── SKILL.md      ← Swift/Xcode-specific debugging workflow
├── memory-layer/
│   └── SKILL.md      ← context for working on memory architecture
└── reflect/
    └── SKILL.md      ← used when working on the reflection engine
```

**Example: `plan-feature/SKILL.md`**
```markdown
---
name: plan-feature
description: Use this skill when starting implementation of any new Timed feature
---

Before writing any code:
1. Read docs/01-architecture.md to confirm which layer this feature belongs to
2. Read docs/07-data-models.md to check if any new data types are needed
3. Write a 5-point implementation plan: data model → service layer → view model → view → tests
4. Ask: "Does this plan violate the observation-only constraint? Does it couple layers that should be separate?"
5. Only proceed to implementation after the plan is confirmed.

Never write code without a confirmed plan for features that touch:
- The memory store
- The reflection engine  
- The Microsoft Graph integration
```

**Example: `checkpoint/SKILL.md`**
```markdown
---
name: checkpoint
description: Use this skill at the end of every session to create a handoff
---

1. Summarise everything accomplished this session in 5 bullet points
2. List any unexpected discoveries, bugs found, or design changes made
3. Update BUILD_STATE.md with current completion status
4. Append SESSION_LOG.md with today's entry in format:
   ### [Date] — [Main thing accomplished]
   **Done**: ...
   **In progress**: ...
   **Discovered**: ...
   **Next**: [exact file and function to start from next session]
5. Confirm docs/08-decisions-log.md is updated if any architectural decision was made
```

### Cursor Rules (`.cursorrules`)

Cursor rules operate at the IDE level — they stay active across the entire project regardless of session state. Create `.cursorrules` at the project root:[^24]

```
You are building Timed, a macOS cognitive intelligence layer for C-suite executives.

ALWAYS:
- Read CLAUDE.md before suggesting any architectural change
- Suggest Swift strict concurrency (async/await, @MainActor) for all UI updates
- Write tests for all ML model logic
- Check docs/08-decisions-log.md before reversing any architectural decision
- Keep the four layers (ingestion → memory → reflection → delivery) isolated

NEVER:
- Add action-taking capabilities (no sending emails, no modifying calendar events)
- Couple the reflection engine directly to the delivery layer
- Use UserDefaults for anything beyond UI preferences
- Suggest cloud-based voice processing (all voice must be local, on-device)
- Change the CoreData schema without creating a migration
```

***

## Part 5: The Obsidian Vault Integration

### The Build Knowledge Base

Your Obsidian vault becomes the living knowledge base that outlasts any single Claude session. Structure a `timed-build/` folder in your vault:[^25][^9]

```
timed-build/
├── rules/                    ← lessons learned that become standing rules
│   ├── swift-patterns.md
│   ├── graph-api-gotchas.md
│   └── coredata-rules.md
├── walkthroughs/             ← post-session walkthroughs (Claude writes these)
│   ├── 2026-04-02-coredata-schema.md
│   ├── 2026-04-05-graph-oauth.md
│   └── ...
├── patterns/                 ← reusable patterns (wiki-linked)
│   ├── actor-based-store.md
│   ├── retry-with-backoff.md
│   └── async-observation.md
└── daily/                    ← daily notes with Dataview queries
```

**The compounding loop for the build process:**
1. End each session with `/checkpoint` — Claude writes a walkthrough to `walkthroughs/`
2. If a bug or pattern recurred, add a rule to `rules/`
3. At the start of the next session, Claude reads the last walkthrough and any relevant rules
4. By session 15, Claude has stopped making the same CoreData or Graph API mistakes because the rules prevent them[^9]

**Key Obsidian plugins to have active:**
- **Dataview** — query your walkthroughs by date, status, layer affected
- **Templater** — auto-generate walkthrough templates when Claude creates them
- **Git** — auto-commit vault changes so you have full history

### The Weekly Obsidian → Claude Bridge

Every Sunday, run this prompt in a fresh Claude session:

> "Read [paste last 5 walkthroughs]. Identify the three most significant patterns or mistakes from this week's build. Suggest any new rules to add to rules/ that would prevent those mistakes. Update CLAUDE.md if any conventions need adding."

This is the meta-reflection engine — the same compounding loop from Timed's architecture, applied to the build process itself.

***

## Part 6: The PRD Architecture for Claude

### Why Claude Needs a PRD, Not Just a Vision Doc

The Research Pack 01 document is your *vision*. A PRD is what Claude actually needs to build from — it's the machine-readable specification. The key difference: vision explains *why*, PRD explains *what exactly* at the level of acceptance criteria.[^26][^27][^28]

### The PRD Document Set for Timed

Create one PRD per major component. Each PRD lives in `docs/` and follows this structure:[^29][^28]

```markdown
# PRD: [Component Name]

## What This Is
One paragraph. What this component does, which layer it belongs to, 
what it connects to.

## User Story
As a C-suite user of Timed, when I [trigger], I expect [outcome].

## Acceptance Criteria
- [ ] AC1: [specific, testable condition]
- [ ] AC2: ...
(These become your test cases)

## Technical Specification
### Data Models
[Swift structs/classes/actors needed]

### Interfaces
[What this component receives, what it returns]

### Constraints
[Non-negotiables — e.g., "must run on background thread", "must not 
exceed 50ms for retrieval"]

## Out of Scope (Explicitly)
[Things Claude might assume are in scope but aren't]

## Dependencies
[Which other components must exist first]
```

**Priority order for PRDs:**
1. `prd-data-models.md` — write this first, everything else depends on it
2. `prd-memory-store.md` — CoreData schema, episodic/semantic/procedural
3. `prd-graph-integration.md` — Microsoft Graph read-only adapter
4. `prd-thompson-sampling.md` — ML scoring model
5. `prd-reflection-engine.md` — the intelligence core
6. `prd-morning-session.md` — delivery layer

***

## Part 7: Token Management on Max 20x

### The Reality of 20x Limits

As of March 2026, Claude Max 20x has a 5-hour session window measured in tokens, not time. During peak hours (05:00–11:00 PT / 13:00–19:00 GMT), the effective throughput is lower. A plan-mode session on a complex codebase that spawns exploration agents can burn through a large fraction of the window in a handful of prompts.[^12][^13][^10]

### Token Conservation Rules for This Project

1. **Use Sonnet for code reviews, documentation, and docs updates.** Opus for architecture decisions, complex debugging, and the reflection engine logic. The cost ratio is roughly 6x — use it strategically.[^14]

2. **Never use plan mode for simple, well-defined tasks.** Plan mode spawns exploration subagents that each consume their own context. Use it for: complex multi-file refactors, new architectural layers, debugging with unknown root cause. Skip it for: adding a function, fixing a specific bug, updating docs.[^30]

3. **Shift heavy sessions to off-peak hours.** Late night (your timezone, Adelaide/Singapore) is off-peak PT. Schedule your longest build sessions for evenings.[^13]

4. **Use subagents explicitly for file reading.** Rather than loading 10 Swift files into the main conversation for Claude to read, spin up a subagent: "Read these 10 files and summarise the relevant patterns for implementing [X]." The subagent does the reading and returns just the signal.[^15]

5. **Use `/compact` proactively, not reactively.** Run it at natural breakpoints (feature done, switching to a new file) rather than waiting until you're close to the limit.

### Comet + Perplexity as Token Offloads

Comet handles browser-based tasks that would otherwise require Claude to navigate and describe page content — each of those exchanges costs significant tokens. Perplexity MCP handles documentation lookup and API research that would otherwise require Claude to reason from training data, which is both less accurate and more verbose.[^19][^21]

The mental model: **Claude thinks, Perplexity searches, Comet browses.** Keep each tool in its lane.

***

## Part 8: The Build Sequence

### Phase 0 — Foundation (Before Writing Code)

Complete all of these before Claude writes a single Swift line:

- [ ] Create the full `docs/` folder with all spec documents (even if incomplete)
- [ ] Write `CLAUDE.md` v1
- [ ] Write `BUILD_STATE.md` v1 (everything empty, all tasks in "not started")
- [ ] Create `SESSION_LOG.md` (empty)
- [ ] Install all MCPs
- [ ] Create `.cursorrules`
- [ ] Create the Obsidian `timed-build/` structure
- [ ] Create all Skills in `.claude/skills/`
- [ ] Write `prd-data-models.md` completely — this is the foundation everything builds on

### Phase 1 — Data Layer

Sessions 1–3. Build and test in isolation:
- CoreData schema: EpisodicMemory, SemanticFact, ProceduralRule, TaskRecord, SignalEvent
- Swift actors for thread-safe store access
- Basic CRUD operations with unit tests

### Phase 2 — Integration Layer

Sessions 4–6:
- Microsoft Graph OAuth (read-only scope: Mail.Read, Calendars.Read)
- Email metadata ingestion pipeline
- Calendar event ingestion pipeline
- Signal event writes to CoreData

### Phase 3 — ML Models

Sessions 7–9:
- Thompson sampling scorer
- EMA time estimation model
- Chronotype inference from completion time data
- All models covered by unit tests with synthetic seed data

### Phase 4 — Intelligence Layer

Sessions 10–14. This is the hardest phase — budget extra tokens and do it at off-peak:
- Memory retrieval (recency × importance × relevance scoring)
- Reflection engine v1 (first-order pattern extraction)
- Reflection engine v2 (second-order synthesis + rule generation)
- Memory tier promotion (episodic → semantic)

### Phase 5 — Delivery Layer

Sessions 15–18:
- Morning session voice input (local, on-device)
- Day plan generation from memory + calendar
- Menu bar presence
- Focus timer + completion data feedback

### Phase 6 — Polish and Testing

Sessions 19–20+:
- End-to-end integration testing
- Memory model with 30 days of synthetic seed data
- Performance profiling (memory retrieval must stay under 200ms)
- Reflection engine unit tests

***

## Part 9: Prompting Discipline for Complex Builds

### The Three-Step Rule

For any task that touches more than one file, **always follow this sequence**:[^3][^1]

1. **Plan first.** "Before writing any code, give me the implementation plan." Review it. Push back on anything wrong.
2. **Confirm constraints.** "Does this plan violate the observation-only constraint? Does it couple layers inappropriately? Does it break any decisions in docs/08-decisions-log.md?"
3. **Execute.** "Proceed with implementation."

This sequence seems slower but eliminates the majority of rework. A wrong architectural decision that gets built takes 3x as long to fix as it did to build.[^1]

### High-Quality Prompt Patterns

**For new components:**
> "Read docs/01-architecture.md and docs/07-data-models.md. I want to implement [X]. Before writing code, give me the implementation plan covering: data model changes needed, which layer this belongs to, the interface it exposes to other layers, and the unit tests that will prove it works. Do not write code yet."

**For debugging:**
> "The issue is [specific symptom]. The file is [filename], the function is [functionName], and the error is [exact error]. Do not rewrite the entire function. Identify the minimal change that fixes this specific issue and explain why it works."

**For architecture questions:**
> "Read docs/01-architecture.md and docs/08-decisions-log.md. I'm considering [option A vs option B]. Which is more consistent with the established architecture and why? What would each choice mean for the reflection engine later?"

**For session start:**
> "Read CLAUDE.md and BUILD_STATE.md. Summarise the current state of the project in three sentences and tell me the exact next task based on BUILD_STATE.md."

### What NOT to Ask Claude to Do

- "Build the whole app" — never ask Claude to build across multiple layers in one prompt
- "Fix all the errors" — give it one error at a time with full context
- "Refactor the entire memory system" — break it into: schema → store → retrieval → one PR per piece
- "What should I build next?" — you decide that; BUILD_STATE.md tells you

***

## Part 10: The Quality Bar

Before any feature is considered done, run this checklist in the session:

```
Ask Claude:
"Review the code for [component] against these criteria:
1. Does it violate the observation-only constraint in any way?
2. Does it couple this layer to any layer it shouldn't know about?
3. Are all CoreData operations on the correct thread/actor?
4. Does it have unit tests that would catch regression?
5. Is there any decision here that should be logged in docs/08-decisions-log.md?
6. Does BUILD_STATE.md need to be updated?"
```

This is the equivalent of a code review — done in-session, by the same model that built it, but with explicit adversarial framing. It catches more issues than a human review of AI-generated code because Claude knows exactly what it built and why.

---

## References

1. [7 Claude Code best practices for 2026 (from real projects) - eesel AI](https://www.eesel.ai/blog/claude-code-best-practices) - The 7 Claude Code best practices for 2025 · 1. Master the CLAUDE.md file for project memory · 2. Get...

2. [Best practices for maintaining project context across sessions?](https://www.reddit.com/r/ClaudeAI/comments/1s6nqvf/best_practices_for_maintaining_project_context/) - Question for regular Claude Code and Cursor users: How are you managing context when starting a new ...

3. [How I structure Claude Code projects (CLAUDE.md, Skills, MCP)](https://www.reddit.com/r/ClaudeAI/comments/1rfwmlh/how_i_structure_claude_code_projects_claudemd/) - Claude Code works best when you design small systems around it, not isolated prompts. I'm curious ho...

4. [Stop Repeating Yourself: Give Claude Code a Memory - Product Talk](https://www.producttalk.org/give-claude-code-a-memory/) - Design a Three-Layer Memory System · Layer 1: Global Preferences (Always on) · Layer 2: Project-Spec...

5. [CLAUDE.md best practices - From Basic to Adaptive - DEV Community](https://dev.to/cleverhoods/claudemd-best-practices-from-basic-to-adaptive-9lm) - My take on it is to find yourself an actual project (not tutorials) and start iterating. I wanted to...

6. [The Ultimate Guide to Claude's Project Memory - The AI Maker](https://aimaker.substack.com/p/ultimate-guide-to-claude-project-memory-system-prompt) - Learn how to build Claude project memory using friction-driven feedback. Train AI to match your writ...

7. [Use Claude's chat search and memory to build on previous context](https://support.claude.com/en/articles/11817273-use-claude-s-chat-search-and-memory-to-build-on-previous-context) - Claude will automatically summarize your conversations and create a synthesis of key insights across...

8. [Does Claude Keep Context in Long Conversations? Memory Depth ...](https://www.datastudios.org/post/does-claude-keep-context-in-long-conversations-memory-depth-and-stability) - Best practices for maximizing context retention in Claude emphasize proactive information management...

9. [How I set up an Obsidian vault where my AI coding tool ... - Reddit](https://www.reddit.com/r/ObsidianMD/comments/1s07p9s/how_i_set_up_an_obsidian_vault_where_my_ai_coding/) - So I set up a vault with a simple loop: A rules/ folder with lessons learned — my AI reads these bef...

10. [Claude Code Pricing 2026: Real Costs - Verdent AI](https://www.verdent.ai/guides/claude-code-pricing-2026) - Standard seats offer 1.25x more usage per session than Pro and have a weekly usage limit. ... token ...

11. [Claude AI Usage Limits: What Changed in 2026 - J.D. Hodges](https://www.jdhodges.com/blog/claude-ai-usage-limits/) - Claude usage limits feel worse in March 2026. Why limits are tighter, what burns quota fastest, and ...

12. [[BUG] Claude Max plan session limits exhausted abnormally fast ...](https://github.com/anthropics/claude-code/issues/38335) - Since March 23, 2026, the 5-hour session window on Claude Max plan is being exhausted abnormally fas...

13. [Anthropic Reduces Claude Session Limits During Peak Hours](https://www.ghacks.net/2026/03/27/anthropic-reduces-claude-session-limits-during-peak-hours-for-free-pro-and-max-users/) - Anthropic is adjusting five-hour session limits during peak hours, meaning some users will hit limit...

14. [Claude Code rate limit on Max plan? The workaround developers ...](https://dev.to/sophiaashi/claude-code-rate-limit-on-max-plan-the-workaround-developers-are-actually-using-in-2026-16g2) - As of early 2026, Anthropic tightened Opus caps — users on Max 20x report roughly 40% lower effectiv...

15. [Claude Code Agents & Subagents: What They Actually Unlock](https://www.ksred.com/claude-code-agents-and-subagents-what-they-actually-unlock/) - I set up Claude Code agents early, stopped using them, then dug back in. Here's what the subagent ar...

16. [CLAUDE.md, Slash Commands, Skills, and Subagents - alexop.dev](https://alexop.dev/posts/claude-code-customization-guide-claudemd-skills-subagents/) - The complete guide to customizing Claude Code. Compare CLAUDE.md, slash commands, skills, and subage...

17. [15 Best MCP Servers You Can Add to Cursor For 10x Productivity](https://www.firecrawl.dev/blog/best-mcp-servers-for-cursor) - Enhance Your Setup: MCP servers work excellently with RAG frameworks for enhanced context retrieval ...

18. [MCP with Claude: Basics, Quick Tutorial & Top 10 MCP Servers](https://obot.ai/resources/learning-center/mcp-claude/) - Development and Coding Workflows via Claude Code. With MCP integrations, Claude can connect to code ...

19. [Perplexity - AI Web Search for Claude & Cursor - MCP Market](https://mcpmarket.com/server/perplexity-28) - Integrate Perplexity AI's powerful web search into your LLMs via Model Context Protocol. Get real-ti...

20. [Perplexity MCP Server — Features, Install & Alternatives - FastMCP](https://fastmcp.me/mcp/details/883/perplexity) - P

21. [built an mcp server that connects claude code to perplexity's comet ...](https://www.reddit.com/r/ClaudeAI/comments/1q7gcch/built_an_mcp_server_that_connects_claude_code_to/) - so i built comet-mcp. it connects claude code to perplexity's comet browser. when claude needs to do...

22. [Scaling AI-Assisted Development with Claude Code Best Practices](https://www.linkedin.com/posts/thecreativemena_mastering-claude-code-advanced-tips-for-activity-7419677601566261251-6aok) - Solution: Create a README and technical documentation from day one. Update it continuously as you bu...

23. [Extend Claude with skills - Claude Code Docs](https://code.claude.com/docs/en/skills) - Create, manage, and share skills to extend Claude's capabilities in Claude Code. Includes custom com...

24. [Guide:How to Handle Big Projects With Cursor](https://forum.cursor.com/t/guide-how-to-handle-big-projects-with-cursor/70997) - Establish Cursor Rules. Create a set of rules for Cursor to follow when working with your code: Codi...

25. [AI-Native Obsidian Vault Setup Guide - Chase Adams](https://curiouslychase.com/posts/ai-native-obsidian-vault-setup-guide/) - This is a living document about how I structure my Obsidian vault, how I maintain my Claude configur...

26. [Writing PRDs for AI Code Generation Tools in 2026 - ChatPRD](https://chatprd.ai/learn/prd-for-ai-codegen) - Learn how to write PRDs for AI code generation tools in 2026, leveraging agentic coding, ChatPRD, an...

27. [The best product requirement doc (PRD) prompt i've ever used](https://www.reddit.com/r/PromptEngineering/comments/1n2qzqr/the_best_product_requirement_doc_prd_prompt_ive/) - Best practices for crafting AI prompts. How to optimize prompts ... PRD TEMPLATE STRUCTURE ### 1. Ex...

28. [How to Write a PRD: Your Complete Guide to Product Requirements ...](https://www.perforce.com/blog/alm/how-write-product-requirements-document-prd) - Learn five steps to writing a modern PRD with best practices, templates, and examples. Discover why ...

29. [How to Write a PRD in the AI Era: Your Complete Guide - Ainna](https://ainna.ai/resources/faq/prd-guide-faq) - Master how to write a Product Requirements Document (PRD) in the AI era. Complete guide covering PRD...

30. [Claude Code creator: Accepting plans now resets context to improve ...](https://www.reddit.com/r/ClaudeAI/comments/1qg1as6/claude_code_creator_accepting_plans_now_resets/) - Boris: Claude usually only uses Plan agents. The subagents generally result in better plans, though ...

