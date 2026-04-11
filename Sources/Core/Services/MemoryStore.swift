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

    func retrieve(query: String, intent: RetrievalIntent, tier: Int?, limit: Int) async throws -> [RetrievalResult] {
        let searchTier = tier ?? 0
        let embedding = try await embeddingService.embed(text: query, tier: searchTier)
        let candidates = try await vectorStore.search(vector: embedding, tier: searchTier, count: limit * 3)
        _ = retrievalEngine

        return candidates.prefix(limit).map { candidate in
            RetrievalResult(
                id: UUID(),
                tier: searchTier,
                content: "",
                compositeScore: Double(1.0 - candidate.distance),
                scores: RetrievalScores(
                    recency: 0.5,
                    importance: 0.5,
                    relevance: Double(1.0 - candidate.distance),
                    temporalProximity: 0.5,
                    tierBoost: searchTier == 0 ? 1.0 : Double(searchTier) * 1.5
                )
            )
        }
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
