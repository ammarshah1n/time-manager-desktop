import Dependencies
import Foundation
import Supabase

actor Tier0Writer: SignalIngestionPort {
    static let shared = Tier0Writer()

    @Dependency(\.supabaseClient) private var supabaseClient

    private let batchSize = 50
    private let flushInterval: Duration = .seconds(300)
    private let tableName = "tier0_observations"
    private let offlineOperationType = "tier0_observations.insert"

    private var buffer: [Tier0Observation] = []
    private var scheduledFlush: Task<Void, Never>?
    private var isFlushing = false

    private init() {}

    func recordObservation(_ observation: Tier0Observation) async throws {
        ensureScheduledFlush()
        buffer.append(observation)

        if buffer.count >= batchSize {
            try await flush()
        }
    }

    func recordObservations(_ observations: [Tier0Observation]) async throws {
        guard !observations.isEmpty else { return }
        ensureScheduledFlush()
        buffer.append(contentsOf: observations)

        if buffer.count >= batchSize {
            try await flush()
        }
    }

    func flush() async throws {
        guard !buffer.isEmpty, !isFlushing else { return }

        isFlushing = true
        defer { isFlushing = false }

        while !buffer.isEmpty {
            let isConnected = await MainActor.run { NetworkMonitor.shared.isConnected }

            if isConnected, let client = supabaseClient.rawClient {
                try await insertOnline(using: client)
            } else {
                try await enqueueOffline()
            }
        }
    }

    private func ensureScheduledFlush() {
        guard scheduledFlush == nil else { return }
        scheduledFlush = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self else { break }
                do {
                    try await self.flush()
                } catch {
                    TimedLogger.dataStore.error(
                        "Tier0Writer scheduled flush failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    private func insertOnline(using client: SupabaseClient) async throws {
        let batch = Array(buffer.prefix(batchSize))

        do {
            try await client
                .from(tableName)
                .insert(batch)
                .execute()

            buffer.removeFirst(batch.count)
            TimedLogger.dataStore.info("Tier0Writer wrote \(batch.count) observation(s) to Supabase")

            // Fire real-time importance scoring (non-blocking)
            let ids = batch.map { $0.id.uuidString }
            Task {
                await self.requestRealtimeScoring(client: client, observationIds: ids)
            }
        } catch {
            TimedLogger.dataStore.error(
                "Tier0Writer failed Supabase write for \(batch.count) observation(s): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func requestRealtimeScoring(client: SupabaseClient, observationIds: [String]) async {
        do {
            try await client.functions.invoke("score-observation-realtime", options: .init(
                body: ["observation_ids": observationIds]
            ))
            TimedLogger.dataStore.info("RT scoring requested for \(observationIds.count) observation(s)")
        } catch {
            // RT scoring failure is non-fatal — batch scoring catches up nightly
            TimedLogger.dataStore.warning(
                "RT scoring request failed (non-fatal): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func enqueueOffline() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let queueCount = min(batchSize, buffer.count)
        var queuedCount = 0

        do {
            while queuedCount < queueCount {
                let observation = buffer[queuedCount]
                let payload = try encoder.encode(observation)
                try await OfflineSyncQueue.shared.enqueue(
                    operationType: offlineOperationType,
                    payload: payload
                )
                queuedCount += 1
            }

            buffer.removeFirst(queuedCount)
            TimedLogger.dataStore.info("Tier0Writer queued \(queuedCount) observation(s) for offline sync")
        } catch {
            if queuedCount > 0 {
                buffer.removeFirst(queuedCount)
            }

            TimedLogger.dataStore.error(
                "Tier0Writer failed offline enqueue after \(queuedCount) observation(s): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }
}
