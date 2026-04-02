# Timed — Calendar Signal Ingestion Spec

**Status:** Implementation-ready
**Last updated:** 2026-04-02
**Layer:** L1 — Signal Ingestion
**Implements:** `CalendarSyncService.swift`, writes to signal queue via `DataStore.swift`
**Dependencies:** `GraphClient.swift` (MSAL OAuth), `TimedLogger.swift`, `TimedScheduler.swift`

---

## 1. Overview

Calendar signals reveal how an executive allocates their most scarce resource — time. The calendar ingestion pipeline reads from Microsoft Graph, extracts event metadata, computes scheduling pattern metrics, and writes structured signals to the local signal queue. Computed signals (meeting density, back-to-back detection, overrun frequency, acceptance rate, free/busy inference) feed directly into L2/L3 for chronotype modelling and cognitive load estimation.

Observation only. Timed never creates, modifies, accepts, declines, or deletes calendar events.

---

## 2. Microsoft Graph Endpoints

### 2.1 Primary Endpoints

| Operation | Method | Endpoint | Scope Required |
|-----------|--------|----------|----------------|
| List events | GET | `/me/events` | `Calendars.Read` |
| Delta sync | GET | `/me/events/delta` | `Calendars.Read` |
| Get event | GET | `/me/events/{id}` | `Calendars.Read` |
| Calendar view (time range) | GET | `/me/calendarView` | `Calendars.Read` |

### 2.2 Query Parameters

Initial sync:
```
GET /me/events/delta
  ?$select=id,subject,start,end,attendees,organizer,location,
           isAllDay,isCancelled,recurrence,showAs,responseStatus,
           importance,sensitivity,categories,onlineMeetingUrl,
           seriesMasterId,type,createdDateTime,lastModifiedDateTime
  &$top=50
  &$orderby=start/dateTime desc
```

Calendar view (for density calculations):
```
GET /me/calendarView
  ?startDateTime={ISO8601}
  &endDateTime={ISO8601}
  &$select=id,subject,start,end,showAs,isCancelled,responseStatus
  &$top=100
```

Delta sync:
```
GET /me/events/delta
  ?$deltatoken={stored_token}
  &$select=<same fields>
  &$top=50
```

### 2.3 Delta Sync Mechanics

1. **First sync**: No delta token. Fetch events from 90 days ago to 30 days ahead (bootstrap window). Follow `@odata.nextLink` until exhausted. Store `@odata.deltaLink`.
2. **Subsequent syncs**: Use stored delta token. Receive only new/modified/deleted events since last sync.
3. **Token expiry**: HTTP 410 (Gone) → discard delta token, full re-sync.
4. **Sync trigger**: Every 5 minutes via `TimedScheduler`. Also triggered on app foreground after > 10 minutes background.
5. **Calendar view refresh**: Separate from delta sync. Fetches today + tomorrow for density/scheduling calculations. Runs every 15 minutes.

---

## 3. Captured Data

### 3.1 Direct Event Metadata (from Graph response)

| Field | Graph Property | Type | Notes |
|-------|---------------|------|-------|
| `eventId` | `id` | String | Graph unique ID |
| `subject` | `subject` | String | Event title/subject |
| `startTime` | `start.dateTime` + `start.timeZone` | Date | Parsed to local timezone |
| `endTime` | `end.dateTime` + `end.timeZone` | Date | Parsed to local timezone |
| `duration` | computed | TimeInterval | `endTime - startTime` in seconds |
| `isAllDay` | `isAllDay` | Bool | All-day events excluded from density calculations |
| `attendees` | `attendees` | `[CalendarAttendee]` | Name, email, type (required/optional), response status |
| `attendeeCount` | computed | Int | Count of `attendees` |
| `organiser` | `organizer.emailAddress` | `{name, address}` | Who created the event |
| `isOrganiser` | computed | Bool | True if organiser email matches user email |
| `location` | `location.displayName` | String? | Physical or virtual location |
| `hasOnlineMeeting` | derived | Bool | True if `onlineMeetingUrl` is non-nil or location contains Teams/Zoom/Meet URL |
| `isRecurring` | derived | Bool | True if `seriesMasterId` is non-nil or `type == "seriesMaster"` |
| `recurrencePattern` | `recurrence` | `RecurrencePattern?` | Type (daily/weekly/monthly), interval, days of week, range |
| `acceptanceStatus` | `responseStatus.response` | `CalendarResponse` | `.none`, `.organizer`, `.tentativelyAccepted`, `.accepted`, `.declined`, `.notResponded` |
| `isCancelled` | `isCancelled` | Bool | Event was cancelled |
| `showAs` | `showAs` | `FreeBusyStatus` | `.free`, `.tentative`, `.busy`, `.oof`, `.workingElsewhere`, `.unknown` |
| `importance` | `importance` | `low\|normal\|high` | Event importance |
| `sensitivity` | `sensitivity` | `normal\|personal\|private\|confidential` | Privacy level |
| `categories` | `categories` | `[String]` | Outlook colour categories |
| `createdAt` | `createdDateTime` | Date | When event was created in calendar |
| `modifiedAt` | `lastModifiedDateTime` | Date | Last modification |

### 3.2 NOT Captured

| Data | Reason |
|------|--------|
| Event body/notes | Often contains meeting agendas with sensitive content. Not needed for scheduling signals. |
| Attachment content on events | Same as email — binary data is out of scope. |
| Other users' calendar availability | Only the authenticated user's calendar. Never query others. |

---

## 4. Computed Fields

All computed fields are derived locally after raw data capture, before writing to signal queue. These feed L2 (Memory Store) and L3 (Reflection Engine) for chronotype and cognitive load modelling.

### 4.1 Meeting Density

```swift
/// Meetings per hour within a given time window.
/// Excludes all-day events, cancelled events, and declined events.
func computeMeetingDensity(
    events: [CalendarSignal],
    windowStart: Date,
    windowEnd: Date
) -> Double {
    let eligible = events.filter { event in
        !event.isAllDay
        && !event.isCancelled
        && event.acceptanceStatus != .declined
        && event.startTime >= windowStart
        && event.startTime < windowEnd
    }
    
    let windowHours = windowEnd.timeIntervalSince(windowStart) / 3600
    guard windowHours > 0 else { return 0 }
    
    return Double(eligible.count) / windowHours
}
```

**Computed windows:**
- Morning block: 08:00-12:00 (4h)
- Afternoon block: 12:00-17:00 (5h)
- Full day: 08:00-17:00 (9h)
- Rolling weekly average: sum of daily densities / 5 (weekdays only)

### 4.2 Back-to-Back Detection

```swift
/// Two events are back-to-back if the gap between them is <= threshold.
/// Default threshold: 0 minutes (end of one == start of next).
/// Extended threshold for "effectively back-to-back": 5 minutes.
struct BackToBackPair {
    let first: CalendarSignal
    let second: CalendarSignal
    let gapMinutes: Int
}

func detectBackToBack(
    events: [CalendarSignal],
    threshold: TimeInterval = 300  // 5 minutes
) -> [BackToBackPair] {
    let sorted = events
        .filter { !$0.isAllDay && !$0.isCancelled && $0.acceptanceStatus != .declined }
        .sorted { $0.startTime < $1.startTime }
    
    var pairs: [BackToBackPair] = []
    for i in 0..<(sorted.count - 1) {
        let gap = sorted[i + 1].startTime.timeIntervalSince(sorted[i].endTime)
        if gap <= threshold && gap >= 0 {
            pairs.append(BackToBackPair(
                first: sorted[i],
                second: sorted[i + 1],
                gapMinutes: Int(gap / 60)
            ))
        }
    }
    return pairs
}
```

**Derived metrics:**
- `backToBackCount`: Number of back-to-back pairs today.
- `backToBackStreak`: Maximum consecutive chain (3 meetings with no gap = streak of 3).
- `backToBackRate`: Pairs / total meetings for the day.

### 4.3 Overrun Frequency

Overruns are detected by comparing scheduled end time with the next event's start time when back-to-back, combined with app focus signals that show the meeting app remained active past the event end time.

```swift
/// An event "overran" if:
/// 1. It is followed by another event within 15 minutes (not necessarily back-to-back)
/// 2. AND app focus signals show meeting app (Teams/Zoom/FaceTime) was active
///    past the event's scheduled endTime
/// If app focus data is unavailable, overrun is inferred probabilistically
/// from the pattern: event ends at X, next event starts at X, user joins next event late.
struct OverrunEvent {
    let event: CalendarSignal
    let scheduledEnd: Date
    let estimatedActualEnd: Date    // From app focus or inference
    let overrunMinutes: Int
}

func computeOverrunFrequency(
    events: [CalendarSignal],
    window: DateInterval
) -> Double {
    let eligible = events.filter { event in
        !event.isAllDay && !event.isCancelled
        && event.acceptanceStatus != .declined
        && window.contains(event.startTime)
    }
    guard !eligible.isEmpty else { return 0 }
    
    let overruns = detectOverruns(events: eligible)
    return Double(overruns.count) / Double(eligible.count)
}
```

**Rolling metric:** 14-day rolling overrun rate. Stored as `overrunRate14d` in memory store.

### 4.4 Acceptance Rate

```swift
/// Proportion of event invitations (where user is NOT the organiser) that were accepted.
func computeAcceptanceRate(window: DateInterval) -> AcceptanceMetrics {
    let invitations = signals.filter { event in
        !event.isOrganiser
        && !event.isCancelled
        && window.contains(event.createdAt)
    }
    
    let accepted = invitations.filter { $0.acceptanceStatus == .accepted }
    let declined = invitations.filter { $0.acceptanceStatus == .declined }
    let tentative = invitations.filter { $0.acceptanceStatus == .tentativelyAccepted }
    let noResponse = invitations.filter { $0.acceptanceStatus == .notResponded }
    
    return AcceptanceMetrics(
        total: invitations.count,
        accepted: accepted.count,
        declined: declined.count,
        tentative: tentative.count,
        noResponse: noResponse.count,
        acceptanceRate: invitations.isEmpty ? 0 : Double(accepted.count) / Double(invitations.count),
        declineRate: invitations.isEmpty ? 0 : Double(declined.count) / Double(invitations.count)
    )
}
```

**Rolling metrics:**
- 7-day acceptance rate
- 30-day acceptance rate
- Per-organiser acceptance rate (do they always accept their manager's meetings but decline team standups?)

### 4.5 Free/Busy Inference

```swift
/// Derives the user's actual availability state for every 15-minute slot in a day.
/// Combines `showAs` status with actual event data.
enum SlotState {
    case free           // No event, or event with showAs == .free
    case busy           // Event with showAs == .busy or .oof
    case tentative      // Event with showAs == .tentative
    case focus          // No meeting, but app focus shows deep work app active > 30 min
    case fragmented     // Free slot < 30 min between two meetings
    case unknown
}

func inferFreeBusy(date: Date) -> [TimeSlot: SlotState] {
    // Generate 15-minute slots from 07:00 to 20:00 (52 slots)
    // Map each slot to its state based on overlapping events
    // A "fragmented" slot is free time < 30 minutes bounded by meetings on both sides
    // "focus" requires integration with L1 app focus signals
}
```

**Output:** A 52-slot daily availability map. This feeds directly into:
- **Chronotype estimation** (L3): When does the user consistently have free slots? When do they choose to schedule deep work?
- **Cognitive load estimation** (L3): High density + fragmented slots + back-to-back streaks = high cognitive load.

---

## 5. Signal Queue Write Path

### 5.1 Signal Schema

```swift
struct CalendarSignal: Codable, Identifiable {
    let id: UUID                           // Local signal ID
    let eventId: String                    // Graph event ID
    let subject: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let isAllDay: Bool
    let attendees: [CalendarAttendee]
    let attendeeCount: Int
    let organiser: EmailContact
    let isOrganiser: Bool
    let location: String?
    let hasOnlineMeeting: Bool
    let isRecurring: Bool
    let recurrencePattern: RecurrencePattern?
    let acceptanceStatus: CalendarResponse
    let isCancelled: Bool
    let showAs: FreeBusyStatus
    let importance: EventImportance
    let sensitivity: EventSensitivity
    let categories: [String]
    let createdAt: Date
    let modifiedAt: Date
    
    // Computed (populated post-capture or on-demand)
    var meetingDensityAtCapture: Double?    // Density for the day this event occurs
    var isBackToBack: Bool                 // Part of a back-to-back pair
    var backToBackGapMinutes: Int?         // Gap to adjacent event (if back-to-back)
    
    // Metadata
    let capturedAt: Date
    let syncBatchId: UUID
    let signalSource: SignalSource         // .calendar
}
```

### 5.2 Supporting Types

```swift
struct CalendarAttendee: Codable {
    let name: String
    let email: String
    let type: AttendeeType          // .required, .optional, .resource
    let responseStatus: CalendarResponse
}

enum CalendarResponse: String, Codable {
    case none, organizer, tentativelyAccepted, accepted, declined, notResponded
}

enum FreeBusyStatus: String, Codable {
    case free, tentative, busy, oof, workingElsewhere, unknown
}

struct RecurrencePattern: Codable {
    let type: RecurrenceType        // .daily, .weekly, .absoluteMonthly, .relativeMonthly
    let interval: Int               // Every N units
    let daysOfWeek: [DayOfWeek]?    // For weekly patterns
    let rangeType: RecurrenceRangeType  // .endDate, .noEnd, .numbered
    let rangeEndDate: Date?
    let numberOfOccurrences: Int?
}

struct AcceptanceMetrics: Codable {
    let total: Int
    let accepted: Int
    let declined: Int
    let tentative: Int
    let noResponse: Int
    let acceptanceRate: Double
    let declineRate: Double
}
```

### 5.3 Write Path

```
Graph API Response
  → JSON deserialization (Codable)
  → Timezone normalisation (all times to user's local timezone)
  → Deduplication check (eventId exists in store?)
    → If exists and modifiedAt changed: update signal
    → If exists and unchanged: skip
    → If new: create signal
    → If deleted (Graph returns @removed): mark as cancelled in store
  → Computed field derivation (density, back-to-back for affected day)
  → CoreData write (DataStore.saveCalendarSignal)
  → Post-write: recalculate daily metrics for affected dates
```

### 5.4 Deduplication

Primary key: `eventId` (Graph unique ID). Update logic mirrors email sync — compare `modifiedAt` to detect real changes. Recurring event instances share `seriesMasterId` but have unique `eventId` per occurrence.

---

## 6. Feeding L2/L3: Chronotype and Cognitive Load

### 6.1 Chronotype Estimation

Calendar signals provide essential data for L3's chronotype model:

| Signal | Contribution |
|--------|-------------|
| Free slot patterns over 30 days | When does the user consistently NOT have meetings? |
| Self-scheduled event times | When does the user CREATE events (vs receiving invitations)? |
| Focus time blocks (if user creates them) | Explicit signal of preferred deep work time |
| Meeting acceptance by time of day | Does the user decline afternoon meetings more often? |
| App focus deep work sessions (cross-signal with L1 app focus) | When does deep work actually happen? |

L3 consumes these as input to a chronotype classification:
- **Peak cognitive hours**: When the user does (or wants to do) their most demanding work.
- **Administrative hours**: When the user handles email, meetings, and reactive tasks.
- **Wind-down hours**: Declining engagement, shorter email replies, fewer context switches.

### 6.2 Cognitive Load Estimation

| Signal | Load Factor | Weight |
|--------|-------------|--------|
| Meeting density > 1.0/hour | High load | 0.3 |
| Back-to-back streak >= 3 | Very high load | 0.4 |
| Fragmented free time (< 30min slots) | Moderate load (no recovery) | 0.2 |
| Context switches (cross-signal) | Cumulative load | 0.1 |
| Overrun events | Load spill — scheduled recovery time consumed | 0.15 |
| All-day events (conferences, offsites) | Sustained high load | 0.35 |

L3's nightly reflection uses these weighted signals to produce a daily cognitive load score (0.0-1.0) and to detect patterns: "Mondays are consistently the highest cognitive load day" or "Cognitive load has increased 20% over the past 2 weeks."

---

## 7. Rate Limits and Error Handling

Identical policy to email sync (see `signal-email.md` Section 6 and Section 7). Same `GraphClient` infrastructure, same retry/backoff logic, same error categories.

Additional calendar-specific errors:

| Error | Action |
|-------|--------|
| Recurring event expansion failure | Log and skip. Fetch individual instances via `/me/events/{seriesMasterId}/instances`. |
| Timezone parsing failure | Fall back to UTC. Log warning. |
| Calendar view window too large (> 180 days) | Split into 30-day chunks. |

---

## 8. Privacy

- Only `Calendars.Read` scope — never `Calendars.ReadWrite` or any write scope.
- Event body/notes never fetched.
- Sensitivity-flagged events (`private`, `confidential`): subject is stored as "[Private]", attendees are not stored. Only times and duration are captured.
- Location details are stored only for non-private events.
- Other users' calendars are never queried.
- Same retention policy as email signals (180-day archive, 365-day purge).

---

## 9. Observation-Only Enforcement

```swift
// GraphClient.swift — Calendar methods
// OBSERVATION ONLY: GET requests exclusively.
// No createEvent(), updateEvent(), deleteEvent(), respondToEvent().

func fetchEvents(deltaToken: String?) async throws -> EventDeltaResponse { ... }
func fetchEvent(id: String) async throws -> GraphEvent { ... }
func fetchCalendarView(start: Date, end: Date) async throws -> [GraphEvent] { ... }
// No write methods exist. Enforced by code review and ObservationOnlyTests.
```

---

## 10. Acceptance Criteria

### 10.1 Functional

- [ ] Initial sync fetches events from 90 days ago to 30 days ahead.
- [ ] Delta sync fetches only new/modified/deleted events since last sync.
- [ ] All direct metadata fields (22 fields) are correctly extracted and stored.
- [ ] Duration is correctly computed from start/end times including timezone handling.
- [ ] Recurring events are correctly expanded (individual instances, not just series master).
- [ ] Cancelled events are marked, not deleted, in local store.
- [ ] Deleted events (Graph `@removed`) are marked as cancelled.
- [ ] Duplicate events (same `eventId`) are updated, not duplicated.
- [ ] Delta token is persisted and reused across app launches.

### 10.2 Computed Metrics

- [ ] Meeting density is calculated per morning/afternoon/full-day/weekly window.
- [ ] Back-to-back pairs are detected with configurable threshold (default 5 min).
- [ ] Back-to-back streak (consecutive chain) is computed correctly.
- [ ] Overrun frequency is computed from event data + app focus cross-signal.
- [ ] Acceptance rate is computed per 7-day and 30-day windows.
- [ ] Per-organiser acceptance rate is computed.
- [ ] Free/busy inference produces correct 15-minute slot map for a given day.
- [ ] All-day events, cancelled events, and declined events are excluded from density calculations.

### 10.3 Chronotype and Cognitive Load Feed

- [ ] Daily cognitive load score (0.0-1.0) is computed and stored.
- [ ] Free slot patterns are aggregated over 30-day window for chronotype input.
- [ ] Self-scheduled vs invited events are distinguished.
- [ ] All computed metrics are available in signal queue for L2/L3 consumption.

### 10.4 Observation-Only

- [ ] No POST, PATCH, PUT, or DELETE requests to Graph Calendar endpoints.
- [ ] No event RSVPs sent.
- [ ] No events created, modified, or deleted.
- [ ] `GraphClient` contains no write methods for calendar.

### 10.5 Privacy

- [ ] Only `Calendars.Read` scope requested.
- [ ] Event body/notes never fetched.
- [ ] Private/confidential events: subject redacted, attendees not stored.
- [ ] Other users' calendars never queried.

### 10.6 Performance

- [ ] Delta sync of 50 events completes in < 3 seconds.
- [ ] Initial sync of 500 events (90-day window) completes in < 30 seconds.
- [ ] Daily metric recalculation (density, back-to-back, overrun) completes in < 500ms.
- [ ] Free/busy inference for a single day completes in < 100ms.
- [ ] Sync does not block the main thread.
