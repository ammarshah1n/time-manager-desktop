import Foundation
import Dependencies
import Supabase

actor EmbeddingService {
    static let shared = EmbeddingService()

    @Dependency(\.supabaseClient) private var supabaseClient

    private let maxBatchSize = 10
    private let cacheLimit = 500
    private var cache: [String: [Float]] = [:]
    private var cacheOrder: [String] = []

    init() {}

    func embed(texts: [String], tier: Int) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        guard (0...3).contains(tier) else {
            throw EmbeddingServiceError.invalidTier(tier)
        }

        var results = Array(repeating: [Float](), count: texts.count)
        var uncached: [(index: Int, key: String, text: String)] = []

        for (index, text) in texts.enumerated() {
            let key = cacheKey(for: text, tier: tier)
            if let cachedEmbedding = cache[key] {
                touchCacheKey(key)
                results[index] = cachedEmbedding
            } else {
                uncached.append((index, key, text))
            }
        }

        guard !uncached.isEmpty else {
            TimedLogger.dataStore.info("EmbeddingService cache hit for \(texts.count) text(s) at tier \(tier)")
            return results
        }

        for start in stride(from: 0, to: uncached.count, by: maxBatchSize) {
            let end = min(start + maxBatchSize, uncached.count)
            let batch = Array(uncached[start..<end])
            let embeddings = try await fetchBatch(texts: batch.map { $0.text }, tier: tier)

            guard embeddings.count == batch.count else {
                throw EmbeddingServiceError.invalidResponse(
                    "Expected \(batch.count) embedding(s), received \(embeddings.count)"
                )
            }

            for (entry, embedding) in zip(batch, embeddings) {
                results[entry.index] = embedding
                insertIntoCache(embedding, forKey: entry.key)
            }
        }

        let uncachedCount = uncached.count
        let batchCount = chunkCount(for: uncachedCount)
        TimedLogger.dataStore.info(
            "EmbeddingService fetched \(uncachedCount) uncached text(s) across \(batchCount) batch(es) at tier \(tier)"
        )
        return results
    }

    func embed(text: String, tier: Int) async throws -> [Float] {
        let embeddings = try await embed(texts: [text], tier: tier)
        guard let embedding = embeddings.first else {
            throw EmbeddingServiceError.invalidResponse("No embedding returned for single text request")
        }
        return embedding
    }

    private func fetchBatch(texts: [String], tier: Int) async throws -> [[Float]] {
        guard texts.count <= maxBatchSize else {
            throw EmbeddingServiceError.batchTooLarge(texts.count)
        }

        guard let client = supabaseClient.rawClient else {
            throw EmbeddingServiceError.supabaseUnavailable
        }

        let request = EmbeddingRequest(texts: texts, tier: tier)
        let response: EmbeddingResponse

        do {
            response = try await client.functions.invoke(
                "generate-embedding",
                options: FunctionInvokeOptions(method: .post, body: request)
            )
        } catch {
            TimedLogger.dataStore.error(
                "EmbeddingService Edge Function invoke failed: \(error.localizedDescription)"
            )
            throw error
        }

        let expectedDimension = expectedDimension(for: tier)
        guard response.dimension == expectedDimension else {
            throw EmbeddingServiceError.invalidResponse(
                "Expected dimension \(expectedDimension), received \(response.dimension)"
            )
        }

        let embeddings = response.embeddings.map { $0.map(Float.init) }
        guard embeddings.allSatisfy({ $0.count == response.dimension }) else {
            throw EmbeddingServiceError.invalidResponse("Embedding payload contained mismatched dimensions")
        }

        TimedLogger.dataStore.info(
            "EmbeddingService received \(embeddings.count) embedding(s) from \(response.model) with dimension \(response.dimension)"
        )
        return embeddings
    }

    private func cacheKey(for text: String, tier: Int) -> String {
        var hasher = Hasher()
        hasher.combine(tier)
        hasher.combine(text)
        return "\(tier):\(hasher.finalize())"
    }

    private func insertIntoCache(_ embedding: [Float], forKey key: String) {
        cache[key] = embedding
        touchCacheKey(key)

        while cacheOrder.count > cacheLimit {
            let leastRecentKey = cacheOrder.removeFirst()
            cache.removeValue(forKey: leastRecentKey)
        }
    }

    private func touchCacheKey(_ key: String) {
        if let existingIndex = cacheOrder.firstIndex(of: key) {
            cacheOrder.remove(at: existingIndex)
        }
        cacheOrder.append(key)
    }

    private func expectedDimension(for tier: Int) -> Int {
        tier == 0 ? 1024 : 3072
    }

    private func chunkCount(for count: Int) -> Int {
        (count + maxBatchSize - 1) / maxBatchSize
    }
}

private struct EmbeddingRequest: Encodable {
    let texts: [String]
    let tier: Int
}

private struct EmbeddingResponse: Decodable {
    let embeddings: [[Double]]
    let dimension: Int
    let model: String
}

private enum EmbeddingServiceError: LocalizedError {
    case invalidTier(Int)
    case batchTooLarge(Int)
    case invalidResponse(String)
    case supabaseUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidTier(let tier):
            return "Invalid embedding tier: \(tier)"
        case .batchTooLarge(let count):
            return "Embedding batch exceeds limit: \(count)"
        case .invalidResponse(let detail):
            return "Invalid embedding response: \(detail)"
        case .supabaseUnavailable:
            return "Supabase client is unavailable"
        }
    }
}
