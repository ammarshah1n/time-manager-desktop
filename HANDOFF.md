# Timed macOS — Session Handoff

## What this is
Native macOS SwiftUI app for executive time management. Email triage → task buckets → daily planning → calendar blocking. No backend yet — this is the UI shell/prototype.

## Remote dev workflow (ACTIVE)
Run this first: `bash scripts/dev-start.sh`
- Opens Terminal 2: Cloudflare tunnel → gives iPhone URL (auto-refresh screenshot preview)
- Opens Terminal 3: fswatch watcher → auto-builds + screenshots on every .swift save
- Manual build+preview: `bash scripts/build-preview.sh`

## Core transcript (READ THIS for all product decisions)
`/Users/integrale/Downloads/file1_transcript_extraction.md`
Key themes: A=triage, B=email→task, C=task mgmt, D=planning engine (THE CORE), E=multi-source, F=transit tasks, G=platform
Core quote: "I'm prepared to do an hour right now and it dishes me up the right work in the right order"

## What's built (V2 — currently running)
Binary: `.build/debug/time-manager-desktop`
V1 binary saved at: `.build/debug/timed-v1`

### Navigation (TimedRootView.swift)
Today (default landing) → Triage → Tasks [6 buckets] → Calendar → Focus → Settings

### 6 Task buckets (PreviewData.swift)
Reply · Action · Transit · Read Today · Read This Week · Waiting
Transit is from transcript F1: "things to do in back of car, on plane"

### Key files
```
Sources/Features/TimedRootView.swift       — nav shell, NavSection enum, SidebarRow
Sources/Features/PreviewData.swift         — ALL mock types: TaskBucket, TimedTask, TriageItem, CalendarBlock
Sources/Features/Today/TodayPane.swift     — landing screen: briefing card + context picker + dish-me-up plan
Sources/Features/Triage/TriagePane.swift   — one-at-a-time keyboard triage (R/A/T/D/W/N/Space)
Sources/Features/Tasks/TasksPane.swift     — per-bucket task list + BlockTimeSheet
Sources/Features/Plan/PlanPane.swift       — older plan pane (superseded by TodayPane but still compiles)
Sources/Features/Calendar/CalendarPane.swift — weekly grid, popover, current-time line
Sources/Features/Focus/FocusPane.swift     — circular countdown timer, FocusSession @Observable
Sources/Features/Prefs/PrefsPane.swift     — 5-tab settings
Sources/Core/Models/EmailMessage.swift     — EmailMessage struct
Sources/Core/Models/CalendarBlock.swift    — CalendarBlock, BlockCategory
Sources/TimeManagerDesktopApp.swift        — @main, WindowGroup("Timed"), defaultSize 1240×820
```

### Legacy v1 files (ignore, don't touch)
Everything in `Sources/` root that isn't `TimeManagerDesktopApp.swift` — old school/study app code that compiles but is unused.

## Known issues / ambiguities to resolve in this session
1. **TodayPane context filtering** — "In Transit" mode filters buckets but the logic is in TodayPane.generate(), not enforced globally. Transit tasks don't surface in the sidebar count differently per context.
2. **TriagePane undo** — undoStack uses title+sender matching to remove tasks which is fragile; should use task ID stored at classify time.
3. **PlanPane vs TodayPane** — NavSection.plan was removed, PlanPane.swift still exists but nothing routes to it. Either delete it or repurpose.
4. **BlockTimeSheet start hour** — defaults to 9am hardcoded, should default to next available slot.
5. **Transit bucket colour** — currently a hardcoded `Color(red:0.2, green:0.6, blue:0.45)`, no system colour equivalent.
6. **FocusPane** — receives `emails: []` always (hardcoded empty array in TimedRootView). Should pass the first task from the selected bucket or today's plan.
7. **CalendarPane weekTitle** — shows month range but doesn't handle same-month weeks (shows "Mar 30 – 5" not "Mar 30 – Apr 5").
8. **No persistence** — all state is @State in TimedRootView, resets on relaunch. Fine for now but note for when real data layer is added.

## Product decisions already made (don't re-debate)
- Mail folders stay in Outlook — this app is the planning layer on top, not an email client
- 6 buckets (not 5) — Transit is a real category from the transcript
- Today screen is the landing (not Triage) — morning ritual replacement
- Triage is one-at-a-time keyboard-driven (not a scrollable list)
- Calendar sync target = user's choice (iCal/Outlook/Google) — not yet implemented, Phase 2
- Karen (PA) sharing = Phase 2, not in shell
- P1/P2 replaced by Action/Read taxonomy — answers "when do I look at this again?" not "how important?"

## Build command
```bash
swift build && open .build/debug/time-manager-desktop
```

## Package.swift
Single executable target `time-manager-desktop`, path `Sources/`, macOS 15+, Swift 6.1.
All files in Sources/ subdirectories are auto-included — no need to edit Package.swift for new .swift files.
