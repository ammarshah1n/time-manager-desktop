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
                .upsert(batch, onConflict: "idempotency_key")
                .execute()

            buffer.removeFirst(batch.count)
            TimedLogger.dataStore.info("Tier0Writer wrote \(batch.count) observation(s) to Supabase")

            // Fire real-time importance scoring (non-blocking).
            // Hand the full batch — not just IDs — so we can route scored alerts
            // back through AlertEngine → AlertsPresenter without a second fetch.
            Task {
                await self.requestRealtimeScoring(client: client, observations: batch)
            }
        } catch {
            TimedLogger.dataStore.error(
                "Tier0Writer failed Supabase write for \(batch.count) observation(s): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    /// Response shape from `score-observation-realtime` Edge Function. Mirrors
    /// `supabase/functions/score-observation-realtime/index.ts` lines 168-175.
    private struct ScoreObservationResponse: Decodable, Sendable {
        let scored: Int
        let alerts: Int
        let alert_details: [AlertDetail]
    }

    private struct AlertDetail: Decodable, Sendable {
        let observation_id: UUID
        let score: Double
        let level: String  // "immediate" | "preliminary" | "batch_gate"
    }

    /// Closes the Tier0Writer → AlertEngine → AlertsPresenter circuit.
    ///
    /// Until 2026-04-28 this fired the EF and discarded the response. Now it
    /// decodes `alert_details`, looks up the originating observation in the
    /// just-written batch (so AlertEngine sees real source + summary, not just
    /// an ID), runs the 5-dim multiplicative scoring, and surfaces any
    /// `.interrupt` decisions through `AlertsPresenter` so `AlertDeliveryView`
    /// can render them on the top-trailing overlay of `TimedRootView`.
    private func requestRealtimeScoring(client: SupabaseClient, observations: [Tier0Observation]) async {
        let observationIds = observations.map { $0.id.uuidString }
        do {
            let response: ScoreObservationResponse = try await client.functions.invoke(
                "score-observation-realtime",
                options: .init(body: ["observation_ids": observationIds])
            )
            TimedLogger.dataStore.info(
                "RT scoring complete: \(response.scored) scored, \(response.alerts) alerts"
            )

            for alert in response.alert_details {
                guard let obs = observations.first(where: { $0.id == alert.observation_id }) else {
                    TimedLogger.dataStore.warning(
                        "RT scoring returned alert for unknown observation \(alert.observation_id) — skipping"
                    )
                    continue
                }

                let decision = await AlertEngine.shared.evaluateRTScore(
                    observationId: alert.observation_id,
                    rtScore: alert.score,
                    source: obs.source.rawString,
                    summary: obs.summary
                )

                if case .interrupt(let scored) = decision {
                    await MainActor.run {
                        AlertsPresenter.shared.show(scored)
                    }
                    TimedLogger.dataStore.info(
                        "Alert surfaced: \(scored.candidate.title, privacy: .public) (composite=\(String(format: "%.3f", scored.compositeScore)))"
                    )
                } else if case .holdForBriefing = decision {
                    // Held alerts roll up into the morning briefing context.
                    // No UI action at the moment of scoring.
                }
            }
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
