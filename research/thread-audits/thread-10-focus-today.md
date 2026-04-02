# Timed — Thread 10: Focus + Today + Plan Daily UX Loop Deep Audit

**Repository:** `ammarshah1n/time-manager-desktop` · Branch: `ui/apple-v1-restore`
**Scope:** `Sources/Features/Focus/FocusPane.swift`, `Sources/Features/Today/TodayPane.swift`, `Sources/Features/Plan/PlanPane.swift`, `Sources/Core/Services/TimedScheduler.swift`, `Sources/Core/Services/TimedLogger.swift`

***

## Executive Summary

The daily UX loop — Focus → Today → Plan — is the most user-facing part of Timed and the loop an executive user will touch 10–20 times per day. The architecture has strong bones: a clean `@Observable` timer, a well-structured bucket-grouped Today view with a live EMA learning loop, and a "Dish Me Up" planner that correctly surfaces priority sequences. However, **three systemic gaps** prevent this from being a best-in-class single-user daily driver:

1. **Focus sessions are ghosts.** `FocusSession` runs in memory but is never persisted, never fires a system notification, never guards against distraction, and is never logged. If the user switches away, the session silently continues with no ambient indicator outside the sheet.

2. **`TimedScheduler` is a stub.** At 30 lines, it schedules only `actionRequired` emails into back-to-back 30-minute blocks, has zero `UNUserNotificationCenter` calls, and has no awareness of DND, calendar gaps, or focus mode state.

3. **`TimedLogger` has no focus category.** All session telemetry — start, pause, stop, natural completion — is unlogged. The EMA learning loop (which *is* working) has no data about *when* sessions happen, so it can never learn time-of-day energy patterns.

These are fixable with targeted additions. The report below ranks every gap and provides exact file paths, function names, and code-level fixes.

***

## Impact-Ranked Findings Table

| # | Finding | File(s) | Severity | Impact |
|---|---------|---------|----------|--------|
| F-01 | `FocusSession` never fires a completion notification | `FocusPane.swift` | **High** | User misses session end; loses momentum |
| F-02 | `TimedScheduler` is an email-only stub — no task or time-aware notifications | `TimedScheduler.swift` | **High** | App is entirely silent; no reminders |
| F-03 | No macOS Focus Filter entitlement — distraction guard absent | `FocusPane.swift` | **High** | Executive UX promise broken vs. competition |
| F-04 | `FocusSession` not persisted — sessions are ephemeral | `FocusPane.swift`, `DataStore.swift` | **High** | No session analytics, no ML feedback on focus durations |
| F-05 | `TimedLogger` has no `focus` category — sessions never logged | `TimedLogger.swift` | **High** | EMA loop is time-blind; can't learn energy patterns |
| F-06 | Today view has no intra-section sort — tasks within a bucket are in insertion order | `TodayPane.swift` | **Medium** | Most urgent task inside a section may be buried |
| F-07 | Today view shows no scheduled start times — no time-blocking visualisation | `TodayPane.swift` | **Medium** | User can't see *when* to do tasks, only *what* |
| F-08 | `moodContext: nil` hardcoded in `PlanPane.generate()` — energy never passed to planner | `PlanPane.swift` | **Medium** | Morning interview mood signal is never used in planning |
| F-09 | `behaviouralRules: []` hardcoded in `PlanPane.generate()` — rules engine bypassed | `PlanPane.swift` | **Medium** | Thread 6 BehaviourRules work is invisible at plan-time |
| F-10 | `sendToCalendar()` only writes to local `@Binding var blocks` — not EKEventStore | `PlanPane.swift` | **Medium** | Calendar export is a no-op outside the app |
| F-11 | "Session 1 of 3" is a hardcoded string — no Pomodoro cycle logic | `FocusPane.swift` | **Medium** | Strip feature promise that doesn't exist |
| F-12 | No streak tracking data model or UI | `DataStore.swift`, `TodayPane.swift` | **Medium** | Motivation layer missing for single executive user |
| F-13 | No end-of-day review flow | *(missing file)* | **Medium** | No closure ritual; daily data never summarised |
| F-14 | Free-time slot banner is read-only — no auto-plan on tap | `TodayPane.swift` | **Low** | Banner surfaces a slot but the CTA calls `onDishMeUp` correctly — just needs wiring |
| F-15 | No weekly reflection prompt | *(missing file)* | **Low** | Good data in `InsightsEngine` never surfaced as a weekly moment |
| F-16 | No energy curve / time-of-day heatmap | *(missing file)* | **Low** | `hourOfDay` is already logged in `BehaviourEventInsert` — just not visualised |
| F-17 | Quick-add hardcodes `estimatedMinutes: 15` | `TodayPane.swift:submitQuickTask()` | **Low** | Should use per-bucket EMA mean from `DataStore.loadBucketEstimates()` |

***

## Finding Detail

### F-01 · Focus session never fires a completion notification

**File:** `Sources/Features/Focus/FocusPane.swift`
**Function:** `FocusSession.start()`, `FocusSession` phase `.idle` observer in `FocusPane.body`

When `secondsRemaining` hits zero, `FocusSession` sets `didFinishNaturally = true` and flips to `.idle`. The `.onChange(of: session.phase)` in the view sets `showNextPrompt = true` — but only if the sheet is on screen and the view is in the responder chain. There is no `UNUserNotificationCenter` call, no sound, and no haptic. If the user has the app in the background (common during a focus block), they never know the session ended.

**Comparison:**
- Forest plants a real tree at completion, fires a system notification, and plays a sound even when backgrounded.
- Centered fires a macOS notification and announces the transition vocally.
- Focusmate uses a partner video call as the ambient signal — the social layer eliminates the need for an OS notification.

**Fix — `FocusPane.swift`, add to `FocusSession.start()` loop:**

```swift
// In FocusSession.start(), replace the natural completion block:
} else {
    self.didFinishNaturally = true
    self.phase = .idle
    await Self.scheduleCompletionNotification(taskTitle: taskTitle)
    return
}

// New helper on FocusSession:
private static func scheduleCompletionNotification(taskTitle: String?) async {
    let center = UNUserNotificationCenter.current()
    let content = UNMutableNotificationContent()
    content.title = "Focus session complete"
    content.body  = taskTitle.map { "Done: \($0)" } ?? "Session finished"
    content.sound = .default
    let request = UNNotificationRequest(
        identifier: "focus.complete.\(UUID())",
        content: content, trigger: nil
    )
    try? await center.add(request)
}
```

`FocusSession` also needs `var taskTitle: String?` injected from `FocusPane.init` so the notification body carries the task name.

***

### F-02 · `TimedScheduler` is an email-only stub

**File:** `Sources/Core/Services/TimedScheduler.swift`
**Function:** `TimedSchedulerService.suggestBlocks(for:)`

The entire scheduler is 30 lines. It iterates emails, classifies `.actionRequired` ones, and appends back-to-back 30-minute `CalendarBlock` objects — with no gap detection, no round-up logic, no existing-block collision check, and zero `UNUserNotificationCenter` involvement. It shares no code path with `PlanningEngine`, `TodayPane`, or `FocusPane`. For a single executive user, this file should be the heartbeat of reminder delivery; instead it's a classification utility masquerading as a scheduler.

**Comparison:**
- Reclaim.ai has a scheduling engine that knows DND windows, calendar event hard stops, and energy preferences — it reschedules in real time when meetings are added.
- Motion uses an LLM to re-run the schedule after every calendar change and pushes notifications at the right moment.

**Fix — replace `TimedSchedulerService` with a `NotificationScheduler` that:**

```swift
// Sources/Core/Services/TimedScheduler.swift — replace entire struct

@MainActor
final class TimedNotificationScheduler {

    static let shared = TimedNotificationScheduler()

    /// Call once after plan is generated or tasks change.
    func scheduleRemindersForPlan(_ items: [PlannedItem]) async {
        let center = UNUserNotificationCenter.current()
        // Remove stale plan reminders
        center.removePendingNotificationRequests(withIdentifiers: items.map { "plan.\($0.id)" })

        for item in items {
            guard let start = item.scheduledStart else { continue }
            let fireDate = start.addingTimeInterval(-5 * 60) // 5-min heads-up
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Starting in 5 min"
            content.body  = item.task.title
            content.sound = .default
            // Respect Focus Filter — use interruptionLevel
            content.interruptionLevel = item.task.isDoFirst ? .timeSensitive : .active

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: fireDate),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: "plan.\(item.id)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
```

This requires `PlannedItem` to gain a `scheduledStart: Date?` field, which `PlanPane.sendToCalendar()` already computes — it just needs to write it back to the model.

***

### F-03 · No macOS Focus Filter entitlement

**File:** `Sources/Features/Focus/FocusPane.swift`

No `FocusFilter` conformance or `AppIntents/FocusFilterIntent` is declared anywhere in the repo. This means Timed cannot hook into macOS Focus modes (Work, Personal, Do Not Disturb). Competing apps (Centered, Fantastical) declare a `FocusFilterIntent` so that when the user activates a Focus mode, the app automatically enters its own focus state — and vice versa.

**Fix — new file `Sources/Core/AppIntents/TimedFocusFilter.swift`:**

```swift
import AppIntents

struct TimedFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Timed"
    static var description = IntentDescription("Mute Timed notifications during Focus sessions.")

    @Parameter(title: "Allow interruptions")
    var allowInterruptions: Bool = false

    func perform() async throws -> some IntentResult {
        // When macOS activates a Focus, silence non-timeSensitive Timed notifications
        TimedNotificationScheduler.shared.pauseNonUrgentReminders(allowInterruptions)
        return .result()
    }
}
```

Also add `NSFocusStatusUsageDescription` to `Info.plist` and the `com.apple.developer.focus-status` entitlement.

***

### F-04 · `FocusSession` not persisted

**File:** `Sources/Features/Focus/FocusPane.swift`, `Sources/Core/Services/DataStore.swift`
**Functions:** `FocusSession.start()`, `FocusSession.stop()`, `FocusSession.pause()`

`FocusSession` holds `secondsRemaining`, `phase`, and `didFinishNaturally` entirely in memory. There is no `FocusSessionRecord` model, no call to `DataStore`, and `TimedLogger` has no `focus` category (`TimedLogger.swift` lists: general, dataStore, graph, supabase, planning, voice, calendar, sharing, triage — focus is absent). This means the ML loop (`InsightsEngine`, EMA in `TodayTaskRow`) has no data about actual session durations — only estimated task minutes — and can never learn whether the user focuses better in the morning or afternoon.

**Fix — `DataStore.swift`, add:**

```swift
struct FocusSessionRecord: Codable, Identifiable {
    let id: UUID
    let taskId: UUID?
    let startedAt: Date
    var endedAt: Date?
    var pauseCount: Int
    var completedNaturally: Bool
    var actualDurationSeconds: Int
}

// In DataStore:
func loadFocusSessions() throws -> [FocusSessionRecord] { try load("focus_sessions") }
func saveFocusSessions(_ v: [FocusSessionRecord]) throws { try save(v, "focus_sessions") }
```

**`TimedLogger.swift`, add:**

```swift
static let focus = Logger(subsystem: "com.timed.app", category: "focus")
```

**`FocusSession`, add persistence calls:**

```swift
func start() {
    startedAt = Date()
    pauseCount = 0
    phase = .running
    TimedLogger.focus.info("Session started — task: \(taskTitle ?? "none", privacy: .public)")
    // ... existing loop
}

func pause() {
    pauseCount += 1
    TimedLogger.focus.info("Session paused — pause #\(pauseCount)")
    task?.cancel(); task = nil; phase = .paused
}

func stop() {
    let record = FocusSessionRecord(
        id: UUID(), taskId: taskId, startedAt: startedAt ?? Date(),
        endedAt: Date(), pauseCount: pauseCount,
        completedNaturally: false,
        actualDurationSeconds: total - secondsRemaining
    )
    Task { try? await DataStore.shared.saveFocusSessions(
        (DataStore.shared.loadFocusSessions() ?? []) + [record]
    ) }
    TimedLogger.focus.info("Session stopped — \(record.actualDurationSeconds)s completed")
    task?.cancel(); task = nil
    phase = .idle; secondsRemaining = total; didFinishNaturally = false
}
```

***

### F-05 · `TimedLogger` has no `focus` category — sessions never logged

**File:** `Sources/Core/Services/TimedLogger.swift`

As noted in F-04, the `focus` logger category is absent. All eight existing categories are defensive but none capture focus telemetry. This is a one-line fix already shown in F-04. The broader issue is that without a `focus` logger, Instruments and Console.app cannot filter focus-related events during debugging, and production diagnostics cannot identify session crash/termination patterns.

***

### F-06 · Today view has no intra-section sort

**File:** `Sources/Features/Today/TodayPane.swift`
**Computed vars:** `doFirst`, `replies`, `actions`, `calls`, `transit`, `readsToday`, `readsWeek`

All seven section computed properties filter by bucket but preserve array insertion order. Within the Action bucket, a task with `daysInQueue == 21` may appear below one with `daysInQueue == 1`. There is no secondary sort by `dueToday`, `daysInQueue`, or `estimatedMinutes`.

**Comparison:**
- Sunsama surfaces the highest-priority tasks at the top of each section during its morning ritual, using a drag-reorder that the user explicitly confirms.
- Motion auto-sorts continuously based on deadline proximity and estimated duration.

**Fix — `TodayPane.swift`, update all section vars:**

```swift
private func prioritySorted(_ list: [TimedTask]) -> [TimedTask] {
    list.sorted {
        // 1. Overdue hard-deadline tasks first
        let aDue = $0.dueToday && $0.daysInQueue > 1
        let bDue = $1.dueToday && $1.daysInQueue > 1
        if aDue != bDue { return aDue }
        // 2. Higher days-in-queue first (aging penalty)
        if $0.daysInQueue != $1.daysInQueue { return $0.daysInQueue > $1.daysInQueue }
        // 3. Shorter tasks first (quick wins reduce overwhelm)
        return $0.estimatedMinutes < $1.estimatedMinutes
    }
}

private var actions: [TimedTask] {
    prioritySorted(tasks.filter { $0.bucket == .action && !$0.isDoFirst && !completedIds.contains($0.id) })
}
// Apply prioritySorted to replies, calls, readsToday, readsWeek similarly
```

***

### F-07 · Today view shows no scheduled start times

**File:** `Sources/Features/Today/TodayPane.swift`, `TodayTaskRow`

Tasks in the Today view have no `scheduledStart: Date?` property surfaced in the UI. The user sees a flat list of tasks organised by bucket but has no indication of *when* each block is scheduled. `sendToCalendar()` in `PlanPane` computes start times, but these are never read back into the Today view.

**Comparison:**
- Sunsama's Today column shows tasks with draggable time blocks on a timeline.
- Motion shows a mini-timeline on the right side of each task row.

**Fix — `TimedTask` model, add `scheduledStart: Date?`; in `TodayTaskRow`, surface it:**

```swift
// In TodayTaskRow.body, add to the HStack after the title VStack:
if let start = task.scheduledStart {
    Text(start, format: .dateTime.hour().minute())
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.indigo)
        .monospacedDigit()
}
```

`PlanPane.sendToCalendar()` should write the cursor time back to `tasks[idx].scheduledStart = cursor` before appending to `blocks`.

***

### F-08 · `moodContext: nil` hardcoded in `PlanPane.generate()`

**File:** `Sources/Features/Plan/PlanPane.swift`
**Function:** `PlanPane.generate()`

```swift
// Line in generate():
moodContext: nil,   // ← always nil
```

The `MorningInterview` flow (covered in Thread 2) captures the user's energy rating. The `PlanRequest` model accepts a `moodContext` field. But `PlanPane` never reads the morning interview output — it hardcodes `nil`. The planner therefore ignores whether the user said "low energy" and will happily sequence a 90-minute deep-work block first.

**Comparison:**
- Reclaim.ai's scheduling preferences include explicit "morning person / evening person" settings that gate high-focus task scheduling.

**Fix — pass mood from shared app state:**

```swift
// PlanPane needs a @State or @Binding var moodScore: Int?
// In generate():
moodContext: moodScore.map { MoodContext(score: $0, capturedAt: Date()) },
```

`MorningInterviewPane` should write `moodScore` to `@AppStorage("morningMoodScore")` and `PlanPane` reads it via `@AppStorage`.

***

### F-09 · `behaviouralRules: []` hardcoded in `PlanPane.generate()`

**File:** `Sources/Features/Plan/PlanPane.swift`
**Function:** `PlanPane.generate()` line: `behaviouralRules: []`

Thread 6 established that `BehaviourRules` are stored in Supabase and govern task sequencing (e.g. "always reply to family emails first", "no deep work after 4 pm"). The `PlanRequest` accepts `behaviouralRules: [BehaviourRule]` but `PlanPane` always passes an empty array, meaning the rules engine inside `PlanningEngine` runs against zero rules.

**Fix — inject rules from AuthService/Supabase at plan time:**

```swift
// In PlanPane.generate(), before constructing PlanRequest:
let rules = await BehaviourRulesService.shared.loadActive()

let request = PlanRequest(
    ...
    behaviouralRules: rules,
    ...
)
```

`BehaviourRulesService` was already introduced in Thread 6 — this is purely a wiring fix.

***

### F-10 · `sendToCalendar()` writes only to local `@Binding var blocks`

**File:** `Sources/Features/Plan/PlanPane.swift`
**Function:** `PlanPane.sendToCalendar()`

The "Send to Calendar" button appends to the in-memory `blocks` binding, which writes to the CalendarSync panel inside the app. It does **not** call `EKEventStore` to write events to the system calendar (macOS Calendar.app, Google Calendar via CalDAV). For an executive user who lives in their calendar, this means the Timed plan is invisible in every other tool.

**Fix — add `EKEventStore` export after appending to blocks:**

```swift
import EventKit

private func sendToCalendar() {
    // ... existing cursor calculation ...
    for item in generatedPlan {
        // Existing local block append
        let block = CalendarBlock(...)
        blocks.append(block)

        // NEW: Write to system calendar
        Task {
            let store = EKEventStore()
            let granted = try? await store.requestFullAccessToEvents()
            guard granted == true else { return }
            let event = EKEvent(eventStore: store)
            event.title     = item.task.title
            event.startDate = block.startTime
            event.endDate   = block.endTime
            event.calendar  = store.defaultCalendarForNewEvents
            try? store.save(event, span: .thisEvent)
        }
        cursor = cursor.addingTimeInterval(duration + 5 * 60)
    }
}
```

Requires `NSCalendarsUsageDescription` in `Info.plist` and `NSCalendarsWriteOnlyAccessUsageDescription`.

***

### F-11 · "Session 1 of 3" is a hardcoded string

**File:** `Sources/Features/Focus/FocusPane.swift`
**Function:** `FocusPane.infoCell("Session", "1 of 3")`

The info strip at the bottom of `FocusPane` shows `Session: 1 of 3`. Both the current session number and the total are hardcoded string literals. There is no Pomodoro session counter, no state persisted between sessions, and no UI to configure the target session count.

**Fix — add session state to `FocusPane`:**

```swift
@State private var completedSessions: Int = 0
@State private var targetSessions: Int = 3

// In .onChange(of: session.phase):
if newPhase == .idle && session.didFinishNaturally {
    completedSessions += 1
    showNextPrompt = true
}

// In infoCell:
infoCell("Session", "\(completedSessions + 1) of \(targetSessions)")
```

`targetSessions` should be `@AppStorage("focus.targetSessions")` defaulting to 3 with a settings picker offering 1–6.

***

### F-12 · No streak tracking

**Files:** `Sources/Core/Services/DataStore.swift`, `Sources/Features/Today/TodayPane.swift`

The `CompletionRecord` model (persisted by `DataStore`) has `completedAt: Date` but no streak inference runs against it. There is no `StreakEngine`, no streak display in `TodayPane`'s header, and no `@AppStorage` key tracking the current streak. For a single executive user, a 7-day "planned every day" streak is one of the highest-leverage motivation levers available.

**Fix — `DataStore.swift`, add streak helpers, and surface in `TodayPane` header:**

```swift
// StreakEngine.swift (new file)
enum StreakEngine {
    static func currentStreak(_ records: [CompletionRecord]) -> Int {
        let calendar = Calendar.current
        let days = Set(records.map { calendar.startOfDay(for: $0.completedAt) })
        var streak = 0
        var date = calendar.startOfDay(for: Date())
        while days.contains(date) {
            streak += 1
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        return streak
    }
}

// In TodayPane header HStack, after dateString:
if streak > 1 {
    Label("\(streak) day streak", systemImage: "flame.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.orange)
}
```

***

### F-13 · No end-of-day review flow

**Files:** Missing — no `EndOfDayPane.swift` or equivalent.

There is no end-of-day review ritual. The user completes tasks throughout the day, but Timed never prompts them to: review what was done, defer incomplete items, capture notes, or prepare tomorrow's queue. The `completedIds` set is in-memory and is only preserved via `tasks[idx].isDone` — there is no summary view.

**Comparison:**
- Sunsama's end-of-day review is a mandatory "shutdown ritual" that asks: (1) did you complete your plan, (2) what do you carry forward, (3) rate your day.
- Centered has a post-session debrief that shows session stats.

**Fix — add `EndOfDayPane.swift` triggered at 5 PM or on app quit:**

```swift
// Triggered from AppDelegate.applicationWillTerminate or a TimedNotificationScheduler
// reminder scheduled at 5 PM daily

struct EndOfDayPane: View {
    let completedTasks: [TimedTask]
    let remainingTasks: [TimedTask]
    let totalFocusSeconds: Int

    var body: some View {
        VStack(spacing: 24) {
            Text("Day complete")
                .font(.system(size: 24, weight: .semibold))
            // Stats: tasks done, total focus time, streak
            // Carry-forward: list of remaining tasks with defer/delete/keep options
            // Rating: 1–5 star day quality (persisted to CompletionRecord-level daily record)
        }
    }
}
```

Fire the 5 PM reminder via `TimedNotificationScheduler`:
```swift
func scheduleEndOfDayReview() async {
    let content = UNMutableNotificationContent()
    content.title = "Day review"
    content.body  = "3 minutes to close the loop."
    content.sound = .default
    var components = DateComponents()
    components.hour = 17; components.minute = 0
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    try? await UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: "eod.review", content: content, trigger: trigger)
    )
}
```

***

### F-14 · Free-time slot banner is read-only

**File:** `Sources/Features/Today/TodayPane.swift`
**Code block:** `if let nextFree = freeTimeSlots.first(where:...)`

The free-time banner shows the next gap and has a "Dish Me Up" CTA, but it calls `onDishMeUp` which navigates to PlanPane — the user then has to re-enter the available minutes manually. The `nextFree.durationMinutes` value is right there but not forwarded.

**Fix — pass `durationMinutes` to `onDishMeUp`:**

```swift
// Change closure signature:
let onDishMeUp: (Int?) -> Void  // nil = manual, Int = pre-filled minutes

// In banner:
Button("Dish Me Up") { onDishMeUp(nextFree.durationMinutes) }

// In PlanPane, accept optional pre-fill:
@Binding var prefilledMinutes: Int?

.onAppear {
    if let pre = prefilledMinutes {
        availableMinutes = pre
        useCustom = false
        generate()
        prefilledMinutes = nil
    }
}
```

***

### F-15 · No weekly reflection prompt

**Files:** Missing.

`InsightsEngine.suggestedAdjustments()` surfaces per-bucket accuracy insights in the Today banner (cite:10). But there is no weekly rollup: no "this week you completed X tasks in Y focus hours, your most productive day was Tuesday" view. The `hourOfDay` and `dayOfWeek` fields in `BehaviourEventInsert` are uploaded to Supabase but never read back for a weekly report.

**Fix — add a `WeeklyReflectionService` that runs each Monday morning:**

```swift
func buildWeeklyReport(from records: [CompletionRecord]) -> WeeklyReport {
    let week = records.filter { Calendar.current.isDateInThisWeek($0.completedAt) }
    return WeeklyReport(
        tasksCompleted: week.count,
        totalFocusMinutes: week.reduce(0) { $0 + ($1.actualMinutes ?? 0) },
        mostProductiveDay: mostProductiveDayOfWeek(week),
        topBucket: topBucket(week),
        estimationAccuracy: InsightsEngine.accuracyByBucket(week)
    )
}
```

Surface this as a sheet on Monday morning's first app open, using a `@AppStorage("lastWeeklyReportShown")` gate.

***

### F-16 · No energy curve visualisation

**Files:** Missing visualisation layer; data exists in Supabase via `BehaviourEventInsert.hourOfDay`.

The `hourOfDay` field is logged on every `task_completed` event (cite:6). This is exactly the data needed to build a 24-hour completion heatmap — "when do you actually get things done?" — which is the kind of insight that makes an executive user trust an app. Nothing reads this data back.

**Fix — add a `ProductivityHeatmap` view in a new Analytics pane:**

```swift
struct ProductivityHeatmap: View {
    let completionsByHour: [Int: Int] // hour → count

    var body: some View {
        HStack(spacing: 3) {
            ForEach(6..<22, id: \.self) { hour in
                let count = completionsByHour[hour, default: 0]
                let maxCount = completionsByHour.values.max() ?? 1
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.indigo.opacity(Double(count) / Double(maxCount)))
                    .frame(width: 16, height: 40)
                    .overlay(
                        Text("\(hour)")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary),
                        alignment: .bottom
                    )
            }
        }
    }
}
```

***

### F-17 · Quick-add hardcodes `estimatedMinutes: 15`

**File:** `Sources/Features/Today/TodayPane.swift`
**Function:** `TodayPane.submitQuickTask()`

```swift
let newTask = TimedTask(..., estimatedMinutes: 15, ...)
```

The EMA bucket estimates are already loaded into `DataStore.loadBucketEstimates()` at app start. Using the learned mean for the selected `quickBucket` would make quick-add immediately more accurate.

**Fix:**

```swift
@State private var bucketEstimates: [String: BucketEstimate] = [:]

// Load in .task block alongside InsightsEngine:
bucketEstimates = (try? await DataStore.shared.loadBucketEstimates()) ?? [:]

// In submitQuickTask():
let estimatedMins = Int(bucketEstimates[quickBucket.rawValue]?.meanMinutes ?? 15)
let newTask = TimedTask(..., estimatedMinutes: estimatedMins, ...)
```

***

## Competitive Benchmarks

### Focus Mode Comparison

| Dimension | Timed (current) | Forest | Centered | Focusmate |
|-----------|----------------|--------|----------|-----------|
| Timer mechanism | Swift async task, 1-sec tick | Native countdown | Electron timer | Video call clock |
| Completion notification | ❌ None | ✅ System notification + sound | ✅ macOS notification + voice | ✅ Partner confirms end |
| Ambient indicator | ❌ Sheet only | ✅ Growing tree (global) | ✅ Menu bar progress ring | ✅ Partner window |
| Distraction guard | ❌ None | ✅ App whitelist | ✅ Website blocker | ✅ Social accountability |
| Session persistence | ❌ Ephemeral | ✅ Full history | ✅ Full history | ✅ Full history |
| macOS Focus Filter | ❌ Absent | ❌ Absent | ✅ Full FocusFilterIntent | ❌ Absent |

### Today View Comparison

| Dimension | Timed (current) | Sunsama | Motion |
|-----------|----------------|---------|--------|
| Task ordering | Bucket-categorical, insertion order within buckets | ML-scored + drag-confirm morning ritual | Auto-scheduled by deadline + duration |
| Time-blocking | ❌ No start times visible | ✅ Timeline column with drag-resize | ✅ AI auto-places blocks |
| Energy awareness | ❌ moodContext always nil | ✅ Morning ritual sets energy | ✅ User-defined "peak hours" |
| Intra-section sort | ❌ None | ✅ Priority + user drag | ✅ Deadline-first |

### Plan View Comparison

| Dimension | Timed (current) | Reclaim.ai |
|-----------|----------------|------------|
| Plan generation | Bucket-priority sequence for N minutes | Constraint-solving scheduler across full calendar |
| Drag-drop time-blocking | ❌ Immutable list | ✅ Full drag-resize on calendar grid |
| Gap-filling | ❌ No real gap awareness | ✅ Fills exact free slots between hard events |
| Calendar export | ❌ Local blocks only | ✅ Native EKEventStore + sync |
| Rules/preferences | ❌ behaviouralRules: [] | ✅ Scheduling hours, buffer rules, priority locks |
| Re-schedule on conflict | ❌ None | ✅ Real-time rescheduling on calendar change |

***

## Recommended Sprint Order (Single Executive User)

| Sprint | Findings | Effort | User Impact |
|--------|----------|--------|-------------|
| Sprint 1 (2 days) | F-01, F-02 (notifications), F-05 (focus logger) | Small | Immediate — app is no longer silent |
| Sprint 2 (2 days) | F-04 (session persistence), F-11 (session counter), F-17 (smart quick-add) | Small-Medium | Focus loop becomes a real data producer |
| Sprint 3 (3 days) | F-08, F-09 (mood + rules wiring), F-06 (intra-section sort), F-07 (start times in Today) | Medium | Planning quality jumps noticeably |
| Sprint 4 (3 days) | F-13 (end-of-day review), F-12 (streak tracking) | Medium | Closure ritual and motivation layer |
| Sprint 5 (5 days) | F-03 (FocusFilter entitlement), F-10 (EKEventStore export), F-15, F-16 (weekly reflection + heatmap) | Large | A+ polish layer |