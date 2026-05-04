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
        #expect(content.contains("let workspaceId = auth.activeOrPrimaryWorkspaceId"),
                "Workspace switch must capture the intended workspace before launching the fetch")
        #expect(content.contains("fetchFromSupabaseIfConnected(expectedWorkspaceId: workspaceId)"),
                "Workspace switch must pass the captured workspace into the fetch")
    }

    @Test("TimedRootView assigns empty Supabase task results")
    func rootAssignsEmptyTaskFetches() throws {
        let content = try source("Sources/TimedKit/Features/TimedRootView.swift")
        #expect(!content.contains("if !dbTasks.isEmpty { tasks = dbTasks.map"),
                "Empty remote task results must replace stale in-memory tasks")
    }

    @Test("TimedRootView guards stale workspace fetch completions")
    func rootGuardsStaleWorkspaceFetches() throws {
        let content = try source("Sources/TimedKit/Features/TimedRootView.swift")
        let bridge = try source("Sources/TimedKit/Core/Services/DataBridge.swift")
        #expect(content.contains("expectedWorkspaceId"),
                "Supabase fetches must accept an expected workspace id")
        #expect(content.contains("auth.activeOrPrimaryWorkspaceId == taskWorkspaceId"),
                "Supabase fetches must guard the active workspace before assigning task state")
        #expect(content.contains("supa.fetchTaskSections(taskWorkspaceId)"),
                "Task sections must be fetched with the same captured workspace id as tasks")
        #expect(content.contains("let sectionRows = try await supa.fetchTaskSections(taskWorkspaceId)"),
                "Task section fetch failures must not be treated as successful empty results")
        #expect(!content.contains("(try? await supa.fetchTaskSections(taskWorkspaceId)) ?? []"),
                "Task section fetch errors must not clear existing section state")
        #expect(!content.contains("DataBridge.shared.loadTaskSections()) ?? []"),
                "Root Supabase fetch must not reload sections through global active workspace state")
        #expect(content.contains("let localStore = DataStore.shared"),
                "Initial task hydration must use local DataStore, not DataBridge remote workspace loads")
        #expect(!content.contains("await store.loadTasks()"),
                "Initial load must not fetch tasks through global active workspace state")
        #expect(!content.contains("await store.loadTaskSections()"),
                "Initial load must not fetch sections through global active workspace state")
        #expect(content.contains("let workspaceId = auth.activeOrPrimaryWorkspaceId"),
                "Persistence observers must capture the active workspace before launching unstructured saves")
        #expect(content.contains("DataBridge.shared.saveTasks(v, workspaceId: workspaceId)"),
                "Task saves must bind to the captured workspace id")
        #expect(content.contains("DataBridge.shared.saveTaskSections(v, workspaceId: workspaceId)"),
                "Section saves must bind to the captured workspace id")
        #expect(occurrences(of: "guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }", in: content) >= 2,
                "Stale task and section saves must be skipped before writing local cache")
        #expect(bridge.contains("private var workspaceGeneration"),
                "DataBridge must invalidate stale task completions across workspace switches")
        #expect(bridge.contains("workspaceGeneration += 1"),
                "Workspace switches must advance the DataBridge generation")
        #expect(bridge.contains("func loadTasks(workspaceId requestedWorkspaceId: UUID? = nil)"),
                "DataBridge task loads must be able to bind to a captured workspace id")
        #expect(bridge.contains("func saveTasks(_ tasks: [TimedTask], workspaceId: UUID?)"),
                "DataBridge task saves must require an explicit workspace id")
        #expect(bridge.contains("func saveTaskSections(_ sections: [TaskSection], workspaceId: UUID?)"),
                "DataBridge section saves must require an explicit workspace id")
        #expect(!bridge.contains("func saveTasks(_ tasks: [TimedTask], workspaceId: UUID? = nil)"),
                "DataBridge task saves must not silently resolve workspace at save time")
        #expect(!bridge.contains("try await saveTasks(tasks)"),
                "DataBridge task mutators must pass the captured workspace id when saving")
        #expect(occurrences(of: "try await saveTasks(tasks, workspaceId: workspaceId)", in: bridge) >= 5,
                "DataBridge task mutators must carry workspace id from read to write")
        #expect(occurrences(of: "guard await isCurrentWorkspace(workspaceId, generation: generation) else { return [] }", in: bridge) >= 2,
                "Remote task and section load completions must revalidate workspace generation before caching")
        #expect(!bridge.contains("if !tasks.isEmpty"),
                "Successful empty remote task fetches must clear stale local task cache")
        #expect(!bridge.contains("if !sections.isEmpty"),
                "Successful empty remote section fetches must clear stale local section cache")
        #expect(content.contains("let workspaceId = auth.activeOrPrimaryWorkspaceId\n        Task"),
                "Task deletes must capture the workspace before awaiting")
        #expect(content.contains("guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }\n            tasks = latest"),
                "Task deletes must ignore stale completions after workspace switches")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func restoreActiveExecutive(_ value: String?) {
        if let value {
            UserDefaults.standard.set(value, forKey: PlatformPaths.activeExecutiveDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: PlatformPaths.activeExecutiveDefaultsKey)
        }
    }
}
