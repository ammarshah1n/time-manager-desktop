import Foundation
import Testing

@testable import time_manager_desktop

struct EmailClassifierTests {
    @Test
    func testStubReturnsInformational() {
        let classifier = EmailClassifierService()
        let email = EmailMessage(
            id: UUID(),
            subject: "Meeting notes",
            sender: "boss@example.com",
            receivedAt: Date(),
            body: "Here are the notes",
            isRead: false
        )

        let result = classifier.classify(email, senderRules: [])
        #expect(result == .informational)
    }

    @Test
    func testEmailCategoryCodable() throws {
        let category = EmailCategory.actionRequired
        let data = try JSONEncoder().encode(category)
        let decoded = try JSONDecoder().decode(EmailCategory.self, from: data)
        #expect(decoded == .actionRequired)
    }
}
