# Architecture

Timed keeps the app deliberately small and native.

## Modules

- `ContentView.swift`
  - Main desktop workspace.
  - Owns the three-column shell, prompt bar, grouped ranked-task list, schedule UI, and quiz/planner chat.
- `TimedCard.swift`
  - Shared glass card primitive used across the workspace.
- `VisualEffectView.swift`
  - AppKit bridge for the real `NSVisualEffectView` blur layer and window transparency.
- `PlannerStore.swift`
  - Single persistence and orchestration layer.
  - Handles imports, ranking rebuilds, prompt submission, quiz lifecycle, task completion, schedule approval, and snapshot save/load.
- `PlanningEngine.swift`
  - Pure ranking and scheduling logic.
  - Computes score bands, reasons, suggested next actions, and capped schedule windows.
- `ImportPipeline.swift`
  - Seqta parsing, TickTick CSV parsing, subject inference, and deduplication.
- `CodexBridge.swift`
  - Local Codex CLI wrapper.
  - Builds prompt execution and parses task-action and subject-boost hints from stdout.
- `CalendarExporter.swift`
  - Apple Calendar write path plus ICS fallback generation.
- `SettingsView.swift`
  - User-facing Codex executable path configuration.

## Data flow

1. Imported or manual tasks enter `PlannerStore`.
2. `PlannerStore` calls `PlanningEngine.rank`.
3. Ranked tasks feed `PlanningEngine.buildSchedule`.
4. User prompts and quiz prompts flow through `CodexBridge`.
5. Approved schedule blocks export through `CalendarExporter`.
6. Everything persists through `PlannerSnapshot`.

## Boundaries

- No direct AI calls in views.
- No ranking logic outside `PlanningEngine`.
- No persistence calls outside `PlannerStore`.
- No external Swift packages.

## AI trust boundary

- `CodexBridge.swift` is the only AI execution path.
- The app launches a local executable and reads back stdout.
- The executable path is user-configurable in `SettingsView.swift`.
- That keeps the trust boundary explicit: Timed trusts the configured Codex binary, not an SDK hidden in the UI layer.

## Distribution boundary

- `scripts/package_app.sh` produces an ad-hoc signed bundle for local use and testing.
- `scripts/notarize_app.sh` provides the notarized distribution path for wider macOS release flows.
