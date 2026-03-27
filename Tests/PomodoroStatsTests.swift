import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Pomodoro statistics")
struct PomodoroStatsTests {
    @MainActor
    @Test("planner store persists daily pomodoro counts")
    func plannerStorePersistsDailyPomodoroCounts() {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-pomodoro-log-\(UUID().uuidString).json")
        let task = TaskItem(
            id: "economics-test",
            title: "Economics test",
            list: "Manual",
            source: .chat,
            subject: "Economics",
            estimateMinutes: 50,
            confidence: 3,
            importance: 10,
            dueDate: nil,
            notes: "",
            energy: .high,
            isCompleted: false,
            completedAt: nil
        )
        let studyDay = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 27, hour: 10))!

        let store = PlannerStore(storageURL: storageURL)
        store.tasks = [task]
        store.contexts = []
        store.schedule = []
        store.chat = []
        store.studyChat = []
        store.selectedTaskID = task.id
        store.recordPomodoro(for: task.id, at: studyDay)

        #expect(store.tasks.first?.pomodoroCount == 1)
        #expect(store.pomodoroLog["2026-03-27"] == 1)

        let reloaded = PlannerStore(storageURL: storageURL)
        #expect(reloaded.tasks.first?.pomodoroCount == 1)
        #expect(reloaded.pomodoroLog["2026-03-27"] == 1)
    }

    @MainActor
    @Test("planner store reports streak and seven day trend from daily log")
    func plannerStoreReportsStreakAndTrendFromDailyLog() {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-pomodoro-streak-\(UUID().uuidString).json")
        let calendar = Calendar.current
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 27, hour: 12))!

        let store = PlannerStore(storageURL: storageURL)
        store.pomodoroLog = [
            "2026-03-21": 0,
            "2026-03-22": 2,
            "2026-03-23": 1,
            "2026-03-24": 0,
            "2026-03-25": 3,
            "2026-03-26": 2,
            "2026-03-27": 1
        ]

        #expect(store.currentPomodoroStreak(referenceDate: today) == 3)
        #expect(store.pomodoroCount(on: today) == 1)
        #expect(store.pomodoroTrend(referenceDate: today).map(\.count) == [0, 2, 1, 0, 3, 2, 1])
    }
}
