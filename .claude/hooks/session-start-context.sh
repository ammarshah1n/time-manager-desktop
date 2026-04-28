#!/usr/bin/env bash
# SessionStart hook — injects session continuity context AND memory-first reminder.
# Loads (in order):
#   1. MEMORY-FIRST PROTOCOL block + live timed-brain snapshot (visible at top)
#   2. HANDOFF.md from vault
#   3. Last SESSION_LOG.md entry
#   4. BUILD_STATE.md architecture summary
#   5. PARKED.md picker (if exists — parallel-session collision fix)
# Budget: <250 lines emitted, <2s runtime.

set -uo pipefail

VAULT="$HOME/Timed-Brain"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_SLUG="-Users-integrale-time-manager-desktop"
PROJECT_DIR="$HOME/.claude/projects/$PROJECT_SLUG"
PARKED_FILE="$PROJECT_DIR/PARKED.md"
TRACK="${TIMED_TRACK:-}"

build_context() {
  printf '# Session Context (auto-loaded)\n\n'

  # ──────── MEMORY-FIRST PROTOCOL — enforced, visible, with live snapshot ────────
  printf '## ⚠️  MEMORY-FIRST PROTOCOL (enforced — read before acting)\n\n'
  printf 'Before ANY of the following actions in this session you MUST first call basic-memory:\n\n'
  printf '  • Web research — `WebSearch`, `WebFetch`, `/comet`, `mcp__perplexity-comet__*`\n'
  printf '  • Architecture / code / decision questions about Timed (current or historical)\n'
  printf '  • Spawning research subagents (`Agent` with general-purpose / Explore for research)\n'
  printf '  • Saying "I do not have prior context on X" or "let me look that up"\n\n'
  printf 'Required first calls (load schemas via `ToolSearch select:mcp__basic-memory__search_notes,mcp__basic-memory__recent_activity,mcp__basic-memory__read_note` if deferred):\n\n'
  printf '```\n'
  printf 'mcp__basic-memory__search_notes(project="timed-brain", query="<your query>")\n'
  printf 'mcp__basic-memory__recent_activity(project="timed-brain", timeframe="14d")  # for "what was I working on"\n'
  printf '```\n\n'
  printf 'AIF questions → also search `project="aif-vault"`. Cross-project → `brain-meta`.\n'
  printf 'Empty results = "no prior knowledge", THEN proceed to web/comet.\n'
  printf 'Non-empty = read top 1–2 hits FIRST, cite them, decide if fresh research is still needed.\n\n'
  printf 'A PreToolUse hook (`memory-gate.sh`) will nag on the FIRST research tool call this session if you skip this — that nag is your reminder, do not ignore it.\n\n'

  # Live snapshot — proves the memory exists and is alive
  if [ -d "$VAULT" ]; then
    NOTE_COUNT=$(find "$VAULT" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    LAST_WRITES=$(find "$VAULT" -name "*.md" -type f -exec stat -f "%m %N" {} \; 2>/dev/null \
                  | sort -rn | head -3 \
                  | awk -v v="$VAULT/" '{$1=""; sub(/^ /, ""); sub(v, ""); print "    • " $0}')
    printf '**timed-brain snapshot:** %s notes total. Last 3 writes:\n%s\n\n' "$NOTE_COUNT" "$LAST_WRITES"
  fi

  printf -- '─────────────────────────────────────────────────────────────────\n\n'

  # ──────── existing continuity context ────────
  if [ -f "$VAULT/HANDOFF.md" ]; then
    printf '## HANDOFF (from last session)\n'
    cat "$VAULT/HANDOFF.md"
    printf '\n'
  else
    printf '## HANDOFF: not found at %s/HANDOFF.md\n\n' "$VAULT"
  fi

  if [ -f "$PROJECT_ROOT/SESSION_LOG.md" ]; then
    printf '## Last Session Log Entry\n'
    awk '
      /^## Session:/     { found=1; block="" }
      found {
        if (/^### (Modified Files|Commits This Session)/) { found=0 }
        else { block = block $0 "\n" }
      }
      /^---$/ {
        if (found) last = block
        found = 0; block = ""
      }
      END { if (block != "") print block; else print last }
    ' "$PROJECT_ROOT/SESSION_LOG.md" | head -30
    printf '\n'
  fi

  if [ -f "$PROJECT_ROOT/BUILD_STATE.md" ]; then
    printf '## Build State Summary\n'
    head -1 "$PROJECT_ROOT/BUILD_STATE.md"
    printf '\n'
    awk '/^## Architecture Status/,/^## [^A]/' "$PROJECT_ROOT/BUILD_STATE.md" | head -25
  fi

  # ──────── PARKED.md picker (parallel-session handoff) ────────
  if [ -f "$PARKED_FILE" ]; then
    printf '\n## 🅿️  Parked tracks (multi-session handoff registry)\n\n'

    ROWS=$(awk -F'|' '
      /^\| / && !/^\| Track / && !/^\|---/ { count++ }
      END { print count+0 }
    ' "$PARKED_FILE")

    if [ "$ROWS" = "0" ]; then
      printf '  (no parked tracks — fresh session)\n\n'
    elif [ "$ROWS" = "1" ]; then
      HANDOFF_REL=$(awk -F'|' '
        /^\| / && !/^\| Track / && !/^\|---/ {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", $5)
          gsub(/`/, "", $5)
          print $5
          exit
        }' "$PARKED_FILE")
      TRACK_NAME=$(awk -F'|' '
        /^\| / && !/^\| Track / && !/^\|---/ {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
          print $2
          exit
        }' "$PARKED_FILE")
      printf '  → 1 parked track ("%s"). Auto-loading handoff:\n\n' "$TRACK_NAME"
      if [ -f "$PROJECT_DIR/$HANDOFF_REL" ]; then
        printf '### Resume target — track=%s\n\n' "$TRACK_NAME"
        cat "$PROJECT_DIR/$HANDOFF_REL"
        printf '\n\n**On your first message, open with: "Resuming %s — {one-sentence resume instruction from above}. Say resume / go / do it."**\n\n' "$TRACK_NAME"
      else
        printf '  (handoff file missing: %s)\n\n' "$HANDOFF_REL"
      fi
    else
      if [ -n "$TRACK" ]; then
        HANDOFF_REL=$(awk -F'|' -v t="$TRACK" '
          /^\| / && !/^\| Track / && !/^\|---/ {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            if ($2 == t) {
              gsub(/^[[:space:]]+|[[:space:]]+$/, "", $5)
              gsub(/`/, "", $5)
              print $5
              exit
            }
          }' "$PARKED_FILE")
        if [ -n "$HANDOFF_REL" ] && [ -f "$PROJECT_DIR/$HANDOFF_REL" ]; then
          printf '  → TIMED_TRACK=%s filter matched. Loading: `%s`\n\n' "$TRACK" "$HANDOFF_REL"
          printf '### Resume target — track=%s\n\n' "$TRACK"
          cat "$PROJECT_DIR/$HANDOFF_REL"
        else
          printf '  → TIMED_TRACK=%s set but no parked row matches. Showing registry:\n\n' "$TRACK"
          cat "$PARKED_FILE"
        fi
      else
        printf '**MULTIPLE PARKED TRACKS — before responding to anything else, you MUST call `AskUserQuestion`** with the parked tracks below as options (plus "start fresh"). After the user picks, `Read` the corresponding handoff file under `~/.claude/projects/%s/`. Do NOT load handoff content until the user picks.\n\n' "$PROJECT_SLUG"
        cat "$PARKED_FILE"
      fi
    fi
  fi
}

CONTEXT="$(build_context)"

# Emit as JSON envelope. Fall back to plain text if python3 missing.
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$CONTEXT" | python3 -c '
import json, sys
payload = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.stdin.read()}}
print(json.dumps(payload))
'
else
  escaped="${CONTEXT//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  escaped="${escaped//$'\n'/\\n}"
  escaped="${escaped//$'\t'/\\t}"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped"
fi
