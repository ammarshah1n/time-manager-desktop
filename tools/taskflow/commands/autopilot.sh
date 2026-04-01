#!/usr/bin/env bash
# taskflow autopilot — autonomous execution loop (Ralph fusion)

cmd_autopilot() {
  local tdd_mode=false
  local max_tasks
  max_tasks=$(config_get defaultMaxTasks)
  max_tasks="${max_tasks:-15}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tdd) tdd_mode=true; shift ;;
      --max-tasks) max_tasks="${2:-15}"; shift 2 ;;
      *) shift ;;
    esac
  done

  echo "═══════════════════════════════════════════════════"
  echo "  taskflow autopilot  [Codex → build verify → Claude debug]"
  echo "  Max tasks: $max_tasks  |  Started: $(date)"
  echo "═══════════════════════════════════════════════════"
  echo ""

  local tasks_done=0

  while true; do
    # Get next available task
    local next_json
    next_json=$(cmd_next --json 2>/dev/null) || true

    if [[ -z "$next_json" || "$next_json" == "null" ]]; then
      echo ""
      echo "All tasks complete or blocked. Exiting autopilot."
      break
    fi

    local task_id
    task_id=$(echo "$next_json" | jq -r '.id')
    local task_title
    task_title=$(echo "$next_json" | jq -r '.title')

    echo "────────────────────────────────────────"
    echo "Starting task $task_id: $task_title"
    echo "$(date)"
    echo "────────────────────────────────────────"

    # Mark in-progress
    cmd_start "$task_id" > /dev/null

    # Dispatch: Codex builds, Claude debugs on failure
    source "$COMMANDS_DIR/dispatch.sh"
    local dispatch_rc=0
    cmd_dispatch "$task_id" || dispatch_rc=$?

    if [[ $dispatch_rc -eq 0 ]]; then
      echo "  ✓ Task $task_id completed"
      cmd_complete "$task_id"
    else
      # dispatch already logged failures and triggered circuit breaker if needed
      echo "  ⚠ Task $task_id failed (dispatch returned $dispatch_rc). Continuing to next task..."
    fi

    tasks_done=$((tasks_done + 1))
    if [[ "$tasks_done" -ge "$max_tasks" ]]; then
      echo ""
      echo "Max tasks ($max_tasks) reached. Exiting autopilot."
      break
    fi
  done

  # Write summary
  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  Autopilot session complete"
  echo "  Tasks attempted: $tasks_done"
  echo "  Ended: $(date)"
  echo "═══════════════════════════════════════════════════"

  # Write summary to Obsidian
  local vault_path
  vault_path="$(config_get vaultPath)"
  vault_path="${vault_path/#\~/$HOME}"
  local wt_dir="$vault_path/$(config_get walkthroughDir)"
  mkdir -p "$wt_dir"
  cmd_status > "$wt_dir/$(date +%Y-%m-%d)-autopilot-summary.md"
  echo "Summary written to $wt_dir/$(date +%Y-%m-%d)-autopilot-summary.md"
}
