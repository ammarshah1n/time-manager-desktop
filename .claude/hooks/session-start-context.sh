#!/bin/bash
# SessionStart hook — injects session continuity context
# Loads: HANDOFF.md (session state) + last SESSION_LOG entry + BUILD_STATE summary
# Budget: <200 lines total. Runs in <1s.

set -euo pipefail

VAULT="$HOME/Timed-Brain"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "# Session Context (auto-loaded)"
echo ""

# ── HANDOFF.md (session-to-session state transfer) ──
if [ -f "$VAULT/HANDOFF.md" ]; then
  echo "## HANDOFF (from last session)"
  cat "$VAULT/HANDOFF.md"
  echo ""
else
  echo "## HANDOFF: not found at $VAULT/HANDOFF.md"
  echo ""
fi

# ── Last SESSION_LOG entry (most recent wrap-up) ──
if [ -f "$PROJECT_ROOT/SESSION_LOG.md" ]; then
  echo "## Last Session Log Entry"
  # Extract the last session block, stop before "### Modified Files" or "### Commits This Session" (build noise)
  awk '/^## Session:/{found=1; block=""} found{if(/^### (Modified Files|Commits This Session)/) {found=0} else {block=block $0 "\n"}} /^---$/{if(found) last=block; found=0; block=""} END{if(block!="") print block; else print last}' "$PROJECT_ROOT/SESSION_LOG.md" | head -30
  echo ""
fi

# ── BUILD_STATE summary (architecture status section only) ──
if [ -f "$PROJECT_ROOT/BUILD_STATE.md" ]; then
  echo "## Build State Summary"
  # First line (title with date) + Architecture Status section
  head -1 "$PROJECT_ROOT/BUILD_STATE.md"
  echo ""
  awk '/^## Architecture Status/,/^## [^A]/' "$PROJECT_ROOT/BUILD_STATE.md" | head -25
fi
