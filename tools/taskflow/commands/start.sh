#!/usr/bin/env bash
# taskflow start — begin a task, output focused context for Claude

cmd_start() {
  local task_id="${1:-}"
  if [[ -z "$task_id" ]]; then
    echo "Usage: taskflow start <task-id>" >&2
    exit 1
  fi

  if [[ ! -f "$TASKS_FILE" ]]; then
    echo "Error: No tasks.json found." >&2
    exit 1
  fi

  # Validate task exists
  local task
  task=$(jq ".tasks[] | select(.id == $task_id)" "$TASKS_FILE")
  if [[ -z "$task" ]]; then
    echo "Error: Task $task_id not found." >&2
    exit 1
  fi

  # Set status to in-progress
  local tmp
  tmp=$(mktemp)
  jq "(.tasks[] | select(.id == $task_id)).status = \"in-progress\"" "$TASKS_FILE" > "$tmp" && mv "$tmp" "$TASKS_FILE"

  # Extract task fields
  local title description spec fr test_file
  title=$(echo "$task" | jq -r '.title')
  description=$(echo "$task" | jq -r '.description')
  spec=$(echo "$task" | jq -r '.spec // empty')
  fr=$(echo "$task" | jq -r '.fr // empty')
  test_file=$(echo "$task" | jq -r '.testFile // empty')

  # Build focused context
  echo "═══════════════════════════════════════════════════"
  echo "TASK $task_id: $title"
  echo "FR: $fr  |  Complexity: $(echo "$task" | jq -r '.complexity')"
  echo "═══════════════════════════════════════════════════"
  echo ""
  echo "## Description"
  echo "$description"
  echo ""

  # Acceptance criteria
  echo "## Acceptance Criteria"
  echo "$task" | jq -r '.acceptanceCriteria[] | "- [ ] \(.)"'
  echo ""

  # Test file
  if [[ -n "$test_file" ]]; then
    echo "## Test File"
    echo "$test_file"
    echo ""
  fi

  # Read spec file if it exists
  if [[ -n "$spec" ]]; then
    local spec_path="$PROJECT_ROOT/$spec"
    if [[ -f "$spec_path" ]]; then
      echo "## FR Spec ($spec)"
      echo '```'
      cat "$spec_path"
      echo '```'
      echo ""
    fi
  fi

  # List completed dependencies for context
  local deps
  deps=$(echo "$task" | jq -r '.dependencies[]' 2>/dev/null)
  if [[ -n "$deps" ]]; then
    echo "## Completed Dependencies"
    for dep_id in $deps; do
      jq -r ".tasks[] | select(.id == $dep_id) | \"- Task \(.id): \(.title) (status: \(.status))\"" "$TASKS_FILE"
    done
    echo ""
  fi

  # CLAUDE.md task system reminder
  echo "## Instructions"
  echo "When ALL acceptance criteria are met and code compiles/tests pass, output: TASK_COMPLETE"
  echo "If you are stuck after 3 attempts on the same error, output: TASK_BLOCKED"
  echo "Never work on tasks not assigned to you via taskflow start."
}
