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
