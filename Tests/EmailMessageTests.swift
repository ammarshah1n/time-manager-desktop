import Foundation
import Testing

@testable import time_manager_desktop

struct EmailMessageTests {
    @Test
    func testCodableRoundtrip() throws {
        let original = EmailMessage(
            id: UUID(),
            subject: "Test Subject",
            sender: "test@example.com",
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: "Test body content",
            isRead: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EmailMessage.self, from: data)

        #expect(decoded == original)
        #expect(decoded.id == original.id)
        #expect(decoded.subject == "Test Subject")
        #expect(decoded.sender == "test@example.com")
        #expect(decoded.isRead == false)
    }
}
