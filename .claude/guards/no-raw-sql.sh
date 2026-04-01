#!/usr/bin/env bash
# PreToolUse guard: block direct SQL execution against cloud databases
# Only allow SQL through migration files

CMD="${CLAUDE_TOOL_INPUT_COMMAND:-$1}"

# If no command provided, allow
[[ -z "$CMD" ]] && exit 0

# Block direct database commands
if echo "$CMD" | grep -qiE "(psql|supabase db execute|\.execute\(|supabase db reset --linked)"; then
  echo "BLOCKED: Direct SQL execution detected." >&2
  echo "All schema changes must go through supabase/migrations/ and 'supabase db push'" >&2
  exit 2
fi

exit 0
