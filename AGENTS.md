# AGENTS.md

## Mandatory skill routing

- Use $SwiftUI-Pro and $build-macos-apps for all Swift and SwiftUI work in this repo.
- Use $macos-app-development for all packaging, signing, and Gatekeeper concerns.
- Use $codex-integration when modifying CodexBridge.swift or the prompt pipeline.
- Use $senior-data-engineer when modifying import parsing, schema, or persistence.
- Use $superpowers before designing any new scoring or scheduling logic.
- NEVER apply web or Next.js skills in this repo.
- NEVER apply mobile/iOS-only patterns — this is macOS 15 desktop only.

## Build commands
- Build: `swift build -c release`
- Test: `swift test`
- Package: `bash scripts/package_app.sh`
- Install: `bash scripts/install_app.sh`

## Architecture rules
- No external Swift dependencies. Pure SwiftUI + Foundation + EventKit + AppKit where needed.
- All AI calls go through CodexBridge. No direct API calls in UI code.
- All persistence goes through PlannerStore. No direct FileManager calls in views.
- All ranking logic lives in PlanningEngine. No scoring in PlannerStore or views.

---
ACCEPTANCE CRITERIA — DO NOT STOP UNTIL THESE ALL PASS

1. swift build -c release exits 0 with no warnings.
2. swift test exits 0. All tests listed above pass.
3. bash scripts/package_app.sh produces a signed dist/timed.app that launches on this Mac without Gatekeeper
prompts.
4. Launching the app shows a genuinely translucent glass window with real window blur (you can see the desktop
behind it).
5. The ranked task list shows all tasks grouped by band. No 4-task cap.
6. Submitting a prompt with tasks loaded produces a Codex response that references at least one task by name
(because the task list is now injected into the prompt).
7. Saying "quiz me on [subject]" in the prompt triggers a quiz question from Codex based on context items for that
subject.
8. Marking a task complete removes it from the ranked list immediately.
9. Approving a schedule block and hitting Export writes an event to Apple Calendar named "Timed" (or falls back to
ICS with error surfaced to user if permission denied).
10. Importing the same Seqta text twice produces exactly one set of tasks (deduplication works).
11. Chat history survives app quit and relaunch.
12. The UI has zero hardcoded repeated card closures — all cards use TimedCard.

Keep going until done. Do not ask for confirmation. If something is ambiguous, make the most reasonable choice and
document it in a comment.
