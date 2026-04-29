#!/usr/bin/env bash
# memory-gate.sh — non-blocking PreToolUse nag enforcing the Memory-First Protocol.
#
# Behaviour:
#   • If basic-memory has been called this session (sentinel exists) → silent, exit 0.
#   • If a research-shaped tool is about to fire (WebSearch/WebFetch/comet/Agent) AND
#     basic-memory has NOT been called this session → print a system-reminder to stderr
#     and EXIT 0 (does not block — Tier 1 of permission-check.sh auto-approves these).
#   • If a basic-memory tool is firing → touch the sentinel, exit 0.
#   • All other tools → silent, exit 0.
#
# Sentinel lives at /tmp/claude-memcheck-${session_id}, scoped per Claude session.
# Survives for the session lifetime (until /tmp is cleared on reboot).

set -uo pipefail

INPUT_JSON="$(cat)"
TOOL="$(echo "$INPUT_JSON" | jq -r '.tool_name // ""')"
SESSION_ID="$(echo "$INPUT_JSON" | jq -r '.session_id // "unknown"')"

SENTINEL="/tmp/claude-memcheck-${SESSION_ID}"

# basic-memory call → mark and exit
case "$TOOL" in
  mcp__basic-memory__*)
    touch "$SENTINEL" 2>/dev/null
    exit 0
    ;;
esac

# Sentinel already exists → user has done a basic-memory call this session, silent
if [ -f "$SENTINEL" ]; then
  exit 0
fi

# Research-shaped tools — nag if no basic-memory yet
NAG=0
case "$TOOL" in
  WebSearch|WebFetch)
    NAG=1
    ;;
  Agent|Task)
    # Agent could be Explore/Plan/general-purpose — assume nag for now
    NAG=1
    ;;
  mcp__perplexity-comet__*)
    NAG=1
    ;;
esac

if [ "$NAG" = "1" ]; then
  cat >&2 <<'EOF'
⚠️  MEMORY-FIRST nag (one-time per session)

You're about to call a research/web/agent tool but you have NOT called
mcp__basic-memory__search_notes yet this session.

Per the Memory-First Protocol (~/CLAUDE.md → Memory Protocol; surfaced at
SessionStart), basic-memory comes FIRST so you don't redo work that's already
captured in the vault. Cancel this call and run instead:

  mcp__basic-memory__search_notes(project="timed-brain", query="<your query>")

  → If results are empty: "no prior knowledge", THEN run the tool you tried.
  → If non-empty: read the top 1–2 hits FIRST, cite them, decide if fresh
    research is still needed.

(After your first basic-memory call this session, this nag goes silent.)

If basic-memory MCP tools aren't loaded yet:
  ToolSearch query="select:mcp__basic-memory__search_notes,mcp__basic-memory__recent_activity,mcp__basic-memory__read_note"
EOF
fi

# Always exit 0 — never block. The nag is the enforcement.
exit 0
