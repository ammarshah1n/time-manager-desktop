# /full-claude — Toggle Codex triage guard

Toggle between full-Claude mode (no triage) and Codex-triage mode.

## Usage
- `/full-claude` or `/full-claude on` — enable full-Claude mode (bypass triage)
- `/full-claude off` — re-enable Codex triage enforcement

## Instructions

Run the appropriate shell command based on the argument:

- If no argument or `on`: run `touch /tmp/claude-full-claude` and confirm "Full-Claude mode enabled — triage bypassed."
- If `off`: run `rm -f /tmp/claude-full-claude` and confirm "Codex triage mode enabled — run /triage before edits."
