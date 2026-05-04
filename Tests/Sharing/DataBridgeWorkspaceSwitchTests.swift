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

    @Test("TimedRootView observes active workspace changes")
    func rootObservesActiveWorkspaceChanges() throws {
        let content = try source("Sources/TimedKit/Features/TimedRootView.swift")
        #expect(content.contains(".onChange(of: auth.activeWorkspaceId)"),
                "TimedRootView must reload task state when the active workspace changes")
        #expect(content.contains("resetWorkspaceScopedState()"),
                "Workspace switch must clear in-memory task state before refetch")
    }

    @Test("TimedRootView assigns empty Supabase task results")
    func rootAssignsEmptyTaskFetches() throws {
        let content = try source("Sources/TimedKit/Features/TimedRootView.swift")
        #expect(!content.contains("if !dbTasks.isEmpty { tasks = dbTasks.map"),
                "Empty remote task results must replace stale in-memory tasks")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }

    private func restoreActiveExecutive(_ value: String?) {
        if let value {
            UserDefaults.standard.set(value, forKey: PlatformPaths.activeExecutiveDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: PlatformPaths.activeExecutiveDefaultsKey)
        }
    }
}
