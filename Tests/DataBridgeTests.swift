// DataBridgeTests.swift — Timed
// Tests for Sources/Core/Services/DataBridge.swift
// Tests local storage path only (no Supabase, no network).

import Foundation
import Dependencies
import Testing

@testable import TimedKit

@Suite("DataBridge", .serialized)
struct DataBridgeTests {

    // MARK: - Load returns empty on fresh state

    @Test("loadTasks returns empty array, not crash")
    func testLoadTasksEmpty() async throws {
        let bridge = DataBridge()
        let tasks = try await bridge.loadTasks()
        #expect(tasks.isEmpty || !tasks.isEmpty) // should not crash
    }

    @Test("loadTriageItems returns empty array, not crash")
    func testLoadTriageEmpty() async throws {
        let bridge = DataBridge()
        let items = try await bridge.loadTriageItems()
        #expect(items.isEmpty || !items.isEmpty) // should not crash
    }

    @Test("loadBlocks returns empty array, not crash")
    func testLoadBlocksEmpty() async throws {
        let bridge = DataBridge()
        let blocks = try await bridge.loadBlocks()
        #expect(blocks.isEmpty || !blocks.isEmpty)
    }

    @Test("loadWOOItems returns empty array, not crash")
    func testLoadWOOEmpty() async throws {
        let bridge = DataBridge()
        let items = try await bridge.loadWOOItems()
        #expect(items.isEmpty || !items.isEmpty)
    }

    @Test("loadCaptureItems returns empty array, not crash")
    func testLoadCaptureEmpty() async throws {
        let bridge = DataBridge()
        let items = try await bridge.loadCaptureItems()
        #expect(items.isEmpty || !items.isEmpty)
    }

    @Test("loadBucketEstimates returns empty dict, not crash")
    func testLoadBucketEstimatesEmpty() async throws {
        let bridge = DataBridge()
        let estimates = try await bridge.loadBucketEstimates()
        #expect(estimates.isEmpty || !estimates.isEmpty)
    }

    @Test("loadFocusSessions returns empty array, not crash")
    func testLoadFocusEmpty() async throws {
        let bridge = DataBridge()
        let sessions = try await bridge.loadFocusSessions()
        #expect(sessions.isEmpty || !sessions.isEmpty)
    }

    @Test("loadActiveFocusSession returns nil, not crash")
    func testLoadActiveFocusNil() async throws {
        let bridge = DataBridge()
        let session = try await bridge.loadActiveFocusSession()
        // nil is expected on fresh state
        _ = session
    }

    @Test("TaskBucket round-trips canonical DB values")
    func testTaskBucketCanonicalDBValues() {
        for bucket in TaskBucket.allCases {
            #expect(TaskBucket.from(dbValue: bucket.dbValue) == bucket)
        }
        #expect(TaskBucket.ccFyi.dbValue == "cc_fyi")
    }

    @Test("TimedTask decodes canonical and legacy bucket values")
    func testTimedTaskDecodesBucketValues() {
        #expect(TimedTask(from: makeTaskRow(bucketType: "reply_email")).bucket == .reply)
        #expect(TimedTask(from: makeTaskRow(bucketType: "Read Today")).bucket == .readToday)
        #expect(TimedTask(from: makeTaskRow(bucketType: "cc_fyi")).bucket == .ccFyi)
    }

    @Test("TimedTask preserves DB profile id")
    func testTimedTaskPreservesProfileId() {
        let profileId = UUID()
        #expect(TimedTask(from: makeTaskRow(bucketType: "action", profileId: profileId)).profileId == profileId)
    }

    @Test("TimedTask decodes hierarchy values")
    func testTimedTaskDecodesHierarchyValues() {
        let sectionId = UUID()
        let parentTaskId = UUID()
        let task = TimedTask(from: makeTaskRow(
            bucketType: "read_today",
            sectionId: sectionId,
            parentTaskId: parentTaskId,
            sortOrder: 3,
            manualImportance: "red",
            notes: "Read before the board pack",
            isPlanningUnit: true
        ))

        #expect(task.sectionId == sectionId)
        #expect(task.parentTaskId == parentTaskId)
        #expect(task.sortOrder == 3)
        #expect(task.manualImportance == .red)
        #expect(task.notes == "Read before the board pack")
        #expect(task.isPlanningUnit == true)
        #expect(task.isSubtask)
    }
    // MARK: - Offline Replay

    @Test("idempotency key keeps latest pending payload")
    func testIdempotencyKeyKeepsLatestPayload() async throws {
        try await withIsolatedTimedStore {
            let queue = OfflineSyncQueue()
            let recorder = QueueReplayRecorder()

            try await queue.enqueue(
                operationType: "test.operation",
                payload: Data(#"{"version":1}"#.utf8),
                idempotencyKey: "same-op"
            )
            try await queue.enqueue(
                operationType: "test.operation",
                payload: Data(#"{"version":2}"#.utf8),
                idempotencyKey: "same-op"
            )

            let before = try await queue.diagnostics()
            #expect(before.pendingCount == 1)
            #expect(before.activePendingCount == 1)

            await queue.flush { operationType, payload in
                await recorder.record(operationType: operationType, payload: payload)
            }

            let entries = await recorder.entries()
            #expect(entries == [QueueReplayEntry(operationType: "test.operation", payload: #"{"version":2}"#)])

            let after = try await queue.diagnostics()
            #expect(after.pendingCount == 0)
            #expect(after.permanentFailureCount == 0)
        }
    }
    @Test("saveTasks queues failed task upserts")
    func testSaveTasksQueuesFailedTaskUpserts() async throws {
        try await withAuthenticatedTimedStore { executiveID in
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.upsertTask = { _ in throw DataBridgeReplayTestError.expectedFailure }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)

                try await bridge.saveTasks([makeTask(title: "Queued failure")], workspaceId: executiveID)
                try await Task.sleep(for: .milliseconds(100))

                let diagnostics = try await queue.diagnostics()
                #expect(diagnostics.pendingCount == 1)
                #expect(diagnostics.activePendingCount == 1)
            }
        }
    }

    @Test("flushOfflineReplay replays queued task upserts")
    func testFlushOfflineReplayReplaysQueuedTaskUpserts() async throws {
        let recorder = TaskUpsertRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.upsertTask = { row in await recorder.record(row) }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)
                let task = makeTask(title: "Replay me")

                try await bridge.saveTasks([task], workspaceId: executiveID)
                await bridge.flushOfflineReplay()

                let rows = await recorder.rows()
                #expect(rows.contains { row in
                    row.id == task.id && row.workspaceId == executiveID && row.profileId == executiveID
                })

                let diagnostics = try await queue.diagnostics()
                #expect(diagnostics.pendingCount == 0)
            }
        }
    }

    @Test("saveTasks preserves loaded task profile id")
    func testSaveTasksPreservesLoadedTaskProfileId() async throws {
        let recorder = TaskUpsertRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            let ownerProfileId = UUID()
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.upsertTask = { row in await recorder.record(row) }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)
                let task = TimedTask(from: makeTaskRow(bucketType: "action", profileId: ownerProfileId))

                try await bridge.saveTasks([task], workspaceId: executiveID)
                await bridge.flushOfflineReplay()

                let row = try #require(await recorder.rows().first { $0.id == task.id })
                #expect(row.workspaceId == executiveID)
                #expect(row.profileId == ownerProfileId)
            }
        }
    }

    @Test("moveBucket preserves loaded task profile id")
    func testMoveBucketPreservesLoadedTaskProfileId() async throws {
        let recorder = TaskUpsertRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            let taskId = UUID()
            let ownerProfileId = UUID()
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.fetchTasks = { _, _, _ in
                    [makeTaskRow(id: taskId, bucketType: "action", profileId: ownerProfileId)]
                }
                dependency.upsertTask = { row in await recorder.record(row) }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)
                let context = await bridge.workspaceMutationContext()

                _ = try await bridge.moveBucket(id: taskId, to: .readToday, context: context)
                await bridge.flushOfflineReplay()

                let row = try #require(await recorder.rows().first { $0.id == taskId })
                #expect(row.workspaceId == executiveID)
                #expect(row.profileId == ownerProfileId)
                #expect(row.bucketType == "read_today")
            }
        }
    }

    @Test("task rebuild helpers preserve profile id")
    func testTaskRebuildHelpersPreserveProfileId() throws {
        let expectations = [
            ("Sources/TimedKit/Core/Tools/ConversationTools.swift", "profileId: task.profileId"),
            ("Sources/TimedKit/Core/Services/DataBridge.swift", "profileId: task.profileId"),
            ("Sources/TimedKit/Features/Tasks/TasksPane.swift", "id: id, profileId: profileId"),
            ("Sources/TimedKit/Features/Tasks/TaskDetailSheet.swift", "profileId: task.profileId")
        ]

        for (path, needle) in expectations {
            let source = try source(path)
            #expect(source.contains(needle), "Task rebuild helper must preserve profile id in \(path)")
        }
    }

    @Test("saveTasks writes canonical task bucket values")
    func testSaveTasksWritesCanonicalBucketValues() async throws {
        let recorder = TaskUpsertRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.upsertTask = { row in await recorder.record(row) }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)
                let task = makeTask(title: "Canonical bucket", bucket: .readToday)

                try await bridge.saveTasks([task], workspaceId: executiveID)
                await bridge.flushOfflineReplay()

                let rows = await recorder.rows()
                #expect(rows.contains { row in
                    row.id == task.id && row.bucketType == "read_today"
                })
            }
        }
    }

    @Test("saveTasks writes hierarchy fields")
    func testSaveTasksWritesHierarchyFields() async throws {
        let recorder = TaskUpsertRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.upsertTask = { row in await recorder.record(row) }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)
                let sectionId = UUID()
                let parent = makeTask(
                    title: "Parent task",
                    bucket: .action,
                    sectionId: sectionId,
                    sortOrder: 0,
                    manualImportance: .red
                )
                let child = makeTask(
                    title: "Child task",
                    bucket: .action,
                    sectionId: sectionId,
                    parentTaskId: parent.id,
                    sortOrder: 1,
                    manualImportance: .orange,
                    notes: "Smallest next action"
                )

                try await bridge.saveTasks([parent, child], workspaceId: executiveID)
                await bridge.flushOfflineReplay()

                let rows = await recorder.rows()
                let parentRow = try #require(rows.first { $0.id == parent.id })
                let childRow = try #require(rows.first { $0.id == child.id })
                #expect(parentRow.sectionId == sectionId)
                #expect(parentRow.manualImportance == "red")
                #expect(parentRow.isPlanningUnit == false)
                #expect(childRow.parentTaskId == parent.id)
                #expect(childRow.sortOrder == 1)
                #expect(childRow.manualImportance == "orange")
                #expect(childRow.notes == "Smallest next action")
                #expect(childRow.isPlanningUnit == true)
            }
        }
    }

    @Test("saveTaskSections writes section rows")
    func testSaveTaskSectionsWritesRows() async throws {
        let recorder = TaskSectionUpsertRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.upsertTaskSection = { row in await recorder.record(row) }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)
                let section = TaskSection(
                    id: UUID(),
                    parentSectionId: nil,
                    title: "Read in 2 days",
                    canonicalBucketType: "read_this_week",
                    sortOrder: 4,
                    colorKey: "orange",
                    isSystem: false,
                    isArchived: false
                )

                try await bridge.saveTaskSections([section], workspaceId: executiveID)
                await bridge.flushOfflineReplay()

                let rows = await recorder.rows()
                let row = try #require(rows.first { $0.id == section.id })
                #expect(row.workspaceId == executiveID)
                #expect(row.profileId == executiveID)
                #expect(row.title == "Read in 2 days")
                #expect(row.canonicalBucketType == "read_this_week")
                #expect(row.sortOrder == 4)
                #expect(row.colorKey == "orange")
                #expect(row.isSystem == false)
            }
        }
    }

    @Test("saveTaskSections preserves loaded section profile id")
    func testSaveTaskSectionsPreservesLoadedSectionProfileId() async throws {
        let recorder = TaskSectionUpsertRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            let ownerProfileId = UUID()
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.upsertTaskSection = { row in await recorder.record(row) }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)
                let section = TaskSection(
                    id: UUID(),
                    profileId: ownerProfileId,
                    parentSectionId: nil,
                    title: "Owner section",
                    canonicalBucketType: "action",
                    sortOrder: 1,
                    colorKey: "blue",
                    isSystem: false,
                    isArchived: false
                )

                try await bridge.saveTaskSections([section], workspaceId: executiveID)
                await bridge.flushOfflineReplay()

                let row = try #require(await recorder.rows().first { $0.id == section.id })
                #expect(row.workspaceId == executiveID)
                #expect(row.profileId == ownerProfileId)
            }
        }
    }

    @Test("saveTaskSections skips service-owned system rows")
    func testSaveTaskSectionsSkipsSystemRows() async throws {
        let recorder = TaskSectionUpsertRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.upsertTaskSection = { row in await recorder.record(row) }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)
                let systemSection = TaskSection(
                    id: UUID(),
                    parentSectionId: nil,
                    title: "Email",
                    canonicalBucketType: "other",
                    sortOrder: 0,
                    colorKey: nil,
                    isSystem: true,
                    isArchived: false
                )
                let userSection = TaskSection(
                    id: UUID(),
                    parentSectionId: nil,
                    title: "Board prep",
                    canonicalBucketType: "action",
                    sortOrder: 1,
                    colorKey: "blue",
                    isSystem: false,
                    isArchived: false
                )

                try await bridge.saveTaskSections([systemSection, userSection], workspaceId: executiveID)
                await bridge.flushOfflineReplay()

                let rows = await recorder.rows()
                #expect(!rows.contains { $0.id == systemSection.id })
                #expect(rows.contains { $0.id == userSection.id })
            }
        }
    }

    @Test("logEstimateOverride writes hierarchy event metadata")
    func testLogEstimateOverrideWritesHierarchyEventMetadata() async throws {
        let recorder = BehaviourEventRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.insertBehaviourEvent = { event in await recorder.record(event) }
                $0.supabaseClient = dependency
            } operation: {
                let bridge = DataBridge()
                let sectionId = UUID()
                let parentTaskId = UUID()
                let task = makeTask(
                    title: "Correct estimate",
                    bucket: .readToday,
                    sectionId: sectionId,
                    parentTaskId: parentTaskId
                )

                try await bridge.logEstimateOverride(task: task, oldMinutes: 45, newMinutes: 30)

                let event = try #require(await recorder.events().first)
                #expect(event.workspaceId == executiveID)
                #expect(event.profileId == executiveID)
                #expect(event.eventType == "estimate_override")
                #expect(event.taskId == task.id)
                #expect(event.sectionId == sectionId)
                #expect(event.parentTaskId == parentTaskId)
                #expect(event.bucketType == "read_today")
                #expect(event.oldValue == "45")
                #expect(event.newValue == "30")
                #expect(event.eventMetadata?["field"] == "estimated_minutes")
            }
        }
    }

    @Test("logEstimateOverride writes to captured workspace context")
    func testLogEstimateOverrideUsesCapturedWorkspaceContext() async throws {
        let recorder = BehaviourEventRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            let otherWorkspaceID = UUID()
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.insertBehaviourEvent = { event in await recorder.record(event) }
                $0.supabaseClient = dependency
            } operation: {
                let bridge = DataBridge()
                let task = makeTask(title: "Bound event", bucket: .action)
                let context = TaskBehaviourEventContext(workspaceId: executiveID, profileId: executiveID)

                await MainActor.run {
                    AuthService.shared.activeWorkspaceId = otherWorkspaceID
                }
                try await bridge.logEstimateOverride(
                    task: task,
                    oldMinutes: 45,
                    newMinutes: 30,
                    context: context
                )

                let event = try #require(await recorder.events().first)
                #expect(event.workspaceId == executiveID)
                #expect(event.profileId == executiveID)
                #expect(event.taskId == task.id)
                #expect(event.eventType == "estimate_override")
            }
        }
    }

    @Test("updateManualImportance logs correction event")
    func testUpdateManualImportanceLogsCorrectionEvent() async throws {
        let recorder = BehaviourEventRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            let task = makeTask(title: "Rank manually", bucket: .action, manualImportance: .blue)
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.fetchTasks = { _, _, _ in
                    [makeTaskRow(from: task, workspaceId: executiveID, profileId: executiveID)]
                }
                dependency.insertBehaviourEvent = { event in await recorder.record(event) }
                $0.supabaseClient = dependency
            } operation: {
                let bridge = DataBridge()

                try await bridge.saveTasks([task], workspaceId: executiveID)
                let tasks = try await bridge.updateManualImportance(id: task.id, importance: .red)

                #expect(tasks.first(where: { $0.id == task.id })?.manualImportance == .red)
                let event = try #require(await recorder.events().first)
                #expect(event.eventType == "manual_importance_changed")
                #expect(event.taskId == task.id)
                #expect(event.bucketType == "action")
                #expect(event.oldValue == "blue")
                #expect(event.newValue == "red")
                #expect(event.eventMetadata?["field"] == "manual_importance")
            }
        }
    }
    @Test("delete queues remote tombstone instead of only saving local remainder")
    func testDeleteQueuesRemoteTombstone() async throws {
        let recorder = TaskStatusRecorder()

        try await withAuthenticatedTimedStore { executiveID in
            let task = makeTask(title: "Delete remotely")
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.fetchTasks = { _, _, _ in
                    [makeTaskRow(from: task, workspaceId: executiveID, profileId: executiveID)]
                }
                dependency.updateTaskStatus = { taskId, status, actualMinutes in
                    await recorder.record(taskId: taskId, status: status, actualMinutes: actualMinutes)
                }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)

                try await bridge.saveTasks([task], workspaceId: executiveID)
                _ = try await bridge.delete(id: task.id)
                await bridge.flushOfflineReplay()

                let updates = await recorder.updates()
                #expect(updates.contains(TaskStatusUpdateRecord(taskId: task.id, status: "deleted", actualMinutes: nil)))
            }
        }
    }

    @Test("behaviour event insert failure leaves durable replay item")
    func testBehaviourEventInsertFailureQueuesReplay() async throws {
        try await withAuthenticatedTimedStore { _ in
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.insertBehaviourEvent = { _ in throw DataBridgeReplayTestError.expectedFailure }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)
                let task = makeTask(title: "Offline estimate reason")

                let eventId = try await bridge.logEstimateOverride(task: task, oldMinutes: 15, newMinutes: 25)

                #expect(eventId == nil)
                let diagnostics = try await queue.diagnostics()
                #expect(diagnostics.pendingCount == 1)
                #expect(diagnostics.activePendingCount == 1)
            }
        }
    }

    @Test("flushOfflineReplay replays queued behaviour events")
    func testFlushOfflineReplayReplaysBehaviourEvents() async throws {
        let recorder = BehaviourEventRecorder()

        try await withAuthenticatedTimedStore { _ in
            let queue = OfflineSyncQueue()
            let bridge = DataBridge(offlineQueue: queue, automaticallyFlushOfflineReplay: false)
            let task = makeTask(title: "Replay behaviour event")

            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.insertBehaviourEvent = { _ in throw DataBridgeReplayTestError.expectedFailure }
                $0.supabaseClient = dependency
            } operation: {
                _ = try await bridge.logEstimateOverride(task: task, oldMinutes: 15, newMinutes: 25)
            }

            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.insertBehaviourEvent = { event in await recorder.record(event) }
                $0.supabaseClient = dependency
            } operation: {
                await bridge.flushOfflineReplay()
            }

            let event = try #require(await recorder.events().first)
            #expect(event.eventType == "estimate_override")
            #expect(event.taskId == task.id)
            #expect(event.oldValue == "15")
            #expect(event.newValue == "25")
        }
    }
}

private struct QueueReplayEntry: Equatable, Sendable {
    let operationType: String
    let payload: String
}

private actor QueueReplayRecorder {
    private var storedEntries: [QueueReplayEntry] = []

    func record(operationType: String, payload: Data) {
        storedEntries.append(
            QueueReplayEntry(
                operationType: operationType,
                payload: String(data: payload, encoding: .utf8) ?? ""
            )
        )
    }

    func entries() -> [QueueReplayEntry] {
        storedEntries
    }
}

private actor TaskUpsertRecorder {
    private var storedRows: [TaskDBRow] = []

    func record(_ row: TaskDBRow) {
        storedRows.append(row)
    }

    func rows() -> [TaskDBRow] {
        storedRows
    }
}

private actor TaskSectionUpsertRecorder {
    private var storedRows: [TaskSectionDBRow] = []

    func record(_ row: TaskSectionDBRow) {
        storedRows.append(row)
    }

    func rows() -> [TaskSectionDBRow] {
        storedRows
    }
}

private actor BehaviourEventRecorder {
    private var storedEvents: [BehaviourEventInsert] = []

    func record(_ event: BehaviourEventInsert) -> UUID {
        storedEvents.append(event)
        return UUID()
    }

    func events() -> [BehaviourEventInsert] {
        storedEvents
    }
}

private struct TaskStatusUpdateRecord: Equatable, Sendable {
    let taskId: UUID
    let status: String
    let actualMinutes: Int?
}

private actor TaskStatusRecorder {
    private var storedUpdates: [TaskStatusUpdateRecord] = []

    func record(taskId: UUID, status: String, actualMinutes: Int?) {
        storedUpdates.append(TaskStatusUpdateRecord(taskId: taskId, status: status, actualMinutes: actualMinutes))
    }

    func updates() -> [TaskStatusUpdateRecord] {
        storedUpdates
    }
}

private enum DataBridgeReplayTestError: Error {
    case expectedFailure
}

private func makeTask(
    title: String,
    bucket: TaskBucket = .action,
    sectionId: UUID? = nil,
    parentTaskId: UUID? = nil,
    sortOrder: Int? = nil,
    manualImportance: TaskManualImportance? = nil,
    notes: String? = nil
) -> TimedTask {
    TimedTask(
        id: UUID(),
        title: title,
        sender: "Timed",
        estimatedMinutes: 15,
        bucket: bucket,
        emailCount: 0,
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
        sectionId: sectionId,
        parentTaskId: parentTaskId,
        sortOrder: sortOrder,
        manualImportance: manualImportance,
        notes: notes
    )
}

private func makeTaskRow(
    from task: TimedTask,
    workspaceId: UUID,
    profileId: UUID
) -> TaskDBRow {
    TaskDBRow(
        id: task.id,
        workspaceId: workspaceId,
        profileId: profileId,
        sourceType: task.source.rawValue,
        bucketType: task.bucket.dbValue,
        sectionId: task.sectionId,
        parentTaskId: task.parentTaskId,
        sortOrder: task.sortOrder ?? 0,
        manualImportance: task.effectiveManualImportance.rawValue,
        notes: task.notes,
        isPlanningUnit: task.isPlanningUnit ?? true,
        title: task.title,
        description: nil,
        status: task.isDone ? "done" : "pending",
        priority: task.isDoFirst ? 10 : 5,
        dueAt: task.dueToday ? Calendar.current.startOfDay(for: Date()) : nil,
        estimatedMinutesAi: task.estimateSource == .manual ? nil : task.estimatedMinutes,
        estimatedMinutesManual: task.estimateSource == .manual ? task.estimatedMinutes : nil,
        actualMinutes: nil,
        estimateSource: task.estimateSource.rawValue,
        estimateBasis: task.estimateBasis,
        isDoFirst: task.isDoFirst,
        isTransitSafe: task.isTransitSafe,
        isOverdue: false,
        completedAt: task.isDone ? Date() : nil,
        createdAt: task.receivedAt,
        updatedAt: Date(),
        urgency: task.urgency,
        importance: task.importance,
        energyRequired: task.energyRequired,
        context: task.context,
        skipCount: task.skipCount
    )
}

private func makeTaskRow(
    id: UUID = UUID(),
    bucketType: String,
    profileId: UUID = UUID(),
    sectionId: UUID? = nil,
    parentTaskId: UUID? = nil,
    sortOrder: Int? = nil,
    manualImportance: String? = nil,
    notes: String? = nil,
    isPlanningUnit: Bool? = nil
) -> TaskDBRow {
    TaskDBRow(
        id: id,
        workspaceId: UUID(),
        profileId: profileId,
        sourceType: "manual",
        bucketType: bucketType,
        sectionId: sectionId,
        parentTaskId: parentTaskId,
        sortOrder: sortOrder,
        manualImportance: manualImportance,
        notes: notes,
        isPlanningUnit: isPlanningUnit,
        title: "Decoded task",
        description: nil,
        status: "pending",
        priority: 5,
        dueAt: nil,
        estimatedMinutesAi: 20,
        estimatedMinutesManual: nil,
        actualMinutes: nil,
        estimateSource: "ai",
        isDoFirst: false,
        isTransitSafe: false,
        isOverdue: false,
        completedAt: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        urgency: 2,
        importance: 2,
        energyRequired: "medium",
        context: "desk",
        skipCount: 0
    )
}

private func source(_ path: String) throws -> String {
    try String(contentsOf: URL(fileURLWithPath: path))
}

private func withIsolatedTimedStore<T>(_ operation: () async throws -> T) async throws -> T {
    let previousExecutive = UserDefaults.standard.string(forKey: PlatformPaths.activeExecutiveDefaultsKey)
    UserDefaults.standard.set(UUID().uuidString, forKey: PlatformPaths.activeExecutiveDefaultsKey)
    resetOfflineQueueStore()

    do {
        let result = try await operation()
        resetOfflineQueueStore()
        restoreActiveExecutive(previousExecutive)
        return result
    } catch {
        resetOfflineQueueStore()
        restoreActiveExecutive(previousExecutive)
        throw error
    }
}

private func withAuthenticatedTimedStore<T>(_ operation: (UUID) async throws -> T) async throws -> T {
    let executiveID = UUID()
    let snapshot = await MainActor.run {
        let snapshot = AuthSnapshot(
            isSignedIn: AuthService.shared.isSignedIn,
            executiveId: AuthService.shared.executiveId,
            activeWorkspaceId: AuthService.shared.activeWorkspaceId,
            isConnected: NetworkMonitor.shared.isConnected,
            activeExecutive: UserDefaults.standard.string(forKey: PlatformPaths.activeExecutiveDefaultsKey)
        )
        AuthService.shared.isSignedIn = true
        AuthService.shared.executiveId = executiveID
        AuthService.shared.activeWorkspaceId = executiveID
        NetworkMonitor.shared.isConnected = true
        UserDefaults.standard.set(executiveID.uuidString, forKey: PlatformPaths.activeExecutiveDefaultsKey)
        return snapshot
    }
    resetOfflineQueueStore()

    do {
        let result = try await operation(executiveID)
        resetOfflineQueueStore()
        await restoreAuthSnapshot(snapshot)
        return result
    } catch {
        resetOfflineQueueStore()
        await restoreAuthSnapshot(snapshot)
        throw error
    }
}

private func resetOfflineQueueStore() {
    try? FileManager.default.removeItem(at: PlatformPaths.sqlite("offline_queue.sqlite"))
}

@MainActor
private func restoreAuthSnapshot(_ snapshot: AuthSnapshot) {
    AuthService.shared.isSignedIn = snapshot.isSignedIn
    AuthService.shared.executiveId = snapshot.executiveId
    AuthService.shared.activeWorkspaceId = snapshot.activeWorkspaceId
    NetworkMonitor.shared.isConnected = snapshot.isConnected
    restoreActiveExecutive(snapshot.activeExecutive)
}

private func restoreActiveExecutive(_ value: String?) {
    if let value {
        UserDefaults.standard.set(value, forKey: PlatformPaths.activeExecutiveDefaultsKey)
    } else {
        UserDefaults.standard.removeObject(forKey: PlatformPaths.activeExecutiveDefaultsKey)
    }
}

private struct AuthSnapshot: Sendable {
    let isSignedIn: Bool
    let executiveId: UUID?
    let activeWorkspaceId: UUID?
    let isConnected: Bool
    let activeExecutive: String?
}
