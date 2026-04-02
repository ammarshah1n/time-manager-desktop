# Acceptance Matrix

This file maps the original desktop-app brief to the shipped repo so a reviewer can verify the implementation without reverse-engineering the entire codebase.

## Core acceptance

1. `swift build -c release` exits 0
   - Evidence: [docs/VALIDATION.md](./VALIDATION.md)
2. `swift test` exits 0
   - Evidence: [docs/VALIDATION.md](./VALIDATION.md)
   - Tests: [Tests/PlanningEngineTests.swift](../Tests/PlanningEngineTests.swift)
3. `bash scripts/package_app.sh` produces a signed bundle
   - Script: [scripts/package_app.sh](../scripts/package_app.sh)
   - Evidence: [docs/VALIDATION.md](./VALIDATION.md)
4. The app uses real window blur, not fake flat cards
   - Implementation: [Sources/VisualEffectView.swift](../Sources/VisualEffectView.swift)
5. Ranked tasks show all tasks grouped by band
   - Implementation: [Sources/ContentView.swift](../Sources/ContentView.swift)
6. Prompt submission includes the ranked task list in the Codex planning prompt
   - Implementation: [Sources/PlannerStore.swift](../Sources/PlannerStore.swift)
   - Bridge: [Sources/CodexBridge.swift](../Sources/CodexBridge.swift)
7. `quiz me on [subject]` starts subject-specific tutor mode
   - Implementation: [Sources/PlannerStore.swift](../Sources/PlannerStore.swift)
8. Completing a task removes it from ranking immediately
   - Implementation: [Sources/PlannerStore.swift](../Sources/PlannerStore.swift)
   - Ranking filter: [Sources/PlanningEngine.swift](../Sources/PlanningEngine.swift)
9. Approved blocks export to Apple Calendar with ICS fallback
   - Implementation: [Sources/CalendarExporter.swift](../Sources/CalendarExporter.swift)
10. Duplicate imports are skipped
   - Implementation: [Sources/ImportPipeline.swift](../Sources/ImportPipeline.swift)
   - Test: [Tests/PlanningEngineTests.swift](../Tests/PlanningEngineTests.swift)
11. Chat history persists across relaunches
   - Snapshot: [Sources/Models.swift](../Sources/Models.swift)
   - Store persistence: [Sources/PlannerStore.swift](../Sources/PlannerStore.swift)
   - Test: [Tests/PlanningEngineTests.swift](../Tests/PlanningEngineTests.swift)
12. Shared `TimedCard` replaces repeated card closures
   - Component: [Sources/TimedCard.swift](../Sources/TimedCard.swift)
   - Usage: [Sources/ContentView.swift](../Sources/ContentView.swift)

## Review shortcuts

- Planner UI screenshot: [docs/assets/timed-planner.png](./assets/timed-planner.png)
- Quiz UI screenshot: [docs/assets/timed-quiz.png](./assets/timed-quiz.png)
- Settings screenshot: [docs/assets/timed-settings.png](./assets/timed-settings.png)
