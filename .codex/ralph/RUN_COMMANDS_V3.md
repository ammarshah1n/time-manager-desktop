# Timed — Ralph Loop V3 Run Commands (STORY-016 to STORY-030)

## Terminal 1 — Main Loop

```bash
cd /Users/ammarshahin/time-manager-desktop

~/.codex/skills/codex-ralph/scripts/ralph.sh \
  --skill-file .codex/ralph/TIMED_SKILL.md \
  --branch ralph/timed-v3 \
  --max-iterations 300 \
  --max-attempts 4 \
  --skip-security \
  2>&1 | tee .codex/ralph/run_v3.log
```

## Terminal 2 — Watchdog

```bash
~/.codex/skills/codex-ralph/scripts/ralph-watchdog.sh \
  --repo /Users/ammarshahin/time-manager-desktop \
  --stale-mins 25 \
  --ralph-cmd "~/.codex/skills/codex-ralph/scripts/ralph.sh \
    --skill-file .codex/ralph/TIMED_SKILL.md \
    --branch ralph/timed-v3 \
    --max-iterations 300 \
    --max-attempts 4 \
    --skip-security"
```

## Terminal 3 — Monitor

```bash
watch -n 10 "jq -r '.userStories[] | select(.id | test(\"STORY-01[6-9]|STORY-0[23]\")) | \"\(.id) [\(if .passes then \"DONE\" else \"    \" end)]: \(.title)\"' /Users/ammarshahin/time-manager-desktop/.codex/ralph/prd.json"
```

## Check progress

```bash
jq '[.userStories[] | select(.passes == false)] | length' /Users/ammarshahin/time-manager-desktop/.codex/ralph/prd.json
git log --oneline | head -20
```
