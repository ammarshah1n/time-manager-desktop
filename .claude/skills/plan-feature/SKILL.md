---
name: plan-feature
description: Use this skill when starting implementation of any new Timed feature. Applies the saved planning architecture — parallelize by default per the dep graph, no deferrals, no time estimates, no checkpointing pauses, dep-graph + parallel-batch schedule output, verification gates auto-fire between batches.
---

# Plan-feature — Timed feature planner

Applies Ammar's mandatory planning architecture (full text in `~/CLAUDE.md` § Planning Architecture and `~/.claude/projects/-Users-integrale-time-manager-desktop/memory/feedback_planning_principles.md`). All six rules apply to every plan output:

1. Parallelize by default given the dep graph; serial only where strict dependency forces it
2. No deferrals — every blocker gets addressed inline OR surfaced as a NAMED human action
3. No time estimates anywhere
4. Plans output a dependency graph + parallel-batch schedule, NOT a serial todo list
5. Verification gates between batches are automated, never a human-pause checkpoint
6. "Get shit done" velocity — planning serves execution

## Pre-plan reads (do all in parallel where possible)

1. `docs/01-architecture.md` — confirm which layer this feature belongs to
2. `docs/07-data-models.md` — check if any new data types are needed
3. `docs/08-decisions-log.md` — check for relevant architectural decisions
4. Search basic-memory `timed-brain` for prior work on the feature area before researching
5. Search claude-mem `time-manager-desktop` for recent observations about adjacent code

## Planning steps

For any non-trivial Timed feature (≥3 files), follow this exact shape:

1. **Brainstorm** — invoke `superpowers:brainstorming` for options + tradeoffs. No deferrals — every option must address every blocker.
2. **Architectural-layer mapping** — explicitly state which layers are touched: data model → service → view model → view → tests. Identify whether the feature crosses platform boundaries (macOS / iOS / shared TimedKit).
3. **Dependency graph** — explicit graph of which steps block which. Output as a Mermaid diagram or numbered batches. Steps that don't strictly depend on each other MUST be in the same parallel batch.
4. **Per-step briefs** — each step has a self-contained brief with files-in-scope, files-out-of-scope, acceptance criteria, and architectural rules inlined verbatim. Format per `~/Timed-Brain/06 - Context/Workflow — CC plans JCode executes worktree-isolated.md` Phase 1 brief template.
5. **Critical-rule audit** — answer:
   - Does this plan violate the observation-only constraint (Timed observes/reflects/recommends, never acts)?
   - Does it couple layers that should be separate?
   - Does it expose AI keys client-side?
   - Does it skip RLS on a new table?
   - Does it bypass `GraphClient` / `SupabaseClient` / `GoogleClient` / `GmailClient`?
6. **Hand off to feature-workflow skill** — once the plan is accepted, the `feature-workflow` skill (`.claude/skills/feature-workflow/SKILL.md`) takes over and dispatches JCode workers per the saved Phase 0–6 architecture. Do NOT manually orchestrate worker dispatch — the workflow has it.

## Hard guardrails

Never write code without a confirmed plan for features that touch:
- The memory store
- The reflection engine (nightly Opus pipeline)
- The Microsoft Graph / Google Gmail integration
- Any new data model
- Any RLS-bound Supabase table or Edge Function
- Any AI dispatch path (Anthropic / OpenAI / ElevenLabs / Deepgram)

## Output contract

The plan I produce is:
- Acceptance criteria at the top of each step (boolean, machine-checkable where possible)
- Files-in-scope and files-out-of-scope explicitly listed per step
- Architectural rules inlined verbatim (not extracted excerpts) so worker briefs are self-contained
- Dependency graph + parallel-batch schedule (not a serial todo)
- A `dispatch.sh` template emitted to `<repo>/.exec/<feature>/dispatch.sh` ready for the feature-workflow skill to execute
- ZERO time estimates
- ZERO deferrals
- ZERO "ready for the next?" checkpointing pauses
