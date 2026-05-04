// DataBridge.swift — Timed Core
// Single interface for all data reads/writes.
// Routes to Supabase when authenticated + online, falls back to DataStore (local JSON).
// Write path: local first (instant), then Supabase sync (fire-and-forget).
// Read path: local cache first, overlaid with Supabase data when available.

import Foundation
import Dependencies
import os
import Supabase

actor DataBridge {
    static let shared = DataBridge()

    @Dependency(\.supabaseClient) private var supabaseClient

    private let local = DataStore.shared
    private let offlineQueue: OfflineSyncQueue
    private let automaticallyFlushOfflineReplay: Bool

    init(offlineQueue: OfflineSyncQueue = .shared, automaticallyFlushOfflineReplay: Bool = true) {
        self.offlineQueue = offlineQueue
        self.automaticallyFlushOfflineReplay = automaticallyFlushOfflineReplay
    }

    func handleWorkspaceSwitch() async {
        await local.clearWorkspaceCaches()
        // Public load* calls repopulate from Supabase under the new active workspace id.
    }

    // MARK: - Tasks

    func loadTasks() async throws -> [TimedTask] {
        let cached = (try? await local.loadTasks()) ?? []
        guard await isAuthenticated, await isOnline else { return cached }
        guard let wsId = await authWorkspaceId, let profileId = await authProfileId else { return cached }
        guard let rows = try? await supabaseClient.fetchTasks(wsId, profileId, ["pending", "in_progress", "done"]) else {
            return cached
        }
        let tasks = rows.map(TimedTask.init(from:))
        if !tasks.isEmpty {
            try? await local.saveTasks(tasks)
            return tasks
        }
        return cached
    }

    func saveTasks(_ tasks: [TimedTask]) async throws {
        let previousTaskIds = Set(((try? await local.loadTasks()) ?? []).map(\.id))
        try await local.saveTasks(tasks)
        // Dual-write to Supabase when authenticated
        guard await isAuthenticated else { return }
        guard let wsId = await authWorkspaceId, let profileId = await authProfileId else { return }
        let parentIdsWithActiveChildren = Set(tasks.compactMap { task in
            task.isDone ? nil : task.parentTaskId
        })
        let rows = tasks.map {
            makeTaskRow(
                $0,
                workspaceId: wsId,
                profileId: profileId,
                parentIdsWithActiveChildren: parentIdsWithActiveChildren
            )
        }
        let newlyCreatedTasks = tasks.filter { !previousTaskIds.contains($0.id) }
        try await enqueueTaskRows(rows)

        guard automaticallyFlushOfflineReplay, await isOnline else { return }
        Task(priority: .utility) { [weak self] in
            await self?.flushOfflineReplay()
            for task in newlyCreatedTasks {
                await EstimationService.shared.estimate(task: task)
            }
        }
    }

    func loadTaskSections() async throws -> [TaskSection] {
        let cached = (try? await local.loadTaskSections()) ?? []
        guard await isAuthenticated, await isOnline else { return cached }
        guard let wsId = await authWorkspaceId else { return cached }
        guard let rows = try? await supabaseClient.fetchTaskSections(wsId) else { return cached }
        let sections = rows.map(TaskSection.init(from:))
        if !sections.isEmpty {
            try? await local.saveTaskSections(sections)
            return sections
        }
        return cached
    }

    func saveTaskSections(_ sections: [TaskSection]) async throws {
        try await local.saveTaskSections(sections)
        guard await isAuthenticated else { return }
        guard let wsId = await authWorkspaceId, let profileId = await authProfileId else { return }
        // System sections are owned/seeded by the service role. User sessions
        // should only write user-created sections; trying to upsert system
        // rows trips task_sections RLS and makes the UI look saved while sync
        // is actually failing.
        let rows = sections
            .filter { !$0.isSystem }
            .map { makeTaskSectionRow($0, workspaceId: wsId, profileId: profileId) }
        try await enqueueTaskSectionRows(rows)

        guard automaticallyFlushOfflineReplay, await isOnline else { return }
        Task(priority: .utility) { [weak self] in
            await self?.flushOfflineReplay()
        }
    }

    func markDone(id: UUID) async throws -> [TimedTask] {
        var tasks = try await loadTasks()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return tasks }
        tasks[index].isDone = true
        try await saveTasks(tasks)
        try? await logTaskCompleted(task: tasks[index])
        return tasks
    }

    func snooze(id: UUID, until: Date) async throws -> [TimedTask] {
        var tasks = try await loadTasks()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return tasks }
        tasks[index].snoozedUntil = until
        try await saveTasks(tasks)
        return tasks
    }

    func moveBucket(id: UUID, to bucket: TaskBucket) async throws -> [TimedTask] {
        var tasks = try await loadTasks()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return tasks }
        let oldBucket = tasks[index].bucket
        tasks[index] = rebuilt(tasks[index], bucket: bucket)
        try await saveTasks(tasks)
        try? await logTaskBucketChanged(task: tasks[index], oldBucket: oldBucket)
        return tasks
    }

    func updateEstimate(id: UUID, minutes: Int) async throws -> [TimedTask] {
        var tasks = try await loadTasks()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return tasks }
        let oldMinutes = tasks[index].estimatedMinutes
        tasks[index].estimatedMinutes = minutes
        try await saveTasks(tasks)
        try? await logEstimateOverride(task: tasks[index], oldMinutes: oldMinutes, newMinutes: minutes)
        return tasks
    }

    func updateManualImportance(id: UUID, importance: TaskManualImportance) async throws -> [TimedTask] {
        var tasks = try await loadTasks()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return tasks }
        let oldImportance = tasks[index].effectiveManualImportance
        tasks[index].manualImportance = importance
        try await saveTasks(tasks)
        try? await logManualImportanceChanged(task: tasks[index], oldImportance: oldImportance, newImportance: importance)
        return tasks
    }

    func delete(id: UUID) async throws -> [TimedTask] {
        var tasks = try await loadTasks()
        guard tasks.contains(where: { $0.id == id }) else { return tasks }
        tasks.removeAll { $0.id == id }
        try await local.saveTasks(tasks)
        guard await isAuthenticated else { return tasks }
        try await enqueueTaskStatusUpdate(taskId: id, status: "deleted", actualMinutes: nil)

        guard automaticallyFlushOfflineReplay, await isOnline else { return tasks }
        Task(priority: .utility) { [weak self] in
            await self?.flushOfflineReplay()
        }
        return tasks
    }

    @discardableResult
    func logEstimateOverride(task: TimedTask, oldMinutes: Int, newMinutes: Int) async throws -> UUID? {
        guard oldMinutes != newMinutes else { return nil }
        return try await insertTaskBehaviourEvent(
            task: task,
            eventType: "estimate_override",
            oldValue: "\(oldMinutes)",
            newValue: "\(newMinutes)",
            metadata: ["field": "estimated_minutes"]
        )
    }

    func attachReasonToOverride(eventId: UUID, reason: String) async throws {
        guard await isAuthenticated else { return }
        guard await isOnline else {
            try await enqueueBehaviourEventReason(eventId: eventId, reason: reason)
            return
        }
        do {
            try await supabaseClient.attachReasonToBehaviourEvent(eventId, reason)
        } catch {
            try await enqueueBehaviourEventReason(eventId: eventId, reason: reason)
        }
    }

    func logTaskSectionChanged(task: TimedTask, oldSectionId: UUID?, newSectionId: UUID?) async throws {
        guard oldSectionId != newSectionId else { return }
        try await insertTaskBehaviourEvent(
            task: task,
            eventType: "task_section_changed",
            oldValue: oldSectionId?.uuidString,
            newValue: newSectionId?.uuidString,
            metadata: ["field": "section_id"]
        )
    }

    func logSubtaskCreated(parent: TimedTask, child: TimedTask) async throws {
        try await insertTaskBehaviourEvent(
            task: child,
            eventType: "subtask_created",
            oldValue: nil,
            newValue: child.id.uuidString,
            metadata: ["parent_task_id": parent.id.uuidString]
        )
    }

    // MARK: - Triage Items

    func loadTriageItems() async throws -> [TriageItem] {
        return (try? await local.loadTriageItems()) ?? []
    }

    func saveTriageItems(_ items: [TriageItem]) async throws {
        try await local.saveTriageItems(items)
    }

    // MARK: - WOO Items

    func loadWOOItems() async throws -> [WOOItem] {
        return (try? await local.loadWOOItems()) ?? []
    }

    func saveWOOItems(_ items: [WOOItem]) async throws {
        try await local.saveWOOItems(items)
    }

    // MARK: - Calendar Blocks

    func loadBlocks() async throws -> [CalendarBlock] {
        return (try? await local.loadBlocks()) ?? []
    }

    func saveBlocks(_ blocks: [CalendarBlock]) async throws {
        try await local.saveBlocks(blocks)
    }

    // MARK: - Capture Items

    func loadCaptureItems() async throws -> [CaptureItem] {
        return (try? await local.loadCaptureItems()) ?? []
    }

    func saveCaptureItems(_ items: [CaptureItem]) async throws {
        try await local.saveCaptureItems(items)
    }

    // MARK: - Completion Records

    func loadCompletionRecords() async throws -> [CompletionRecord] {
        return (try? await local.loadCompletionRecords()) ?? []
    }

    func saveCompletionRecords(_ records: [CompletionRecord]) async throws {
        try await local.saveCompletionRecords(records)
    }

    // MARK: - Bucket Estimates

    func loadBucketEstimates() async throws -> [String: BucketEstimate] {
        return (try? await local.loadBucketEstimates()) ?? [:]
    }

    func saveBucketEstimates(_ estimates: [String: BucketEstimate]) async throws {
        try await local.saveBucketEstimates(estimates)
    }

    // MARK: - Focus Sessions

    func loadFocusSessions() async throws -> [FocusSessionRecord] {
        return (try? await local.loadFocusSessions()) ?? []
    }

    func saveFocusSessions(_ sessions: [FocusSessionRecord]) async throws {
        try await local.saveFocusSessions(sessions)
    }

    func loadActiveFocusSession() async throws -> FocusSessionRecord? {
        return try? await local.loadActiveFocusSession()
    }

    func saveActiveFocusSession(_ session: FocusSessionRecord?) async throws {
        try await local.saveActiveFocusSession(session)
    }

    // MARK: - Offline Replay

    func startOfflineReplay() async {
        await offlineQueue.startMonitoring { [weak self] operationType, payload in
            guard let self else {
                throw OfflineSyncQueue.QueueError.replayDeferred("DataBridge unavailable")
            }
            try await self.replayQueuedOperation(operationType: operationType, payload: payload)
        }
    }

    func flushOfflineReplay() async {
        await startOfflineReplay()
        await offlineQueue.flushRegistered()
        try? await offlineQueue.cleanup()
        await refreshSyncHealthDiagnostics()
    }

    func offlineQueueDiagnostics() async -> OfflineSyncQueue.Diagnostics {
        let diagnostics = (try? await offlineQueue.diagnostics())
            ?? OfflineSyncQueue.Diagnostics(pendingCount: 0, activePendingCount: 0, permanentFailureCount: 0)
        await SyncHealthCenter.shared.update(diagnostics: diagnostics)
        return diagnostics
    }

    private func refreshSyncHealthDiagnostics() async {
        guard let diagnostics = try? await offlineQueue.diagnostics() else { return }
        await SyncHealthCenter.shared.update(diagnostics: diagnostics)
    }

    private func enqueueTaskRows(_ rows: [TaskDBRow]) async throws {
        let encoder = Self.queueEncoder()
        for row in rows {
            let payload = try encoder.encode(row)
            try await offlineQueue.enqueue(
                operationType: "tasks.upsert",
                payload: payload,
                idempotencyKey: row.id.uuidString.lowercased()
            )
        }
    }

    private func enqueueTaskSectionRows(_ rows: [TaskSectionDBRow]) async throws {
        let encoder = Self.queueEncoder()
        for row in rows {
            let payload = try encoder.encode(row)
            try await offlineQueue.enqueue(
                operationType: "task_sections.upsert",
                payload: payload,
                idempotencyKey: row.id.uuidString.lowercased()
            )
        }
    }

    private func enqueueTaskStatusUpdate(taskId: UUID, status: String, actualMinutes: Int?) async throws {
        let payload = try Self.queueEncoder().encode(TaskStatusQueuePayload(
            taskId: taskId,
            status: status,
            actualMinutes: actualMinutes
        ))
        try await offlineQueue.enqueue(
            operationType: "tasks.status",
            payload: payload,
            idempotencyKey: taskId.uuidString.lowercased()
        )
    }

    private func enqueueBehaviourEvent(_ event: BehaviourEventInsert) async throws {
        let payload = try Self.queueEncoder().encode(event)
        let idempotency = [
            event.eventType,
            event.taskId?.uuidString ?? "no-task",
            event.oldValue ?? "nil",
            event.newValue ?? "nil",
            event.eventMetadata?["field"] ?? "nil"
        ].joined(separator: ":").lowercased()
        try await offlineQueue.enqueue(
            operationType: "behaviour_events.insert",
            payload: payload,
            idempotencyKey: idempotency
        )
    }

    private func enqueueBehaviourEventReason(eventId: UUID, reason: String) async throws {
        let payload = try Self.queueEncoder().encode(BehaviourEventReasonQueuePayload(eventId: eventId, reason: reason))
        try await offlineQueue.enqueue(
            operationType: "behaviour_events.attach_reason",
            payload: payload,
            idempotencyKey: eventId.uuidString.lowercased()
        )
    }

    private func replayQueuedOperation(operationType: String, payload: Data) async throws {
        guard await isAuthenticated else {
            throw OfflineSyncQueue.QueueError.replayDeferred("No signed-in executive for offline replay")
        }
        guard await isOnline else {
            throw OfflineSyncQueue.QueueError.replayDeferred("Network is offline")
        }

        let decoder = Self.queueDecoder()
        switch operationType {
        case "task_sections.upsert":
            let row = try decoder.decode(TaskSectionDBRow.self, from: payload)
            try await supabaseClient.upsertTaskSection(row)
        case "tasks.upsert":
            let row = try decoder.decode(TaskDBRow.self, from: payload)
            try await supabaseClient.upsertTask(row)
        case "tasks.status":
            let update = try decoder.decode(TaskStatusQueuePayload.self, from: payload)
            try await supabaseClient.updateTaskStatus(update.taskId, update.status, update.actualMinutes)
        case "behaviour_events.insert":
            let event = try decoder.decode(BehaviourEventInsert.self, from: payload)
            _ = try await supabaseClient.insertBehaviourEvent(event)
        case "behaviour_events.attach_reason":
            let update = try decoder.decode(BehaviourEventReasonQueuePayload.self, from: payload)
            try await supabaseClient.attachReasonToBehaviourEvent(update.eventId, update.reason)
        case "email_observations.insert":
            let row = try decoder.decode(EmailObservationRow.self, from: payload)
            try await supabaseClient.insertEmailObservation(row)
        case "calendar_observations.insert":
            let row = try decoder.decode(CalendarObservationRow.self, from: payload)
            try await supabaseClient.insertCalendarObservation(row)
        case "tier0_observations.insert":
            guard let client = supabaseClient.rawClient else {
                throw OfflineSyncQueue.QueueError.replayDeferred("Supabase client unavailable")
            }
            let observation = try decoder.decode(Tier0Observation.self, from: payload)
            try await client
                .from("tier0_observations")
                .upsert([observation], onConflict: "idempotency_key")
                .execute()
        default:
            throw OfflineReplayError.unsupportedOperation(operationType)
        }
    }

    // MARK: - Network & Auth status

    private var isOnline: Bool {
        get async { await NetworkMonitor.shared.isConnected }
    }

    private var isAuthenticated: Bool {
        get async { await MainActor.run { AuthService.shared.executiveId != nil } }
    }

    private var authWorkspaceId: UUID? {
        get async { await MainActor.run { AuthService.shared.workspaceId } }
    }

    private var authProfileId: UUID? {
        get async { await MainActor.run { AuthService.shared.profileId } }
    }

    private func logTaskCompleted(task: TimedTask) async throws {
        try await insertTaskBehaviourEvent(
            task: task,
            eventType: task.parentTaskId == nil ? "task_completed" : "subtask_completed",
            oldValue: "pending",
            newValue: "done",
            metadata: ["field": "status"]
        )
    }

    func logTaskBucketChanged(task: TimedTask, oldBucket: TaskBucket) async throws {
        guard oldBucket != task.bucket else { return }
        try await insertTaskBehaviourEvent(
            task: task,
            eventType: "task_section_changed",
            oldValue: oldBucket.dbValue,
            newValue: task.bucket.dbValue,
            metadata: ["field": "bucket_type"]
        )
    }

    func logManualImportanceChanged(
        task: TimedTask,
        oldImportance: TaskManualImportance,
        newImportance: TaskManualImportance
    ) async throws {
        guard oldImportance != newImportance else { return }
        try await insertTaskBehaviourEvent(
            task: task,
            eventType: "manual_importance_changed",
            oldValue: oldImportance.rawValue,
            newValue: newImportance.rawValue,
            metadata: ["field": "manual_importance"]
        )
    }

    @discardableResult
    private func insertTaskBehaviourEvent(
        task: TimedTask,
        eventType: String,
        oldValue: String?,
        newValue: String?,
        metadata: [String: String]
    ) async throws -> UUID? {
        guard await isAuthenticated else { return nil }
        guard let wsId = await authWorkspaceId, let profileId = await authProfileId else { return nil }
        let now = Date()
        let event = BehaviourEventInsert(
            workspaceId: wsId,
            profileId: profileId,
            eventType: eventType,
            taskId: task.id,
            sectionId: task.sectionId,
            parentTaskId: task.parentTaskId,
            bucketType: task.bucket.dbValue,
            hourOfDay: Calendar.current.component(.hour, from: now),
            dayOfWeek: Calendar.current.component(.weekday, from: now) - 1,
            oldValue: oldValue,
            newValue: newValue,
            eventMetadata: metadata
        )
        guard await isOnline else {
            try await enqueueBehaviourEvent(event)
            return nil
        }
        do {
            return try await supabaseClient.insertBehaviourEvent(event)
        } catch {
            try await enqueueBehaviourEvent(event)
            return nil
        }
    }

    private struct TaskStatusQueuePayload: Codable, Sendable {
        let taskId: UUID
        let status: String
        let actualMinutes: Int?
    }

    private struct BehaviourEventReasonQueuePayload: Codable, Sendable {
        let eventId: UUID
        let reason: String
    }

    private static func queueEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func queueDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func makeTaskRow(
        _ task: TimedTask,
        workspaceId: UUID,
        profileId: UUID,
        parentIdsWithActiveChildren: Set<UUID>
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
            isPlanningUnit: task.isPlanningUnit ?? !parentIdsWithActiveChildren.contains(task.id),
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

    private func makeTaskSectionRow(_ section: TaskSection, workspaceId: UUID, profileId: UUID) -> TaskSectionDBRow {
        TaskSectionDBRow(
            id: section.id,
            workspaceId: workspaceId,
            profileId: section.isSystem ? nil : profileId,
            parentSectionId: section.parentSectionId,
            title: section.title,
            canonicalBucketType: section.canonicalBucketType,
            sortOrder: section.sortOrder,
            colorKey: section.colorKey,
            isSystem: section.isSystem,
            isArchived: section.isArchived,
            createdAt: nil,
            updatedAt: Date()
        )
    }

    private func rebuilt(_ task: TimedTask, bucket: TaskBucket) -> TimedTask {
        TimedTask(
            id: task.id,
            title: task.title,
            sender: task.sender,
            estimatedMinutes: task.estimatedMinutes,
            bucket: bucket,
            emailCount: task.emailCount,
            receivedAt: task.receivedAt,
            sectionId: task.sectionId,
            parentTaskId: task.parentTaskId,
            sortOrder: task.sortOrder,
            manualImportance: task.manualImportance,
            notes: task.notes,
            isPlanningUnit: task.isPlanningUnit,
            priority: task.priority,
            replyMedium: task.replyMedium,
            dueToday: task.dueToday,
            isDoFirst: task.isDoFirst,
            isTransitSafe: task.isTransitSafe,
            waitingOn: task.waitingOn,
            askedDate: task.askedDate,
            expectedByDate: task.expectedByDate,
            isDone: task.isDone,
            estimateUncertainty: task.estimateUncertainty,
            planScore: task.planScore,
            scheduledStartTime: task.scheduledStartTime,
            urgency: task.urgency,
            importance: task.importance,
            energyRequired: task.energyRequired,
            context: task.context,
            skipCount: task.skipCount,
            snoozedUntil: task.snoozedUntil,
            source: task.source,
            estimateSource: task.estimateSource,
            estimateBasis: task.estimateBasis
        )
    }

    private enum OfflineReplayError: Error, LocalizedError {
        case unsupportedOperation(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedOperation(let operationType):
                "Unsupported offline operation: \(operationType)"
            }
        }
    }
}
