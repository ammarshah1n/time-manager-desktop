---
name: feature-workflow
description: Use when Ammar wants to implement, ship, build, or execute any Timed feature touching multiple files. Auto-triggers on phrases "ship feature", "implement feature", "build feature X", "let's ship Y", "execute the plan", "run the workflow", "let's add Z", or any planning-then-execution sequence on Timed. Drives the full CC-plans-JCode-executes pipeline saved at ~/Timed-Brain/06 - Context/Workflow — CC plans JCode executes worktree-isolated.md. Phases 0–6 are end-to-end automated except for the plan-acceptance gate. Workers dispatch in parallel git worktrees via the installed jcode v0.11.16-dev binary (which has all 12 executor flags). GPT-5.5 + Opus 4.7 review fires automatically after each batch. NO DEFERRALS, NO TIME ESTIMATES, parallel by default. Skip only for single-file edits / typos / doc-only changes — for those, just Edit directly.
---

# Feature Workflow — CC plans, JCode workers execute

You are running this skill because Ammar asked to ship, implement, build, or execute a Timed feature. The full canonical architecture lives in `~/Timed-Brain/06 - Context/Workflow — CC plans JCode executes worktree-isolated.md` and `~/Timed-Brain/06 - Context/Workflow extensions — automated post-build review and dock update.md`. Read those if you need full detail. This skill is the operational entry point.

**Apply the saved planning principles** (`feedback_planning_principles.md`):
- Parallelize by default given the dependency graph
- No deferrals — fillable gaps get dispatched, not punted
- No time estimates anywhere
- Get shit done

## Phase 0 — Setup (only on first feature in a session, or if missing)

Verify these are in place; create if missing:

```bash
test -d ~/timed-worktrees || mkdir -p ~/timed-worktrees
test -f ~/.jcode/prompt-overlay.md  # Executor Contract section should be present
grep -q '^\.exec/' /Users/integrale/time-manager-desktop/.gitignore
ls /Users/integrale/time-manager-desktop/.claude/skills/code-review-objective-aligned/SKILL.md
ls /Users/integrale/time-manager-desktop/scripts/verify-worker-output.sh
ls /Users/integrale/time-manager-desktop/scripts/post-batch-review.sh
which jcode  # should resolve to /opt/homebrew/bin/jcode (v0.11.16-dev)
jcode --version  # should show v0.11.16-dev
```

If any check fails: stop and surface to Ammar with the exact action needed.

## Phase 1 — Plan with CC + Superpowers + ultrathink

Invoke in order:
1. `superpowers:brainstorming` — explore options + tradeoffs for the feature. No deferrals — every option must address every blocker.
2. `superpowers:writing-plans` — synthesize into a structured plan with explicit dependency graph + parallel-batch schedule.

Write to `<repo>/.exec/<feature>/`:
- `plan.md` — top-level with dependency graph
- `step-<N>.md` — per-step briefs (one per worker)
- `step-<N>.scope` — newline-delimited in-scope file paths (consumed by `--scope-file`)
- `dispatch.sh` — worktree-aware parallel-batch shell script

Per-step brief template (rich + self-contained because workers don't inherit conversation context):

```markdown
# Step N: <task>

## Acceptance criteria (boolean) — TOP for visibility
- swift build (in your worktree) passes
- swift test --filter <name> passes
- diff scope: only files listed in §Files in scope
- no commits, no remote pushes, no migration writes, no dotenv writes

## Files in scope
- path/x.swift — modify Y
- path/test.swift — add test for Y

## Files OUT of scope (any touch = automatic FAIL)
- everything else (CC verification gate scans diff post-run)

## Architectural rules (verbatim — not extracted excerpts)
<full text of relevant CLAUDE.md / .claude/rules/ sections>

## Skills inlined (only step-specific)
<full text of relevant skills — superpowers:test-driven-development for tested code, swift-testing-pro for tests, supabase-postgres-best-practices for SQL, etc.>

## Task
<exact thing to do>

## Constraints
- Do NOT commit, do NOT push to remote, do NOT modify migrations, do NOT write dotenv files
- All swift / xcodebuild commands run in YOUR worktree (the cwd JCode launched in)
- If unresolvable error: write verbatim to summary, touch step-N.failed marker, exit non-zero
```

## Phase 2 — Plan acceptance (one allowed pause)

Print the plan to Ammar. Wait for explicit approval before generating worktrees + dispatching. This is the ONE allowed human pause; not a violation of "no checkpointing pauses" because it requires real-world human review.

Plan format for review:
- Bullet-list steps + dependencies
- Anchor sizing: A (PA-sharing-class ~15-file features) → 2-3 subsystem worktrees, B (60-item-style punch list) → up to 5 file-non-overlapping worktrees per batch
- Show which steps run in parallel vs serial
- Surface any blockers needing human action (Apple Developer cert, OAuth grant, Yasser confirmation)

## Phase 3 — Dispatch via dispatch.sh

`dispatch.sh` template shape (CC's planner emits this per feature):

```bash
#!/usr/bin/env bash
set -uo pipefail
REPO=/Users/integrale/time-manager-desktop
FEATURE="${FEATURE:?must set FEATURE}"
SCRATCH="$REPO/.exec/$FEATURE"
WORKTREES="$HOME/timed-worktrees"
mkdir -p "$SCRATCH" "$WORKTREES"

run_batch() {
  local label="$1"; shift
  local pids=() rc=0
  echo "[batch] $label start"
  for cmd in "$@"; do bash -c "$cmd" & pids+=($!); done
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      rc=$((rc+1))
      for other in "${pids[@]}"; do kill -TERM "$other" 2>/dev/null || true; done
    fi
  done
  echo "[batch] $label done failures=$rc"
  return $rc
}

mk_worktree() {
  local n="$1"
  git -C "$REPO" worktree add "$WORKTREES/step-$n-$FEATURE" -b "step-$n-$FEATURE" 2>&1
}

# Batch 1 — independent steps in isolated worktrees (parallel)
mk_worktree 1; mk_worktree 2; mk_worktree 3
run_batch "B1" \
  "jcode -C $WORKTREES/step-1-$FEATURE --provider openai --model gpt-5.5 --reasoning-effort xhigh run --brief-file $SCRATCH/step-1.md --scope-file $SCRATCH/step-1.scope --summary-out $SCRATCH/step-1-summary.md --done-out $SCRATCH/step-1.done --failed-out $SCRATCH/step-1.failed --max-tool-calls 80 --trace-out $SCRATCH/step-1.trace.jsonl --scope-violation-policy abort > $SCRATCH/step-1-out.log 2>&1" \
  "jcode -C $WORKTREES/step-2-$FEATURE --provider openai --model gpt-5.5 --reasoning-effort xhigh run --brief-file $SCRATCH/step-2.md --scope-file $SCRATCH/step-2.scope --summary-out $SCRATCH/step-2-summary.md --done-out $SCRATCH/step-2.done --failed-out $SCRATCH/step-2.failed --max-tool-calls 80 --trace-out $SCRATCH/step-2.trace.jsonl --scope-violation-policy abort > $SCRATCH/step-2-out.log 2>&1" \
  "jcode -C $WORKTREES/step-3-$FEATURE --provider openai --model gpt-5.5 --reasoning-effort xhigh run --brief-file $SCRATCH/step-3.md --scope-file $SCRATCH/step-3.scope --summary-out $SCRATCH/step-3-summary.md --done-out $SCRATCH/step-3.done --failed-out $SCRATCH/step-3.failed --max-tool-calls 80 --trace-out $SCRATCH/step-3.trace.jsonl --scope-violation-policy abort > $SCRATCH/step-3-out.log 2>&1"

# Phase 3 + 3.5 verification + review block fires AUTOMATICALLY after each batch
bash "$REPO/scripts/post-batch-review.sh" "$FEATURE" 1 1 2 3
B1_RC=$?

# Map B1_RC: 0=APPROVE→continue, 1=GATE_FAILED, 2=REQUEST_CHANGES, 3=BLOCKED_ON_HUMAN
if [[ $B1_RC -ne 0 ]]; then
  echo "Batch 1 verdict requires action. See $SCRATCH/batch-1-review-summary.md"
  exit $B1_RC
fi

# Batch 2 — depends on B1 (e.g., integration step, single worker, sequential)
mk_worktree 4
jcode -C "$WORKTREES/step-4-$FEATURE" --provider openai --model gpt-5.5 --reasoning-effort xhigh \
  run --brief-file "$SCRATCH/step-4.md" --scope-file "$SCRATCH/step-4.scope" \
  --summary-out "$SCRATCH/step-4-summary.md" --done-out "$SCRATCH/step-4.done" \
  --failed-out "$SCRATCH/step-4.failed" --trace-out "$SCRATCH/step-4.trace.jsonl"
bash "$REPO/scripts/post-batch-review.sh" "$FEATURE" 2 4 || exit $?

# Batch 3 — review pass with mixed providers for orthogonal blind spots
# (only fire if the feature is security-sensitive or complex; otherwise the
# Phase 3.5 review block from earlier batches is sufficient)
```

For Anthropic workers (e.g., complex SQL or multi-file refactor needing Opus 4.7):

```bash
jcode -C $WORKTREES/step-N-$FEATURE \
  --provider claude --model claude-opus-4-7 --thinking-effort high \
  run --brief-file $SCRATCH/step-N.md --scope-file $SCRATCH/step-N.scope \
      --summary-out $SCRATCH/step-N-summary.md --done-out $SCRATCH/step-N.done \
      --failed-out $SCRATCH/step-N.failed --trace-out $SCRATCH/step-N.trace.jsonl \
      --scope-violation-policy abort
```

`--thinking-effort high` injects `thinking.budget_tokens=8192` into the Anthropic API request body.

CC fires `bash dispatch.sh` and reads aggregate exit codes from each batch's review-summary.

## Phase 3 (deterministic gate) + Phase 3.5 (auto review) — fire automatically inside dispatch.sh

After each batch's `wait`, dispatch.sh calls `bash scripts/post-batch-review.sh <feature> <batch-N> <step-N>...` which runs:

1. `verify-worker-output.sh` per step (deterministic gate: done/failed marker check, scope check, forbidden patterns)
2. GPT-5.5 (xhigh) reviewer per step in parallel via the `code-review-objective-aligned` skill
3. Opus 4.7 final-check on GPT-APPROVED steps in parallel
4. Aggregate verdict in `batch-N-review-summary.md`
5. Exit code: 0=APPROVE, 1=GATE_FAILED, 2=REQUEST_CHANGES, 3=BLOCKED_ON_HUMAN

**No CC orchestration step needed between worker completion and review start.** Review is automatic.

CC's job after dispatch.sh exits:
- 0 → continue to Phase 4 merge
- 1 → CC plans fix step for the failed gate, re-dispatches, re-runs post-batch-review.sh
- 2 → CC reads `step-N.review-gpt55.md` + `step-N.review-opus47.md`, plans fix per the requested changes, re-dispatches
- 3 → CC surfaces the human blocker to Ammar with the exact action required (the only allowed pause beyond Phase 2)

## Phase 4 — Merge worktrees with conflict policy

After all batches APPROVE:

```bash
cd /Users/integrale/time-manager-desktop
git checkout unified
git checkout -b "feature/$FEATURE" 2>/dev/null || git checkout "feature/$FEATURE"

for n in 1 2 3 ...; do
  git merge --no-ff "step-$n-$FEATURE"
done
```

Conflict policy:
- **Shared infrastructure** (`Package.swift`, `project.yml`, test target lists, `.gitignore`): additive merge, include all additions
- **Logic conflicts** (same function/region modified by two workers): plan reconciliation step, don't auto-resolve
- **Generated files** (`Timed.xcodeproj/` from xcodegen, derived data): drop conflicting versions, regenerate post-merge

After all merges:
```bash
swift build -Xswiftc -skipMacroValidation -Xswiftc -skipPackagePluginValidation
swift test
```

If anything broke: plan fix step, re-dispatch, re-merge. NO DEFERRALS.

Worktrees pruned: `for n in 1 2 3 ...; do git worktree remove "$HOME/timed-worktrees/step-$n-$FEATURE"; done`. Branches kept until feature ships.

## Phase 5 — Dock app reinstall

```bash
cd /Users/integrale/time-manager-desktop
bash scripts/package_app.sh   # builds dist.noindex/Timed.app
bash scripts/install_app.sh   # quits running Timed, replaces /Applications/Timed.app
```

After this, Ammar's Dock icon launches the freshly built version. The batch isn't complete until this succeeds.

## Phase 6 — Memory writeback (CC parent's hooks fire)

When the feature ships or `/wrap-up` runs:
- Stop hook → claude-mem captures parent session
- Stop hook → updates HANDOFF.md, SESSION_LOG.md
- CC explicitly calls `mcp__basic-memory__write_note(project="timed-brain", directory="06 - Context", ...)` with synthesis
- Worker summaries archived from `<repo>/.exec/<feature>/` if useful

## Anchor sizing rules (apply when planning)

### Anchor A — PA-sharing-class (~15 files, coupled subsystems)
Decompose by SUBSYSTEM, not by file. **2–3 worktrees, NOT 5+:**
- WT1: Backend (Postgres RPC + RLS + Edge Function)
- WT2: Swift client (Service + Pane + Sheet + deep links)
- WT3: Tests + security audit (after WT1+WT2 land)
Then a single integration step, no workers.

### Anchor B — 60-item punch list (parallel-friendly)
- Up to 5 worktrees per batch where items are file-non-overlapping
- Group by file-set (notarize + DMG + Next.js landing + voice polish + iOS UI mock = 5 in one batch)
- Supabase items run sequentially in their OWN batch (not parallel) against remote project

## Skip the workflow when:
- Single-file edit with obvious scope
- Typo or one-line fix
- Doc-only changes
- Debugging exploration (use `superpowers:systematic-debugging` instead)
- Configuration tweaks not affecting build/runtime

## When to invoke

**Auto-fire on phrases:**
- "ship feature X" / "let's ship Y" / "let's ship the X feature"
- "implement X" / "implement the Y feature"
- "build X" / "build a Y" / "let's build Z"
- "execute the plan" / "run the workflow"
- "let's add Z" (when Z is a multi-file feature)
- "add a Y" (when Y is a feature, not a single-line change)

**Don't fire on:**
- "fix the typo in X"
- "rename Y in Z"
- "what does X do"
- "show me Y"
- "explain Z"

## Output style during workflow execution
- Terse status per phase
- Show actual command outputs (truncate huge ones)
- Surface human blockers prominently with exact actions Ammar must take
- Never claim a step is done without reading the verdict from review-summary.md
