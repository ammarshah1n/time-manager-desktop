// DataBridge.swift — Timed Core
// Single interface for all data reads/writes.
// Routes to Supabase when authenticated + online, falls back to DataStore (local JSON).
// Write path: local first (instant), then Supabase sync.
// Read path: Supabase when available, local cache when not.
//
// Phase 0.04: initial implementation — all types delegate to local DataStore.
// Supabase sync for each type will be wired incrementally as schemas align.

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

    // MARK: - Network status

    private var isOnline: Bool {
        get async { await NetworkMonitor.shared.isConnected }
    }

    private var isAuthenticated: Bool {
        get async { await AuthService.shared.executiveId != nil }
    }
}
