#!/usr/bin/env bash
# taskflow complete — mark task done, trigger hooks

cmd_complete() {
  local task_id="${1:-}"
  local tokens=0 turns=0

  if [[ -z "$task_id" ]]; then
    echo "Usage: taskflow complete <task-id> [--tokens N] [--turns N]" >&2
    exit 1
  fi
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tokens) tokens="${2:-0}"; shift 2 ;;
      --turns)  turns="${2:-0}"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ ! -f "$TASKS_FILE" ]]; then
    echo "Error: No tasks.json found." >&2
    exit 1
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Update task
  local tmp
  tmp=$(mktemp)
  jq "(.tasks[] | select(.id == $task_id)) |= (
    .status = \"complete\" |
    .completedAt = \"$now\" |
    .tokensUsed = $tokens |
    .turnsUsed = $turns
  )" "$TASKS_FILE" > "$tmp" && mv "$tmp" "$TASKS_FILE"

  local task
  task=$(jq ".tasks[] | select(.id == $task_id)" "$TASKS_FILE")
  local title fr spec description
  title=$(echo "$task" | jq -r '.title')
  fr=$(echo "$task" | jq -r '.fr // "N/A"')
  spec=$(echo "$task" | jq -r '.spec // "N/A"')
  description=$(echo "$task" | jq -r '.description')

  echo "✓ Task $task_id marked complete: $title"

  # Write walkthrough to Obsidian
  _write_walkthrough "$task_id" "$title" "$fr" "$spec" "$description" "$tokens" "$turns" "$task"

  # Update PLAN.md
  _update_plan

  # Show next task
  echo ""
  cmd_next 2>/dev/null || true
}

_write_walkthrough() {
  local task_id="$1" title="$2" fr="$3" spec="$4" description="$5" tokens="$6" turns="$7" task="$8"
  local vault_path
  vault_path="$(config_get vaultPath)"
  vault_path="${vault_path/#\~/$HOME}"
  local wt_dir="$vault_path/$(config_get walkthroughDir)"
  local date_str
  date_str=$(date +%Y-%m-%d)

  if [[ ! -d "$vault_path" ]]; then
    mkdir -p "$wt_dir"
  fi
  mkdir -p "$wt_dir"

  local ac
  ac=$(echo "$task" | jq -r '.acceptanceCriteria[] | "- [x] \(.)"')

  local template
  template="$(cat "$TASKFLOW_DIR/templates/walkthrough.md")"
  template="${template//\{\{TASK_ID\}\}/$task_id}"
  template="${template//\{\{TASK_TITLE\}\}/$title}"
  template="${template//\{\{DATE\}\}/$date_str}"
  template="${template//\{\{FR\}\}/$fr}"
  template="${template//\{\{SPEC_FILE\}\}/$spec}"
  template="${template//\{\{DESCRIPTION\}\}/$description}"
  template="${template//\{\{TOKENS\}\}/$tokens}"
  template="${template//\{\{TURNS\}\}/$turns}"
  template="${template//\{\{ACCEPTANCE_CRITERIA\}\}/$ac}"

  echo "$template" > "$wt_dir/${date_str}-task-${task_id}.md"
  echo "  → Walkthrough written to $wt_dir/${date_str}-task-${task_id}.md"
}

_update_plan() {
  local plan_file="$PROJECT_ROOT/$(config_get planFile)"
  if [[ ! -f "$plan_file" ]]; then
    return
  fi

  local total complete blocked pending
  total=$(jq '.tasks | length' "$TASKS_FILE")
  complete=$(jq '[.tasks[] | select(.status == "complete")] | length' "$TASKS_FILE")
  blocked=$(jq '[.tasks[] | select(.status == "blocked")] | length' "$TASKS_FILE")
  pending=$(jq '[.tasks[] | select(.status == "pending")] | length' "$TASKS_FILE")

  local progress_line="**taskflow progress:** $complete/$total complete, $blocked blocked, $pending pending — $(date +%Y-%m-%d\ %H:%M)"

  # Append or update progress line in PLAN.md
  if grep -q "^\*\*taskflow progress:\*\*" "$plan_file" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    sed "s/^\*\*taskflow progress:\*\*.*/$(echo "$progress_line" | sed 's/[&/\]/\\&/g')/" "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"
  else
    echo "" >> "$plan_file"
    echo "$progress_line" >> "$plan_file"
  fi
}
