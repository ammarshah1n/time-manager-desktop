import CryptoKit
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

    @Test("testSeqtaParsingMatchesSubjectAliases")
    func testSeqtaParsingMatchesSubjectAliases() {
        let batch = ImportPipeline.parseImport(
            title: "Seqta import",
            source: .seqta,
            text: """
            Due Monday: SACE Economics test prep
            Due: tomorrow: Eng Stds comparative response
            Due 30 March 2026: Specialist practice set
            Due: Monday: S&C photo essay notes
            """,
            now: fixedNow,
            existingTaskIDs: []
        )

        #expect(batch.taskDrafts.count == 4)
        #expect(batch.taskDrafts.map(\.subject) == ["Economics", "English", "Maths", "Society and Culture"])
        #expect(batch.taskDrafts.allSatisfy { $0.dueDate >= fixedNow })
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

    @Test("testAIImportParsingUsesStructuredExtraction")
    func testAIImportParsingUsesStructuredExtraction() async {
        let response = """
        {
          "tasks": [
            {
              "title": "Maths investigation",
              "subject": "Maths",
              "estimateMinutes": 90,
              "importance": 4,
              "dueDate": "2026-03-23T09:00:00Z",
              "notes": "Complete the write-up.",
              "energy": "High"
            }
          ],
          "messages": ["AI extraction parsed 1 task."]
        }
        """

        let batch = await ImportPipeline.parseImportWithAI(
            title: "Seqta import",
            source: .seqta,
            text: "10MAT due Monday: Mr Smith - Maths investigation",
            now: fixedNow,
            existingTaskIDs: [],
            workingRoot: "/tmp",
            additionalRoots: [],
            autonomousMode: false,
            runner: { _ in .success(response) }
        )

        let task = batch.taskDrafts.first
        #expect(batch.taskDrafts.count == 1)
        #expect(task?.title == "Maths investigation")
        #expect(task?.subject == "Maths")
        #expect(task?.estimateMinutes == 90)
        #expect(task?.importance == 4)
        #expect(task?.energy == .high)
        #expect(batch.messages == ["AI extraction parsed 1 task."])
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

    @Test("testSeqtaReimportMergesLegacyTaskIdentity")
    @MainActor
    func testSeqtaReimportMergesLegacyTaskIdentity() {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-seqta-legacy-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        store.tasks = [
            TaskItem(
                id: legacyTaskID(source: .seqta, title: "English comparative essay"),
                title: "English comparative essay",
                list: "Seqta",
                source: .seqta,
                subject: "English",
                estimateMinutes: 45,
                confidence: 3,
                importance: 3,
                dueDate: nil,
                notes: "Imported from Seqta.",
                energy: .medium,
                isCompleted: false,
                completedAt: nil
            )
        ]
        store.contexts = []
        store.chat = []
        store.schedule = []

        store.importTitle = "Seqta import"
        store.importSource = .seqta
        store.importText = "Due Monday: Eng Stds English comparative essay"
        store.importCurrentPayload(now: fixedNow)
        store.applyPendingImport()

        #expect(store.tasks.count == 1)
        #expect(store.tasks.first?.subject == "English")
        #expect(store.tasks.first?.dueDate != nil)
    }

    @Test("testCrossSourceDeduplication")
    @MainActor
    func testCrossSourceDeduplication() {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-cross-source-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        store.tasks = []
        store.contexts = []
        store.chat = []
        store.schedule = []

        store.importTitle = "Seqta import"
        store.importSource = .seqta
        store.importText = "Due Monday: Maths investigation"
        store.importCurrentPayload(now: fixedNow)
        store.applyPendingImport()

        store.importTitle = "TickTick import"
        store.importSource = .tickTick
        store.importText = "Maths investigation"
        store.importCurrentPayload(now: fixedNow)
        if store.pendingImportBatch != nil {
            store.applyPendingImport()
        }

        #expect(store.tasks.count == 1)
        #expect(store.tasks.first?.title == "Maths investigation")
    }

    @Test("testManualTaskQueuesConfidenceCalibrationForNewSubject")
    @MainActor
    func testManualTaskQueuesConfidenceCalibrationForNewSubject() {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-calibration-queue-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        store.tasks = []
        store.contexts = []
        store.chat = []
        store.schedule = []
        store.subjectConfidences = [:]

        let error = store.addManualTask(
            AddTaskDraft(
                title: "Economics test revision",
                subject: "Economics",
                estimateMinutes: 45,
                importance: 5,
                confidence: 3,
                dueDate: fixedNow,
                energy: .medium,
                source: .chat,
                notes: "Revise workbook."
            )
        )

        #expect(error == nil)
        #expect(store.pendingCalibrationSubject == "Economics")
        #expect(store.subjectConfidences["Economics"] == nil)
    }

    @Test("testTaskDecompositionCreatesChildTasks")
    @MainActor
    func testTaskDecompositionCreatesChildTasks() async {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-decompose-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        let parentTask = TaskItem(
            id: StableID.makeTaskID(source: .seqta, title: "Economics test"),
            title: "Economics test",
            list: "Seqta",
            source: .seqta,
            subject: "Economics",
            estimateMinutes: 60,
            confidence: 3,
            importance: 5,
            dueDate: fixedNow,
            notes: "",
            energy: .medium,
            isCompleted: false,
            completedAt: nil
        )

        store.tasks = [parentTask]
        store.contexts = []
        store.chat = []
        store.schedule = []

        await store.decompose(task: parentTask) { prompt in
            #expect(
                prompt ==
                    "Break this task into 3-5 concrete subtasks. Task: Economics test. Subject: Economics. Return as a numbered list, one per line, no preamble."
            )
            return .success(
                """
                1. Review class notes
                2. Make a one-page summary
                3. Answer two practice questions
                """
            )
        }

        let children = store.children(of: parentTask.id)
        #expect(children.count == 3)
        #expect(children.map(\.title) == [
            "Review class notes",
            "Make a one-page summary",
            "Answer two practice questions"
        ])
        #expect(children.allSatisfy { $0.parentId == parentTask.id })
        #expect(store.canUndoDecomposition)
    }

    @Test("testUndoLastDecompositionRemovesChildBatch")
    @MainActor
    func testUndoLastDecompositionRemovesChildBatch() async {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-decompose-undo-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        let parentTask = TaskItem(
            id: StableID.makeTaskID(source: .chat, title: "English assessment"),
            title: "English assessment",
            list: "Chat",
            source: .chat,
            subject: "English",
            estimateMinutes: 45,
            confidence: 3,
            importance: 4,
            dueDate: fixedNow,
            notes: "",
            energy: .medium,
            isCompleted: false,
            completedAt: nil
        )

        store.tasks = [parentTask]
        store.contexts = []
        store.chat = []
        store.schedule = []

        await store.decompose(task: parentTask) { _ in
            .success(
                """
                1. Pick quotes
                2. Draft a paragraph
                3. Proofread the response
                """
            )
        }

        #expect(store.tasks.count == 4)
        store.undoLastDecomposition()
        #expect(store.tasks.count == 1)
        #expect(store.children(of: parentTask.id).isEmpty)
        #expect(!store.canUndoDecomposition)
    }

    @Test("testParseSubtaskLinesIgnoresNonNumberedPreamble")
    @MainActor
    func testParseSubtaskLinesIgnoresNonNumberedPreamble() {
        let parsed = PlannerStore.parseSubtaskLines(
            from: """
            Here you go:
            1. Read the brief
            2. Draft the response
            3. Check the rubric
            """
        )

        #expect(parsed == [
            "Read the brief",
            "Draft the response",
            "Check the rubric"
        ])
    }

    @Test("testConfidenceCalibrationAppliesPercentAndHints")
    @MainActor
    func testConfidenceCalibrationAppliesPercentAndHints() {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-calibration-apply-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)
        store.tasks = [
            TaskItem(
                id: StableID.makeTaskID(source: .seqta, title: "Economics test"),
                title: "Economics test",
                list: "Seqta",
                source: .seqta,
                subject: "Economics",
                estimateMinutes: 60,
                confidence: 3,
                importance: 5,
                dueDate: fixedNow,
                notes: "Workbook questions.",
                energy: .high,
                isCompleted: false,
                completedAt: nil
            )
        ]
        store.pendingCalibrationSubject = "Economics"

        store.applyConfidenceCalibration(
            subject: "Economics",
            percentConfidence: 42,
            hints: [
                "Redo elasticity graphs from the workbook.",
                "Turn the latest class example into a 10-minute recap.",
                "Write one definition from memory for each weak concept."
            ],
            draft: ConfidenceCalibrationDraft(
                subject: "Economics",
                confidence: 2,
                recentTopic: "Elasticity",
                leastSureAbout: "PES vs PED",
                assessmentDate: "Friday",
                resources: "Workbook and class notes"
            ),
            now: fixedNow
        )

        #expect(store.subjectConfidences["Economics"] == 42)
        #expect(store.subjectConfidenceValue(for: "Economics") == 3)
        #expect(store.tasks.first?.confidence == 3)
        #expect(store.tasks.first?.notes.contains("Study hints for Economics:") == true)
        #expect(store.tasks.first?.notes.contains("Redo elasticity graphs from the workbook.") == true)
        #expect(store.pendingCalibrationSubject == nil)
    }

    @Test("testLegacyTaskIDsCollapseOnLoad")
    @MainActor
    func testLegacyTaskIDsCollapseOnLoad() throws {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-legacy-\(UUID().uuidString).json")
        let task = TaskItem(
            id: legacyTaskID(source: .seqta, title: "Maths investigation"),
            title: "Maths investigation",
            list: "Seqta",
            source: .seqta,
            subject: "Maths",
            estimateMinutes: 45,
            confidence: 3,
            importance: 3,
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: fixedNow),
            notes: "Imported from Seqta.",
            energy: .medium,
            isCompleted: false,
            completedAt: nil
        )
        let duplicate = TaskItem(
            id: legacyTaskID(source: .tickTick, title: "Maths investigation"),
            title: "Maths investigation",
            list: "TickTick",
            source: .tickTick,
            subject: "Maths",
            estimateMinutes: 30,
            confidence: 3,
            importance: 4,
            dueDate: Calendar.current.date(byAdding: .day, value: 2, to: fixedNow),
            notes: "Imported from TickTick.",
            energy: .medium,
            isCompleted: false,
            completedAt: nil
        )
        let snapshot = PlannerSnapshot(
            tasks: [task, duplicate],
            contexts: [],
            schedule: [
                ScheduleBlock(
                    id: "block-1",
                    taskID: duplicate.id,
                    title: duplicate.title,
                    start: fixedNow,
                    end: fixedNow.addingTimeInterval(1800),
                    timeRange: "10:00 AM - 10:30 AM",
                    note: "Legacy duplicate",
                    isApproved: true
                )
            ],
            subjectConfidences: [:],
            quizQuestionsBySubject: [:],
            selectedTaskID: duplicate.id,
            selectedContextID: nil,
            promptText: "",
            chat: [],
            studyChat: [],
            promptBoostSubject: nil,
            dismissedScheduleTaskIDs: []
        )
        let data = try JSONEncoder.pretty.encode(snapshot)
        try data.write(to: storageURL, options: [.atomic])

        let reloaded = PlannerStore(storageURL: storageURL)
        let canonicalID = StableID.makeTaskID(source: .seqta, title: "Maths investigation")

        #expect(reloaded.tasks.count == 1)
        #expect(reloaded.tasks.first?.id == canonicalID)
        #expect(reloaded.selectedTaskID == canonicalID)
        #expect(reloaded.schedule.first?.taskID == canonicalID)
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

    @Test("testConfidenceHistoryPersistsAndCapsAtThirtyEntries")
    @MainActor
    func testConfidenceHistoryPersistsAndCapsAtThirtyEntries() {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent("timed-confidence-history-\(UUID().uuidString).json")
        let store = PlannerStore(storageURL: storageURL)

        for dayOffset in 0..<35 {
            let recordedAt = Calendar.current.date(byAdding: .day, value: dayOffset, to: fixedNow) ?? fixedNow
            store.recordConfidence(
                subject: dayOffset.isMultiple(of: 2) ? "Economics" : "economics",
                value: Double(dayOffset) / 100.0,
                date: recordedAt
            )
        }

        let reloaded = PlannerStore(storageURL: storageURL)
        let allReadings = reloaded.lastConfidenceReadings(for: "Economics", limit: 30)
        let latestSeven = reloaded.lastConfidenceReadings(for: "Economics", limit: 7)

        #expect(allReadings.count == 30)
        #expect(latestSeven.count == 7)
        #expect(allReadings.first?.date == Calendar.current.date(byAdding: .day, value: 5, to: fixedNow))
        #expect(latestSeven.first?.date == Calendar.current.date(byAdding: .day, value: 28, to: fixedNow))
        #expect(latestSeven.last?.value == 0.34)
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

    @Test("testSubjectImportanceMultiplierOrdersEconomicsEnglishThenSociety")
    func testSubjectImportanceMultiplierOrdersEconomicsEnglishThenSociety() {
        let economics = makeTask(id: "economics", title: "Economics test", subject: "Economics", dueOffsetDays: 5)
        let english = makeTask(id: "english", title: "English assessment", subject: "English", dueOffsetDays: 5)
        let society = makeTask(id: "society", title: "Society and Culture photo essay", subject: "Society and Culture", dueOffsetDays: 5)

        let ranked = PlanningEngine.rank(
            tasks: [society, english, economics],
            contexts: [],
            now: fixedNow,
            promptBoostSubject: nil,
            subjectImportance: [
                "Economics": 2.0,
                "English": 1.6,
                "Society and Culture": 1.0
            ]
        )

        #expect(ranked.map { $0.task.subject } == ["Economics", "English", "Society and Culture"])
    }

    @Test("testEconomicsRanksFirstAndMathsBeatsEnglishNearDeadline")
    func testEconomicsRanksFirstAndMathsBeatsEnglishNearDeadline() {
        let economics = makeTask(id: "economics", title: "Economics test", subject: "Economics", dueOffsetDays: 3)
        let maths = makeTask(id: "maths", title: "Maths investigation", subject: "Maths", dueOffsetDays: 2)
        let english = makeTask(id: "english", title: "English assessment", subject: "English", dueOffsetDays: 5)

        let ranked = PlanningEngine.rank(
            tasks: [english, maths, economics],
            contexts: [],
            now: fixedNow,
            promptBoostSubject: nil,
            subjectImportance: [
                "Economics": 2.0,
                "Maths": 1.4,
                "English": 1.6
            ]
        )

        #expect(ranked.first?.task.title == "Economics test")
        #expect(ranked.dropFirst().first?.task.title == "Maths investigation")
    }

    @Test("testConfidenceOverrideRaisesUrgency")
    func testConfidenceOverrideRaisesUrgency() {
        var english = makeTask(id: "english", title: "English assessment", subject: "English", dueOffsetDays: 4)
        let maths = makeTask(id: "maths", title: "Maths investigation", subject: "Maths", dueOffsetDays: 4)
        english.confidence = 5

        let ranked = PlanningEngine.rank(
            tasks: [maths, english],
            contexts: [],
            now: fixedNow,
            promptBoostSubject: nil,
            subjectImportance: [:],
            confidenceOverride: ["English": 1]
        )

        #expect(ranked.first?.task.subject == "English")
    }

    @Test("testExplainRankIncludesScoreBreakdown")
    func testExplainRankIncludesScoreBreakdown() {
        let economics = makeTask(id: "economics", title: "Economics test", subject: "Economics", dueOffsetDays: 3)

        let explanation = PlanningEngine.explainRank(
            task: economics,
            contexts: [],
            now: fixedNow,
            promptBoostSubject: nil,
            subjectImportance: ["Economics": 2.0],
            confidenceOverride: ["Economics": 2]
        )

        #expect(explanation.contains("importance="))
        #expect(explanation.contains("mult="))
        #expect(explanation.contains("deadline="))
        #expect(explanation.contains("confidenceGap="))
        #expect(explanation.contains("total="))
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

    private func legacyTaskID(source: TaskSource, title: String) -> String {
        let seed = "\(source.rawValue)-\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hash = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "task-\(hash)"
    }
}
