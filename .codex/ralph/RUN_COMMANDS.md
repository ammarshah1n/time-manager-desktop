# Timed — Ralph Loop Run Commands

## Terminal 1 — Main Loop (open this first)

```bash
cd /Users/ammarshahin/time-manager-desktop

~/.codex/skills/codex-ralph/scripts/ralph.sh \
  --skill-file .codex/ralph/TIMED_SKILL.md \
  --branch ralph/timed-v2 \
  --max-iterations 300 \
  --max-attempts 4 \
  --skip-security \
  2>&1 | tee .codex/ralph/run.log
```

## Terminal 2 — Monitor (open alongside Terminal 1)

```bash
# Watch live events
tail -f /Users/ammarshahin/time-manager-desktop/.codex/ralph/events.log

# OR watch story progress
watch -n 10 "jq -r '.userStories[] | \"\(.id) [\(if .passes then \"DONE\" else \"    \" end)]: \(.title)\"' /Users/ammarshahin/time-manager-desktop/.codex/ralph/prd.json"
```

## Check progress anytime

```bash
# Count remaining stories
jq '[.userStories[] | select(.passes == false)] | length' /Users/ammarshahin/time-manager-desktop/.codex/ralph/prd.json

# See what's been committed
cd /Users/ammarshahin/time-manager-desktop && git log --oneline | head -20
```

## Force-skip a blocked story

```bash
jq '(.userStories[] | select(.id == "STORY-003")).passes = true' \
  /Users/ammarshahin/time-manager-desktop/.codex/ralph/prd.json > /tmp/prd_tmp.json && \
  mv /tmp/prd_tmp.json /Users/ammarshahin/time-manager-desktop/.codex/ralph/prd.json
```

## Stop and resume

Ctrl+C to stop. Re-run Terminal 1 command to resume from next incomplete story.
