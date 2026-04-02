# AI Coding Session Skills Library

> Timed v1 Intelligence Layer | Last updated: 2026-04-02

---

## Overview

Five reusable skill definitions for Claude Code sessions on the Timed project. Each skill is a structured instruction set that gives Claude specialised behaviour for a specific task type. Skills add constraints on top of CLAUDE.md -- they never relax existing rules.

Skills are stored at `.claude/skills/[skill-name]/SKILL.md` in the repository.

---

## Skill 1: plan-feature

### File: `.claude/skills/plan-feature/SKILL.md`

```markdown
# Skill: plan-feature

## Trigger
Invoke when starting work on any new feature, component, or spec item. ALWAYS plan before coding. If you catch yourself writing implementation code without a plan, stop and run this skill first.

## Purpose
Reads all relevant specs and codebase state, then produces a detailed implementation plan. The plan is the contract for what gets built. No code is written until the plan is reviewed.

## Context to Load
1. `CLAUDE.md` (always loaded -- confirms constraints)
2. The spec doc for the feature (from `docs/` -- identify by feature name)
3. The layer's current source files (read directory listing of the affected `Sources/Timed/Layer[N]/`)
4. The layer's current tests (read directory listing of `Tests/TimedTests/Layer[N]/`)
5. `Protocols/` directory (to check existing layer boundary protocols)
6. Last `SESSION_LOG.md` entry (for continuity)

## Steps

### Step 1: Read and Understand the Spec
- Read the relevant spec document end-to-end.
- Identify: required types, required protocols, required CoreData entities, required API calls, required tests.
- Note any ambiguities or gaps in the spec.

### Step 2: Map Affected Files and Interfaces
- List every file that will be created or modified.
- For each file: what changes, what's new, what's at risk of breaking.
- Identify cross-layer touchpoints: does this feature require changes to a layer boundary protocol?

### Step 3: Enumerate New Types
- List every new Swift type (struct, enum, actor, protocol, view) with:
  - Name
  - Layer
  - Responsibility (one sentence)
  - Dependencies (what it imports/uses)
  - Public interface (key methods and properties)

### Step 4: Determine Implementation Order
- Order the types so each depends only on types already built.
- Identify the "root" type (no Timed dependencies) -- build this first.
- Identify the "integration" type (depends on everything) -- build this last.

### Step 5: Estimate Effort
- Count new types and estimate: S (<50 lines), M (50-150 lines), L (150-400 lines), XL (400+ lines).
- Estimate total sessions needed.
- Flag anything that might take longer than expected (new API integration, complex CoreData relationships, prompt engineering).

### Step 6: Identify Risks and Unknowns
- What could go wrong?
- What needs research before implementation?
- What depends on external APIs or system permissions?
- What has no test strategy yet?

### Step 7: Produce the Plan
Write the plan to `docs/plans/[feature-name].md` with this structure:

```
# Implementation Plan: [Feature Name]

## Spec Reference
[Link to spec doc]

## Summary
[One paragraph: what this feature does and why]

## New Types
| Type | Layer | File | Size | Dependencies |
|------|-------|------|------|--------------|
| ...  | ...   | ...  | ...  | ...          |

## Modified Files
| File | What Changes | Risk |
|------|-------------|------|
| ...  | ...         | ...  |

## Implementation Order
1. [First type] -- [why first]
2. [Second type] -- [depends on #1]
...

## Tests Required
| Test | What It Verifies | Layer |
|------|-----------------|-------|
| ...  | ...             | ...   |

## Risks and Unknowns
- [Risk 1]
- [Risk 2]

## Estimated Sessions: [N]

## Ambiguities in Spec (need resolution)
- [Ambiguity 1]
- [Ambiguity 2]
```

## Output Format
A markdown file saved to `docs/plans/[feature-name].md`. The plan is presented to the developer before any code is written. If there are spec ambiguities, list them and ask for resolution before proceeding.

## Anti-Patterns
- Starting to code before the plan is complete.
- Missing cross-layer impacts (e.g., new Layer 2 entity that requires a Layer 1 signal type change).
- Forgetting test requirements.
- Underestimating prompt engineering work for Layer 3 features.
- Not checking if similar functionality already exists in the codebase.
```

---

## Skill 2: checkpoint

### File: `.claude/skills/checkpoint/SKILL.md`

```markdown
# Skill: checkpoint

## Trigger
Invoke at natural stopping points: feature complete, all tests passing, end of session, before switching to a different layer, or explicitly requested. Minimum once per session. Maximum every 30 minutes of active work.

## Purpose
Snapshots current progress. Ensures the codebase is in a clean, committable state. Updates the session log. Creates a point the developer can return to.

## Context to Load
None beyond what's already in context. This skill operates on the current working state.

## Steps

### Step 1: Verify Build
```
swift build 2>&1
```
- If build fails: STOP. Report the errors. Do NOT proceed to commit. Fix the build first.
- If build succeeds: continue.

### Step 2: Run Tests
```
swift test 2>&1
```
- If tests fail: report which tests failed and why. Do NOT commit. Fix the failures first or explicitly acknowledge known failures.
- If all tests pass: continue.
- Record: total tests, passed, failed, skipped.

### Step 3: Stage and Commit
- `git add` only the files related to the current logical change. Never `git add -A` blindly.
- Verify no secrets, API keys, or `.env` files are staged (`git diff --cached --name-only`).
- Commit with conventional commit format: `type(scope): description`
- One commit per logical change. If multiple logical changes are pending, make multiple commits.

### Step 4: Update Session Log
Append to `SESSION_LOG.md`:
```
### Checkpoint [N] — [HH:MM]
- **Commit:** `[hash]` — [message]
- **Tests:** [passed]/[total] passing
- **What was done:** [one sentence]
- **Build status:** clean / warnings: [count]
```

### Step 5: Confirm
Report to the developer:
```
Checkpoint complete.
  Commit: [hash]
  Tests: [X]/[Y] passing
  Build: clean
  Session log: updated
```

## Output Format
A commit hash, test results, and session log update.

## Anti-Patterns
- Committing code that doesn't compile.
- Committing without running tests.
- Batch-committing multiple logical changes in one commit.
- Staging files that contain secrets or user data.
- Skipping the session log update.
```

---

## Skill 3: debug-swift

### File: `.claude/skills/debug-swift/SKILL.md`

```markdown
# Skill: debug-swift

## Trigger
Invoke when encountering a build error, test failure, or runtime issue. Do NOT guess at fixes. Follow this structured process.

## Purpose
Systematic debugging that minimises token waste. Diagnose -> classify -> apply targeted fix -> verify. Maximum 3 cycles before escalating.

## Context to Load
1. The exact error message (full compiler output or test failure).
2. The file and line number where the error occurs.
3. 50 lines of context above and below the error location.
4. For cross-layer errors: the protocol definition being violated.

## Steps

### Step 1: Read the Error
- Copy the exact error message.
- Identify: file path, line number, error code (if Swift compiler).
- Do NOT assume you know the fix from the error message alone.

### Step 2: Read Context
- Read the file containing the error, focusing on the error line +/- 50 lines.
- If the error references another type or protocol, read that definition too.
- If the error is in a test, also read the code being tested.

### Step 3: Classify the Error

| Error Class | Diagnostic Path |
|-------------|-----------------|
| **Type mismatch** | Check both sides of the assignment/return. Check if a DTO vs managed object confusion. Check if Optional vs non-Optional. |
| **Missing import** | Check which module the type belongs to. Verify the file is in the correct target. Check if it's a cross-layer import violation (if so, this is an architecture problem, not an import problem). |
| **Concurrency violation** | Check actor isolation. Check if a non-sendable type crosses an isolation boundary. Check if `@MainActor` is needed for UI code. |
| **CoreData threading** | Check if a managed object is being accessed on the wrong context. Check if a background context write is missing `perform {}`. |
| **API contract violation** | Check the protocol definition. Check if a method signature changed. Check if a new required method was added to a protocol. |
| **SwiftUI state issue** | Check if @State vs @Binding vs @Observable is correct. Check if a view is modifying state during body evaluation. |
| **Test failure** | Check expected vs actual values. Check if test data is stale. Check if an async operation needs `await`. |
| **Runtime crash** | Check for force unwraps (there should be none). Check for array index out of bounds. Check for nil access. |

### Step 4: Propose Fix
- State the root cause in one sentence.
- Propose the minimal fix (change as few lines as possible).
- Explain WHY this fix addresses the root cause.
- If the fix requires changing a protocol or layer boundary, flag this -- it needs discussion before applying.

### Step 5: Apply and Verify
- Apply the fix.
- Run `swift build` to verify compilation.
- Run the specific failing test (if test failure): `swift test --filter [TestName]`.
- If the fix works: run full `swift test` to check for regressions.

### Step 6: Cycle or Escalate
- If the fix didn't work: return to Step 2 with expanded context (read more files, check recent git changes).
- Maximum 3 cycles. After 3 failed fix attempts:
  - Summarise: what you tried, what happened, what the root cause might be.
  - Check recent commits: `git log --oneline -10` -- did a recent change break something?
  - Suggest: either a different approach or that the developer needs to investigate manually.

## Output Format
```
**Error:** [the error]
**Root cause:** [one sentence]
**Fix:** [what was changed]
**Verification:** build clean, [X] tests passing
```

## Anti-Patterns
- Shotgun debugging (changing multiple things hoping one works).
- Suppressing errors with force-try, force-unwrap, or `as!`.
- Adding `@Sendable` or `nonisolated` without understanding why the isolation error occurs.
- Fixing a test by changing the expected value to match the wrong output.
- Not checking for regressions after a fix.
```

---

## Skill 4: memory-layer

### File: `.claude/skills/memory-layer/SKILL.md`

```markdown
# Skill: memory-layer

## Trigger
Invoke when working on any Layer 2 (Memory Store) component: episodic/semantic/procedural repositories, core memory manager, retrieval engine, consolidation engine, embedding pipeline, vector search.

## Purpose
Loads specialised context for the memory architecture. Enforces memory-specific rules that go beyond CLAUDE.md general rules.

## Context to Load
1. `CLAUDE.md` (always)
2. Memory specs: `docs/episodic-memory.md`, `docs/semantic-memory.md`, `docs/procedural-memory.md`
3. Retrieval spec: `docs/memory-retrieval.md`
4. Context management spec: `docs/memgpt-context-management.md`
5. Tier promotion spec: `docs/memory-tier-promotion.md`
6. CoreData model: `Sources/Timed/Models/Timed.xcdatamodeld/` (or equivalent)
7. All Layer 2 source files: `Sources/Timed/Layer2/`
8. Layer 2 tests: `Tests/TimedTests/Layer2/`
9. Layer boundary protocols: `Sources/Timed/Protocols/MemoryStoring.swift`, `MemoryQuerying.swift`, `MemoryWriting.swift`

## Active Rules (supplement CLAUDE.md)

### Embedding Rule
Every memory write MUST generate an embedding. The sequence is:
1. Create the memory record in CoreData (without embedding).
2. Call `EmbeddingService.embed(content)` asynchronously.
3. On success: update the memory record with the embedding data.
4. On failure: log the error, mark the memory as `embedding_pending = true`, retry in next batch.

Never skip embedding generation. Never write a memory without scheduling an embedding.

### Retrieval Rule
Every memory query MUST go through `MemoryRetrievalEngine`. The engine applies three-axis scoring:
- `recency = 0.995 ^ hours_since_access`
- `importance = memory.importance_score`
- `relevance = cosine_similarity(query_embedding, memory_embedding)`
- `composite = w_r * recency + w_i * importance + w_v * relevance`

Never query CoreData directly from outside Layer 2. Never return unsorted/unscored results.

### Semantic Memory Confidence Rule
Every semantic fact has a confidence score in [0.0, 1.0]:
- Initial confidence: set by the reflection engine (typically 0.4-0.6 for new facts).
- Reinforcement: each confirming observation increments confidence by `min(0.1, (1.0 - current) * 0.2)`.
- Decay: -0.01 per week without reinforcement (floor: 0.1).
- Contradiction: flag for reflection engine resolution. Do NOT auto-reduce confidence.

### Procedural Memory Source Attribution
Every procedural rule MUST link to:
- The reflection cycle that generated it (cycle ID).
- The pattern(s) that it was derived from (pattern IDs).
- The episodic memories that constitute evidence (memory IDs).

Without source attribution, a rule is untraceable and untestable. Never create a rule without these links.

### CoreData Context Rule
- All writes: `container.newBackgroundContext()` with `context.perform { }`.
- All reads from Layer 2 internal code: background context is fine.
- All reads that will be displayed in UI: must use value-type DTOs, never pass managed objects.
- Merge policy: `NSMergeByPropertyObjectTrumpMergePolicy` (last writer wins for property-level conflicts).

### Migration Test Rule
Every schema change to a Layer 2 CoreData entity MUST have a migration test:
1. Create a store with the old schema version.
2. Populate with test data.
3. Migrate to the new schema version.
4. Verify: no data loss, new attributes have correct defaults, relationships intact.

## Output Format
Layer 2 code (actors, repositories, engines) that conforms to all the above rules plus all CLAUDE.md rules. Every new public method has a test. Every CoreData operation uses background contexts. Every memory write generates an embedding.

## Anti-Patterns
- Querying CoreData directly from Layer 3 or Layer 4 (use the protocol).
- Skipping embedding generation to "add it later."
- Creating semantic facts without confidence scores.
- Creating procedural rules without source attribution.
- Passing managed objects across actor boundaries.
- Forgetting to update `last_accessed_at` on retrieval (breaks recency scoring).
```

---

## Skill 5: reflect

### File: `.claude/skills/reflect/SKILL.md`

```markdown
# Skill: reflect

## Trigger
Invoke when working on any Layer 3 (Reflection Engine) component: the nightly orchestrator, any of the 6 stages, pattern extraction, rule generation, prompt templates, pattern lifecycle management, model versioning.

## Purpose
Loads specialised context for the reflection engine. Enforces reflection-specific rules. This is the most critical layer -- intelligence quality IS the product. Every shortcut here degrades the product's core value.

## Context to Load
1. `CLAUDE.md` (always)
2. Reflection engine architecture spec: `docs/reflection-engine-architecture.md`
3. Stage-specific specs:
   - `docs/first-order-pattern-extraction.md`
   - `docs/second-order-insight-synthesis.md`
   - `docs/rule-generation.md`
4. Prompt templates: `Sources/Timed/Layer3/Prompts/ReflectionPrompts.swift`
5. Named pattern library spec: `docs/named-pattern-library.md`
6. Prompt template spec: `docs/reflection-engine-prompt-templates.md`
7. All Layer 3 source files: `Sources/Timed/Layer3/`
8. Layer 3 tests: `Tests/TimedTests/Layer3/`
9. Layer boundary protocols: `Sources/Timed/Protocols/ReflectionRunning.swift`, `MemoryQuerying.swift`, `MemoryWriting.swift`
10. Core memory buffer content (if available): the current state of what goes into every Opus prompt's system message.

## Active Rules (supplement CLAUDE.md)

### Privacy Pipeline Rule (CRITICAL)
Every prompt sent to Opus/Sonnet MUST go through `PrivacyAbstractor.sanitise()` BEFORE the API call. This means:
1. Assemble the prompt with real data.
2. Run `PrivacyAbstractor.sanitise(prompt)` -> replaces names, emails, phone numbers, company names with tokens `[PERSON_1]`, `[EMAIL_1]`, `[COMPANY_1]`.
3. Send sanitised prompt to Claude API.
4. Receive response.
5. Run `PrivacyAbstractor.restore(response)` -> re-inserts real names.

Never send raw episodic memories containing real names/emails to the API. Test this by inspecting logged prompts.

### Reflection Output Structure Rule
Every reflection cycle MUST produce all of the following (even if empty):
1. **First-order observations** (array of `FirstOrderPattern`)
2. **Second-order insights** (array of `SecondOrderInsight`)
3. **New/updated rules** (array of `ProceduralRule`)
4. **Model delta** (diff of semantic facts added/modified/removed)
5. **Morning brief payload** (`MorningBrief`)
6. **Quality self-assessment** (`ReflectionQuality`)

If any stage fails, save partial results. A reflection with only Stages 1-2 is still valuable.

### No Direct Memory Modification Rule
The reflection engine NEVER calls CoreData methods or repository methods directly. It emits reflection results as structured output, and the `Stage5ModelUpdater` writes them through the `MemoryWriting` protocol. This separation allows:
- Testing reflection logic without a database.
- Reviewing proposed model changes before they're applied.
- Rolling back a bad reflection without database surgery.

### Contradiction Detection Rule
When Stage 4 generates a new rule:
1. Compare the new rule's conditions and conclusions against ALL existing procedural rules.
2. If a direct contradiction exists ("do X in situation Y" vs "avoid X in situation Y"), flag BOTH rules.
3. Include the contradiction in the `MorningBrief` as a "needs resolution" item.
4. Do NOT silently override the old rule. Do NOT silently discard the new rule.
5. If the executive resolves the contradiction (via morning session or correction), the resolution itself becomes a high-confidence procedural rule.

### Prompt Template Versioning Rule
All prompt templates are Swift string constants in `ReflectionPrompts.swift`. They are version-controlled with the code. Every template has:
- A `version` string (e.g., "stage3-v2").
- A structured JSON output schema documented in a comment above the template.
- Example input and expected output in the test file.

When modifying a prompt template:
1. Create a new version (don't overwrite the old one).
2. Run the existing test fixtures against the new version.
3. If quality degrades, revert. If quality improves or is equivalent, mark the old version as deprecated.

### Pattern Quality Testing Rule
Reflection tests must verify QUALITY, not just execution. This means:
- Given synthetic episodic memories with a known embedded pattern (e.g., "always defers people decisions"), the reflection engine must detect that pattern.
- Given episodic memories with NO pattern, the reflection engine must NOT hallucinate patterns.
- Test fixtures: at least 5 "pattern present" scenarios and 5 "no pattern" scenarios.
- Acceptance threshold: detect known patterns >= 80% of the time. False positive rate < 20%.

### Resource Awareness Rule
Log token usage for every API call in the reflection pipeline:
```swift
Logger.layer3.info("Stage 3 Opus call: \(inputTokens) in, \(outputTokens) out, \(durationMs)ms")
```
After the full cycle, log total:
```swift
Logger.layer3.info("Reflection cycle complete: \(totalTokens) tokens, $\(estimatedCost), \(totalDurationSeconds)s")
```
This data feeds into cost monitoring and quality-per-token analysis.

## Output Format
Layer 3 code (orchestrator, stages, prompts, pattern management) that conforms to all the above rules plus all CLAUDE.md rules. Every prompt goes through the privacy pipeline. Every reflection produces structured output. Every test verifies quality, not just execution.

## Anti-Patterns
- Sending raw user data (names, emails, company info) to the Claude API without sanitisation.
- Testing that the reflection "ran without errors" without verifying the output is meaningful.
- Overwriting prompt templates instead of versioning them.
- Silently resolving contradictions (either discarding old or new rules without flagging).
- Calling Layer 2 methods directly instead of through the protocol.
- Skipping the quality self-assessment step.
- Not logging token usage (makes cost monitoring impossible).
```

---

## Interaction Between Skills and CLAUDE.md

Skills layer ON TOP of CLAUDE.md. They never contradict or relax base rules:

```
CLAUDE.md (always active)
    + Skill: plan-feature (when starting a feature)
    + Skill: checkpoint (at stopping points)
    + Skill: debug-swift (when errors occur)
    + Skill: memory-layer (when working on Layer 2)
    + Skill: reflect (when working on Layer 3)
```

Multiple skills can be active simultaneously. Example: when debugging a Layer 2 issue, both `debug-swift` and `memory-layer` are active. The rules from both apply.

If a skill rule and a CLAUDE.md rule cover the same ground, the MORE RESTRICTIVE rule wins. Example: CLAUDE.md says "no force unwraps." A skill cannot say "force unwraps are okay here."

---

## Example Invocations

### Starting a New Feature

```
/plan-feature episodic-memory-repository

# Claude Code will:
# 1. Read CLAUDE.md
# 2. Read docs/episodic-memory.md
# 3. Read Sources/Timed/Layer2/ directory
# 4. Read Tests/TimedTests/Layer2/ directory
# 5. Produce docs/plans/episodic-memory-repository.md
```

### After Implementing a Feature

```
/checkpoint

# Claude Code will:
# 1. swift build
# 2. swift test
# 3. git add [relevant files]
# 4. git commit -m "feat(layer2): add episodic memory repository"
# 5. Update SESSION_LOG.md
```

### Encountering a Build Error

```
/debug-swift

# Claude Code will:
# 1. Read the error
# 2. Read context around the error
# 3. Classify: "type mismatch -- DTO vs managed object"
# 4. Propose: "Change return type from NSManagedObject to EpisodicMemoryDTO"
# 5. Apply fix
# 6. swift build + swift test
```

### Working on Memory Layer

```
# Activating the skill when starting Layer 2 work:
"I'm going to work on the semantic memory repository. Load the memory-layer skill."

# Claude Code will:
# 1. Read all memory specs
# 2. Read CoreData model
# 3. Read existing Layer 2 code
# 4. Apply memory-specific rules on top of CLAUDE.md
```

### Working on Reflection Engine

```
# Activating the skill when starting Layer 3 work:
"I'm working on Stage 3 of the reflection engine. Load the reflect skill."

# Claude Code will:
# 1. Read all reflection specs
# 2. Read prompt templates
# 3. Read existing Layer 3 code
# 4. Apply reflection-specific rules on top of CLAUDE.md
# 5. Every prompt goes through privacy pipeline
# 6. Every test verifies quality, not just execution
```
