# Timed — Thread 8: CalendarSync & Calendar Feature Deep Audit

**Repo:** `ammarshah1n/time-manager-desktop` · **Branch:** `ui/apple-v1-restore`
**Files audited:** `Sources/Core/Services/CalendarSyncService.swift` · `Sources/Features/Calendar/CalendarPane.swift` · `Sources/Core/Models/CalendarBlock.swift` · `Sources/Core/Services/AuthService.swift` (calendar auth portions) · `Sources/Core/Clients/GraphClient.swift` · `Sources/Core/Services/PlanningEngine.swift` · `Sources/Features/TimedRootView.swift`

***

## Executive Summary

The calendar subsystem is the weakest engine link in the entire Timed stack. There are **zero EventKit imports** anywhere in the codebase — Timed bypasses Apple's native calendar entirely and fetches only from Outlook/Graph. Calendar data flows read-only and today-only into a local view state; it **never reaches PlanningEngine** as a constraint. Free-time slots are computed correctly but are orphaned in the UI — they never reduce `availableMinutes` in a `PlanRequest`. There is no bidirectional sync, no meeting-prep block generation, no post-meeting action item extraction, and no calendar delta query. For a single executive whose calendar is the ground truth of their day, this is the highest-ROI area to fix in the entire application.

***

## Impact-Ranked Findings

| # | Finding | Severity | Files Affected |
|---|---------|----------|----------------|
| F1 | `CalendarBlock` never fed into `PlanningEngine` — engine is blind to meetings | **CRITICAL** | `PlanningEngine.swift`, `TimedRootView.swift`, `DishMeUpSheet` |
| F2 | `AuthService` calendar scope gap — Graph token absent = silent skip | **HIGH** | `AuthService.swift` |
| F3 | Today-only fetch, no delta/incremental sync | **HIGH** | `CalendarSyncService.swift`, `GraphClient.swift` |
| F4 | Sync is entirely one-way (no Timed → Calendar push) | **HIGH** | `GraphClient.swift`, `CalendarBlock.swift` |
| F5 | No meeting prep block auto-generation | **HIGH** | `CalendarSyncService.swift`, `GraphClient.swift` |
| F6 | Naive conflict resolution — fetched blocks can overwrite user-created blocks | **MEDIUM** | `CalendarPane.swift` (syncCalendar) |
| F7 | `CalendarBlock` model lacks critical metadata (attendees, recurrence, importance) | **MEDIUM** | `CalendarBlock.swift`, `GraphClient.swift` |
| F8 | No EventKit integration — Apple Calendar events invisible | **MEDIUM** | None (feature missing entirely) |
| F9 | No calendar analytics — meeting load, fragmentation, trends | **MEDIUM** | None (feature missing entirely) |
| F10 | Free-time slots rendered today-column only; no multi-day visualization | **LOW** | `CalendarPane.swift` (CalendarGrid) |

***

## F1 — CRITICAL: PlanningEngine is Calendar-Blind

### What the code shows

`PlanningEngine.generatePlan(_ request: PlanRequest)` receives a `PlanRequest` struct that contains `availableMinutes: Int`, `tasks`, `behaviouralRules`, and `bucketStats`. There is no `calendarBlocks` or `busyMinutes` parameter anywhere in `PlanRequest`. The free-time detection logic in `CalendarSyncService.detectFreeTime()` correctly computes the gaps between events within the 09:00–18:00 workday, but the computed `[FreeTimeSlot]` array is stored only in `TimedRootView`'s local `@State private var freeTimeSlots` — it is passed to `TodayPane` and `CalendarPane` for display purposes and **never passed to `DishMeUpSheet` or the plan generation call**.

`DishMeUpSheet` receives only `$tasks`:
```swift
// TimedRootView.swift — dishMeUpSheet
DishMeUpSheet(tasks: $tasks) { ... }
```

No `blocks` or `freeTimeSlots` binding is passed. This means that on a day where the executive has 4 hours of back-to-back meetings, Timed will cheerfully plan the same number of tasks as a clear day.

### Fix

**Step 1 — Extend `PlanRequest`:**
```swift
// PlanningEngine.swift
struct PlanRequest: Sendable {
    // ... existing fields ...
    let calendarBusyMinutes: Int          // NEW: sum of meeting durations today
    let nextMeetingAt: Date?              // NEW: earliest upcoming meeting start
    let meetingBlockCount: Int            // NEW: for fragmentation warnings
}
```

**Step 2 — Compute `availableMinutes` dynamically in `TimedRootView`:**
```swift
// TimedRootView.swift — computed property
private var todayAvailableMinutes: Int {
    let totalFree = freeTimeSlots.reduce(0) { $0 + $1.durationMinutes }
    return max(30, totalFree)   // floor at 30 min so plan is never empty
}

private var nextMeetingAt: Date? {
    blocks
        .filter { $0.category == .meeting && $0.startTime > Date() }
        .sorted { $0.startTime < $1.startTime }
        .first?.startTime
}
```

**Step 3 — Pass into `DishMeUpSheet`:**
```swift
DishMeUpSheet(
    tasks: $tasks,
    availableMinutes: todayAvailableMinutes,   // NEW
    nextMeetingAt: nextMeetingAt               // NEW
) { ... }
```

**Step 4 — Add a `timingBump` in `PlanningEngine.scoreTask()` for tasks that fit before the next meeting:**
```swift
// In scoreTask(), after existing timing rules:
if let nextMeeting = request.nextMeetingAt {
    let minutesUntilMeeting = Int(nextMeeting.timeIntervalSince(now) / 60)
    let effectiveDuration = bucketEstimates[task.bucketType].map { Int($0) } ?? task.estimatedMinutes
    if effectiveDuration <= minutesUntilMeeting - 5 {   // 5-min buffer
        timingBump += 150   // fits cleanly in current free slot
    }
}
```

***

## F2 — HIGH: Calendar Scope Gap in AuthService

### What the code shows

`AuthService.signInWithMicrosoft()` calls `client.auth.getOAuthSignInURL(provider: .azure, scopes: "email profile openid")` — no calendar scopes. The Supabase OAuth callback gives back only an identity token. Calendar access requires a **separate** `signInWithGraph()` call, which triggers a full MSAL interactive flow for `Calendars.Read`, `Calendars.ReadWrite`, and `offline_access`. However, `signInWithGraph()` is never triggered automatically — `startCalendarSyncIfReady()` in `TimedRootView` guards on `auth.graphAccessToken`, which will be `nil` for any user who only completed the Supabase sign-in flow. The calendar sync then silently bails:

```swift
// CalendarPane.syncCalendar()
guard let token = auth.graphAccessToken, !token.isEmpty else {
    TimedLogger.calendar.warning("Sync Calendar: No Graph access token — skipping sync")
    return
}
```

A user can be fully signed in and see a working app but never get calendar data.

### Fix

**Trigger Graph auth automatically after Supabase sign-in if not already acquired:**

```swift
// AuthService.swift — add after bootstrapWorkspace() completes
func restoreSession() async {
    // ... existing session restore ...
    await bootstrapWorkspace()
    // Auto-trigger Graph silent auth
    if graphAccessToken == nil {
        await signInWithGraph(loginHint: userEmail ?? "")
    }
}
```

**Add a visible Calendar onboarding prompt** in `CalendarPane` when `graphAccessToken` is nil:

```swift
// CalendarPane.swift — add to body
if auth.graphAccessToken == nil {
    ContentUnavailableView {
        Label("Connect Outlook Calendar", systemImage: "calendar.badge.exclamationmark")
    } description: {
        Text("Sign in with your Microsoft account to sync events.")
    } actions: {
        Button("Connect") { Task { await auth.signInWithGraph() } }
            .buttonStyle(.borderedProminent)
    }
}
```

***

## F3 — HIGH: Today-Only Fetch, No Incremental Sync

### What the code shows

`CalendarSyncService.fetchTodayEvents()` computes `startOfDay` and `endOfDay` for the current calendar day only. `GraphClient.fetchCalendarEvents()` calls `/me/calendarView?startDateTime=...&endDateTime=...` as a full calendarView query with `$top=100`. There is no `@deltaLink` stored for calendar events, no `lastSyncTimestamp`, and no `TimedScheduler` entry for periodic calendar refresh (contrast: email sync uses delta queries and background scheduling extensively). Every manual "Sync Calendar" button press re-fetches all of today's events from scratch.

### Fix

**Add delta sync to `CalendarSyncService`:**

```swift
// CalendarSyncService.swift
actor CalendarSyncService {
    private var lastDeltaLink: String?       // NEW — persisted between syncs
    private var lastSyncedDate: String?      // NEW — invalidate delta if day changes

    func fetchEvents(accessToken: String) async throws -> [CalendarBlock] {
        let today = DateFormatter.ymd.string(from: Date())
        
        // Invalidate delta if new day
        if lastSyncedDate != today { lastDeltaLink = nil }
        
        let (events, newDeltaLink) = try await graphClient.fetchCalendarEventsDelta(
            startOfWeek: currentWeekStart(),
            endOfWeek: currentWeekEnd(),
            deltaLink: lastDeltaLink,
            accessToken: accessToken
        )
        
        lastDeltaLink = newDeltaLink
        lastSyncedDate = today
        return events.compactMap(mapToBlock)
    }
}
```

**Add to `GraphClient`:**

```swift
// GraphClient.swift — new method in GraphClientDependency
var fetchCalendarEventsDelta: @Sendable (Date, Date, String?, String) async throws 
    -> ([GraphCalendarEvent], String?) = { _, _, _, _ in
    throw NotImplementedError(methodName: "fetchCalendarEventsDelta")
}
```

**Background auto-refresh via `TimedScheduler`:**

```swift
// TimedScheduler.swift — add a calendar refresh task
timer.schedule(every: 5 * 60) {   // every 5 minutes
    guard let token = await AuthService.shared.graphAccessToken else { return }
    try await CalendarSyncService.shared.fetchEvents(accessToken: token)
}
```

Persist `lastDeltaLink` to `UserDefaults` so it survives app restarts.

***

## F4 — HIGH: Sync is One-Way (No Timed → Calendar Push)

### What the code shows

`GraphClient` has no method for creating, updating, or deleting calendar events. `CalendarBlock.swift` has no `externalEventId: String?` field to track the corresponding Outlook event ID. When a user drags to create a block in `CalendarGrid`, it creates a local `CalendarBlock` with a new `UUID()` and calls `onCreate`, which appends to `blocks` — no Graph API call follows. Focus time blocks booked in `FocusPane` are similarly local-only. There is nowhere for the executive's calendar to reflect that they have committed to deep-focus time.

### Fix

**Step 1 — Extend `CalendarBlock`:**
```swift
// CalendarBlock.swift
struct CalendarBlock: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var sourceEmailId: UUID?
    var category: BlockCategory
    var externalEventId: String?        // NEW — Outlook event ID
    var isSynced: Bool = false          // NEW — pushed to remote
    var isLocalOnly: Bool = false       // NEW — user-created, not from Graph
}
```

**Step 2 — Add `createCalendarEvent` to `GraphClient`:**
```swift
var createCalendarEvent: @Sendable (String, Date, Date, String, String) async throws -> String
    = { _, _, _, _, _ in throw NotImplementedError(methodName: "createCalendarEvent") }
// Implementation: POST /me/events, returns new event ID
```

**Step 3 — Push on drag-create in `CalendarPane`:**
```swift
// CalendarPane.swift — syncCalendar() extension
private func pushBlockToCalendar(_ block: CalendarBlock) {
    guard let token = auth.graphAccessToken else { return }
    Task {
        let eventId = try? await CalendarSyncService.shared.createEvent(
            block: block, accessToken: token)
        if let eventId {
            await MainActor.run {
                if let idx = blocks.firstIndex(where: { $0.id == block.id }) {
                    blocks[idx].externalEventId = eventId
                    blocks[idx].isSynced = true
                }
            }
        }
    }
}
```

For an executive, being able to "defend" deep-focus time by having Timed auto-create a block in Outlook is more valuable than most other features.

***

## F5 — HIGH: No Meeting Prep Block Auto-Generation

### What the code shows

`CalendarSyncService` detects free-time gaps correctly but makes no use of meeting metadata to generate preparatory blocks. `GraphCalendarEvent` only fetches `id, subject, start, end, isAllDay, isCancelled, location` in the `$select` — the `body`, `attendees`, `importance`, and `onlineMeetingUrl` fields are not requested. There is no logic anywhere in the codebase to insert a "Prep: [Meeting Name]" block in the free slot preceding a meeting.

### Fix

**Step 1 — Expand `$select` in `fetchCalendarEvents`:**
```swift
// GraphClient.swift — fetchCalendarEvents implementation
let raw = "\(graphBaseURL)/me/calendarView"
    + "?startDateTime=\(start)"
    + "&endDateTime=\(end)"
    + "&$select=id,subject,start,end,isAllDay,isCancelled,location,importance,"
    + "attendees,bodyPreview,isOrganizer,seriesMasterId,recurrence,onlineMeetingUrl"
    + "&$top=100"
```

**Step 2 — Extend `GraphCalendarEvent`:**
```swift
struct GraphCalendarEvent: Codable, Identifiable, Sendable {
    // ... existing fields ...
    let importance: String?              // "low" | "normal" | "high"
    let attendees: [GraphAttendee]?
    let bodyPreview: String?
    let isOrganizer: Bool?
    let seriesMasterId: String?          // non-nil if recurring
    let onlineMeetingUrl: String?
}
```

**Step 3 — Auto-generate prep blocks in `CalendarSyncService`:**
```swift
// CalendarSyncService.swift — new method
func generatePrepBlocks(
    events: [CalendarBlock],
    prepDuration: Int = 10    // minutes; configurable from Prefs
) -> [CalendarBlock] {
    events
        .filter { $0.category == .meeting }
        .compactMap { meeting -> CalendarBlock? in
            let prepEnd = meeting.startTime
            let prepStart = prepEnd.addingTimeInterval(-Double(prepDuration * 60))
            // Only create prep block if the slot is genuinely free
            let overlaps = events.contains {
                $0.id != meeting.id && $0.startTime < prepEnd && $0.endTime > prepStart
            }
            guard !overlaps else { return nil }
            return CalendarBlock(
                id: UUID(), title: "Prep: \(meeting.title)",
                startTime: prepStart, endTime: prepEnd,
                sourceEmailId: nil, category: .focus,
                isLocalOnly: true
            )
        }
}
```

***

## F6 — MEDIUM: Naive Conflict Resolution

### What the code shows

`CalendarPane.syncCalendar()` removes all blocks whose IDs appear in `syncedBlockIDs`, then unconditionally appends the freshly fetched blocks:

```swift
blocks.removeAll { syncedBlockIDs.contains($0.id) }
syncedBlockIDs.removeAll()
// then:
blocks.append(contentsOf: fetched)
syncedBlockIDs = newIDs
```

There is no overlap check against user-created blocks (`isLocalOnly == true`). A user who drags a focus block from 10:00–11:00 and then hits "Sync Calendar" will not lose that block today — but if a newly fetched meeting spans the same slot, both are rendered overlapping with no UI indication of the conflict.

### Fix

```swift
// CalendarPane.swift — replace the merge section in syncCalendar()
let userBlocks = blocks.filter { !syncedBlockIDs.contains($0.id) }  // user-created only

// Remove fetched events that fully overlap a user-created focus/admin block
let filteredFetched = fetched.filter { incoming in
    !userBlocks.contains { userBlock in
        userBlock.category == .focus &&
        incoming.startTime < userBlock.endTime &&
        incoming.endTime > userBlock.startTime
    }
}

blocks = userBlocks + filteredFetched
syncedBlockIDs = Set(filteredFetched.map(\.id))
```

For conflicting user focus blocks that a meeting partially overlaps, surface a macOS notification: `"⚠️ [Meeting] overlaps your 10–11am focus block."` This is the executive-first equivalent of Reclaim's "conflict defender."

***

## F7 — MEDIUM: Anemic `CalendarBlock` Model

### What the code shows

The `CalendarBlock` struct contains only six fields: `id`, `title`, `startTime`, `endTime`, `sourceEmailId`, `category`. The `detectCategory()` function in `CalendarSyncService` uses a keyword heuristic over title strings only — there are 3 transit keywords and 5 focus keywords; everything else defaults to `.meeting`. There is no attendee count, no recurrence flag, no importance level, and no organizer indicator. As a result, a 1:1 check-in, a 12-person board meeting, and a recurring weekly standup are all scored identically.

### Fix

**Extend `CalendarBlock`:**
```swift
struct CalendarBlock: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var sourceEmailId: UUID?
    var category: BlockCategory
    // NEW metadata fields
    var externalEventId: String?
    var isLocalOnly: Bool = false
    var isSynced: Bool = false
    var attendeeCount: Int = 0
    var isRecurring: Bool = false
    var importance: MeetingImportance = .normal
    var location: String?
    var isOrganizer: Bool = false
    var onlineMeetingUrl: String?
}

enum MeetingImportance: String, Codable, Sendable {
    case low, normal, high
}
```

**Enrich `detectCategory()` with attendee count and importance:**
```swift
private func detectCategory(title: String, importance: String?, attendeeCount: Int) -> BlockCategory {
    let lower = title.lowercased()
    if transitKeywords.contains(where: { lower.contains($0) }) { return .transit }
    if focusKeywords.contains(where: { lower.contains($0) }) { return .focus }
    if attendeeCount == 0 { return .focus }           // solo block
    if attendeeCount == 1 { return .meeting }          // 1:1
    return .meeting
}
```

***

## F8 — MEDIUM: No EventKit / Apple Calendar Integration

### What the code shows

Zero references to `EventKit`, `EKEventStore`, `EKAuthorizationStatus`, or `EKEvent` exist anywhere in the repository. The app is exclusively wired to Microsoft Graph. A user whose calendar is Apple Calendar, Google Calendar (via Apple Calendar subscription), or any CalDAV source has no way to sync.

### Fix

For a single executive using macOS, EventKit should be an **additive** source rather than a replacement. Add an `EventKitSyncService` that reads `EKEvent` objects from `EKEventStore` and maps them to `CalendarBlock` using the same `detectCategory()` logic:

```swift
// Sources/Core/Services/EventKitSyncService.swift (new file)
import EventKit

actor EventKitSyncService {
    private let store = EKEventStore()

    func requestAccess() async throws -> Bool {
        if #available(macOS 14, *) {
            return try await store.requestFullAccessToEvents()
        } else {
            return try await store.requestAccess(to: .event)
        }
    }

    func fetchTodayEvents() -> [CalendarBlock] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 7, to: start)!  // week look-ahead
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred)
            .filter { !$0.isAllDay }
            .map { mapEKEvent($0) }
    }

    private func mapEKEvent(_ event: EKEvent) -> CalendarBlock {
        CalendarBlock(
            id: UUID(), title: event.title ?? "Untitled",
            startTime: event.startDate, endTime: event.endDate,
            sourceEmailId: nil,
            category: detectCategory(title: event.title ?? ""),
            isLocalOnly: false,
            attendeeCount: event.attendees?.count ?? 0,
            isRecurring: event.hasRecurrenceRules,
            isOrganizer: event.organizer?.isCurrentUser == true
        )
    }
}
```

Request permission during onboarding alongside Graph auth. Merge EventKit results with Graph results, deduplicating by `startTime + title` to avoid showing the same event twice (Outlook events are often mirrored into Apple Calendar via the system account).

***

## F9 — MEDIUM: No Calendar Analytics

The `InsightsEngine.swift` file is a stub (940 bytes) that does not consume calendar data. There is no computation of meeting load percentage, average deep-focus hours per day, or fragmentation score. For a single executive, three metrics are highest priority:

**Add to `CalendarSyncService`:**

```swift
struct CalendarDaySummary: Sendable {
    let date: Date
    let meetingMinutes: Int
    let focusMinutes: Int              // contiguous blocks >= 90 min
    let fragmentedSlots: Int           // free slots < 30 min
    let meetingCount: Int
    var meetingLoadPct: Double { Double(meetingMinutes) / (9 * 60) }   // vs 9h day
}

func summariseDay(_ blocks: [CalendarBlock]) -> CalendarDaySummary {
    let meetings = blocks.filter { $0.category == .meeting }
    let meetingMins = meetings.reduce(0) {
        $0 + Int($1.endTime.timeIntervalSince($1.startTime) / 60)
    }
    let freeSlots = detectFreeTime(events: blocks)
    let focusMins = freeSlots.filter { $0.durationMinutes >= 90 }
                             .reduce(0) { $0 + $1.durationMinutes }
    let fragmented = freeSlots.filter { $0.durationMinutes < 30 }.count
    return CalendarDaySummary(
        date: Date(), meetingMinutes: meetingMins, focusMinutes: focusMins,
        fragmentedSlots: fragmented, meetingCount: meetings.count
    )
}
```

Expose this in `TodayPane` as a single-line contextual banner: `"6h in meetings today — 1 focus block available (2h)"`.

***

## F10 — LOW: Free-Time Slots Only Rendered Today

### What the code shows

`CalendarGrid` renders `FreeTimeSlotCell` entries exclusively on the `todayIdx` column:

```swift
if let ti = todayIdx {
    ForEach(freeTimeSlots) { slot in
        // ... renders only at x = kTimeW + colW * CGFloat(ti) + 2
    }
}
```

The `detectFreeTime()` algorithm already filters to today's events so extension to multi-day would require refactoring `detectFreeTime()` to accept a `Date` parameter.

### Fix

```swift
// CalendarSyncService.swift — generalise detectFreeTime
func detectFreeTime(events: [CalendarBlock], for date: Date, ...) -> [FreeTimeSlot]
// Change filter from: cal.isDateInToday($0.startTime)
// To:               cal.isDate($0.startTime, inSameDayAs: date)
```

```swift
// CalendarGrid — render for each weekday column
ForEach(Array(dates.enumerated()), id: \.offset) { dayIdx, date in
    let daySlots = freeTimeSlots.filter {
        Calendar.current.isDate($0.start, inSameDayAs: date)
    }
    ForEach(daySlots) { slot in
        FreeTimeSlotCell(slot: slot)
            .frame(width: colW - 4, height: slotHeight(slot))
            .offset(x: kTimeW + colW * CGFloat(dayIdx) + 2, y: slotYOffset(slot))
    }
}
```

***

## Comparison: Reclaim.ai, Clockwise, and Timed

| Capability | Reclaim.ai | Clockwise | Timed (current) |
|-----------|-----------|-----------|-----------------|
| Calendar source | Google Calendar + Outlook (bidirectional) | Google Calendar (bidirectional) | Outlook only, read-only |
| EventKit / native macOS | Via GCal | Via GCal | None |
| Incremental sync | Delta queries, real-time webhooks | Real-time sync | Manual button, today-only |
| Task → Calendar push | Auto-schedules tasks as events | Focus Time blocks auto-created | No push capability |
| Meeting conflict defense | Auto-reschedules tasks around meetings | Clusters meetings, protects Focus Time | No defense, planning engine blind |
| Meeting prep blocks | Auto-generates buffer blocks | Travel time blocks | Not implemented |
| Attendee / importance scoring | Yes (attendee count, organizer) | Yes (ML model) | Keyword heuristic only |
| Calendar analytics | Dashboard with trends | Weekly focus report | None |
| Recurrence awareness | Yes — schedules around recurring meetings | Yes | No recurrence field in model |

The most important structural gap separating Timed from these products is that Reclaim and Clockwise treat the **calendar as the constraint layer** — the available-minutes budget is always derived from what the calendar leaves free, not entered manually. Timed currently does the inverse: the plan is generated from a user-reported available-minutes estimate that has no knowledge of what the calendar actually contains. Closing F1 (engine wiring) is the single change that would deliver the most value per line of code.

***

## What's Missing for A+ Calendar Integration

For a single executive user, the following roadmap would close the gap:

**Sprint 1 — Unblock the engine (F1 + F2)**
- Wire `freeTimeSlots` into `PlanRequest.availableMinutes` computation in `TimedRootView`
- Auto-trigger Graph silent auth on app launch; surface onboarding CTA in `CalendarPane` when token is missing
- Estimated effort: ~4 hours, no new dependencies

**Sprint 2 — Bidirectional sync + conflict defense (F4 + F6)**
- Add `createCalendarEvent` + `updateCalendarEvent` + `deleteCalendarEvent` to `GraphClient`
- Add `externalEventId` + `isLocalOnly` to `CalendarBlock`
- Implement conflict defender: prevent fetched meetings from overwriting user focus blocks
- Estimated effort: ~2 days

**Sprint 3 — Smart prep blocks + metadata richness (F5 + F7)**
- Expand `$select` in `fetchCalendarEvents` to include `attendees`, `importance`, `bodyPreview`, `recurrence`
- Implement `generatePrepBlocks()` in `CalendarSyncService`
- Surface meeting importance in `CalendarBlockCell` (colour intensity or badge)
- Estimated effort: ~1 day

**Sprint 4 — Incremental sync + EventKit (F3 + F8)**
- Add `@deltaLink` persistence to `CalendarSyncService`
- Add `EventKitSyncService` for Apple Calendar events
- Background 5-minute polling via `TimedScheduler`
- Estimated effort: ~2 days

**Sprint 5 — Analytics + multi-day free slots (F9 + F10)**
- Add `CalendarDaySummary` and a banner in `TodayPane`
- Generalise `detectFreeTime()` to work per-date for week view rendering
- Add weekly meeting-load trend chart in `PrefsPane` or a new Insights pane
- Estimated effort: ~1 day