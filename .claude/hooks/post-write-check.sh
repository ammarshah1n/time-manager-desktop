#!/usr/bin/env bash
# PostToolUse: auto-check Swift compilation after file writes
# Only runs on .swift files

FILE_PATH="${CLAUDE_FILE_PATH:-$1}"

# Only check Swift files
[[ "$FILE_PATH" != *.swift ]] && exit 0

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ~/time-manager-desktop)" || exit 0

# Quick typecheck — don't block on failure, just report
swift build 2>&1 | tail -5
exit 0
