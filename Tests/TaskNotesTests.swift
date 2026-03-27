import Foundation
import Testing

@testable import time_manager_desktop

@Suite("Task notes")
struct TaskNotesTests {
    @Test("legacy task items decode with empty notes")
    func legacyTaskItemsDecodeWithEmptyNotes() throws {
        let json = """
        {
          "id": "economics-test",
          "title": "Economics test",
          "list": "Seqta",
          "source": "Seqta",
          "subject": "Economics",
          "estimateMinutes": 45,
          "confidence": 3,
          "importance": 5,
          "dueDate": null,
          "energy": "Medium",
          "isCompleted": false,
          "completedAt": null
        }
        """

        let task = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        #expect(task.notes.isEmpty)
    }

    @MainActor
    @Test("planner store persists task note edits")
    func plannerStorePersistsTaskNoteEdits() {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-task-notes-\(UUID().uuidString).json")
        let task = TaskItem(
            id: "english-assessment",
            title: "English assessment",
            list: "Manual",
            source: .chat,
            subject: "English",
            estimateMinutes: 60,
            confidence: 3,
            importance: 4,
            dueDate: nil,
            notes: "",
            energy: .medium,
            isCompleted: false,
            completedAt: nil
        )

        let store = PlannerStore(storageURL: storageURL)
        store.tasks = [task]
        store.contexts = []
        store.schedule = []
        store.chat = []
        store.studyChat = []
        store.selectedTaskID = task.id
        store.save()

        store.updateTaskNotes(taskID: task.id, notes: "**Quotes**\n- Revise intro\n`compare`")

        let reloaded = PlannerStore(storageURL: storageURL)
        #expect(reloaded.tasks.first?.notes == "**Quotes**\n- Revise intro\n`compare`")
    }
}
