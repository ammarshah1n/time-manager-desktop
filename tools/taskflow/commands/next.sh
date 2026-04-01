#!/usr/bin/env bash
# taskflow next — find highest-priority available task

cmd_next() {
  local json_mode=false
  [[ "${1:-}" == "--json" ]] && json_mode=true

  if [[ ! -f "$TASKS_FILE" ]]; then
    echo "Error: No tasks.json found. Run 'taskflow parse' first." >&2
    exit 1
  fi

  # Find first pending task where all deps are complete
  local result
  result=$(jq -r '
    .tasks as $all |
    [.tasks[] | select(.status == "complete") | .id] as $done |
    [.tasks[] | select(
      .status == "pending" and
      ([.dependencies[] | select(. as $d | $done | index($d) | not)] | length) == 0
    )] | first
  ' "$TASKS_FILE")

  if [[ "$result" == "null" || -z "$result" ]]; then
    # Check if everything is done or something is blocking
    local total pending blocked complete in_progress
    total=$(jq '.tasks | length' "$TASKS_FILE")
    complete=$(jq '[.tasks[] | select(.status == "complete")] | length' "$TASKS_FILE")
    blocked=$(jq '[.tasks[] | select(.status == "blocked")] | length' "$TASKS_FILE")
    pending=$(jq '[.tasks[] | select(.status == "pending")] | length' "$TASKS_FILE")
    in_progress=$(jq '[.tasks[] | select(.status == "in-progress")] | length' "$TASKS_FILE")

    if [[ "$pending" -eq 0 && "$in_progress" -eq 0 ]]; then
      echo "All tasks complete (or blocked). $complete/$total done, $blocked blocked."
    else
      echo "No task available — blocked by incomplete dependencies."
      echo ""
      echo "Pending tasks waiting on:"
      jq -r '
        .tasks as $all |
        [.tasks[] | select(.status == "complete") | .id] as $done |
        .tasks[] | select(
          .status == "pending" and
          ([.dependencies[] | select(. as $d | $done | index($d) | not)] | length) > 0
        ) |
        "  Task \(.id): \(.title) — waiting on: \([.dependencies[] | select(. as $d | ($done | index($d) | not))] | map("task \(.)") | join(", "))"
      ' "$TASKS_FILE" | head -10
    fi
    exit 1
  fi

  if [[ "$json_mode" == true ]]; then
    echo "$result"
  else
    echo "$result" | jq -r '"
Next task: \(.id) — \(.title)
Complexity: \(.complexity)  |  FR: \(.fr)  |  Spec: \(.spec)
Dependencies: \(if .dependencies | length > 0 then .dependencies | map(tostring) | join(", ") else "none" end)

Acceptance Criteria:
\(.acceptanceCriteria | to_entries | map("  [\(if .value then "✓" else " " end)] \(.value)") | join("\n"))
"'
  fi
}
