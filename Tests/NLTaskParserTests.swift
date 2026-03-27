import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Natural language task parser")
struct NLTaskParserTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private let fixedNow = ISO8601DateFormatter().date(from: "2026-03-20T10:00:00Z")!

    @Test("parses due Friday importance and subject")
    func parsesDueFridayImportanceAndSubject() throws {
        let parser = NLTaskParser(calendar: calendar)
        let parsed = parser.parse("Economics test due Friday importance 10", now: fixedNow)

        #expect(parsed.title == "test")
        #expect(parsed.subject == "Economics")
        #expect(parsed.importance == 10)

        let dueDate = try #require(parsed.dueDate)
        let components = calendar.dateComponents([.year, .month, .day], from: dueDate)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 27)
    }

    @Test("parses tomorrow without due keyword")
    func parsesTomorrowWithoutDueKeyword() throws {
        let parser = NLTaskParser(calendar: calendar)
        let parsed = parser.parse("Maths homework tomorrow", now: fixedNow)

        #expect(parsed.title == "homework")
        #expect(parsed.subject == "Maths")

        let dueDate = try #require(parsed.dueDate)
        let components = calendar.dateComponents([.year, .month, .day], from: dueDate)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 21)
    }

    @Test("keeps plain text as title with default fields untouched")
    func keepsPlainTextAsTitle() {
        let parser = NLTaskParser(calendar: calendar)
        let parsed = parser.parse("Read chapter 3", now: fixedNow)

        #expect(parsed.title == "Read chapter 3")
        #expect(parsed.subject == nil)
        #expect(parsed.dueDate == nil)
        #expect(parsed.importance == nil)
    }

    @Test("manual task creation resolves natural language draft")
    @MainActor
    func manualTaskCreationResolvesNaturalLanguageDraft() throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-nl-parser-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        store.tasks = []
        store.contexts = []
        store.chat = []
        store.schedule = []

        var draft = AddTaskDraft()
        draft.title = "Economics test due Friday importance 10"

        let error = store.addManualTask(draft, now: fixedNow)
        #expect(error == nil)

        let createdTask = try #require(store.tasks.first)
        #expect(createdTask.title == "test")
        #expect(createdTask.subject == "Economics")
        #expect(createdTask.importance == 10)

        let dueDate = try #require(createdTask.dueDate)
        let components = calendar.dateComponents([.year, .month, .day], from: dueDate)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 27)
    }
}
