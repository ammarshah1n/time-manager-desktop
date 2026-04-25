import Foundation
import Testing

@testable import TimedKit

struct DataStoreTests {

    // MARK: - TimedTask roundtrip

    @Test
    func testTimedTaskRoundtrip() throws {
        let task = TimedTask(
            id: UUID(),
            title: "Test task",
            sender: "Sender",
            estimatedMinutes: 30,
            bucket: .action,
            emailCount: 1,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([task])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([TimedTask].self, from: data)

        #expect(loaded.count == 1)
        #expect(loaded[0].title == "Test task")
        #expect(loaded[0].bucket == .action)
        #expect(loaded[0].estimatedMinutes == 30)
        #expect(loaded[0].sender == "Sender")
    }

    // MARK: - WOOItem roundtrip

    @Test
    func testWOOItemRoundtrip() throws {
        let item = WOOItem(
            id: UUID(),
            contact: "John",
            description: "Waiting on contract",
            category: "Business",
            askedDate: Date(timeIntervalSince1970: 1_700_000_000),
            expectedByDate: Date(timeIntervalSince1970: 1_700_100_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([item])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([WOOItem].self, from: data)

        #expect(loaded.count == 1)
        #expect(loaded[0].contact == "John")
        #expect(loaded[0].category == "Business")
        #expect(loaded[0].hasReplied == false)
    }

    // MARK: - CaptureItem roundtrip

    @Test
    func testCaptureItemRoundtrip() throws {
        let item = CaptureItem(
            id: UUID(),
            inputType: .voice,
            rawText: "Call John back, five minutes",
            parsedTitle: "Call John back",
            suggestedBucket: .calls,
            suggestedMinutes: 5,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([item])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([CaptureItem].self, from: data)

        #expect(loaded.count == 1)
        #expect(loaded[0].parsedTitle == "Call John back")
        #expect(loaded[0].suggestedBucket == .calls)
        #expect(loaded[0].isConverted == false)
    }

    // MARK: - CalendarBlock roundtrip

    @Test
    func testCalendarBlockRoundtrip() throws {
        let block = CalendarBlock(
            id: UUID(),
            title: "Focus: Review",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_001_800),
            sourceEmailId: UUID(),
            category: .focus
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([block])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([CalendarBlock].self, from: data)

        #expect(loaded.count == 1)
        #expect(loaded[0].title == "Focus: Review")
        #expect(loaded[0].category == .focus)
    }

    // MARK: - TriageItem roundtrip

    @Test
    func testTriageItemRoundtrip() throws {
        let item = TriageItem(
            id: UUID(),
            sender: "Marcus Webb",
            subject: "Quick question",
            preview: "Hey, just wanted to clarify...",
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([item])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([TriageItem].self, from: data)

        #expect(loaded.count == 1)
        #expect(loaded[0].sender == "Marcus Webb")
        #expect(loaded[0].subject == "Quick question")
    }
}
