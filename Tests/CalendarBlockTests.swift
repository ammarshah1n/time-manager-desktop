import Foundation
import Testing

@testable import time_manager_desktop

struct CalendarBlockTests {
    @Test
    func testCodableRoundtrip() throws {
        let original = CalendarBlock(
            id: UUID(),
            title: "Focus: Review PR",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_001_800),
            sourceEmailId: UUID(),
            category: .focus
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalendarBlock.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func testBlockCategoryBreakCase() throws {
        let data = try JSONEncoder().encode(BlockCategory.break)
        let decoded = try JSONDecoder().decode(BlockCategory.self, from: data)
        #expect(decoded == .break)
    }
}
