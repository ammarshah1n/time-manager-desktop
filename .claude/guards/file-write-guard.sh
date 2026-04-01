#!/usr/bin/env bash
# PreToolUse guard: block writes outside allowed directories
# Reads CLAUDE_FILE_PATH from environment (set by Claude Code hooks)

FILE_PATH="${CLAUDE_FILE_PATH:-$1}"

# If no path provided, allow (non-file tool)
[[ -z "$FILE_PATH" ]] && exit 0

# Allowed write directories
ALLOWED_PATTERNS=(
  "Sources/"
  "Tests/"
  "supabase/"
  "Package.swift"
  ".claude/"
  "docs/"
  "scripts/"
  "PRD.md"
  "CLAUDE.md"
  "AGENTS.md"
)

for pattern in "${ALLOWED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    exit 0
  fi
done

# Block writes to cloud DB
if echo "$FILE_PATH" | grep -qiE '\.env|credentials|secret|\.pem|\.key'; then
  echo "BLOCKED: Cannot write to sensitive file: $FILE_PATH" >&2
  exit 1
fi

# For now, warn but don't block on unknown paths (during early dev)
echo "WARNING: Write to unusual path: $FILE_PATH" >&2
exit 0
