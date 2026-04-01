import Foundation
import Testing

@testable import time_manager_desktop

struct TimedSchedulerTests {
    @Test
    func testStubReturnsNoBlocksForInformationalEmails() {
        let scheduler = TimedSchedulerService()
        let emails = [
            EmailMessage(
                id: UUID(),
                subject: "FYI: meeting notes",
                sender: "team@example.com",
                receivedAt: Date(),
                body: "Notes attached",
                isRead: false
            )
        ]

        // Stub classifier returns .informational, so no blocks generated
        let blocks = scheduler.suggestBlocks(for: emails)
        #expect(blocks.isEmpty)
    }

    @Test
    func testEmptyInputReturnsNoBlocks() {
        let scheduler = TimedSchedulerService()
        let blocks = scheduler.suggestBlocks(for: [])
        #expect(blocks.isEmpty)
    }
}
