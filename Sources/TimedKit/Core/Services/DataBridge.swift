// DataBridge.swift — Timed Core
// Single interface for all data reads/writes.
// Routes to Supabase when authenticated + online, falls back to DataStore (local JSON).
// Write path: local first (instant), then Supabase sync (fire-and-forget).
// Read path: local cache first, overlaid with Supabase data when available.

import Foundation
import Dependencies
import os

actor DataBridge {
    static let shared = DataBridge()

    @Dependency(\.supabaseClient) private var supabaseClient

    private let local = DataStore.shared

    // MARK: - Tasks

    func loadTasks() async throws -> [TimedTask] {
        return (try? await local.loadTasks()) ?? []
    }

    func saveTasks(_ tasks: [TimedTask]) async throws {
        try await local.saveTasks(tasks)
        // Dual-write to Supabase when authenticated
        guard await isAuthenticated, await isOnline else { return }
        guard let wsId = await authWorkspaceId, let profileId = await authProfileId else { return }
        Task.detached(priority: .utility) { [supabaseClient] in
            for task in tasks {
                let row = TaskDBRow(
                    id: task.id,
                    workspaceId: wsId,
                    profileId: profileId,
                    sourceType: "manual",
                    bucketType: task.bucket.rawValue,
                    title: task.title,
                    description: nil,
                    status: task.isDone ? "done" : "pending",
                    priority: task.isDoFirst ? 10 : 5,
                    dueAt: task.dueToday ? Calendar.current.startOfDay(for: Date()) : nil,
                    estimatedMinutesAi: nil,
                    estimatedMinutesManual: task.estimatedMinutes,
                    actualMinutes: nil,
                    estimateSource: "manual",
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
                do {
                    try await supabaseClient.upsertTask(row)
                } catch {
                    TimedLogger.supabase.error("DataBridge: task sync failed for \(task.id): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func markDone(id: UUID) async throws -> [TimedTask] {
        var tasks = try await loadTasks()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return tasks }
        tasks[index].isDone = true
        try await saveTasks(tasks)
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
        tasks[index] = rebuilt(tasks[index], bucket: bucket)
        try await saveTasks(tasks)
        return tasks
    }

    func delete(id: UUID) async throws -> [TimedTask] {
        var tasks = try await loadTasks()
        tasks.removeAll { $0.id == id }
        try await saveTasks(tasks)
        return tasks
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

    private func rebuilt(_ task: TimedTask, bucket: TaskBucket) -> TimedTask {
        TimedTask(
            id: task.id,
            title: task.title,
            sender: task.sender,
            estimatedMinutes: task.estimatedMinutes,
            bucket: bucket,
            emailCount: task.emailCount,
            receivedAt: task.receivedAt,
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
            snoozedUntil: task.snoozedUntil
        )
    }
}
