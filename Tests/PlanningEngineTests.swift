import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Timed critical paths")
struct PlanningEngineTests {
    private let fixedNow = ISO8601DateFormatter().date(from: "2026-03-20T10:00:00Z")!

    @Test("testSeqtaParsingExtractsDueDates")
    func testSeqtaParsingExtractsDueDates() throws {
        let batch = ImportPipeline.parseImport(
            title: "Seqta import",
            source: .seqta,
            text: "Due Monday: English comparative essay",
            now: fixedNow,
            existingTaskIDs: []
        )

        let dueDate = try #require(batch.taskDrafts.first?.dueDate)
        let interval = dueDate.timeIntervalSince(fixedNow)

        #expect(interval > 0)
        #expect(interval <= 7 * 24 * 60 * 60)
    }

    @Test("testTickTickCSVParsing")
    func testTickTickCSVParsing() {
        let csv = """
        Task Name,Tag,Note,Due Date,Priority,Status
        English notes,English,Revise quotes,2026-03-21,2,0
        Maths worksheet,Maths,Finish questions,2026-03-22,1,0
        Chem summary,Chemistry,Review equilibrium,2026-03-23,0,0
        """

        let batch = ImportPipeline.parseImport(
            title: "TickTick import",
            source: .tickTick,
            text: csv,
            now: fixedNow,
            existingTaskIDs: []
        )

        #expect(batch.taskDrafts.count == 3)
        #expect(batch.taskDrafts.map(\.title) == ["English notes", "Maths worksheet", "Chem summary"])
        #expect(batch.taskDrafts.map(\.importance) == [5, 3, 1])
    }

    @Test("testDeduplication")
    @MainActor
    func testDeduplication() {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-dedupe-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        store.tasks = []
        store.contexts = []
        store.chat = []
        store.schedule = []

        store.importTitle = "Seqta import"
        store.importSource = .seqta
        store.importText = "Due Monday: English comparative essay"
        store.importCurrentPayload(now: fixedNow)
        store.applyPendingImport()

        store.importText = "Due Monday: English comparative essay"
        store.importCurrentPayload(now: fixedNow)
        if store.pendingImportBatch != nil {
            store.applyPendingImport()
        }

        #expect(store.tasks.count == 1)
    }

    @Test("testCompletedTasksExcludedFromRanking")
    func testCompletedTasksExcludedFromRanking() {
        var taskOne = makeTask(id: "one", title: "English essay", subject: "English", dueOffsetDays: 0)
        let taskTwo = makeTask(id: "two", title: "Maths worksheet", subject: "Maths", dueOffsetDays: 1)
        let taskThree = makeTask(id: "three", title: "Economics revision", subject: "Economics", dueOffsetDays: 2)
        taskOne.isCompleted = true
        taskOne.completedAt = fixedNow

        let ranked = PlanningEngine.rank(tasks: [taskOne, taskTwo, taskThree], now: fixedNow)
        #expect(ranked.count == 2)
        #expect(ranked.contains(where: { $0.task.id == "one" }) == false)
    }

    @Test("testScheduleCapAtWindow")
    func testScheduleCapAtWindow() {
        let ranked = (1...5).map { index in
            RankedTask(
                task: makeTask(id: "\(index)", title: "Task \(index)", subject: "Maths", estimateMinutes: 60, dueOffsetDays: index),
                score: 120 - index,
                band: "Today",
                reasons: ["Reason \(index)"],
                suggestedNextAction: "Action \(index)"
            )
        }

        let schedule = PlanningEngine.buildSchedule(tasks: ranked, now: fixedNow, windowMinutes: 180)
        #expect(schedule.count <= 3)
    }

    @Test("testICSGeneration")
    func testICSGeneration() {
        let blocks = [
            ScheduleBlock(
                id: "block-1",
                taskID: "one",
                title: "English essay",
                start: fixedNow,
                end: fixedNow.addingTimeInterval(3600),
                timeRange: "10:00 AM - 11:00 AM",
                note: "Importance 90",
                isApproved: true
            ),
            ScheduleBlock(
                id: "block-2",
                taskID: "two",
                title: "Maths worksheet",
                start: fixedNow.addingTimeInterval(5400),
                end: fixedNow.addingTimeInterval(9000),
                timeRange: "11:30 AM - 12:30 PM",
                note: "Importance 72",
                isApproved: true
            )
        ]

        let ics = CalendarExporter.makeICS(schedule: blocks)
        #expect(ics.contains("BEGIN:VCALENDAR"))
        #expect(ics.contains("SUMMARY:English essay"))
        #expect(ics.contains("SUMMARY:Maths worksheet"))
        #expect(ics.contains("DTSTART"))
        #expect(ics.contains("DTEND"))
    }

    @Test("testPromptBoostSubject")
    func testPromptBoostSubject() {
        let english = makeTask(id: "english", title: "English essay", subject: "English", dueOffsetDays: 2)
        let maths = makeTask(id: "maths", title: "Maths worksheet", subject: "Maths", dueOffsetDays: 2)

        let ranked = PlanningEngine.rank(
            tasks: [maths, english],
            contexts: [],
            now: fixedNow,
            promptBoostSubject: "English"
        )

        #expect(ranked.first?.task.subject == "English")
    }

    @Test("testChatPersistence")
    @MainActor
    func testChatPersistence() {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-chat-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        store.chat = [PromptMessage(role: .assistant, text: "Stored message", createdAt: fixedNow)]
        store.tasks = []
        store.contexts = []
        store.schedule = []
        store.save()

        let reloaded = PlannerStore(storageURL: storageURL)
        reloaded.load()

        #expect(reloaded.chat.contains(where: { $0.text == "Stored message" }))
    }

    private func makeTask(
        id: String,
        title: String,
        subject: String,
        estimateMinutes: Int = 30,
        dueOffsetDays: Int
    ) -> TaskItem {
        TaskItem(
            id: id,
            title: title,
            list: "School",
            source: .seqta,
            subject: subject,
            estimateMinutes: estimateMinutes,
            confidence: 3,
            importance: 3,
            dueDate: Calendar.current.date(byAdding: .day, value: dueOffsetDays, to: fixedNow),
            notes: "",
            energy: .medium,
            isCompleted: false,
            completedAt: nil
        )
    }
}
