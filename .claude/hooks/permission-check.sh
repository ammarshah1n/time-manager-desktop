#!/usr/bin/env bash
# 3-Tier Permission Hook for TimeBlock autopilot runs
# Tier 1: Auto-approve (read-only, safe)
# Tier 2: Auto-deny (destructive, irreversible)
# Tier 3: Pass-through (ambiguous — human decides at prompt)

TOOL="$1"
INPUT="$2"

# ── TIER 1: Auto-approve (no prompt) ────────────────────────────────────────
SAFE_TOOLS="Read|Glob|Grep|WebFetch|WebSearch|TaskGet|TaskList|TaskOutput"
if echo "$TOOL" | grep -qE "^($SAFE_TOOLS)$"; then
  exit 0
fi

# ── TIER 2: Auto-deny (catastrophic operations) ─────────────────────────────
# Supabase production resets
if echo "$INPUT" | grep -qE "supabase db reset|supabase db push.*--linked"; then
  echo "BLOCKED: supabase db reset/push-to-production is not allowed in autopilot." >&2
  exit 1
fi

# Force push to main/master
if echo "$INPUT" | grep -qE "git push.*(--force|-f).*(main|master)|git push.*(main|master).*(--force|-f)"; then
  echo "BLOCKED: force push to main/master is not allowed." >&2
  exit 1
fi

# .env file writes
if echo "$INPUT" | grep -qE '\.env($|[^.])'; then
  if [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ]; then
    echo "BLOCKED: writes to .env files are not allowed in autopilot." >&2
    exit 1
  fi
fi

# Migration deletion
if echo "$INPUT" | grep -qE "supabase/migrations/.*\.(sql|ts)"; then
  if echo "$INPUT" | grep -qE "^(rm|unlink|delete)"; then
    echo "BLOCKED: deleting migration files is not allowed." >&2
    exit 1
  fi
fi

# rm -rf anywhere
if echo "$INPUT" | grep -qE "rm\s+-[a-zA-Z]*r[a-zA-Z]*f|rm\s+-[a-zA-Z]*f[a-zA-Z]*r"; then
  echo "BLOCKED: rm -rf is not allowed in autopilot." >&2
  exit 1
fi

# ── TIER 3: Pass-through (human prompt handles it) ──────────────────────────
exit 0
