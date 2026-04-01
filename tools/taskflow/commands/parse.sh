#!/usr/bin/env bash
# taskflow parse — decompose PRD into tasks.json

cmd_parse() {
  local prd_path="${1:-}"
  if [[ -z "$prd_path" ]]; then
    echo "Usage: taskflow parse <prd-path>" >&2
    exit 1
  fi

  # Resolve relative to project root
  if [[ ! "$prd_path" = /* ]]; then
    prd_path="$PROJECT_ROOT/$prd_path"
  fi

  if [[ ! -f "$prd_path" ]]; then
    echo "Error: PRD file not found: $prd_path" >&2
    exit 1
  fi

  local project_name
  project_name="$(config_get projectName)"
  local specs_dir
  specs_dir="$(config_get specsDir)"

  # Gather spec files for context
  local spec_list=""
  if [[ -d "$PROJECT_ROOT/$specs_dir" ]]; then
    spec_list=$(ls "$PROJECT_ROOT/$specs_dir"/*.md 2>/dev/null | while read -r f; do
      echo "- $(basename "$f")"
    done)
  fi

  local prd_content
  prd_content="$(cat "$prd_path")"

  local prompt
  prompt="Decompose this PRD into atomic implementation tasks for the project \"$project_name\".

For each task provide:
- id: sequential integer starting at 1
- title: short descriptive title
- description: what to implement (1-3 sentences)
- spec: path to the FR spec file it belongs to (under $specs_dir/)
- fr: the FR identifier (e.g. FR-01)
- status: \"pending\"
- complexity: 1-10 score
- dependencies: array of task IDs this depends on (must be lower IDs)
- subtasks: empty array (will be populated for complexity > 7)
- testFile: suggested test file path
- acceptanceCriteria: array of specific, verifiable criteria
- completedAt: null
- failureLog: null
- tokensUsed: 0
- turnsUsed: 0

Rules:
- Order by dependency — no task should reference a dependency with a higher ID
- Keep tasks atomic — each should be completable in one Claude session
- Group by FR spec
- Any task with complexity > 7 should be broken into subtasks

Available spec files:
$spec_list

Output ONLY valid JSON matching this structure:
{
  \"projectName\": \"$project_name\",
  \"generatedFrom\": \"$(basename "$prd_path")\",
  \"tasks\": [...]
}

PRD Content:
$prd_content"

  echo "Parsing PRD into tasks.json..."
  echo "(This calls Claude to decompose the PRD — may take 30-60 seconds)"

  local output
  output=$(claude --print "$prompt" 2>/dev/null)

  # Extract JSON from Claude's response (handle markdown code blocks)
  local json
  json=$(echo "$output" | sed -n '/^```json/,/^```$/p' | sed '1d;$d')
  if [[ -z "$json" ]]; then
    json=$(echo "$output" | sed -n '/^{/,/^}/p')
  fi
  if [[ -z "$json" ]]; then
    json="$output"
  fi

  # Validate JSON
  if ! echo "$json" | jq . >/dev/null 2>&1; then
    echo "Error: Claude did not return valid JSON." >&2
    echo "Raw output saved to /tmp/taskflow-parse-raw.txt" >&2
    echo "$output" > /tmp/taskflow-parse-raw.txt
    exit 1
  fi

  # Auto-decompose high complexity tasks
  local task_count
  task_count=$(echo "$json" | jq '.tasks | length')
  local high_complexity
  high_complexity=$(echo "$json" | jq '[.tasks[] | select(.complexity > 7)] | length')

  echo "$json" > "$TASKS_FILE"
  echo "✓ Generated $task_count tasks ($high_complexity with complexity > 7)"

  if [[ "$high_complexity" -gt 0 ]]; then
    echo "High-complexity tasks should be manually reviewed and decomposed with subtasks."
    echo "IDs with complexity > 7:"
    echo "$json" | jq -r '.tasks[] | select(.complexity > 7) | "  Task \(.id): \(.title) (complexity: \(.complexity))"'
  fi

  echo "Tasks written to: $TASKS_FILE"
}
