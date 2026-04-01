# Hooks & Guards

## Configured in settings.json

| Event | Script | What It Does |
|-------|--------|-------------|
| PreToolUse (all tools) | `.claude/hooks/permission-check.sh` | 3-tier autopilot safety: auto-approve reads, auto-deny destructive ops (db reset, force push, rm -rf, .env writes), pass-through ambiguous |

## Guard Scripts (on disk, not wired to settings.json — wire up when needed)

| Script | Purpose | Wire As |
|--------|---------|---------|
| `.claude/guards/file-write-guard.sh` | Blocks writes outside Sources/, Tests/, supabase/, docs/, .claude/ | PreToolUse (Write/Edit) |
| `.claude/guards/no-raw-sql.sh` | Blocks psql/db execute/db reset --linked | PreToolUse (Bash) |

## PostToolUse Hooks (on disk, not wired)

| Script | Purpose | Wire As |
|--------|---------|---------|
| `.claude/hooks/post-write-check.sh` | Runs swift build after .swift file writes | PostToolUse (Write) |
| `.claude/hooks/write-obsidian-walkthrough.sh` | Writes session walkthrough to Timed-Brain/01 - Walkthroughs/ | Stop |

## To enable a guard, add to .claude/settings.json:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{ "type": "command", "command": "bash .claude/guards/file-write-guard.sh", "timeout": 5 }]
      }
    ]
  }
}
```

## Notes
- `write-obsidian-walkthrough.sh` path already updated to `~/Timed-Brain/` — ready to wire before wiring up
- Guards are passive (warn, don't block on unknown paths) during early dev — tighten before autopilot use
