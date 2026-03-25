import EventKit
import Foundation

struct CalendarExportResult {
    let message: String
    let fallbackICSURL: URL?
}

enum CalendarExporter {
    static func exportApprovedBlocks(_ schedule: [ScheduleBlock]) async -> CalendarExportResult {
        let approvedBlocks = schedule.filter(\.isApproved)
        guard !approvedBlocks.isEmpty else {
            return CalendarExportResult(message: "No approved blocks to export.", fallbackICSURL: nil)
        }

        let store = EKEventStore()

        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else {
                let fallbackURL = try writeFallbackICS(schedule: approvedBlocks)
                return CalendarExportResult(
                    message: "Calendar permission was denied. Wrote an ICS fallback instead.",
                    fallbackICSURL: fallbackURL
                )
            }

            let calendar = try timedCalendar(in: store)
            try sync(eventsFor: approvedBlocks, in: calendar, store: store)

            return CalendarExportResult(
                message: "Exported \(approvedBlocks.count) approved block(s) to Apple Calendar.",
                fallbackICSURL: nil
            )
        } catch {
            let fallbackURL = try? writeFallbackICS(schedule: approvedBlocks)
            return CalendarExportResult(
                message: "Calendar export failed. Wrote an ICS fallback instead.",
                fallbackICSURL: fallbackURL
            )
        }
    }

    static func makeICS(schedule: [ScheduleBlock]) -> String {
        let stamp = Self.utcFormatter.string(from: .now)
        let timezoneIdentifier = TimeZone.current.identifier

        let events = schedule.map { block in
            """
            BEGIN:VEVENT
            UID:\(block.id)@timed
            DTSTAMP:\(stamp)
            DTSTART;TZID=\(timezoneIdentifier):\(Self.localFormatter.string(from: block.start))
            DTEND;TZID=\(timezoneIdentifier):\(Self.localFormatter.string(from: block.end))
            SUMMARY:\(escape(block.title))
            DESCRIPTION:\(escape(block.note))
            END:VEVENT
            """
        }.joined(separator: "\n")

        return """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Timed//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        \(events)
        END:VCALENDAR
        """
    }

    private static func sync(eventsFor schedule: [ScheduleBlock], in calendar: EKCalendar, store: EKEventStore) throws {
        guard
            let start = schedule.map(\.start).min()?.addingTimeInterval(-86400),
            let end = schedule.map(\.end).max()?.addingTimeInterval(86400)
        else {
            return
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        let existingEvents = store.events(matching: predicate)
        let existingByURL: [String: EKEvent] = Dictionary(
            uniqueKeysWithValues: existingEvents.compactMap { event in
                guard let absoluteString = event.url?.absoluteString else { return nil }
                return (absoluteString, event)
            }
        )

        for block in schedule {
            let eventURLString = "timed://block/\(block.id)"
            let event = existingByURL[eventURLString] ?? EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = block.title
            event.startDate = block.start
            event.endDate = block.end
            event.notes = block.note
            event.url = URL(string: eventURLString)
            try store.save(event, span: .thisEvent, commit: false)
        }

        try store.commit()
    }

    private static func timedCalendar(in store: EKEventStore) throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == "Timed" }) {
            return existing
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Timed"
        calendar.cgColor = CGColor(gray: 0.85, alpha: 1)

        if let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first {
            calendar.source = source
        } else {
            throw NSError(domain: "TimedCalendar", code: 1)
        }

        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    private static func writeFallbackICS(schedule: [ScheduleBlock]) throws -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fileName = "timed-plan-\(ISO8601DateFormatter().string(from: .now)).ics"
        let exportURL = downloads.appendingPathComponent(fileName)
        let ics = makeICS(schedule: schedule)
        try ics.write(to: exportURL, atomically: true, encoding: .utf8)
        return exportURL
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
    }

    private static var utcFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }

    private static var localFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter
    }
}
