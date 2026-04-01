#!/usr/bin/env bash
# taskflow — fused task orchestration (Task Master AI + Ralph Wiggum)
# Pure bash + jq. No npm, no Python.

set -euo pipefail

TASKFLOW_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
COMMANDS_DIR="$TASKFLOW_DIR/commands"
CONFIG_FILE="$TASKFLOW_DIR/config.json"
TASKS_FILE="$TASKFLOW_DIR/tasks.json"

# Resolve project root (two levels up from tools/taskflow/)
PROJECT_ROOT="$(cd "$TASKFLOW_DIR/../.." && pwd)"

export TASKFLOW_DIR COMMANDS_DIR CONFIG_FILE TASKS_FILE PROJECT_ROOT

# Read config helper
config_get() {
  jq -r ".$1 // empty" "$CONFIG_FILE"
}
export -f config_get

usage() {
  cat <<'EOF'
taskflow — fused task orchestration

Usage:
  taskflow parse <prd-path>                    Parse PRD into tasks.json
  taskflow next [--json]                       Show next available task
  taskflow start <task-id>                     Begin task, output focused context
  taskflow complete <task-id> [--tokens N] [--turns N]   Mark task complete
  taskflow fail <task-id> --reason "message"   Mark task failed
  taskflow status                              Show progress dashboard
  taskflow autopilot [--tdd] [--max-tasks N]    Autonomous loop (Codex → Claude debug)
  taskflow dispatch <task-id>                  Run single task via Codex + Claude debug
  taskflow worktree <fr-name>                  Run FR in isolated worktree

Options:
  -h, --help    Show this help
  -v, --version Show version
EOF
}

version() {
  echo "taskflow 1.0.0"
}

# Route to subcommand
case "${1:-}" in
  parse|next|start|complete|fail|status|autopilot|dispatch|worktree)
    COMMAND="$1"
    shift
    source "$COMMANDS_DIR/$COMMAND.sh"
    cmd_"$COMMAND" "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  -v|--version)
    version
    ;;
  "")
    usage
    exit 1
    ;;
  *)
    echo "taskflow: unknown command '$1'" >&2
    echo "Run 'taskflow --help' for usage." >&2
    exit 1
    ;;
esac
