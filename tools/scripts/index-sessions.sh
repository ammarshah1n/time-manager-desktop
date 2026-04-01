#!/bin/bash
# Indexes all Claude Code session transcripts for the Timed project
# Converts raw .jsonl to readable .md and reports statistics
# Heavy extraction (decisions, prompts) → use codex-index-prompt.md in Codex, not here

PROJECT_SESSIONS="$HOME/.claude/projects/-Users-integrale-time-manager-desktop"
EXPORT_DIR="$HOME/Timed-Brain/05 - Dev Log/sessions"
CHANGELOG="$(git rev-parse --show-toplevel 2>/dev/null)/CHANGELOG.md"

mkdir -p "$EXPORT_DIR"

echo "=== Session Index $(date) ==="
echo "Source: $PROJECT_SESSIONS"
echo ""

TOTAL=0
NEW=0
SKIPPED=0

for SESSION in "$PROJECT_SESSIONS"/*.jsonl; do
  [ -f "$SESSION" ] || continue
  TOTAL=$((TOTAL + 1))

  BASENAME=$(basename "$SESSION" .jsonl)
  MTIME=$(date -r "$SESSION" +%Y-%m-%d_%H-%M 2>/dev/null || stat -f "%Sm" -t "%Y-%m-%d_%H-%M" "$SESSION" 2>/dev/null)
  MD_FILE="$EXPORT_DIR/session-${MTIME}-${BASENAME:0:8}.md"

  if [ -f "$MD_FILE" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "Exporting: $BASENAME → $(basename $MD_FILE)"

  echo "# Session $MTIME" > "$MD_FILE"
  echo "Source: $BASENAME" >> "$MD_FILE"
  echo "" >> "$MD_FILE"

  python3 - "$SESSION" <<'PYEOF' >> "$MD_FILE" 2>/dev/null
import json, sys

session_file = sys.argv[1]
with open(session_file) as f:
    for line in f:
        try:
            entry = json.loads(line)
            msg = entry.get('message', entry)
            role = msg.get('role', entry.get('type', ''))
            if role not in ('user', 'assistant', 'human', 'HUMAN'):
                continue
            content = msg.get('content', '')
            if isinstance(content, list):
                parts = []
                for c in content:
                    if isinstance(c, dict):
                        parts.append(c.get('text', ''))
                    elif isinstance(c, str):
                        parts.append(c)
                content = '\n'.join(filter(None, parts))
            content = str(content).strip()
            if content:
                print(f'## {role.upper()}')
                print(content[:5000])
                print()
        except Exception:
            pass
PYEOF

  NEW=$((NEW + 1))
done

echo ""
echo "Total sessions: $TOTAL"
echo "New exports:    $NEW"
echo "Skipped:        $SKIPPED"
echo ""
echo "For decision/prompt extraction, run tools/scripts/codex-index-prompt.md in Codex."
