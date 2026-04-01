#!/bin/bash
# SessionEnd hook: converts most recent .jsonl transcript to readable markdown
# Output: ~/Timed-Brain/05 - Dev Log/sessions/session-YYYY-MM-DD_HH-MM.md

DATE=$(date +%Y-%m-%d_%H-%M)
EXPORT_DIR="$HOME/Timed-Brain/05 - Dev Log/sessions"
PROJECT_SESSIONS="$HOME/.claude/projects/-Users-integrale-time-manager-desktop"

mkdir -p "$EXPORT_DIR"

# Find most recently modified .jsonl for this project
LATEST=$(ls -t "$PROJECT_SESSIONS"/*.jsonl 2>/dev/null | head -1)

if [ -z "$LATEST" ] || [ ! -f "$LATEST" ]; then
  echo "post-session-export: no .jsonl found, skipping"
  exit 0
fi

OUTFILE="$EXPORT_DIR/session-${DATE}.md"

echo "# Session $DATE" > "$OUTFILE"
echo "Source: $LATEST" >> "$OUTFILE"
echo "" >> "$OUTFILE"

python3 - <<'PYEOF' >> "$OUTFILE" 2>/dev/null
import json, sys, os

latest = os.environ.get('LATEST_JSONL', '')
if not latest:
    # Find it again inside python
    import glob
    files = sorted(glob.glob(os.path.expanduser(
        '~/.claude/projects/-Users-integrale-time-manager-desktop/*.jsonl'
    )), key=os.path.getmtime, reverse=True)
    latest = files[0] if files else ''

if not latest:
    sys.exit(0)

with open(latest) as f:
    for line in f:
        try:
            entry = json.loads(line)
            # Handle message wrapper
            msg = entry.get('message', entry)
            role = msg.get('role', entry.get('type', 'system'))
            content = msg.get('content', '')
            if isinstance(content, list):
                parts = []
                for c in content:
                    if isinstance(c, dict):
                        parts.append(c.get('text', ''))
                    elif isinstance(c, str):
                        parts.append(c)
                content = '\n'.join(parts)
            if content and str(content).strip():
                print(f'## {str(role).upper()}')
                print(str(content)[:4000])
                print()
        except Exception:
            pass
PYEOF

LINES=$(wc -l < "$OUTFILE")
echo "post-session-export: wrote $LINES lines to $OUTFILE"
