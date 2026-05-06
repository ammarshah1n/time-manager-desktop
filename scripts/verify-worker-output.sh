#!/usr/bin/env bash
# Phase 3 verification gate for a single JCode worker output.
# Used by the CC-plans-JCode-executes workflow.
# Exits 0 = PASS, non-zero = FAIL with reason printed to stderr.
#
# Usage: bash scripts/verify-worker-output.sh <feature> <step-N> <worktree-path>
#
# Checks (all must pass):
#   1. step-N.failed marker NOT present
#   2. step-N.done marker present (atomic last action proof)
#   3. step-N-summary.md present
#   4. Diff against base stays inside Files-in-scope from the brief
#   5. Diff does not contain forbidden patterns (commit invocations, push to remote,
#      migration writes, dotenv writes)
#
# Test execution is NOT part of this gate — caller (CC) runs `swift test` itself
# because it knows the filter from the brief. This script is the deterministic
# part of the gate that does not require model dispatch.

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <feature> <step-N> <worktree-path>" >&2
  exit 2
fi

FEATURE="$1"
STEP="$2"
WORKTREE="$3"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$REPO/.exec/$FEATURE"
BRIEF="$SCRATCH/$STEP.md"
SUMMARY="$SCRATCH/$STEP-summary.md"
DONE_MARKER="$SCRATCH/$STEP.done"
FAILED_MARKER="$SCRATCH/$STEP.failed"

fail() {
  echo "FAIL[$STEP]: $*" >&2
  exit 1
}

# 1. Failed marker takes priority — worker explicitly reported failure
if [[ -f "$FAILED_MARKER" ]]; then
  fail "worker reported failure (see $FAILED_MARKER and $SUMMARY)"
fi

# 2. Done marker required — its absence means worker died mid-run or skipped the atomic write
if [[ ! -f "$DONE_MARKER" ]]; then
  fail "no done marker at $DONE_MARKER — worker died before completing"
fi

# 3. Summary required — even passing workers must emit one
if [[ ! -f "$SUMMARY" ]]; then
  fail "no summary at $SUMMARY"
fi

# 4. Worktree exists
if [[ ! -d "$WORKTREE" ]]; then
  fail "worktree missing at $WORKTREE"
fi

# 5. Brief exists (otherwise we can't extract scope)
if [[ ! -f "$BRIEF" ]]; then
  fail "brief missing at $BRIEF"
fi

# Extract Files in scope from brief — block between "## Files in scope" and the next ## header
SCOPE_FILE="$SCRATCH/$STEP.scope"
awk '/^## Files in scope/,/^## /' "$BRIEF" \
  | grep -E '^- ' \
  | sed 's/^- //' \
  | awk '{print $1}' \
  | grep -v '^$' > "$SCOPE_FILE" || true

if [[ ! -s "$SCOPE_FILE" ]]; then
  fail "no Files in scope section parsed from brief — review brief format"
fi

# Determine base for diff (default: unified)
BASE="${WORKER_BASE:-unified}"

# 6. Scope check — every changed file must appear in the brief's scope list
CHANGED=$(cd "$WORKTREE" && git diff "$BASE" --name-only 2>/dev/null || git diff --name-only)
OUT_OF_SCOPE=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if ! grep -qF "$f" "$SCOPE_FILE"; then
    OUT_OF_SCOPE="$OUT_OF_SCOPE $f"
  fi
done <<< "$CHANGED"

if [[ -n "$OUT_OF_SCOPE" ]]; then
  fail "out-of-scope changes:$OUT_OF_SCOPE"
fi

# 7. Forbidden-pattern check (avoid trigger substrings in this file by using char-class regex)
DIFF_BODY=$(cd "$WORKTREE" && git diff "$BASE" 2>/dev/null || git diff)

# Patterns that indicate the worker tried to commit / push / touch migrations / write secrets
FORBIDDEN_HITS=$(echo "$DIFF_BODY" | grep -nE '\bg[i]t commit -m|\bg[i]t pus[h] origin|/migrations/.*\.sql|^\+.*\.[e]nv' || true)

if [[ -n "$FORBIDDEN_HITS" ]]; then
  fail "forbidden patterns in diff:"$'\n'"$FORBIDDEN_HITS"
fi

# All gates passed
N_CHANGED=$(echo "$CHANGED" | grep -cE '^[^[:space:]]' || true)
echo "PASS[$STEP]: $N_CHANGED files changed, all in scope"
exit 0
