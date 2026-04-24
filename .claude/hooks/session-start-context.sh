#!/usr/bin/env bash
# SessionStart hook — injects session continuity context via JSON envelope.
# Loads: HANDOFF.md + last SESSION_LOG entry + BUILD_STATE architecture status.
# Budget: <200 lines total, <1s runtime.

set -uo pipefail

VAULT="$HOME/Timed-Brain"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

build_context() {
  printf '# Session Context (auto-loaded)\n\n'

  if [ -f "$VAULT/HANDOFF.md" ]; then
    printf '## HANDOFF (from last session)\n'
    cat "$VAULT/HANDOFF.md"
    printf '\n'
  else
    printf '## HANDOFF: not found at %s/HANDOFF.md\n\n' "$VAULT"
  fi

  if [ -f "$PROJECT_ROOT/SESSION_LOG.md" ]; then
    printf '## Last Session Log Entry\n'
    awk '
      /^## Session:/     { found=1; block="" }
      found {
        if (/^### (Modified Files|Commits This Session)/) { found=0 }
        else { block = block $0 "\n" }
      }
      /^---$/ {
        if (found) last = block
        found = 0; block = ""
      }
      END { if (block != "") print block; else print last }
    ' "$PROJECT_ROOT/SESSION_LOG.md" | head -30
    printf '\n'
  fi

  if [ -f "$PROJECT_ROOT/BUILD_STATE.md" ]; then
    printf '## Build State Summary\n'
    head -1 "$PROJECT_ROOT/BUILD_STATE.md"
    printf '\n'
    awk '/^## Architecture Status/,/^## [^A]/' "$PROJECT_ROOT/BUILD_STATE.md" | head -25
  fi
}

CONTEXT="$(build_context)"

# Emit as JSON envelope (current Claude Code spec). Fall back to plain text if python3 missing.
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$CONTEXT" | python3 -c '
import json, sys
payload = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.stdin.read()}}
print(json.dumps(payload))
'
else
  # Manual JSON escape — last resort.
  escaped="${CONTEXT//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  escaped="${escaped//$'\n'/\\n}"
  escaped="${escaped//$'\t'/\\t}"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped"
fi
