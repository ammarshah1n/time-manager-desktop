#!/usr/bin/env bash
# taskflow status — progress dashboard

cmd_status() {
  if [[ ! -f "$TASKS_FILE" ]]; then
    echo "Error: No tasks.json found. Run 'taskflow parse' first." >&2
    exit 1
  fi

  local project_name
  project_name=$(jq -r '.projectName // "Project"' "$TASKS_FILE")

  local total complete in_progress blocked pending failed
  total=$(jq '.tasks | length' "$TASKS_FILE")
  complete=$(jq '[.tasks[] | select(.status == "complete")] | length' "$TASKS_FILE")
  in_progress=$(jq '[.tasks[] | select(.status == "in-progress")] | length' "$TASKS_FILE")
  blocked=$(jq '[.tasks[] | select(.status == "blocked")] | length' "$TASKS_FILE")
  failed=$(jq '[.tasks[] | select(.status == "failed")] | length' "$TASKS_FILE")
  pending=$(jq '[.tasks[] | select(.status == "pending")] | length' "$TASKS_FILE")

  local total_tokens
  total_tokens=$(jq '[.tasks[].tokensUsed] | add // 0' "$TASKS_FILE")

  echo ""
  echo "$project_name — Task Progress"
  echo "$(printf '=%.0s' $(seq 1 $((${#project_name} + 18))))"
  echo "Total: $total  Complete: $complete  In Progress: $in_progress  Blocked: $blocked  Failed: $failed  Pending: $pending"
  echo "Tokens used: $total_tokens"
  echo ""

  # Per-FR progress bars
  local frs
  frs=$(jq -r '[.tasks[].fr] | unique | sort[]' "$TASKS_FILE" 2>/dev/null)

  if [[ -n "$frs" ]]; then
    while IFS= read -r fr; do
      [[ -z "$fr" || "$fr" == "null" ]] && continue

      local fr_total fr_complete
      fr_total=$(jq "[.tasks[] | select(.fr == \"$fr\")] | length" "$TASKS_FILE")
      fr_complete=$(jq "[.tasks[] | select(.fr == \"$fr\" and .status == \"complete\")] | length" "$TASKS_FILE")

      local pct=0
      if [[ "$fr_total" -gt 0 ]]; then
        pct=$(( fr_complete * 100 / fr_total ))
      fi

      # Build progress bar (10 chars wide)
      local filled=$(( pct / 10 ))
      local empty=$(( 10 - filled ))
      local bar=""
      for ((i=0; i<filled; i++)); do bar+="█"; done
      for ((i=0; i<empty; i++)); do bar+="░"; done

      # Check if blocked
      local fr_blocked
      fr_blocked=$(jq "[.tasks[] | select(.fr == \"$fr\" and .status == \"blocked\")] | length" "$TASKS_FILE")
      local suffix="($fr_complete/$fr_total tasks)"
      if [[ "$fr_blocked" -gt 0 ]]; then
        suffix="($fr_complete/$fr_total tasks, $fr_blocked blocked)"
      fi

      printf "  %-6s %s %3d%%  %s\n" "$fr" "$bar" "$pct" "$suffix"
    done <<< "$frs"
  fi

  echo ""

  # Show next available task
  local next_task
  next_task=$(jq -r '
    .tasks as $all |
    [.tasks[] | select(.status == "complete") | .id] as $done |
    [.tasks[] | select(
      .status == "pending" and
      ([.dependencies[] | select(. as $d | $done | index($d) | not)] | length) == 0
    )] | first | if . then "Next available: Task \(.id) — \"\(.title)\"" else "No tasks available" end
  ' "$TASKS_FILE")

  echo "$next_task"
  echo ""
}
