#!/usr/bin/env bash
# tools/watchdog/watchdog.sh — resurrects taskflow autopilot if it dies with work remaining
#
# Runs continuously. Intended to be managed by launchd (com.timed.watchdog.plist).
# Writes heartbeat to Timed-Brain vault every 5 minutes so you can check
# progress from Obsidian on your phone.

set -euo pipefail

TASKFLOW="${HOME}/time-manager-desktop/tools/taskflow/taskflow.sh"
PROJECT_ROOT="${HOME}/time-manager-desktop"
LOG_DIR="${PROJECT_ROOT}/logs"
VAULT_DEV_LOG="${HOME}/Timed-Brain/05 - Dev Log"
HEARTBEAT_INTERVAL=300   # seconds — write to vault every 5 min
CHECK_INTERVAL=60        # seconds — check if autopilot alive every 1 min
BUDGET_DAILY_TASKS=80    # hard stop: don't dispatch more than this per calendar day

mkdir -p "$LOG_DIR"
mkdir -p "$VAULT_DEV_LOG" 2>/dev/null || true

# ── Logging ──────────────────────────────────────────────────────────────────

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" | tee -a "${LOG_DIR}/watchdog.log"
  echo "$msg" >> "${VAULT_DEV_LOG}/watchdog.log" 2>/dev/null || true
}

# ── Heartbeat (written to vault) ─────────────────────────────────────────────

heartbeat() {
  local today
  today=$(date '+%Y-%m-%d')
  local heartbeat_file="${VAULT_DEV_LOG}/${today}-heartbeat.md"

  local pending_count done_count blocked_count
  pending_count=$("$TASKFLOW" status 2>/dev/null | grep -c "pending" || echo "?")
  done_count=$("$TASKFLOW" status 2>/dev/null | grep -c "complete" || echo "?")
  blocked_count=$("$TASKFLOW" status 2>/dev/null | grep -c "blocked" || echo "?")

  local next_task
  next_task=$("$TASKFLOW" next 2>/dev/null | grep "^TASK" | head -1 || echo "none pending")

  local last_dispatch_outcome
  last_dispatch_outcome=$(tail -1 "${LOG_DIR}/dispatch-history.jsonl" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('outcome','?'))" 2>/dev/null || echo "no dispatches yet")

  cat >> "$heartbeat_file" <<EOF
## $(date '+%H:%M:%S')
- pending: ${pending_count}  done: ${done_count}  blocked: ${blocked_count}
- next: ${next_task}
- last dispatch: ${last_dispatch_outcome}
EOF

  log "HEARTBEAT | pending:${pending_count} done:${done_count} blocked:${blocked_count} | ${next_task}"
}

# ── Budget guard ──────────────────────────────────────────────────────────────

dispatches_today() {
  local today
  today=$(date -u '+%Y-%m-%d')
  grep -c "\"started\":\"${today}" "${LOG_DIR}/dispatch-history.jsonl" 2>/dev/null || echo 0
}

# ── Process checks ───────────────────────────────────────────────────────────

is_autopilot_running() {
  pgrep -f "taskflow autopilot\|autopilot.sh" > /dev/null 2>&1
}

has_pending_tasks() {
  local next
  next=$("$TASKFLOW" next --json 2>/dev/null || echo "")
  [[ -n "$next" && "$next" != "null" ]]
}

# ── Main loop ─────────────────────────────────────────────────────────────────

log "Watchdog started (PID $$) — project: ${PROJECT_ROOT}"

last_heartbeat=0

while true; do
  now=$(date +%s)

  # Heartbeat
  if (( now - last_heartbeat >= HEARTBEAT_INTERVAL )); then
    heartbeat
    last_heartbeat=$now
  fi

  # Budget check
  local_dispatches=$(dispatches_today)
  if (( local_dispatches >= BUDGET_DAILY_TASKS )); then
    log "BUDGET | ${local_dispatches}/${BUDGET_DAILY_TASKS} tasks dispatched today. Watchdog standing by until tomorrow."
    sleep $HEARTBEAT_INTERVAL
    continue
  fi

  # Resurrection
  if ! is_autopilot_running; then
    if has_pending_tasks; then
      log "RESURRECT | Autopilot not running, pending tasks remain. Restarting..."
      nohup "$TASKFLOW" autopilot >> "${LOG_DIR}/autopilot.log" 2>&1 &
      log "RESURRECT | Autopilot restarted (PID $!)"
      sleep 10  # brief pause before next check
    else
      log "IDLE | No pending tasks. Watchdog standing by."
    fi
  fi

  sleep $CHECK_INTERVAL
done
