#!/usr/bin/env bash
# taskflow worktree — run FR in isolated git worktree

cmd_worktree() {
  local fr_name="${1:-}"
  if [[ -z "$fr_name" ]]; then
    echo "Usage: taskflow worktree <fr-name>" >&2
    echo "Example: taskflow worktree FR-01" >&2
    exit 1
  fi

  local fr_lower
  fr_lower=$(echo "$fr_name" | tr '[:upper:]' '[:lower:]')
  local worktree_path
  worktree_path="$(dirname "$PROJECT_ROOT")/timeblock-$fr_lower"
  local branch="feat/$fr_lower"

  echo "Creating worktree for $fr_name..."

  # Check if we're in a git repo
  if ! git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: Not a git repository." >&2
    exit 1
  fi

  # Create branch if it doesn't exist
  if ! git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    git -C "$PROJECT_ROOT" branch "$branch"
  fi

  # Create worktree
  if [[ -d "$worktree_path" ]]; then
    echo "Worktree already exists at $worktree_path"
  else
    git -C "$PROJECT_ROOT" worktree add "$worktree_path" "$branch"
  fi

  # Copy tasks.json and filter to only this FR's tasks
  mkdir -p "$worktree_path/tools/taskflow"
  cp "$CONFIG_FILE" "$worktree_path/tools/taskflow/config.json"
  cp -r "$TASKFLOW_DIR/templates" "$worktree_path/tools/taskflow/templates"
  cp -r "$TASKFLOW_DIR/commands" "$worktree_path/tools/taskflow/commands"
  cp "$TASKFLOW_DIR/taskflow.sh" "$worktree_path/tools/taskflow/taskflow.sh"

  # Filter tasks to only this FR (keep dependency tasks from other FRs too)
  jq --arg fr "$fr_name" '
    .tasks as $all |
    [.tasks[] | select(.fr == $fr)] as $fr_tasks |
    [$fr_tasks[].dependencies[]] as $dep_ids |
    .tasks = [.tasks[] | select(.fr == $fr or (.id as $id | $dep_ids | index($id)))]
  ' "$TASKS_FILE" > "$worktree_path/tools/taskflow/tasks.json"

  local task_count
  task_count=$(jq '.tasks | length' "$worktree_path/tools/taskflow/tasks.json")

  echo ""
  echo "✓ Worktree created:"
  echo "  Path:   $worktree_path"
  echo "  Branch: $branch"
  echo "  Tasks:  $task_count (filtered to $fr_name + dependencies)"
  echo ""
  echo "To run autopilot in this worktree:"
  echo "  cd $worktree_path && tools/taskflow/taskflow.sh autopilot --tdd"
}
