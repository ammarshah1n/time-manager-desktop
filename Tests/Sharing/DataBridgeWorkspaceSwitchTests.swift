import Testing
import Foundation
@testable import TimedKit

@Suite("DataBridge workspace switch", .serialized)
struct DataBridgeWorkspaceSwitchTests {
    @Test("handleWorkspaceSwitch empties task and section caches")
    func clearsWorkspaceCaches() async throws {
        let previousExecutive = UserDefaults.standard.string(forKey: PlatformPaths.activeExecutiveDefaultsKey)
        let testExecutive = UUID()
        UserDefaults.standard.set(testExecutive.uuidString, forKey: PlatformPaths.activeExecutiveDefaultsKey)
        defer { restoreActiveExecutive(previousExecutive) }

        let store = DataStore.shared
        try await store.saveTasks([
            TimedTask(
            id: UUID(),
            title: "stale",
            sender: "Ammar",
            estimatedMinutes: 15,
            bucket: .action,
            emailCount: 0,
            receivedAt: Date(),
            isDone: false
        )
        ])
        try await store.saveTaskSections([
            TaskSection(
            id: UUID(),
            parentSectionId: nil,
            title: "Stale",
            canonicalBucketType: "action",
            sortOrder: 0,
            colorKey: nil,
            isSystem: false,
            isArchived: false
        )
        ])

        await DataBridge.shared.handleWorkspaceSwitch()

        let tasks = try await store.loadTasks()
        let sections = try await store.loadTaskSections()
        #expect(tasks.isEmpty)
        #expect(sections.isEmpty)
    }

    private func restoreActiveExecutive(_ value: String?) {
        if let value {
            UserDefaults.standard.set(value, forKey: PlatformPaths.activeExecutiveDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: PlatformPaths.activeExecutiveDefaultsKey)
        }
    }
}
