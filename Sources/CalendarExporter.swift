import Foundation

enum CalendarExporter {
    static func makeICS(schedule: [ScheduleBlock]) -> String {
        let stamp = Self.utcFormatter.string(from: .now)
        let timezoneIdentifier = TimeZone.current.identifier

        let events = schedule.map { block in
            """
            BEGIN:VEVENT
            UID:\(block.id)@timemanagerdesktop
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
        PRODID:-//Time Manager Desktop//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        \(events)
        END:VCALENDAR
        """
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
