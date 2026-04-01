#!/usr/bin/env bash
# taskflow fail — mark task failed, circuit breaker logic

cmd_fail() {
  local task_id="${1:-}"
  local reason=""

  if [[ -z "$task_id" ]]; then
    echo "Usage: taskflow fail <task-id> --reason \"message\"" >&2
    exit 1
  fi
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$reason" ]]; then
    echo "Error: --reason is required." >&2
    exit 1
  fi

  if [[ ! -f "$TASKS_FILE" ]]; then
    echo "Error: No tasks.json found." >&2
    exit 1
  fi

  local max_retries
  max_retries=$(config_get maxRetries)
  max_retries="${max_retries:-3}"

  # Count existing failures for this task (from failureLog)
  local current_failures
  current_failures=$(jq ".tasks[] | select(.id == $task_id) | .failureLog | if type == \"array\" then length else 0 end" "$TASKS_FILE")

  local new_count=$((current_failures + 1))
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build failure entry
  local failure_entry
  failure_entry=$(jq -n --arg reason "$reason" --arg ts "$now" --argjson attempt "$new_count" '{
    attempt: $attempt,
    reason: $reason,
    timestamp: $ts
  }')

  # Update task — append to failureLog array
  local tmp
  tmp=$(mktemp)
  local new_status="failed"
  if [[ "$new_count" -ge "$max_retries" ]]; then
    new_status="blocked"
  fi

  jq "(.tasks[] | select(.id == $task_id)) |= (
    .status = \"$new_status\" |
    .failureLog = (if .failureLog == null then [] else (if .failureLog | type == \"array\" then .failureLog else [] end) end) + [$failure_entry]
  )" "$TASKS_FILE" > "$tmp" && mv "$tmp" "$TASKS_FILE"

  local task
  task=$(jq ".tasks[] | select(.id == $task_id)" "$TASKS_FILE")
  local title fr spec
  title=$(echo "$task" | jq -r '.title')
  fr=$(echo "$task" | jq -r '.fr // "N/A"')
  spec=$(echo "$task" | jq -r '.spec // "N/A"')

  echo "✗ Task $task_id failed (attempt $new_count/$max_retries): $title"
  echo "  Reason: $reason"

  # Write error to Obsidian
  _write_error "$task_id" "$title" "$fr" "$spec" "$reason" "$new_count" "$max_retries" "$task"

  if [[ "$new_count" -ge "$max_retries" ]]; then
    echo ""
    echo "⚠ CIRCUIT BREAKER: Task $task_id blocked after $max_retries failures"
    echo "  Manual intervention required."
  fi

  # Output failure count for autopilot to read
  echo "$new_count"
}

_write_error() {
  local task_id="$1" title="$2" fr="$3" spec="$4" reason="$5" attempt="$6" max_retries="$7" task="$8"
  local vault_path
  vault_path="$(config_get vaultPath)"
  vault_path="${vault_path/#\~/$HOME}"
  local err_dir="$vault_path/$(config_get errorDir)"
  local date_str
  date_str=$(date +%Y-%m-%d)

  mkdir -p "$err_dir"

  local ac
  ac=$(echo "$task" | jq -r '.acceptanceCriteria[] | "- [ ] \(.)"')

  local template
  template="$(cat "$TASKFLOW_DIR/templates/error.md")"
  template="${template//\{\{TASK_ID\}\}/$task_id}"
  template="${template//\{\{TASK_TITLE\}\}/$title}"
  template="${template//\{\{DATE\}\}/$date_str}"
  template="${template//\{\{FR\}\}/$fr}"
  template="${template//\{\{SPEC_FILE\}\}/$spec}"
  template="${template//\{\{REASON\}\}/$reason}"
  template="${template//\{\{ATTEMPT\}\}/$attempt}"
  template="${template//\{\{MAX_RETRIES\}\}/$max_retries}"
  template="${template//\{\{ACCEPTANCE_CRITERIA\}\}/$ac}"

  echo "$template" > "$err_dir/${date_str}-task-${task_id}-failure.md"
}
