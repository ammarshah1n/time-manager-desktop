// OfflineSyncQueue.swift — Timed Core
// SQLite-backed queue for Supabase operations when offline.
// Uses GRDB.swift. Flushes chronologically on network restore.
// Exponential backoff: 1s → 2s → 4s → 8s → max 5 min.
// 7-day buffer capacity (~50MB typical).

import Foundation
import GRDB
import os

actor OfflineSyncQueue {
    static let shared = OfflineSyncQueue()

    struct Diagnostics: Equatable, Sendable {
        let pendingCount: Int
        let activePendingCount: Int
        let permanentFailureCount: Int
    }

    private var dbQueue: DatabaseQueue?
    private var isProcessing = false
    private var currentBackoff: TimeInterval = 1.0
    private let maxBackoff: TimeInterval = 300.0 // 5 minutes
    private let retentionDays = 7
    private let maxSizeBytes: UInt64 = 50_000_000 // ~50MB
    private var syncHandler: (@Sendable (String, Data) async throws -> Void)?
    private var monitorTask: Task<Void, Never>?

    init() {
        do {
            let dbPath = PlatformPaths.sqlite("offline_queue.sqlite").path
            let queue = try DatabaseQueue(path: dbPath)
            try Self.createTableIfNeeded(in: queue)
            dbQueue = queue
            TimedLogger.dataStore.info("OfflineSyncQueue initialised at \(dbPath, privacy: .public)")
        } catch {
            TimedLogger.dataStore.error("OfflineSyncQueue init failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Schema

    private static func createTableIfNeeded(in queue: DatabaseQueue) throws {
        try queue.write { db in
            try db.create(table: "pending_operations", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("operation_type", .text).notNull()
                t.column("payload_json", .text).notNull()
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("synced_at", .datetime)
            }
            // Phase 6.6 — track per-row failure count so a permanently-invalid
            // op (e.g., reference to a deleted workspace) doesn't block the
            // entire queue. Adds two columns to existing tables; defaults
            // mean older rows are seen as "0 failures, never permanently
            // failed" and proceed normally on next flush.
            let columns = try db.columns(in: "pending_operations").map(\.name)
            if !columns.contains("failed_count") {
                try db.execute(sql: "ALTER TABLE pending_operations ADD COLUMN failed_count INTEGER NOT NULL DEFAULT 0")
            }
            if !columns.contains("permanently_failed") {
                try db.execute(sql: "ALTER TABLE pending_operations ADD COLUMN permanently_failed INTEGER NOT NULL DEFAULT 0")
            }
            if !columns.contains("idempotency_key") {
                try db.execute(sql: "ALTER TABLE pending_operations ADD COLUMN idempotency_key TEXT")
            }
            try db.create(
                index: "idx_pending_operations_replay",
                on: "pending_operations",
                columns: ["synced_at", "permanently_failed", "created_at"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_pending_operations_idempotency",
                on: "pending_operations",
                columns: ["operation_type", "idempotency_key"],
                ifNotExists: true
            )
        }
    }

    private static let maxFailures = 3

    // MARK: - Enqueue

    func enqueue(operationType: String, payload: Data, idempotencyKey: String? = nil) throws {
        guard let dbQueue else { throw QueueError.notInitialised }
        let payloadString = String(data: payload, encoding: .utf8) ?? "{}"
        try dbQueue.write { db in
            if let idempotencyKey,
               let existingID = try Int64.fetchOne(
                db,
                sql: """
                    SELECT id FROM pending_operations
                    WHERE operation_type = ? AND idempotency_key = ? AND synced_at IS NULL
                    LIMIT 1
                    """,
                arguments: [operationType, idempotencyKey]
               ) {
                try db.execute(
                    sql: """
                        UPDATE pending_operations
                        SET payload_json = ?, failed_count = 0, permanently_failed = 0
                        WHERE id = ?
                        """,
                    arguments: [payloadString, existingID]
                )
                return
            }

            try db.execute(
                sql: "INSERT INTO pending_operations (operation_type, payload_json, idempotency_key) VALUES (?, ?, ?)",
                arguments: [operationType, payloadString, idempotencyKey]
            )
        }
        TimedLogger.dataStore.debug("Enqueued \(operationType, privacy: .public)")
    }

    // MARK: - Network Monitor Integration

    func startMonitoring(execute: @escaping @Sendable (String, Data) async throws -> Void) {
        syncHandler = execute
        guard monitorTask == nil else {
            Task { await flushRegistered() }
            return
        }
        monitorTask = Task { [weak self] in
            await self?.flushRegistered()
            var wasOffline = false
            while !Task.isCancelled {
                let connected = await NetworkMonitor.shared.isConnected
                if connected && wasOffline {
                    await self?.flush(execute: execute)
                    try? await self?.cleanup()
                }
                wasOffline = !connected
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        syncHandler = nil
    }

    func flushRegistered() async {
        while isProcessing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let syncHandler else { return }
        await flush(execute: syncHandler)
    }

    // MARK: - Flush (called on network restore)

    func flush(execute: @Sendable (String, Data) async throws -> Void) async {
        guard let dbQueue, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            // Filter out permanently-failed rows so one bad op (deleted
            // workspace reference, etc.) doesn't permanently block the
            // queue. Phase 6.6.
            let pending: [(Int64, String, String, Int)] = try await dbQueue.read { db in
                try Row.fetchAll(db,
                    sql: "SELECT id, operation_type, payload_json, failed_count FROM pending_operations WHERE synced_at IS NULL AND permanently_failed = 0 ORDER BY created_at ASC"
                ).map { row in
                    (row["id"] as Int64, row["operation_type"] as String, row["payload_json"] as String, row["failed_count"] as Int)
                }
            }

            for (id, opType, payloadJson, prevFailedCount) in pending {
                guard let payloadData = payloadJson.data(using: .utf8) else { continue }
                do {
                    try await execute(opType, payloadData)
                    // Mark as synced
                    try await dbQueue.write { db in
                        try db.execute(
                            sql: "UPDATE pending_operations SET synced_at = CURRENT_TIMESTAMP WHERE id = ?",
                            arguments: [id]
                        )
                    }
                    currentBackoff = 1.0 // Reset on success
                } catch {
                    if let queueError = error as? QueueError, case .replayDeferred = queueError {
                        TimedLogger.dataStore.info(
                            "Flush deferred for op \(id): \(error.localizedDescription, privacy: .public)"
                        )
                        break
                    }

                    let newFailedCount = prevFailedCount + 1
                    let permanentlyFailed = newFailedCount >= Self.maxFailures
                    TimedLogger.dataStore.warning(
                        "Flush failed for op \(id) (attempt \(newFailedCount)/\(Self.maxFailures))\(permanentlyFailed ? " — marking permanently_failed" : ""): \(error.localizedDescription, privacy: .public)"
                    )
                    // Increment failure counter; mark permanently_failed if at cap so
                    // subsequent flushes skip this row instead of retrying forever.
                    try? await dbQueue.write { db in
                        try db.execute(
                            sql: "UPDATE pending_operations SET failed_count = ?, permanently_failed = ? WHERE id = ?",
                            arguments: [newFailedCount, permanentlyFailed ? 1 : 0, id]
                        )
                    }
                    // Move on to the next item rather than blocking the
                    // whole queue on a single bad row.
                    try? await Task.sleep(for: .seconds(currentBackoff))
                    currentBackoff = min(currentBackoff * 2, maxBackoff)
                    continue
                }
            }
        } catch {
            TimedLogger.dataStore.error("Flush read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Cleanup (remove synced operations older than retention period)

    func cleanup() throws {
        guard let dbQueue else { return }
        // Age-based: remove synced operations older than retention period
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM pending_operations WHERE synced_at IS NOT NULL AND synced_at < datetime('now', ?)",
                arguments: ["-\(retentionDays) days"]
            )
        }
        // Size-based: if DB exceeds ~50MB, drop oldest synced rows until under limit
        let path = dbQueue.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64, size > maxSizeBytes {
            try dbQueue.write { db in
                try db.execute(
                    sql: """
                        DELETE FROM pending_operations WHERE id IN (
                            SELECT id FROM pending_operations
                            WHERE synced_at IS NOT NULL
                            ORDER BY created_at ASC
                            LIMIT 1000
                        )
                        """
                )
            }
        }
    }

    // MARK: - Stats

    func pendingCount() throws -> Int {
        guard let dbQueue else { return 0 }
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_operations WHERE synced_at IS NULL") ?? 0
        }
    }

    func diagnostics() throws -> Diagnostics {
        guard let dbQueue else {
            return Diagnostics(pendingCount: 0, activePendingCount: 0, permanentFailureCount: 0)
        }
        return try dbQueue.read { db in
            let pending = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pending_operations WHERE synced_at IS NULL"
            ) ?? 0
            let active = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pending_operations WHERE synced_at IS NULL AND permanently_failed = 0"
            ) ?? 0
            let permanent = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pending_operations WHERE synced_at IS NULL AND permanently_failed = 1"
            ) ?? 0
            return Diagnostics(
                pendingCount: pending,
                activePendingCount: active,
                permanentFailureCount: permanent
            )
        }
    }

    enum QueueError: Error, LocalizedError {
        case notInitialised
        case replayDeferred(String)

        var errorDescription: String? {
            switch self {
            case .notInitialised:
                "Offline queue is not initialised"
            case .replayDeferred(let reason):
                reason
            }
        }
    }
}
