import Dependencies
import Foundation
import Supabase

protocol MemoryStoreProtocol: Sendable {
    func writeObservation(_ observation: Tier0Observation) async throws
    func retrieve(query: String, intent: RetrievalIntent, tier: Int?, limit: Int) async throws -> [RetrievalResult]
    func activeContextBuffer(variant: ACBVariant) async throws -> Data
}

enum RetrievalIntent: String, Sendable {
    case what
    case when
    case why
    case pattern
    case change
}

enum ACBVariant: String, Sendable {
    case full
    case light
}

struct RetrievalResult: Sendable {
    let id: UUID
    let tier: Int
    let content: String
    let compositeScore: Double
    let scores: RetrievalScores
}

struct RetrievalScores: Sendable {
    let recency: Double
    let importance: Double
    let relevance: Double
    let temporalProximity: Double
    let tierBoost: Double
}

actor MemoryStoreActor: MemoryStoreProtocol {
    static let shared = MemoryStoreActor()

    @Dependency(\.supabaseClient) private var supabaseClient
    private let vectorStore = LocalVectorStore.shared
    private let embeddingService = EmbeddingService.shared
    private let retrievalEngine = RetrievalEngine()

    func writeObservation(_ observation: Tier0Observation) async throws {
        try await Tier0Writer.shared.recordObservation(observation)
    }

    // NOTE: MVP retrieval queries Tier 0 only via pgvector. Tiers 1-3 use 3072-dim vectors
    // which exceed pgvector's HNSW/IVFFlat cap — full multi-tier retrieval requires dimension
    // reduction or a different vector store.
    func retrieve(query: String, intent: RetrievalIntent, tier: Int?, limit: Int) async throws -> [RetrievalResult] {
        guard let client = supabaseClient.rawClient else {
            throw MemoryStoreError.supabaseUnavailable
        }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else {
            throw MemoryStoreError.noExecutive
        }

        let searchTier = tier ?? 0
        let embedding = try await embeddingService.embed(text: query, tier: searchTier)

        let params = MatchTier0Params(
            query_embedding: embedding,
            match_profile_id: executiveId.uuidString,
            match_count: limit * 3
        )
        let rows: [MemoryRow] = try await client
            .rpc("match_tier0_observations", params: params)
            .execute()
            .value

        let formatter = ISO8601DateFormatter()
        let candidates = rows.compactMap { row -> (id: UUID, tier: Int, content: String, occurredAt: Date, importanceScore: Double, cosineSimilarity: Double)? in
            guard let date = formatter.date(from: row.occurredAt) else { return nil }
            return (id: row.id, tier: searchTier, content: row.summary ?? "",
                    occurredAt: date, importanceScore: row.importanceScore,
                    cosineSimilarity: row.similarity)
        }

        return Array(retrievalEngine.score(candidates: candidates, intent: intent).prefix(limit))
    }

    func activeContextBuffer(variant: ACBVariant) async throws -> Data {
        guard let client = supabaseClient.rawClient else {
            throw MemoryStoreError.supabaseUnavailable
        }

        let rpcName = variant == .full ? "get_acb_full" : "get_acb_light"
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else {
            throw MemoryStoreError.noExecutive
        }

        let response: Data = try await client
            .rpc(rpcName, params: ["exec_id": executiveId.uuidString])
            .execute()
            .data
        return response
    }
}

private struct MatchTier0Params: Encodable, Sendable {
    let query_embedding: [Float]
    let match_profile_id: String
    let match_count: Int
}

private struct MemoryRow: Decodable, Sendable {
    let id: UUID
    let summary: String?
    let source: String
    let eventType: String
    let occurredAt: String
    let importanceScore: Double
    let similarity: Double

    enum CodingKeys: String, CodingKey {
        case id, summary, source, similarity
        case eventType = "event_type"
        case occurredAt = "occurred_at"
        case importanceScore = "importance_score"
    }
}

private enum MemoryStoreError: LocalizedError {
    case supabaseUnavailable
    case noExecutive

    var errorDescription: String? {
        switch self {
        case .supabaseUnavailable:
            return "Supabase client is unavailable"
        case .noExecutive:
            return "No executive ID available"
        }
    }
}
