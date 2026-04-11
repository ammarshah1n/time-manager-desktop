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
            let folder = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Timed", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dbPath = folder.appendingPathComponent("offline_queue.sqlite").path
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
        }
    }

    // MARK: - Enqueue

    func enqueue(operationType: String, payload: Data) throws {
        guard let dbQueue else { throw QueueError.notInitialised }
        let payloadString = String(data: payload, encoding: .utf8) ?? "{}"
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO pending_operations (operation_type, payload_json) VALUES (?, ?)",
                arguments: [operationType, payloadString]
            )
        }
        TimedLogger.dataStore.debug("Enqueued \(operationType, privacy: .public)")
    }

    // MARK: - Network Monitor Integration

    func startMonitoring(execute: @escaping @Sendable (String, Data) async throws -> Void) {
        syncHandler = execute
        monitorTask = Task { [weak self] in
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

    // MARK: - Flush (called on network restore)

    func flush(execute: @Sendable (String, Data) async throws -> Void) async {
        guard let dbQueue, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            let pending: [(Int64, String, String)] = try await dbQueue.read { db in
                try Row.fetchAll(db,
                    sql: "SELECT id, operation_type, payload_json FROM pending_operations WHERE synced_at IS NULL ORDER BY created_at ASC"
                ).map { row in
                    (row["id"] as Int64, row["operation_type"] as String, row["payload_json"] as String)
                }
            }

            for (id, opType, payloadJson) in pending {
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
                    TimedLogger.dataStore.warning("Flush failed for op \(id): \(error.localizedDescription, privacy: .public)")
                    // Exponential backoff
                    try? await Task.sleep(for: .seconds(currentBackoff))
                    currentBackoff = min(currentBackoff * 2, maxBackoff)
                    break // Stop processing on failure — retry later
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

    enum QueueError: Error {
        case notInitialised
    }
}
