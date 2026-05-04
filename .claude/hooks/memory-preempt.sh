#!/usr/bin/env bash
# memory-preempt.sh — UserPromptSubmit hook (Layer 1 of the memory-first system).
#
# Goal: once per session, inject a small reminder into Claude's context window
# pointing at the basic-memory vault. This is the "preempt" half of the design —
# Claude sees the reminder before deciding to spawn any research/agent tool, so
# vault-relevant work routes through memory naturally instead of needing a gate.
#
# Behaviour:
#   • First UserPromptSubmit of the session → emit additionalContext reminder, touch flag.
#   • Subsequent prompts → silent (flag exists).
#
# Cost: ~200 tokens, once per session. Fits well within noise.
# Reversible: deleting this hook restores prior behaviour exactly.

set -uo pipefail

INPUT_JSON="$(cat)"
SESSION_ID="$(echo "$INPUT_JSON" | jq -r '.session_id // "unknown"')"
FLAG="/tmp/claude-mem-preempt-${SESSION_ID}"

# Only inject once per session — second prompt onwards is silent.
if [ -f "$FLAG" ]; then
  exit 0
fi
touch "$FLAG" 2>/dev/null

# Inject the reminder. additionalContext goes straight into Claude's context window
# (visible to reasoning loop, unlike stderr).
jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "[memory-first protocol — auto-injected, once per session]\n\nYour basic-memory vault (project: timed-brain) holds 1198+ notes on this project: architecture, prior decisions, bug history, research, comet reports. Before spawning Agent/Task subagents or calling WebSearch/WebFetch/comet-bridge on anything project-related, call mcp__basic-memory__search_notes first. If the vault has the answer, use it. If it does not, proceed with whatever tool you were going to use — burn the tokens, that is the point. After ONE basic-memory call this session (even one returning no useful hits), the PreToolUse gate stays out of your way. This is a router, not a roadblock. Pure-syntax / refactor / rename / format work bypasses the gate entirely."
  }
}'

exit 0
