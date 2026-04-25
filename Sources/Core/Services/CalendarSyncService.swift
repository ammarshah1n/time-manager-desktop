// CalendarSyncService.swift — Timed Core
// Fetches Outlook calendar events via GraphClient and converts them to CalendarBlocks.
// Also detects free-time gaps within the workday.

import Foundation
import Dependencies
import os

// MARK: - Free Time Slot

struct FreeTimeSlot: Identifiable, Sendable {
    let id = UUID()
    let start: Date
    let end: Date

    var durationMinutes: Int {
        Int(end.timeIntervalSince(start) / 60)
    }
}

// MARK: - Calendar Sync Service

actor CalendarSyncService {
    static let shared = CalendarSyncService()

    @Dependency(\.graphClient) private var graphClient
    @Dependency(\.supabaseClient) private var supabaseClient

    private var knownEventSchedules: [String: (start: Date, end: Date)] = [:]
    private var emittedCancelledEvents: Set<String> = []
    private var emittedAttendedEvents: Set<String> = []

    // MARK: - Background Sync Loop

    private var syncTask: Task<Void, Never>?
    private var isRunning = false
    var pollInterval: TimeInterval = 300 // 5 minutes — calendar changes less frequently than email

    /// Starts a background sync loop that periodically fetches calendar events and emits Tier 0 observations.
    func start(tokenProvider: @escaping @Sendable () async throws -> String) {
        guard !isRunning else { return }
        isRunning = true
        syncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    _ = try await self.autoSync(tokenProvider: tokenProvider)
                } catch {
                    TimedLogger.calendar.error("CalendarSyncService background sync error: \(error.localizedDescription, privacy: .public)")
                }
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    /// Stops the background sync loop.
    func stop() {
        syncTask?.cancel()
        syncTask = nil
        isRunning = false
    }

    // MARK: - Fetch Today's Events

    /// Fetches today's calendar events from Outlook and returns CalendarBlocks.
    ///
    /// - Parameter tokenProvider: Closure that returns a fresh Graph access token on each call.
    func fetchTodayEvents(tokenProvider: @escaping @Sendable () async throws -> String) async throws -> [CalendarBlock] {
        let accessToken = try await tokenProvider()
        return try await fetchTodayEvents(accessToken: accessToken)
    }

    /// Fetches today's calendar events using a pre-acquired access token.
    /// Prefer `fetchTodayEvents(tokenProvider:)` for automatic token refresh.
    func fetchTodayEvents(accessToken: String) async throws -> [CalendarBlock] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else {
            TimedLogger.calendar.error("Failed to compute end-of-day date")
            return []
        }

        TimedLogger.calendar.info("Fetching calendar events for today")

        let graphEvents = try await graphClient.fetchCalendarEvents(startOfDay, endOfDay, accessToken)

        TimedLogger.calendar.info("Fetched \(graphEvents.count) events from Outlook")

        let parsedEvents = graphEvents.compactMap { event -> ParsedCalendarEvent? in
            guard let startDate = parseGraphDateTime(event.start),
                  let endDate = parseGraphDateTime(event.end) else {
                TimedLogger.calendar.warning("Skipping event with unparseable dates: \(event.subject ?? "untitled", privacy: .private)")
                return nil
            }
            return ParsedCalendarEvent(event: event, startDate: startDate, endDate: endDate)
        }

        let backToBackEventIDs = makeBackToBackEventIDs(from: parsedEvents)
        for parsedEvent in parsedEvents {
            await emitCalendarObservationsIfPossible(
                for: parsedEvent,
                isBackToBack: backToBackEventIDs.contains(parsedEvent.event.id)
            )
        }

        let blocks = parsedEvents.compactMap { parsedEvent -> CalendarBlock? in
            let event = parsedEvent.event
            guard !event.isCancelled else { return nil }

            // Skip all-day events — they don't belong on the hour grid
            if event.isAllDay { return nil }

            let title = event.subject ?? "Untitled Event"
            let category = detectCategory(title: title)
            let names = event.attendees?.compactMap { $0.emailAddress?.name }.filter { !$0.isEmpty }

            return CalendarBlock(
                id: UUID(),
                title: title,
                startTime: parsedEvent.startDate,
                endTime: parsedEvent.endDate,
                sourceEmailId: nil,
                category: category,
                attendeeNames: names?.isEmpty == true ? nil : names
            )
        }

        TimedLogger.calendar.info("Converted \(blocks.count) events to CalendarBlocks")
        return blocks
    }

    // MARK: - Free Time Detection

    /// Detects free time gaps between calendar events within workday hours.
    /// Only returns gaps >= 15 minutes.
    func detectFreeTime(
        events: [CalendarBlock],
        workdayStart: Int = 9,
        workdayEnd: Int = 18
    ) -> [FreeTimeSlot] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        guard let dayStart = cal.date(bySettingHour: workdayStart, minute: 0, second: 0, of: today),
              let dayEnd = cal.date(bySettingHour: workdayEnd, minute: 0, second: 0, of: today) else {
            return []
        }

        // Filter to today's events only, sorted by start time
        let todayEvents = events
            .filter { cal.isDateInToday($0.startTime) }
            .sorted { $0.startTime < $1.startTime }

        var slots: [FreeTimeSlot] = []
        var cursor = dayStart

        for event in todayEvents {
            // Clamp event to workday bounds
            let eventStart = max(event.startTime, dayStart)
            let eventEnd = min(event.endTime, dayEnd)

            guard eventStart < dayEnd, eventEnd > dayStart else { continue }

            if eventStart > cursor {
                let gapMinutes = Int(eventStart.timeIntervalSince(cursor) / 60)
                if gapMinutes >= 15 {
                    slots.append(FreeTimeSlot(start: cursor, end: eventStart))
                }
            }

            cursor = max(cursor, eventEnd)
        }

        // Gap after last event until workday end
        if cursor < dayEnd {
            let gapMinutes = Int(dayEnd.timeIntervalSince(cursor) / 60)
            if gapMinutes >= 15 {
                slots.append(FreeTimeSlot(start: cursor, end: dayEnd))
            }
        }

        TimedLogger.calendar.info("Detected \(slots.count) free time slots")
        return slots
    }

    // MARK: - Auto Sync (fetch + free time detection)

    /// Convenience: fetches today's events and detects free time slots in one call.
    ///
    /// - Parameter tokenProvider: Closure that returns a fresh Graph access token on each call.
    func autoSync(tokenProvider: @escaping @Sendable () async throws -> String) async throws -> (blocks: [CalendarBlock], freeSlots: [FreeTimeSlot]) {
        let blocks = try await fetchTodayEvents(tokenProvider: tokenProvider)
        let freeSlots = detectFreeTime(events: blocks)
        return (blocks, freeSlots)
    }

    /// Convenience overload using a pre-acquired access token (no auto-refresh).
    func autoSync(accessToken: String) async throws -> (blocks: [CalendarBlock], freeSlots: [FreeTimeSlot]) {
        let blocks = try await fetchTodayEvents(accessToken: accessToken)
        let freeSlots = detectFreeTime(events: blocks)
        return (blocks, freeSlots)
    }

    // MARK: - Private Helpers

    private struct ParsedCalendarEvent: Sendable {
        let event: GraphCalendarEvent
        let startDate: Date
        let endDate: Date
    }

    private func emitCalendarObservationsIfPossible(
        for parsedEvent: ParsedCalendarEvent,
        isBackToBack: Bool
    ) async {
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return }
        guard let emission = calendarObservationEmission(for: parsedEvent) else { return }

        let attendeeCount = parsedEvent.event.attendees?.count ?? 0
        let durationMinutes = max(0, Int(parsedEvent.endDate.timeIntervalSince(parsedEvent.startDate) / 60))
        let isOrganiser = parsedEvent.event.isOrganizer ?? false
        let meetingType = inferMeetingType(for: parsedEvent.event)
        let rawData: [String: AnyCodable] = [
            "attendee_count": AnyCodable(attendeeCount),
            "duration_minutes": AnyCodable(durationMinutes),
            "is_organiser": AnyCodable(isOrganiser),
            "is_back_to_back": AnyCodable(isBackToBack),
            "meeting_type": AnyCodable(meetingType)
        ]

        let observation = Tier0Observation(
            profileId: executiveId,
            occurredAt: emission.occurredAt,
            source: .calendar,
            eventType: emission.eventType,
            entityType: "calendar_event",
            summary: calendarSummary(for: parsedEvent.event, eventType: emission.eventType),
            rawData: rawData,
            importanceScore: 0.5
        )
        do {
            try await Tier0Writer.shared.recordObservation(observation)
        } catch {
            TimedLogger.calendar.error("Tier0 calendar observation write failed: \(error.localizedDescription)")
        }

        let calendarObservation = CalendarObservationRow(
            id: UUID(),
            executiveId: executiveId,
            observedAt: emission.occurredAt,
            eventStart: parsedEvent.startDate,
            eventEnd: parsedEvent.endDate,
            attendeeCount: attendeeCount,
            organiserIsSelf: isOrganiser,
            responseStatus: parsedEvent.event.responseStatus?.response,
            wasCancelled: emission.eventType == "calendar.cancelled",
            wasRescheduled: emission.eventType == "calendar.rescheduled",
            originalStart: emission.originalStart
        )
        do {
            try await persistCalendarObservation(calendarObservation)
        } catch {
            TimedLogger.calendar.error("Calendar observation persist failed: \(error.localizedDescription)")
        }
    }

    private func calendarObservationEmission(for parsedEvent: ParsedCalendarEvent) -> CalendarObservationEmission? {
        let event = parsedEvent.event
        let previousSchedule = knownEventSchedules[event.id]
        let wasRescheduled = previousSchedule.map {
            $0.start != parsedEvent.startDate || $0.end != parsedEvent.endDate
        } ?? false
        knownEventSchedules[event.id] = (parsedEvent.startDate, parsedEvent.endDate)

        if event.isCancelled {
            let inserted = emittedCancelledEvents.insert(event.id).inserted
            guard inserted else { return nil }
            return CalendarObservationEmission(
                eventType: "calendar.cancelled",
                occurredAt: parsedEvent.startDate,
                originalStart: previousSchedule?.start
            )
        }

        if wasRescheduled {
            return CalendarObservationEmission(
                eventType: "calendar.rescheduled",
                occurredAt: parsedEvent.startDate,
                originalStart: previousSchedule?.start
            )
        }

        if parsedEvent.endDate <= Date(),
           isAttended(responseStatus: event.responseStatus?.response) {
            let inserted = emittedAttendedEvents.insert(event.id).inserted
            guard inserted else { return nil }
            return CalendarObservationEmission(
                eventType: "calendar.attended",
                occurredAt: parsedEvent.endDate,
                originalStart: nil
            )
        }

        if previousSchedule == nil {
            return CalendarObservationEmission(
                eventType: "calendar.event_created",
                occurredAt: parsedEvent.startDate,
                originalStart: nil
            )
        }

        return nil
    }

    private func persistCalendarObservation(_ observation: CalendarObservationRow) async throws {
        let isConnected = await NetworkMonitor.shared.isConnected
        guard isConnected, supabaseClient.rawClient != nil else {
            try await enqueueCalendarObservationOffline(observation)
            return
        }

        try await supabaseClient.insertCalendarObservation(observation)
    }

    private func enqueueCalendarObservationOffline(_ observation: CalendarObservationRow) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(observation)
        try await OfflineSyncQueue.shared.enqueue(
            operationType: "calendar_observations.insert",
            payload: payload
        )
    }

    private func makeBackToBackEventIDs(from parsedEvents: [ParsedCalendarEvent]) -> Set<String> {
        let sortedEvents = parsedEvents.sorted { $0.startDate < $1.startDate }
        guard sortedEvents.count > 1 else { return [] }

        var result: Set<String> = []
        let threshold: TimeInterval = 300

        for index in sortedEvents.indices {
            let currentEvent = sortedEvents[index]

            if index > 0 {
                let previousEvent = sortedEvents[index - 1]
                if abs(currentEvent.startDate.timeIntervalSince(previousEvent.endDate)) <= threshold {
                    result.insert(currentEvent.event.id)
                    result.insert(previousEvent.event.id)
                }
            }

            if index + 1 < sortedEvents.count {
                let nextEvent = sortedEvents[index + 1]
                if abs(nextEvent.startDate.timeIntervalSince(currentEvent.endDate)) <= threshold {
                    result.insert(currentEvent.event.id)
                    result.insert(nextEvent.event.id)
                }
            }
        }

        return result
    }

    private func inferMeetingType(for event: GraphCalendarEvent) -> String {
        let title = (event.subject ?? "").lowercased()
        let location = (event.location?.displayName ?? "").lowercased()

        if title.contains("1:1") || title.contains("one on one") {
            return "one_on_one"
        }
        if title.contains("board") {
            return "board"
        }
        if title.contains("interview") {
            return "interview"
        }
        if location.contains("zoom") || location.contains("teams") || location.contains("meet.google") {
            return "virtual"
        }

        return detectCategory(title: event.subject ?? "Untitled Event").rawValue
    }

    private func isAttended(responseStatus: String?) -> Bool {
        switch responseStatus?.lowercased() {
        case "accepted", "organizer", "tentativelyaccepted":
            return true
        default:
            return false
        }
    }

    private func calendarSummary(for event: GraphCalendarEvent, eventType: String) -> String {
        let title = event.subject ?? "Untitled Event"
        switch eventType {
        case "calendar.cancelled":
            return "Calendar event cancelled: \(title)"
        case "calendar.rescheduled":
            return "Calendar event rescheduled: \(title)"
        case "calendar.attended":
            return "Calendar event attended: \(title)"
        default:
            return "Calendar event created: \(title)"
        }
    }

    /// Detect block category from event title using keyword heuristics.
    private func detectCategory(title: String) -> BlockCategory {
        let lower = title.lowercased()
        let transitKeywords = ["travel", "flight", "drive", "airport", "commute", "train", "uber", "taxi"]
        let focusKeywords = ["focus", "deep work", "heads down", "no meetings", "blocked"]

        if transitKeywords.contains(where: { lower.contains($0) }) {
            return .transit
        }
        if focusKeywords.contains(where: { lower.contains($0) }) {
            return .focus
        }
        return .meeting
    }

    /// Parse Graph API datetime string (ISO 8601 without timezone, plus timezone name).
    private func parseGraphDateTime(_ dt: GraphDateTimeTimeZone) -> Date? {
        // Graph returns dateTime like "2026-03-31T09:00:00.0000000" with a separate timeZone field
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try with the provided timezone
        if let tz = TimeZone(identifier: dt.timeZone) {
            formatter.timeZone = tz
        }

        // Graph sometimes omits the Z suffix — try with and without
        if let date = formatter.date(from: dt.dateTime) {
            return date
        }

        // Fallback: append Z and retry
        if let date = formatter.date(from: dt.dateTime + "Z") {
            return date
        }

        // Last resort: DateFormatter with a more lenient pattern
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
        if let tz = TimeZone(identifier: dt.timeZone) {
            fallback.timeZone = tz
        }
        return fallback.date(from: dt.dateTime)
    }
}

private struct CalendarObservationEmission: Sendable {
    let eventType: String
    let occurredAt: Date
    let originalStart: Date?
}
