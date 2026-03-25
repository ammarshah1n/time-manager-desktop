import EventKit
import Foundation

struct SchoolLesson: Identifiable, Hashable {
    let id: String
    let lessonNumber: Int
    let title: String
    let subject: String?
    let start: Date
    let end: Date
    let location: String
    let calendarTitle: String

    var timeRange: String {
        "\(start.formatted(date: .omitted, time: .shortened)) - \(end.formatted(date: .omitted, time: .shortened))"
    }
}

struct SchoolDayPlan {
    let targetDate: Date
    let lessons: [SchoolLesson]
    let message: String

    var isTomorrow: Bool {
        !Calendar.current.isDateInToday(targetDate)
    }
}

enum SchoolCalendarService {
    static func loadPlan(now: Date = .now) async -> SchoolDayPlan {
        let store = EKEventStore()

        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else {
                return SchoolDayPlan(targetDate: targetDate(from: now), lessons: [], message: "Calendar access was denied.")
            }

            let targetDate = targetDate(from: now)
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: targetDate)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                return SchoolDayPlan(targetDate: targetDate, lessons: [], message: "Could not build the school day range.")
            }

            let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
            let events = store.events(matching: predicate)
                .filter { isSchoolRelated($0, referenceYear: calendar.component(.year, from: now)) }
                .sorted { $0.startDate < $1.startDate }

            let lessons = events.enumerated().map { index, event in
                let eventTitle = event.title ?? "Untitled lesson"
                return SchoolLesson(
                    id: event.eventIdentifier ?? "\(event.calendar.calendarIdentifier)-\(event.startDate.timeIntervalSince1970)",
                    lessonNumber: lessonNumber(for: eventTitle, fallback: index + 1),
                    title: eventTitle,
                    subject: SubjectCatalog.matchingSubject(
                        in: "\(eventTitle) \(event.notes ?? "") \(event.location ?? "")"
                    ),
                    start: event.startDate,
                    end: event.endDate,
                    location: event.location ?? "",
                    calendarTitle: event.calendar.title
                )
            }

            let message: String
            if lessons.isEmpty {
                message = targetDate == calendar.startOfDay(for: targetDate)
                    ? "No school lessons matched your local calendars."
                    : "No school lessons matched your local calendars."
            } else {
                message = "Loaded \(lessons.count) school calendar event(s)."
            }

            return SchoolDayPlan(targetDate: targetDate, lessons: lessons, message: message)
        } catch {
            return SchoolDayPlan(targetDate: targetDate(from: now), lessons: [], message: "Could not read Apple Calendar.")
        }
    }

    private static func targetDate(from now: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0

        if hour < 15 || (hour == 15 && minute < 30) {
            return now
        }

        return calendar.date(byAdding: .day, value: 1, to: now) ?? now
    }

    private static func isSchoolRelated(_ event: EKEvent, referenceYear: Int) -> Bool {
        let calendar = Calendar.current
        guard calendar.component(.year, from: event.startDate) == referenceYear else { return false }

        let haystack = [
            event.title,
            event.calendar.title,
            event.location ?? "",
            event.notes ?? ""
        ].joined(separator: " ").lowercased()

        let keywords = [
            "school", "pac", "prince alfred", "lesson", "period", "timetable", "year 11", "class",
            "english", "math", "maths", "economics", "chemistry", "physics", "biology",
            "legal", "history", "geography", "pe", "sport", "language"
        ]

        return keywords.contains(where: haystack.contains)
    }

    private static func lessonNumber(for title: String, fallback: Int) -> Int {
        let lowered = title.lowercased()
        let patterns = [
            #"lesson\s*([1-7])"#,
            #"period\s*([1-7])"#,
            #"\bl([1-7])\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: (lowered as NSString).length)
            guard let match = regex.firstMatch(in: lowered, range: range), match.numberOfRanges > 1 else { continue }
            let value = (lowered as NSString).substring(with: match.range(at: 1))
            if let lessonNumber = Int(value) {
                return lessonNumber
            }
        }

        return min(max(fallback, 1), 7)
    }
}
