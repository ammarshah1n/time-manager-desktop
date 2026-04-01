#!/usr/bin/env bash
# taskflow dispatch — Codex-first execution with Claude debug fallback
#
# Flow:
#   1. Build Codex prompt (task context + AGENTS.md)
#   2. codex exec --full-auto
#   3. swift build && swift test
#   4. If fail → Claude --continue debug loop (up to 3 attempts)
#   5. If still failing → trigger circuit breaker (3x cmd_fail)
#
# Return codes:
#   0 — success (build + tests pass)
#   1 — task was already blocked before dispatch ran
#   3 — circuit breaker triggered (3 failures logged)

cmd_dispatch() {
  local task_id="${1:-}"
  if [[ -z "$task_id" ]]; then
    echo "Usage: taskflow dispatch <task-id>" >&2
    exit 1
  fi

  local dispatch_log="${PROJECT_ROOT}/logs/dispatch-history.jsonl"
  local codex_output="/tmp/taskflow-codex-${task_id}.txt"
  local build_log="/tmp/taskflow-build-${task_id}.txt"
  local start_time
  start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  mkdir -p "${PROJECT_ROOT}/logs"
  > "$codex_output"
  > "$build_log"

  # Check task isn't already blocked
  local current_status
  current_status=$(jq -r ".tasks[] | select(.id == $task_id) | .status" "$TASKS_FILE" 2>/dev/null || echo "unknown")
  if [[ "$current_status" == "blocked" ]]; then
    echo "  [dispatch] Task $task_id is already blocked. Skipping."
    return 1
  fi

  # --- Build Codex prompt ---
  local task
  task=$(jq ".tasks[] | select(.id == $task_id)" "$TASKS_FILE")
  local title description fr spec
  title=$(echo "$task" | jq -r '.title')
  description=$(echo "$task" | jq -r '.description')
  fr=$(echo "$task" | jq -r '.fr // "N/A"')
  spec=$(echo "$task" | jq -r '.spec // empty')

  local acceptance_criteria
  acceptance_criteria=$(echo "$task" | jq -r '.acceptanceCriteria[] | "- [ ] \(.)"')

  local spec_content=""
  if [[ -n "$spec" && -f "${PROJECT_ROOT}/$spec" ]]; then
    spec_content="$(cat "${PROJECT_ROOT}/$spec")"
  fi

  local agents_content=""
  if [[ -f "${PROJECT_ROOT}/AGENTS.md" ]]; then
    agents_content="$(cat "${PROJECT_ROOT}/AGENTS.md")"
  fi

  local codex_prompt
  codex_prompt="You are implementing a task for the Timed macOS app (Swift 6.1, SwiftUI, macOS 15+).

## ARCHITECTURE RULES
${agents_content}

---

## TASK ${task_id}: ${title}
FR: ${fr}

### Description
${description}

### Acceptance Criteria
${acceptance_criteria}
"

  if [[ -n "$spec_content" ]]; then
    codex_prompt+="
### FR Spec
\`\`\`
${spec_content}
\`\`\`
"
  fi

  codex_prompt+="
## Instructions
- Working directory: ${PROJECT_ROOT}
- Run \`swift build\` to verify your work compiles
- When ALL acceptance criteria are met and \`swift build\` exits 0, output: TASK_COMPLETE
- If stuck after 3 attempts on the same error, output: TASK_BLOCKED"

  # --- Run Codex ---
  echo "  [dispatch] Codex → task ${task_id}: ${title}"
  echo "$codex_prompt" | codex exec \
    --full-auto \
    -C "$PROJECT_ROOT" \
    -o "$codex_output" \
    - 2>/dev/null || true

  # Self-reported blocked
  if grep -q "TASK_BLOCKED" "$codex_output" 2>/dev/null; then
    echo "  [dispatch] Codex self-reported TASK_BLOCKED"
    _log_dispatch "$dispatch_log" "$task_id" "$title" "codex_blocked" "$start_time"
    cmd_fail "$task_id" --reason "Codex: TASK_BLOCKED"
    cmd_fail "$task_id" --reason "Codex: TASK_BLOCKED (2)"
    cmd_fail "$task_id" --reason "Codex: TASK_BLOCKED (3)"
    return 3
  fi

  # --- Verify build + tests ---
  echo "  [dispatch] Verifying build..."
  if ! (cd "$PROJECT_ROOT" && swift build > "$build_log" 2>&1); then
    echo "  [dispatch] Build failed. Entering Claude debug loop..."
    _debug_loop "$task_id" "Build failure" "$build_log" "$dispatch_log" "$start_time"
    return $?
  fi

  echo "  [dispatch] Build OK. Running tests..."
  if ! (cd "$PROJECT_ROOT" && swift test >> "$build_log" 2>&1); then
    echo "  [dispatch] Tests failed. Entering Claude debug loop..."
    _debug_loop "$task_id" "Test failures" "$build_log" "$dispatch_log" "$start_time"
    return $?
  fi

  echo "  [dispatch] ✓ Build + tests pass"
  _log_dispatch "$dispatch_log" "$task_id" "$title" "success_codex" "$start_time"
  return 0
}

_debug_loop() {
  local task_id="$1" failure_reason="$2" build_log="$3" dispatch_log="$4" start_time="$5"
  local debug_output="/tmp/taskflow-debug-${task_id}.txt"
  local error_context
  error_context=$(tail -40 "$build_log")

  local initial_prompt="The previous Codex implementation produced a ${failure_reason}.

Error output:
\`\`\`
${error_context}
\`\`\`

Working directory: ${PROJECT_ROOT}
Fix the error. Run \`swift build\` after your fix. When build and tests pass, output BUILD_FIXED."

  for attempt in 1 2 3; do
    echo "  [debug] Claude attempt ${attempt}/3..."
    > "$debug_output"

    if [[ $attempt -eq 1 ]]; then
      claude --print --max-turns 15 "$initial_prompt" 2>/dev/null | tee "$debug_output" || true
    else
      local new_error
      new_error=$(cd "$PROJECT_ROOT" && swift build 2>&1 | tail -20 || true)
      claude --print --continue --max-turns 10 \
        "Still failing on attempt ${attempt}. Current error:
\`\`\`
${new_error}
\`\`\`
Fix this. Output BUILD_FIXED when build and tests pass." 2>/dev/null | tee "$debug_output" || true
    fi

    # Verify
    if (cd "$PROJECT_ROOT" && swift build > /dev/null 2>&1) && \
       (cd "$PROJECT_ROOT" && swift test > /dev/null 2>&1); then
      echo "  [debug] ✓ Fixed on Claude attempt ${attempt}"
      _log_dispatch "$dispatch_log" "$task_id" "" "success_claude_debug_${attempt}" "$start_time"
      return 0
    fi
  done

  # Exhausted
  local final_error
  final_error=$(cd "$PROJECT_ROOT" && swift build 2>&1 | head -5 || true)
  echo "  [debug] All 3 debug attempts failed. Triggering circuit breaker."
  _log_dispatch "$dispatch_log" "$task_id" "" "blocked_debug_exhausted" "$start_time"
  cmd_fail "$task_id" --reason "Debug exhausted: $(echo "$final_error" | tr '\n' ' ' | cut -c1-120)"
  cmd_fail "$task_id" --reason "Debug exhausted (2)"
  cmd_fail "$task_id" --reason "Debug exhausted (3)"
  return 3
}

_log_dispatch() {
  local log_file="$1" task_id="$2" title="$3" outcome="$4" start_time="$5"
  local end_time
  end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # Escape title for JSON
  local safe_title
  safe_title=$(echo "$title" | sed 's/"/\\"/g')
  printf '{"task_id":%s,"title":"%s","outcome":"%s","started":"%s","ended":"%s"}\n' \
    "$task_id" "$safe_title" "$outcome" "$start_time" "$end_time" >> "$log_file"
}
