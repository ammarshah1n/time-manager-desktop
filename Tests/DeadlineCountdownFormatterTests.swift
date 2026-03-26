import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Deadline countdown badges")
struct DeadlineCountdownFormatterTests {
    private let fixedNow = ISO8601DateFormatter().date(from: "2026-03-26T03:38:00Z")!

    @Test("shows compact hours when under 48 hours")
    func showsCompactHours() {
        let dueDate = fixedNow.addingTimeInterval(23 * 3600)
        #expect(DeadlineCountdownFormatter.badgeText(for: dueDate, now: fixedNow) == "23h")
    }

    @Test("shows hours and minutes when both matter")
    func showsHoursAndMinutes() {
        let dueDate = fixedNow.addingTimeInterval((4 * 3600) + (30 * 60))
        #expect(DeadlineCountdownFormatter.badgeText(for: dueDate, now: fixedNow) == "4h 30m")
    }

    @Test("shows overdue when the deadline passed")
    func showsOverdueState() {
        let dueDate = fixedNow.addingTimeInterval(-60)
        #expect(DeadlineCountdownFormatter.badgeText(for: dueDate, now: fixedNow) == "Overdue")
    }

    @Test("hides the badge when the deadline is too far away")
    func hidesFarAwayDeadlines() {
        let dueDate = fixedNow.addingTimeInterval(72 * 3600)
        #expect(DeadlineCountdownFormatter.badgeText(for: dueDate, now: fixedNow) == nil)
    }
}
