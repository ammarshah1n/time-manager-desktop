import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Planning Engine")
struct PlanningEngineTests {
    @Test("Ranks urgent school work above lower priority work")
    func ranksUrgentWorkFirst() {
        let now = Date()
        let urgent = TaskItem(
            id: "urgent",
            title: "English essay",
            list: "School",
            source: .seqta,
            subject: "English",
            estimateMinutes: 40,
            confidence: 1,
            importance: 5,
            dueDate: now,
            notes: "",
            energy: .high
        )

        let lowerPriority = TaskItem(
            id: "later",
            title: "Admin task",
            list: "Home",
            source: .chat,
            subject: "Admin",
            estimateMinutes: 30,
            confidence: 5,
            importance: 2,
            dueDate: nil,
            notes: "",
            energy: .low
        )

        let ranked = PlanningEngine.rank(tasks: [lowerPriority, urgent], now: now)

        #expect(ranked.first?.task.id == "urgent")
        #expect(ranked.first?.band == "Do now")
    }

    @Test("Builds time boxes from the ranked tasks")
    func buildsTimeBoxes() {
        let task = TaskItem(
            id: "task-1",
            title: "Maths investigation",
            list: "School",
            source: .seqta,
            subject: "Maths",
            estimateMinutes: 75,
            confidence: 2,
            importance: 5,
            dueDate: Date(),
            notes: "",
            energy: .high
        )

        let ranked = PlanningEngine.rank(tasks: [task])
        let schedule = PlanningEngine.buildSchedule(tasks: ranked, now: Date())

        #expect(schedule.count == 1)
        #expect(schedule.first?.title.contains("Maths investigation") == true)
        #expect(schedule.first?.timeRange.contains("-") == true)
    }
}
