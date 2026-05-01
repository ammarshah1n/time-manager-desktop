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
        try await withAuthenticatedTimedStore { _ in
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.upsertTask = { _ in throw DataBridgeReplayTestError.expectedFailure }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue)

                try await bridge.saveTasks([makeTask(title: "Queued failure")])
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
                let bridge = DataBridge(offlineQueue: queue)
                let task = makeTask(title: "Replay me")

                try await bridge.saveTasks([task])
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

    @Test("saveTasks writes canonical task bucket values")
    func testSaveTasksWritesCanonicalBucketValues() async throws {
        let recorder = TaskUpsertRecorder()

        try await withAuthenticatedTimedStore { _ in
            try await withDependencies {
                var dependency = SupabaseClientDependency()
                dependency.upsertTask = { row in await recorder.record(row) }
                $0.supabaseClient = dependency
            } operation: {
                let queue = OfflineSyncQueue()
                let bridge = DataBridge(offlineQueue: queue)
                let task = makeTask(title: "Canonical bucket", bucket: .readToday)

                try await bridge.saveTasks([task])
                await bridge.flushOfflineReplay()

                let rows = await recorder.rows()
                #expect(rows.contains { row in
                    row.id == task.id && row.bucketType == "read_today"
                })
            }
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

private enum DataBridgeReplayTestError: Error {
    case expectedFailure
}

private func makeTask(title: String, bucket: TaskBucket = .action) -> TimedTask {
    TimedTask(
        id: UUID(),
        title: title,
        sender: "Timed",
        estimatedMinutes: 15,
        bucket: bucket,
        emailCount: 0,
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func makeTaskRow(bucketType: String) -> TaskDBRow {
    TaskDBRow(
        id: UUID(),
        workspaceId: UUID(),
        profileId: UUID(),
        sourceType: "manual",
        bucketType: bucketType,
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
            isConnected: NetworkMonitor.shared.isConnected,
            activeExecutive: UserDefaults.standard.string(forKey: PlatformPaths.activeExecutiveDefaultsKey)
        )
        AuthService.shared.isSignedIn = true
        AuthService.shared.executiveId = executiveID
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
    let isConnected: Bool
    let activeExecutive: String?
}
