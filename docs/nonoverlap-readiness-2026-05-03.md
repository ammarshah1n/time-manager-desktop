# Non-overlap app readiness triage — 2026-05-03

Branch/worktree: `jcode/nonoverlap-readiness-20260503T123258Z` at `/Users/integrale/time-manager-desktop-nonoverlap-readiness`.

This pass intentionally stayed separate from the active DoD #2 scheduled-briefing plan and the dirty main worktree. It did not merge or push anything.

## What was checked

### A1 — Verification reliability

- `swift test --filter DataBridgeTests` passed in this isolated worktree: **19 tests passed**.
- The earlier Jcode 600s timeout came from the main worktree's dirty test set, not committed `unified` at this branch point.
- Main-worktree logs showed SQLite warnings such as `vnode unlinked while in use` under `Tests/DataBridgeTests.swift`; because `DataBridge.swift` and `Tests/DataBridgeTests.swift` are dirty/owned in the main worktree, this pass did not patch them.

### A2 — Installed app launch sanity

- `/Applications/Timed.app` exists.
- `codesign --verify --deep --strict --verbose=2 /Applications/Timed.app` passed.
- Installed binary hash: `a29abf1408fa1d3992e191e92f4e46d7c16df4e77e0777c2133e1eec534f40d0`.
- Timed was running as `/Applications/Timed.app/Contents/MacOS/timed`.
- Recent logs did not show a Timed crash loop.

### A3/A4 — Gmail/offline-sync read-only trace

- Gmail restore and connect paths are present: `AuthService.restoreSession` restores Google and calls `connectGmailIfPossible`, which starts Gmail and Google Calendar sync.
- Offline replay is registered on app launch in `TimedAppShell`: `startOfflineReplay()` then `flushOfflineReplay()`, and another flush occurs on sign-in changes.
- `DataBridge` and Gmail/Auth files are dirty/owned in the main worktree, so this pass did not edit them.

### A5/A6 — Remaining user-blocking issues outside DoD #2

Fixed in this branch:

- First-run voice onboarding no longer silently clears the resume setup affordance when `extract-onboarding-profile` fails. It now:
  - requires the current Supabase session JWT,
  - checks non-2xx HTTP responses,
  - returns a persistence success boolean,
  - leaves `pendingVoiceOnboarding = true` if backend profile extraction did not persist, so Settings can offer `Resume voice setup`.

Blocked/skipped until owners finish or Ammar is awake:

- `MorningCheckInManager.swift` still has committed internal/provider wording and fire-and-forget learning extraction behavior, but that file is dirty/owned in the main worktree.
- `PrefsPane.swift` still has committed Voice ID UI in this branch point, but that file is dirty/owned in the main worktree and likely part of the UI cleanup session.
- `trigger/src/tasks/ingestion-health-watchdog.ts` and `outcome-harvester.ts` are callable-on-demand because the Trigger.dev hobby plan schedule cap forced them off cron. They are clean, but restoring schedules may exceed the current Trigger schedule cap and requires cloud deployment/alert rules, so this was documented rather than changed.
- `trigger/node_modules` is missing in this worktree, so `npm run typecheck` was skipped to avoid package installation/mutation.

## Files changed in this worktree

- `Sources/TimedKit/Features/Onboarding/VoiceOnboardingView.swift`
- `Tests/VoicePathGuardTests.swift`
- `docs/nonoverlap-readiness-2026-05-03.md`

## Validation run

- `swift test --filter DataBridgeTests` ✅
- `swift test --filter ProductionReadinessGuardTests/voiceOnboardingDoesNotClearResumeWhenExtractorFails` ✅

Run before merge review:

```bash
cd /Users/integrale/time-manager-desktop-nonoverlap-readiness
swift build
swift test
```

## Merge notes

Do not merge automatically. Review this branch after the active main-worktree sessions finish, especially because several related files are dirty in the main worktree.
