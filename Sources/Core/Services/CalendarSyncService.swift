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

        let blocks = graphEvents.compactMap { event -> CalendarBlock? in
            guard !event.isCancelled else { return nil }

            guard let startDate = parseGraphDateTime(event.start),
                  let endDate = parseGraphDateTime(event.end) else {
                TimedLogger.calendar.warning("Skipping event with unparseable dates: \(event.subject ?? "untitled", privacy: .public)")
                return nil
            }

            // Skip all-day events — they don't belong on the hour grid
            if event.isAllDay { return nil }

            let title = event.subject ?? "Untitled Event"
            let category = detectCategory(title: title)

            return CalendarBlock(
                id: UUID(),
                title: title,
                startTime: startDate,
                endTime: endDate,
                sourceEmailId: nil,
                category: category
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
