#!/usr/bin/env bash
# memory-gate.sh v2 — content-aware PreToolUse gate.
#
# Goal: route through basic-memory FIRST so we leverage 1198+ vault notes,
# but never become a roadblock. Once memory is checked (even if it returned
# nothing useful), the gate steps aside and lets Claude burn whatever tokens
# the task actually needs.
#
# Decision tree:
#   1. mcp__basic-memory__*    → touch sentinel, exit 0   (mark vault searched)
#   2. Not Agent/Task/WebSearch/WebFetch/comet → exit 0    (gate doesn't fire)
#   3. Sentinel exists         → inject light reminder via additionalContext, allow
#   4. Prompt is syntax-shaped → exit 0                    (refactor/rename/format bypass)
#   5. Prompt is research-shaped + no sentinel → BLOCK (exit 2) with actionable reason
#   6. Ambiguous (no clear signal) → exit 0                (default-pass, friction-averse)
#
# Block reason text is fed back to Claude as a model-visible message,
# so Claude self-corrects without user intervention.
#
# Avoids known Claude Code bugs:
#   • No `permissionDecision: "allow"` (GH #16598 — intermittent crash).
#   • No `updatedInput` on Agent (GH #39814 — silently dropped).

set -uo pipefail

INPUT_JSON="$(cat)"
TOOL="$(echo "$INPUT_JSON" | jq -r '.tool_name // ""')"
SESSION_ID="$(echo "$INPUT_JSON" | jq -r '.session_id // "unknown"')"
SENTINEL="/tmp/claude-memcheck-${SESSION_ID}"

# ── 1. basic-memory call → mark sentinel and exit ─────────────────────────────
case "$TOOL" in
  mcp__basic-memory__*)
    touch "$SENTINEL" 2>/dev/null
    exit 0
    ;;
esac

# ── 2. Not a research-class tool → silent pass-through ────────────────────────
case "$TOOL" in
  WebSearch|WebFetch|Agent|Task|mcp__comet_bridge__*|mcp__comet-bridge__*)
    : # fall through to gate logic
    ;;
  *)
    exit 0
    ;;
esac

# ── 3. Sentinel exists → inject a light reminder, allow ───────────────────────
# Vault was already searched this session. Don't block, just nudge reuse.
if [ -f "$SENTINEL" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[memory-gate] basic-memory was already called this session. Reuse those vault hits before spawning new research where possible."}}'
  exit 0
fi

# ── 4. Sentinel absent — inspect prompt for intent ────────────────────────────
PROMPT="$(echo "$INPUT_JSON" | jq -r '.tool_input.prompt // .tool_input.query // .tool_input.description // ""' 2>/dev/null)"

# Syntax / mechanical patterns → safe to bypass (vault has no opinion on these)
if echo "$PROMPT" | grep -qiE \
   '(refactor|rename|extract (function|method|class|variable)|move file|format(ting)?|lint|type.?check|add (test|spec)|fix(ing)? (test|build|lint|type)|update (import|dependency|version)|bump version|delete (file|function|class)|inline (function|variable))'; then
  exit 0
fi

# Research / discovery patterns → require vault check first
RESEARCH_SHAPED=0
if echo "$PROMPT" | grep -qiE \
   '(how (does|do|is|to)|what (is|are|was|were)|why (is|does|did|do)|when (did|was|will)|find (all|any|where|the)|search (for|the)|look(ing)? (for|up|into|at)|explore|investigate|understand|learn about|document(ation)?|https?://|api |endpoint|sdk |library|package |architecture|design|pattern|best practice)'; then
  RESEARCH_SHAPED=1
fi

if [ "$RESEARCH_SHAPED" = "1" ]; then
  # Hard-block with actionable reason fed to Claude via stderr.
  cat >&2 <<'EOF'
🧠 MEMORY-FIRST GATE — vault check required before this research-shaped call

Your basic-memory vault contains 1198+ notes covering this project's architecture,
prior decisions, bug history, and research. The current tool call looks research-shaped
but mcp__basic-memory__search_notes has NOT been called this session.

ACTION: Call mcp__basic-memory__search_notes first with a query relevant to the task.

  mcp__basic-memory__search_notes(project="timed-brain", query="<terms>")

If the vault HAS the answer → use it, no further research needed.
If the vault DOESN'T have it → proceed with the original tool call. The sentinel
will be set after any basic-memory call (even one with empty results), so this
gate will stay out of your way for the rest of the session.

This is a one-time-per-session check. Burn tokens freely once memory has been queried.

(If basic-memory MCP isn't loaded: ToolSearch query="select:mcp__basic-memory__search_notes,mcp__basic-memory__recent_activity,mcp__basic-memory__read_note")
EOF
  exit 2
fi

# ── 5. Ambiguous → default-pass (friction-averse) ─────────────────────────────
exit 0
