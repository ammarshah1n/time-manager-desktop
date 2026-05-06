#!/usr/bin/env bash
# Phase 3.5 automated post-build review block.
#
# Called by dispatch.sh IMMEDIATELY after a batch's `wait` returns.
# Self-contained: runs the deterministic gate, GPT-5.5 first-pass review,
# Opus 4.7 final-check (only on APPROVED steps), then aggregates verdicts.
# CC reads the aggregate summary file and decides next action (merge / fix / human-block).
#
# This makes "review fires immediately after a big execution" a property of
# dispatch.sh itself — not something CC has to remember to orchestrate.
#
# Usage: bash scripts/post-batch-review.sh <feature> <batch-N> <step-numbers...>
# Example: bash scripts/post-batch-review.sh pa-sharing 1 1 2 3
#
# Outputs (written to .exec/<feature>/):
#   step-<N>.gate.log              — verify-worker-output.sh output per step
#   step-<N>.review-brief.md       — review brief sent to reviewer JCode workers
#   step-<N>.review-gpt55.md       — GPT-5.5 first-pass review output
#   step-<N>.review-opus47.md      — Opus 4.7 final-check output (only if GPT approved)
#   batch-<BATCH>-review-summary.md — aggregate verdict for CC to read
#
# Exit codes:
#   0 — batch ALL_APPROVE, proceed to merge
#   1 — gate failed (one or more workers failed deterministic checks)
#   2 — review verdict is REQUEST_CHANGES (fixes needed)
#   3 — review verdict is BLOCKED_ON_HUMAN (Ammar must act)
#   4 — usage error or infrastructure error

set -uo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <feature> <batch-N> <step-N> [step-N ...]" >&2
  exit 4
fi

FEATURE="$1"
BATCH="$2"
shift 2
STEPS=("$@")

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$REPO/.exec/$FEATURE"
WORKTREES="$HOME/timed-worktrees"
WORKER_BASE="${WORKER_BASE:-unified}"

if [[ ! -d "$SCRATCH" ]]; then
  echo "no scratch dir at $SCRATCH" >&2
  exit 4
fi

SUMMARY_FILE="$SCRATCH/batch-$BATCH-review-summary.md"
> "$SUMMARY_FILE"

echo "# Batch $BATCH review summary — feature=$FEATURE" >> "$SUMMARY_FILE"
echo "Run started: $(date -Iseconds)" >> "$SUMMARY_FILE"
echo "Steps: ${STEPS[*]}" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# ============================================================
# Phase 3 — deterministic verification gate per step (sequential, fast)
# ============================================================

echo "## Phase 3 — deterministic gate" >> "$SUMMARY_FILE"
GATE_FAILURES=()
for n in "${STEPS[@]}"; do
  WORKTREE="$WORKTREES/step-$n-$FEATURE"
  if bash "$REPO/scripts/verify-worker-output.sh" "$FEATURE" "step-$n" "$WORKTREE" > "$SCRATCH/step-$n.gate.log" 2>&1; then
    echo "- step-$n: GATE_PASS" >> "$SUMMARY_FILE"
  else
    GATE_FAILURES+=("step-$n")
    echo "- step-$n: **GATE_FAIL** (see step-$n.gate.log)" >> "$SUMMARY_FILE"
  fi
done

if [[ ${#GATE_FAILURES[@]} -gt 0 ]]; then
  {
    echo ""
    echo "## Final batch verdict"
    echo "**GATE_FAILED** — reviewer block SKIPPED. CC must plan fix steps for: ${GATE_FAILURES[*]}"
  } >> "$SUMMARY_FILE"
  echo "GATE_FAILED ${GATE_FAILURES[*]}"
  exit 1
fi

# ============================================================
# Phase 3.5 Sub-pass A — GPT-5.5 first-pass review per step (PARALLEL)
# Fires IMMEDIATELY after gate passes. No CC orchestration needed.
# ============================================================

prepare_review_brief() {
  local n="$1"
  local out="$SCRATCH/step-$n.review-brief.md"
  local worktree="$WORKTREES/step-$n-$FEATURE"

  {
    echo "# Code review — feature=$FEATURE step-$n"
    echo ""
    echo "You are running the \`code-review-objective-aligned\` skill on the diff below."
    echo "Output structured verdict per the skill's schema. Your final line MUST be exactly one of:"
    echo "  APPROVE"
    echo "  REQUEST_CHANGES"
    echo "  BLOCKED_ON_HUMAN"
    echo "(uppercase, no other text on that line)."
    echo ""
    echo "## Diff"
    echo '```diff'
    cd "$worktree" && git diff "$WORKER_BASE" 2>/dev/null || git diff
    echo '```'
    echo ""
    echo "## Original brief (worker's task)"
    cat "$SCRATCH/step-$n.md"
    echo ""
    echo "## Worker summary (NOT the verdict — context only)"
    cat "$SCRATCH/step-$n-summary.md"
    echo ""
    echo "## Plan context"
    cat "$SCRATCH/plan.md" 2>/dev/null || echo "(no plan.md present)"
  } > "$out"
}

echo "" >> "$SUMMARY_FILE"
echo "## Phase 3.5 Sub-pass A — GPT-5.5 first-pass" >> "$SUMMARY_FILE"

PIDS=()
for n in "${STEPS[@]}"; do
  prepare_review_brief "$n"
  (
    jcode -C "$WORKTREES/step-$n-$FEATURE" \
      --provider openai --model gpt-5.5 --reasoning xhigh \
      run "$(cat "$SCRATCH/step-$n.review-brief.md")" \
      > "$SCRATCH/step-$n.review-gpt55.md" 2>&1
  ) &
  PIDS+=($!)
done

# Wait for all GPT-5.5 reviewers; tolerate individual failures
for pid in "${PIDS[@]}"; do wait "$pid" || true; done

# Parse GPT-5.5 verdicts
declare -A GPT_VERDICT
for n in "${STEPS[@]}"; do
  v=$(grep -oE '^(APPROVE|REQUEST_CHANGES|BLOCKED_ON_HUMAN)$' "$SCRATCH/step-$n.review-gpt55.md" | tail -1 || echo "PARSE_FAIL")
  GPT_VERDICT[$n]="$v"
  echo "- step-$n: GPT-5.5 → $v" >> "$SUMMARY_FILE"
done

# ============================================================
# Phase 3.5 Sub-pass B — Opus 4.7 final-check on APPROVED steps only (PARALLEL)
# ============================================================

echo "" >> "$SUMMARY_FILE"
echo "## Phase 3.5 Sub-pass B — Opus 4.7 final-check (APPROVED steps only)" >> "$SUMMARY_FILE"

APPROVED_STEPS=()
for n in "${STEPS[@]}"; do
  if [[ "${GPT_VERDICT[$n]}" == "APPROVE" ]]; then
    APPROVED_STEPS+=("$n")
  fi
done

declare -A OPUS_VERDICT
if [[ ${#APPROVED_STEPS[@]} -gt 0 ]]; then
  PIDS=()
  for n in "${APPROVED_STEPS[@]}"; do
    (
      jcode -C "$WORKTREES/step-$n-$FEATURE" \
        --provider claude --model claude-opus-4-7 \
        run "$(cat "$SCRATCH/step-$n.review-brief.md")" \
        > "$SCRATCH/step-$n.review-opus47.md" 2>&1
    ) &
    PIDS+=($!)
  done
  for pid in "${PIDS[@]}"; do wait "$pid" || true; done

  for n in "${APPROVED_STEPS[@]}"; do
    v=$(grep -oE '^(APPROVE|REQUEST_CHANGES|BLOCKED_ON_HUMAN)$' "$SCRATCH/step-$n.review-opus47.md" | tail -1 || echo "PARSE_FAIL")
    OPUS_VERDICT[$n]="$v"
    echo "- step-$n: Opus 4.7 → $v" >> "$SUMMARY_FILE"
  done
fi

# Steps that GPT didn't approve get N/A for Opus
for n in "${STEPS[@]}"; do
  if [[ -z "${OPUS_VERDICT[$n]:-}" ]]; then
    OPUS_VERDICT[$n]="N/A"
    echo "- step-$n: Opus 4.7 → SKIPPED (GPT-5.5 did not APPROVE)" >> "$SUMMARY_FILE"
  fi
done

# ============================================================
# Aggregate verdict + tiebreaker
# ============================================================

# Tiebreaker rule from code-review-objective-aligned skill:
# - Both APPROVE → batch APPROVE
# - GPT REQUEST_CHANGES → REQUEST_CHANGES (regardless of Opus)
# - Either BLOCKED_ON_HUMAN → BLOCKED_ON_HUMAN
# - GPT APPROVE + Opus REQUEST_CHANGES → REQUEST_CHANGES (trust Opus on subtle drift)
# - GPT APPROVE + Opus PARSE_FAIL → REQUEST_CHANGES (treat as untrusted)
# - PARSE_FAIL on either → REQUEST_CHANGES + flag for manual

BATCH_VERDICT="APPROVE"
for n in "${STEPS[@]}"; do
  g="${GPT_VERDICT[$n]}"
  o="${OPUS_VERDICT[$n]}"
  if [[ "$g" == "BLOCKED_ON_HUMAN" || "$o" == "BLOCKED_ON_HUMAN" ]]; then
    BATCH_VERDICT="BLOCKED_ON_HUMAN"
    break
  fi
  if [[ "$g" != "APPROVE" || ( "$o" != "APPROVE" && "$o" != "N/A" ) ]]; then
    BATCH_VERDICT="REQUEST_CHANGES"
    # Don't break — still want to detect BLOCKED_ON_HUMAN on later steps
  fi
done

# Override: if any Opus verdict is REQUEST_CHANGES, that wins regardless
for n in "${APPROVED_STEPS[@]}"; do
  if [[ "${OPUS_VERDICT[$n]}" == "REQUEST_CHANGES" ]]; then
    BATCH_VERDICT="REQUEST_CHANGES"
  fi
done

{
  echo ""
  echo "## Final batch verdict"
  echo "**$BATCH_VERDICT**"
  echo ""
  case "$BATCH_VERDICT" in
    APPROVE)
      echo "All steps cleared both reviewer passes. CC: proceed to Phase 4 merge."
      ;;
    REQUEST_CHANGES)
      echo "One or more steps need fixes. CC: plan fix step(s), re-dispatch, re-run this script."
      echo "Per-step issues: see step-N.review-gpt55.md and step-N.review-opus47.md."
      ;;
    BLOCKED_ON_HUMAN)
      echo "Reviewer flagged a human blocker. CC: surface to Ammar with the exact action required."
      echo "Per-step blockers: grep BLOCKED_ON_HUMAN step-*.review-*.md."
      ;;
  esac
  echo ""
  echo "Run completed: $(date -Iseconds)"
} >> "$SUMMARY_FILE"

echo "$BATCH_VERDICT"

case "$BATCH_VERDICT" in
  APPROVE) exit 0 ;;
  REQUEST_CHANGES) exit 2 ;;
  BLOCKED_ON_HUMAN) exit 3 ;;
  *) exit 4 ;;
esac
