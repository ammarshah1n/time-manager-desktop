// GmailCalendarSyncService.swift — Timed Core
// Polls Google Calendar v3 (`/calendars/primary/events`) for today's events
// and emits Tier 0 observations + calendar_observations rows.
//
// Mirror of CalendarSyncService but for Google. Slimmer for v1:
//   - No reschedule / cancellation tracking (Google API has these signals;
//     we add them once the Microsoft side has been load-tested with both
//     providers writing into calendar_observations).
//   - No back-to-back event detection (orthogonal feature).
// What it does keep: Tier 0 observation emission per event, persistence to
// `calendar_observations`, and the same poll cadence as Microsoft.

import Foundation
import Dependencies
import os

actor GmailCalendarSyncService {
    static let shared = GmailCalendarSyncService()

    @Dependency(\.gmailClient) private var gmailClient
    @Dependency(\.supabaseClient) private var supabaseClient

    private var syncTask: Task<Void, Never>?
    private var isRunning = false
    var pollInterval: TimeInterval = 300 // 5 minutes — calendar changes less frequently

    /// Idempotent. `tokenProvider` returns a fresh Google access token.
    func start(tokenProvider: @escaping @Sendable () async throws -> String) {
        guard !isRunning else { return }
        isRunning = true
        syncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    _ = try await self.fetchTodayEvents(tokenProvider: tokenProvider)
                } catch {
                    TimedLogger.calendar.error("GmailCalendarSyncService background sync error: \(error.localizedDescription, privacy: .public)")
                }
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    func stop() {
        syncTask?.cancel()
        syncTask = nil
        isRunning = false
    }

    /// Fetches today's events and writes calendar_observations + Tier 0 rows.
    /// Returns the number of events processed.
    @discardableResult
    func fetchTodayEvents(tokenProvider: @escaping @Sendable () async throws -> String) async throws -> Int {
        let accessToken = try await tokenProvider()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }

        TimedLogger.calendar.info("Fetching Google calendar events for today")
        let events = try await gmailClient.fetchCalendarEvents(startOfDay, endOfDay, accessToken)
        TimedLogger.calendar.info("Fetched \(events.count) events from Google Calendar")

        for event in events {
            await emit(event: event)
        }
        return events.count
    }

    // MARK: - Tier 0 + calendar_observations

    private func emit(event: GoogleCalendarEvent) async {
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else { return }
        guard let parsedStart = parseTime(event.start),
              let parsedEnd = parseTime(event.end) else {
            return
        }

        let attendeeCount = event.attendees?.count ?? 0
        let durationMinutes = max(0, Int(parsedEnd.timeIntervalSince(parsedStart) / 60))
        let isOrganiser = event.organizer?.`self` == true
        let isCancelled = event.status?.lowercased() == "cancelled"

        var rawData: [String: AnyCodable] = [
            "attendee_count": AnyCodable(attendeeCount),
            "duration_minutes": AnyCodable(durationMinutes),
            "is_organiser": AnyCodable(isOrganiser),
            "meeting_type": AnyCodable(inferMeetingType(event: event))
        ]
        if let link = event.hangoutLink, !link.isEmpty {
            rawData["has_hangout_link"] = AnyCodable(true)
        }

        let eventType: String = {
            if isCancelled { return "calendar.cancelled" }
            if parsedEnd <= Date() { return "calendar.attended" }
            return "calendar.event_created"
        }()

        let observation = Tier0Observation(
            profileId: executiveId,
            occurredAt: parsedStart,
            source: .calendar,
            eventType: eventType,
            entityType: "calendar_event",
            summary: summary(for: event, eventType: eventType),
            rawData: rawData,
            importanceScore: 0.5
        )
        do {
            try await Tier0Writer.shared.recordObservation(observation)
        } catch {
            TimedLogger.calendar.error("GmailCalendar Tier0 write failed: \(error.localizedDescription)")
        }

        // Map to my own attendee response, falling back nil if not present.
        let myResponse = event.attendees?
            .first(where: { $0.`self` == true })?
            .responseStatus

        let calendarObservation = CalendarObservationRow(
            id: UUID(),
            executiveId: executiveId,
            observedAt: parsedStart,
            eventStart: parsedStart,
            eventEnd: parsedEnd,
            attendeeCount: attendeeCount,
            organiserIsSelf: isOrganiser,
            responseStatus: myResponse,
            wasCancelled: isCancelled,
            wasRescheduled: false,
            originalStart: nil,
            title: event.summary,
            description: event.location
        )
        do {
            try await persist(calendarObservation)
        } catch {
            TimedLogger.calendar.error("GmailCalendar persist failed: \(error.localizedDescription)")
        }
    }

    private func persist(_ observation: CalendarObservationRow) async throws {
        let isConnected = await NetworkMonitor.shared.isConnected
        guard isConnected, supabaseClient.rawClient != nil else {
            try await enqueueOffline(observation)
            return
        }
        try await supabaseClient.insertCalendarObservation(observation)
    }

    private func enqueueOffline(_ observation: CalendarObservationRow) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(observation)
        try await OfflineSyncQueue.shared.enqueue(
            operationType: "calendar_observations.insert",
            payload: payload
        )
    }

    private func inferMeetingType(event: GoogleCalendarEvent) -> String {
        let title = (event.summary ?? "").lowercased()
        let location = (event.location ?? "").lowercased()
        if title.contains("1:1") || title.contains("one on one") { return "one_on_one" }
        if title.contains("board") { return "board" }
        if title.contains("interview") { return "interview" }
        if event.hangoutLink != nil { return "virtual" }
        if location.contains("zoom") || location.contains("teams") || location.contains("meet.google") {
            return "virtual"
        }
        return "meeting"
    }

    private func summary(for event: GoogleCalendarEvent, eventType: String) -> String {
        let title = event.summary ?? "Untitled Event"
        switch eventType {
        case "calendar.cancelled": return "Calendar event cancelled: \(title)"
        case "calendar.attended": return "Calendar event attended: \(title)"
        default: return "Calendar event created: \(title)"
        }
    }

    /// Parses a GoogleCalendarTime into a Swift Date.
    /// All-day events use `date` (YYYY-MM-DD), timed events use `dateTime` (ISO 8601).
    private func parseTime(_ t: GoogleCalendarTime) -> Date? {
        if let raw = t.dateTime {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: raw) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: raw)
        }
        if let raw = t.date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: t.timeZone ?? "UTC") ?? TimeZone(identifier: "UTC")
            return f.date(from: raw)
        }
        return nil
    }
}
