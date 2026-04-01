#!/usr/bin/env bash
# Stop hook: write a walkthrough note to the Obsidian vault
# Called when Claude finishes a task

VAULT="$HOME/Timed-Brain/01 - Walkthroughs"
DATE=$(date '+%Y-%m-%d')
TIME=$(date '+%H:%M')
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ~/time-manager-desktop)"
BRANCH="$(cd "$REPO_ROOT" && git branch --show-current 2>/dev/null || echo 'unknown')"

# Get recent commits from this session (last 30 min)
RECENT_COMMITS="$(cd "$REPO_ROOT" && git log --oneline --since='30 minutes ago' 2>/dev/null || echo 'none')"

# Get changed files
CHANGED_FILES="$(cd "$REPO_ROOT" && git diff --name-only HEAD~3 HEAD 2>/dev/null | head -20 || echo 'none')"

# Generate filename
FILENAME="${DATE}-${BRANCH}.md"
FILEPATH="${VAULT}/${FILENAME}"

# If file already exists for this branch today, append
if [[ -f "$FILEPATH" ]]; then
  cat >> "$FILEPATH" <<EOF

---

## Session at ${TIME}

### Recent Commits
\`\`\`
${RECENT_COMMITS}
\`\`\`

### Changed Files
\`\`\`
${CHANGED_FILES}
\`\`\`

### Notes
_Claude: fill in WHAT was built, HOW data flows, WHERE files live, WHY this approach._

EOF
else
  cat > "$FILEPATH" <<EOF
# Walkthrough: ${BRANCH}
**Date:** ${DATE}
**Branch:** ${BRANCH}

## Session at ${TIME}

### WHAT was built


### HOW data flows through it


### WHERE files live
\`\`\`
${CHANGED_FILES}
\`\`\`

### Recent Commits
\`\`\`
${RECENT_COMMITS}
\`\`\`

### WHY this approach was chosen


### RULE SUGGESTION
_If a new rule should be added to 00 - Rules/, describe it here._

EOF
fi

echo "Walkthrough written: ${FILEPATH}"
