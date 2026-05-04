#!/usr/bin/env bash
# 3-Tier Permission Hook — reads hook event JSON from stdin (current Claude Code spec).
# Tier 1: Auto-approve (read-only tools)
# Tier 2: Auto-deny (destructive operations)
# Tier 3: Pass-through (Claude Code's normal permission flow)

INPUT_JSON="$(cat)"
TOOL="$(echo "$INPUT_JSON" | jq -r '.tool_name // ""')"
# All input fields concatenated — any destructive string in command, file_path, etc. will match.
INPUT="$(echo "$INPUT_JSON" | jq -r '.tool_input // {} | tostring')"

# ── TIER 1: Auto-approve (no prompt) ────────────────────────────────────────
case "$TOOL" in
  Read|Glob|Grep|WebFetch|WebSearch|TaskGet|TaskList|TaskOutput) exit 0 ;;
esac

# ── TIER 2: Auto-deny (catastrophic operations) ─────────────────────────────
# Supabase production resets
if echo "$INPUT" | grep -qE "supabase db reset|supabase db push.*--linked"; then
  echo "BLOCKED: supabase db reset/push-to-production not allowed in autopilot." >&2
  exit 2
fi

# Force push to main/master
if echo "$INPUT" | grep -qE "git push.*(--force|-f).*(main|master)|git push.*(main|master).*(--force|-f)"; then
  echo "BLOCKED: force push to main/master not allowed." >&2
  exit 2
fi

# .env file writes
if [[ "$TOOL" == "Write" || "$TOOL" == "Edit" ]]; then
  if echo "$INPUT" | grep -qE '\.env($|[^.a-zA-Z])'; then
    echo "BLOCKED: writes to .env files not allowed in autopilot." >&2
    exit 2
  fi
fi

# Migration deletion — only block actual bash file-deletion verbs targeting
# migration files. Previously also matched the word `delete`, which trips on
# legitimate SQL inside Write/Edit content (e.g. `on delete cascade`).
if [[ "$TOOL" == "Bash" ]] && \
   echo "$INPUT" | grep -qE "supabase/migrations/.*\.(sql|ts)" && \
   echo "$INPUT" | grep -qE "\\brm\\b|\\bunlink\\b"; then
  echo "BLOCKED: deleting migration files via bash not allowed." >&2
  exit 2
fi

# rm -rf anywhere in bash
if [[ "$TOOL" == "Bash" ]] && echo "$INPUT" | grep -qE 'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f|rm[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*r'; then
  echo "BLOCKED: rm -rf not allowed in autopilot." >&2
  exit 2
fi

# ── TIER 3: Pass-through ────────────────────────────────────────────────────
exit 0
