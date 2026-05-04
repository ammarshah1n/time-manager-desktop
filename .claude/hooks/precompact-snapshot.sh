#!/usr/bin/env bash
# PreCompact hook — captures in-flight session state before compaction collapses detail.
#
# Why: Stop hook is too late — by Stop, auto-compaction may have already summarized
# the working set away. PreCompact fires *before* compaction, so we can:
#   1. Snapshot the in-flight state (last prompt, last assistant turn, edited files,
#      open TodoWrite items) to $PROJECT_ROOT/.claude/precompact-state.md
#   2. Return additionalContext to bias the compaction summarizer toward preserving
#      that state verbatim instead of paraphrasing it away
#
# Triggered by: settings.json PreCompact entry (manual /compact + auto-compact).

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATE_FILE="$PROJECT_ROOT/.claude/precompact-state.md"

mkdir -p "$(dirname "$STATE_FILE")"

# Read full payload from stdin once, hand it to Python via env var. (Heredoc + `python3 -`
# would conflict on stdin — the heredoc IS the script, the env var carries the JSON.)
export PRECOMPACT_PAYLOAD="$(cat)"

python3 - "$STATE_FILE" <<'PY'
import json, os, sys, datetime

STATE_FILE = sys.argv[1]

try:
    payload = json.loads(os.environ.get("PRECOMPACT_PAYLOAD", "") or "{}")
except Exception:
    payload = {}

transcript = payload.get("transcript_path") or ""
trigger = payload.get("trigger") or "unknown"
session_id = payload.get("session_id") or ""

last_user = ""
last_assistant = ""
files = []
seen = set()
todos_snapshot = []

if transcript and os.path.exists(transcript):
    try:
        with open(transcript) as f:
            for line in f:
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                t = obj.get("type")
                if t == "user":
                    content = obj.get("message", {}).get("content", "")
                    if isinstance(content, list):
                        content = " ".join(
                            c.get("text", "")
                            for c in content
                            if isinstance(c, dict) and c.get("type") == "text"
                        )
                    if isinstance(content, str) and content.strip():
                        last_user = content
                elif t == "assistant":
                    content = obj.get("message", {}).get("content", [])
                    if isinstance(content, list):
                        text = " ".join(
                            c.get("text", "")
                            for c in content
                            if isinstance(c, dict) and c.get("type") == "text"
                        ).strip()
                        if text:
                            last_assistant = text
                        for c in content:
                            if not isinstance(c, dict) or c.get("type") != "tool_use":
                                continue
                            name = c.get("name", "")
                            inp = c.get("input", {}) or {}
                            if name in ("Edit", "Write", "Read", "NotebookEdit"):
                                fp = inp.get("file_path") or inp.get("path")
                                if fp and fp not in seen:
                                    seen.add(fp)
                                    files.append((name, fp))
                            elif name == "TodoWrite":
                                items = inp.get("todos") or []
                                if isinstance(items, list):
                                    todos_snapshot = items[:20]
    except Exception:
        pass

files = files[-15:]


def fmt_todos(items):
    out = []
    for it in items:
        if not isinstance(it, dict):
            continue
        status = it.get("status", "?")
        text = it.get("content") or it.get("text") or ""
        out.append(f"  - [{status}] {text}")
    return "\n".join(out) if out else "  (none captured)"


def fmt_files(items):
    return "\n".join(f"  - {n}: {p}" for n, p in items) or "  (none)"


state_md = f"""# PreCompact State Snapshot

_Captured: {datetime.datetime.now().isoformat(timespec='seconds')} | trigger: {trigger} | session: {session_id[:8]}_

Written by the PreCompact hook just before context compaction. The post-compact
session can re-load from here if compaction summarised the working set away.

## Last user prompt

{last_user[:3000] or '(none captured)'}

## Last assistant message

{last_assistant[:3000] or '(none captured)'}

## Recently-touched files (last 15 unique)

{fmt_files(files)}

## TodoWrite snapshot (last seen)

{fmt_todos(todos_snapshot)}
"""

with open(STATE_FILE, "w") as f:
    f.write(state_md)

file_list = ", ".join(p for _, p in files[-8:]) if files else "(none)"

ctx = f"""COMPACTION IS HAPPENING NOW (trigger: {trigger}).

The compacted summary MUST preserve, verbatim where possible:

1. The user's most recent ask (the last user message before this compaction).
2. The active in-flight work — files being edited or read: {file_list}.
3. Any uncommitted code changes mentioned in the last 5 assistant turns.
4. The current hypothesis or decision being implemented.
5. Open TodoWrite items if any were tracked.

A full snapshot has been written to {STATE_FILE} for post-compact recovery.
Reference it by path rather than re-summarising its contents.
"""

print(
    json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreCompact",
                "additionalContext": ctx,
            }
        }
    )
)
PY
