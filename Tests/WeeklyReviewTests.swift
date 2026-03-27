import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Weekly review")
struct WeeklyReviewTests {
    @MainActor
    @Test("weekly review shows once per Sunday cycle and persists dismissal")
    func weeklyReviewShowsOncePerSundayCycle() {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-weekly-review-\(UUID().uuidString).json")
        let calendar = Calendar(identifier: .gregorian)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 9))!
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9))!
        let nextSunday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 9))!

        let store = PlannerStore(storageURL: storageURL)
        store.tasks = []
        store.contexts = []
        store.schedule = []
        store.chat = []
        store.studyChat = []
        store.lastWeeklyReview = nil

        store.refreshWeeklyReviewState(now: monday)
        #expect(store.showWeeklyReview)

        store.dismissWeeklyReview(now: monday)
        #expect(store.showWeeklyReview == false)

        let reloaded = PlannerStore(storageURL: storageURL)
        #expect(reloaded.lastWeeklyReview == monday)

        reloaded.refreshWeeklyReviewState(now: wednesday)
        #expect(reloaded.showWeeklyReview == false)

        reloaded.refreshWeeklyReviewState(now: nextSunday)
        #expect(reloaded.showWeeklyReview)
    }

    @MainActor
    @Test("weekly review summary reports completed tasks pomodoros confidence deltas and top priorities")
    func weeklyReviewSummaryReportsWeeklyStats() {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-weekly-review-summary-\(UUID().uuidString).json")
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 18))!

        let economics = TaskItem(
            id: "economics",
            title: "Economics test revision",
            list: "Seqta",
            source: .seqta,
            subject: "Economics",
            estimateMinutes: 90,
            confidence: 2,
            importance: 10,
            dueDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 9)),
            notes: "",
            energy: .high,
            isCompleted: false,
            completedAt: nil
        )
        let english = TaskItem(
            id: "english",
            title: "English assessment draft",
            list: "Seqta",
            source: .seqta,
            subject: "English",
            estimateMinutes: 75,
            confidence: 3,
            importance: 8,
            dueDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9)),
            notes: "",
            energy: .medium,
            isCompleted: false,
            completedAt: nil
        )
        let maths = TaskItem(
            id: "maths",
            title: "Maths investigation edits",
            list: "Seqta",
            source: .seqta,
            subject: "Maths",
            estimateMinutes: 60,
            confidence: 3,
            importance: 7,
            dueDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 2, hour: 9)),
            notes: "",
            energy: .medium,
            isCompleted: false,
            completedAt: nil
        )
        let society = TaskItem(
            id: "society",
            title: "Society and Culture photo essay",
            list: "Seqta",
            source: .seqta,
            subject: "Society and Culture",
            estimateMinutes: 45,
            confidence: 4,
            importance: 5,
            dueDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 9)),
            notes: "",
            energy: .low,
            isCompleted: false,
            completedAt: nil
        )
        let completedThisWeek = TaskItem(
            id: "completed-week",
            title: "Finished history reading",
            list: "Manual",
            source: .chat,
            subject: "History",
            estimateMinutes: 30,
            confidence: 3,
            importance: 4,
            dueDate: nil,
            notes: "",
            energy: .low,
            isCompleted: true,
            completedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 24, hour: 17))
        )
        let completedYesterday = TaskItem(
            id: "completed-yesterday",
            title: "Finished chemistry notes",
            list: "Manual",
            source: .chat,
            subject: "Chemistry",
            estimateMinutes: 35,
            confidence: 3,
            importance: 4,
            dueDate: nil,
            notes: "",
            energy: .low,
            isCompleted: true,
            completedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 14))
        )
        let completedEarlier = TaskItem(
            id: "completed-earlier",
            title: "Old completed task",
            list: "Manual",
            source: .chat,
            subject: "Chemistry",
            estimateMinutes: 20,
            confidence: 3,
            importance: 2,
            dueDate: nil,
            notes: "",
            energy: .low,
            isCompleted: true,
            completedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 9))
        )

        let store = PlannerStore(storageURL: storageURL)
        store.tasks = [
            economics,
            english,
            maths,
            society,
            completedThisWeek,
            completedYesterday,
            completedEarlier
        ]
        store.contexts = []
        store.schedule = []
        store.chat = []
        store.studyChat = []
        store.pomodoroLog = [
            "2026-03-23": 1,
            "2026-03-24": 2,
            "2026-03-25": 0,
            "2026-03-26": 1,
            "2026-03-27": 3,
            "2026-03-28": 1,
            "2026-03-29": 2
        ]
        store.confidenceHistory = [
            "Economics": [
                ConfidenceReading(date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 22, hour: 9))!, value: 0.4),
                ConfidenceReading(date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!, value: 0.7)
            ],
            "English": [
                ConfidenceReading(date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 21, hour: 9))!, value: 0.8),
                ConfidenceReading(date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 27, hour: 18))!, value: 0.6)
            ]
        ]

        let summary = store.weeklyReviewSummary(now: now)

        #expect(summary.completedTaskCount == 2)
        #expect(summary.totalPomodoros == 10)
        #expect(summary.confidenceDeltas.count == 2)
        #expect(summary.confidenceDeltas.map(\.subject) == ["Economics", "English"])
        #expect(abs(summary.confidenceDeltas[0].delta - 0.3) < 0.0001)
        #expect(abs(summary.confidenceDeltas[1].delta + 0.2) < 0.0001)
        #expect(summary.topPriorities.map(\.task.title) == [
            "Economics test revision",
            "English assessment draft",
            "Maths investigation edits"
        ])
    }
}
