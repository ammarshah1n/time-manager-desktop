# Audit and Consistency Prompt

> Timed v1 Intelligence Layer | Last updated: 2026-04-02

---

## Purpose

This document is a prompt to execute AFTER all spec documents are generated and placed in `~/timed-docs/docs/`. It reads every spec, cross-references them, and produces a prioritised issue list. It is the final quality gate before coding begins.

Run this prompt in a Claude Code session with access to the full `~/timed-docs/docs/` directory.

---

## The Audit Prompt

```
You are performing a comprehensive consistency audit of a specification library for Timed, a macOS cognitive intelligence layer for C-suite executives. The system has four strict layers: Signal Ingestion -> Memory Store -> Reflection Engine -> Intelligence Delivery.

Read every document in ~/timed-docs/docs/ and cross-reference them against each other. Your job is to find every inconsistency, gap, contradiction, and quality issue BEFORE coding begins. Every issue you find here saves hours of debugging later.

Be ruthless. Do not be polite about document quality. Be precise about what is wrong and what needs to happen to fix it.

## What to Check

### 1. Schema Conflicts

Cross-reference every entity, attribute, relationship, and enum across all documents. Specifically:

- Does the data models spec (01-data-models) define entities consistently with how they are used in the memory specs (13-16)?
- Does the reflection engine architecture (25) reference memory entities exactly as defined in the memory specs?
- Does the signal spec (07-11) define signal types that match what the background agent architecture (42) expects?
- Are enum values consistent? (e.g., if one doc says PatternStatus has 4 states and another implies 5, that is a conflict.)
- Are field names spelled consistently? (e.g., `last_accessed_at` vs `lastAccessedAt` vs `lastAccessed`)
- Are data types consistent? (e.g., importance as Float vs Int vs Double across documents)

For each conflict found, report:
- Which documents conflict
- The specific attribute/entity/enum in question
- What each document says
- Proposed resolution

### 2. Interface Mismatches

For every layer boundary, verify that BOTH sides agree on the data contract:

**Layer 1 -> Layer 2:**
- What signal types does Layer 1 emit? (check signal specs 07-11, background agent spec 42)
- What signal types does Layer 2 expect to receive? (check memory specs 13-16, data models 01)
- Do they match exactly?

**Layer 2 -> Layer 3:**
- What retrieval interface does Layer 2 expose? (check memory retrieval spec 16)
- What retrieval interface does Layer 3 call? (check reflection engine spec 25, stages 26-28)
- Do the query parameters, return types, and scoring weights match?

**Layer 3 -> Layer 2:**
- What write interface does Layer 3 use to update memory? (check reflection engine spec 25, rule generation 28)
- What write interface does Layer 2 expose? (check memory specs 13-15)
- Do the write payloads match the entity schemas?

**Layer 3 -> Layer 4:**
- What intelligence payloads does Layer 3 produce? (check reflection engine spec 25, morning session spec 31)
- What intelligence payloads does Layer 4 expect? (check morning session 31, alerts 33, menu bar 34)
- Do they match?

**Layer 4 -> Layer 1:**
- What user interaction signals does Layer 4 emit? (check morning session 31, query interface 37)
- What signals does Layer 1 expect? (check signal specs, data models 01)
- Is the feedback loop actually closed?

For each mismatch found, report:
- Which boundary
- What one side expects vs what the other side provides
- Proposed resolution

### 3. Undefined Terms and References

Search for terms used in one document that are never defined anywhere:

- Entity names referenced but not in the data model
- Protocol names referenced but not specified
- Enum values used but not enumerated
- Acronyms without expansion
- Configuration values referenced but not documented
- File paths referenced but not in the directory structure

For each undefined term:
- Where it appears
- What it seems to mean from context
- Where its definition should live

### 4. Circular Dependencies

Check for:
- Components that depend on each other (A needs B, B needs A)
- Build phases that reference incomplete predecessors
- Features that require features that require the first feature
- Protocols that reference types from the layer they are supposed to abstract

For each circular dependency:
- The dependency cycle
- Which documents create it
- Proposed resolution (usually: introduce an abstraction or reorder)

### 5. Missing Acceptance Criteria

For every spec document, check:
- Does it define how to verify the component works? (not just "it should work" -- specific, measurable criteria)
- For ML models: are there quality thresholds? (e.g., pattern detection rate >= 80%)
- For UI components: are there interaction specs? (what happens on tap, on dismiss, on error)
- For agents: are there health check definitions? (how to know if it has silently failed)
- For integration points: are there error handling specs? (what happens when the external API is down)

For each missing acceptance criterion:
- Which document
- What is missing
- What it should say

### 6. Direct Contradictions

Find explicit conflicts between documents:

- One says data stays local, another implies sync
- One says Haiku classifies emails, another says Sonnet
- One says reflection runs nightly, another implies on-demand
- One says embeddings are stored locally, another implies pgvector
- One says CoreData, another implies SwiftData
- Different token budgets for the same operation
- Different polling intervals for the same agent
- Different model tier assignments for the same task

For each contradiction:
- The two (or more) conflicting statements
- Which documents contain them
- Which statement should be canonical
- Proposed resolution

### 7. Gaps

Things not covered by any document but obviously needed:

- Error handling for specific failure modes
- Edge cases (what happens on first-ever launch with no data?)
- Platform requirements (minimum macOS version, hardware requirements)
- Performance targets (latency, throughput, memory usage)
- Security considerations not covered by the privacy spec
- Accessibility (VoiceOver, keyboard navigation)
- Localisation considerations
- Rate limiting strategy for external APIs
- Data backup and recovery
- What happens when the user has no internet
- What happens when disk is full
- What happens when the user hasn't opened the app in a month

For each gap:
- What is missing
- Which documents should address it
- Priority (critical / major / minor)

### 8. Specification Quality Ratings

For each document, rate on a 1-5 scale:

| Criterion | 1 (Poor) | 3 (Adequate) | 5 (Excellent) |
|-----------|----------|---------------|----------------|
| **Completeness** | Major sections missing | Covers main topics | Covers every aspect including edge cases |
| **Implementability** | Too vague to code from | A developer could build most of it | A developer could build it entirely from this doc |
| **Testability** | No acceptance criteria | Some criteria, vaguely stated | Every feature has specific, measurable criteria |
| **Consistency** | Contradicts other docs | Mostly consistent | Perfectly aligned with all other docs |

## Output Format

```markdown
# Timed Specification Audit Report

**Documents audited:** [count]
**Date:** [date]
**Auditor:** Claude Code

---

## Critical Issues (MUST fix before coding begins)

Issues that will cause build failures, data corruption, or architectural deadlocks if not resolved.

### CRIT-1: [Issue title]
- **Type:** [Schema conflict / Interface mismatch / Contradiction / Circular dependency]
- **Documents affected:** [list]
- **The issue:** [precise description]
- **Evidence:** [quotes from conflicting documents]
- **Proposed resolution:** [specific fix]

### CRIT-2: ...

---

## High Priority Issues (fix during Phase 1)

Issues that won't block initial development but will cause problems soon.

### HIGH-1: [Issue title]
...

---

## Medium Priority Issues (fix when the component is built)

Issues that can be resolved when the relevant code is being written.

### MED-1: [Issue title]
...

---

## Low Priority Issues (nice to resolve)

Stylistic inconsistencies, minor gaps, documentation quality improvements.

### LOW-1: [Issue title]
...

---

## Document Quality Ratings

| # | Document | Completeness | Implementability | Testability | Consistency | Notes |
|---|----------|--------------|------------------|-------------|-------------|-------|
| 01 | Data Models | X/5 | X/5 | X/5 | X/5 | ... |
| 02 | Architecture | X/5 | X/5 | X/5 | X/5 | ... |
| ... | ... | ... | ... | ... | ... | ... |

**Average scores:** Completeness: X.X | Implementability: X.X | Testability: X.X | Consistency: X.X

---

## Unresolved Design Questions

Decisions that no document has made and that someone needs to decide before coding.

1. [Question] — affects [which documents/components]
2. [Question] — affects [which documents/components]
...

---

## Recommended Consolidation

Where multiple documents overlap and should be merged, cross-referenced, or have a single source of truth designated.

1. [Overlap description] — recommendation
2. [Overlap description] — recommendation
...

---

## Systemic Findings

Top-level observations about the specification library as a whole.

1. [Finding] — [recommendation]
2. [Finding] — [recommendation]
...
```

## Scoring Rubric for Severity

| Severity | Definition |
|----------|-----------|
| **Critical** | Will cause a build failure, data corruption, or makes a component unimplementable. Blocks coding. |
| **High** | Will cause confusion or rework within the first 2 phases. Should be fixed before the affected component is built. |
| **Medium** | Will require a decision during implementation. Can be resolved when encountered but should be logged. |
| **Low** | Stylistic, minor naming inconsistency, or documentation improvement. Fix anytime. |

## Execution Notes

- Read EVERY document, not just the ones that seem related. Conflicts often hide between distant specs.
- Pay special attention to the BOUNDARIES between layers. That is where mismatches concentrate.
- Check that every entity referenced in a non-schema document actually exists in the data model spec.
- Check that every protocol referenced in a non-architecture document is defined in the architecture spec.
- Check that the build sequence phases match the dependency requirements implied by the specs.
- If the audit reveals a systemic issue (e.g., a layer boundary that is unclear across ALL documents), call it out as a top-level systemic finding.
```

---

## How to Run the Audit

### Prerequisites
- All spec documents generated and placed in `~/timed-docs/docs/`
- Each document is a standalone `.md` file

### Execution

1. Open a fresh Claude Code session (clean context, no prior work loaded).
2. Paste the audit prompt above, or reference this document:
   ```
   Read ~/timed-docs/staging/audit-prompt.md and execute the audit prompt inside it against all documents in ~/timed-docs/docs/.
   ```
3. Claude Code will read every document and produce the audit report.
4. Save the report to `~/timed-docs/docs/50-audit-report.md`.

### Expected Duration
- ~30-45 documents to cross-reference
- Claude Code will need to read each document fully
- Expect 10-20 minutes for the full audit
- Output: 2,000-5,000 word report

### After the Audit

1. **Critical issues:** Fix immediately. These are structural problems that will cascade.
2. **High issues:** Fix before starting the affected phase. Add them to the Phase 1 task list.
3. **Medium issues:** Log them in the Obsidian vault as `decisions/` items. Resolve when the component is built.
4. **Low issues:** Fix opportunistically. Don't block coding for these.
5. **Unresolved design questions:** These need developer decisions. Schedule 30 minutes to decide each one, then update the relevant spec docs.
6. **Re-run the audit** after fixing critical and high issues to verify they are resolved.

### Audit Frequency

- **Initial:** Run once after all specs are generated (before Phase 1).
- **Phase boundaries:** Run after each phase completes (before starting the next phase). Update the prompt to focus on the upcoming phase's documents.
- **After major spec changes:** If a spec is rewritten or a new one is added, run a targeted audit on the changed document and its neighbours.

---

## Audit Checklist (Quick Reference)

Use this checklist to manually spot-check before running the full automated audit:

### Schema Consistency
- [ ] Every entity in the data model spec is referenced by at least one other spec
- [ ] Every entity referenced in a non-schema spec exists in the data model spec
- [ ] Enum values are consistent across all documents that reference them
- [ ] Field names use consistent casing (camelCase for Swift, snake_case for database)
- [ ] Data types are consistent (Float vs Double, Int vs Int64, Date vs TimeInterval)

### Layer Boundaries
- [ ] Layer 1 output types match Layer 2 input types
- [ ] Layer 2 query interface matches Layer 3 query usage
- [ ] Layer 3 write interface matches Layer 2 write acceptance
- [ ] Layer 3 intelligence payloads match Layer 4 consumption
- [ ] Layer 4 feedback signals match Layer 1 signal types
- [ ] No spec implies cross-layer imports

### AI Model Assignments
- [ ] Every AI task (classification, estimation, reflection, direction) has a clear model assignment
- [ ] No task is assigned to two different models in different specs
- [ ] Token budgets are consistent across specs referencing the same operation

### Build Sequence Alignment
- [ ] Every component in the build sequence has a corresponding spec
- [ ] Every spec's component appears in the build sequence
- [ ] Phase dependencies in the build sequence match the spec dependencies
- [ ] Completion criteria in the build sequence are testable

### Privacy
- [ ] Every spec that involves external API calls references the privacy pipeline
- [ ] No spec implies sending raw PII to external services
- [ ] Voice spec confirms raw audio is never stored
- [ ] App focus spec confirms window titles are opt-in

### Error Handling
- [ ] Every external API integration spec has error/retry/fallback defined
- [ ] Every agent spec has a health check mechanism
- [ ] The reflection engine spec handles partial failures
- [ ] The build sequence accounts for graceful degradation
