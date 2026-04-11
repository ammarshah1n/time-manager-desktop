import Foundation
import USearch

actor LocalVectorStore {
    static let shared = LocalVectorStore()

    private var indexes: [Int: USearchIndex] = [:]

    init() {
        for tier in 0...3 {
            let dimensions: UInt32 = tier == 0 ? 1024 : 3072
            if let index = try? USearchIndex.make(
                metric: .cos,
                dimensions: dimensions,
                connectivity: 16,
                quantization: .f32
            ) {
                indexes[tier] = index
            }
        }
    }

    func add(key: USearchKey, vector: [Float32], tier: Int) throws {
        let index = try index(for: tier)
        try index.add(key: key, vector: vector)
    }

    func search(vector: [Float32], tier: Int, count: Int) throws -> [(key: USearchKey, distance: Float)] {
        guard count > 0 else { return [] }
        let index = try index(for: tier)
        let (keys, distances) = try index.search(vector: vector, count: count)
        return zip(keys, distances).map { (key: $0, distance: $1) }
    }

    @discardableResult
    func remove(key: USearchKey, tier: Int) throws -> UInt32 {
        let index = try index(for: tier)
        return try index.remove(key: key)
    }

    func count(tier: Int) -> Int {
        guard let index = indexes[tier] else { return 0 }
        return (try? index.count) ?? 0
    }

    func reserve(capacity: Int, tier: Int) throws {
        let index = try index(for: tier)
        try index.reserve(UInt32(capacity))
    }

    private func index(for tier: Int) throws -> USearchIndex {
        guard let index = indexes[tier] else {
            throw LocalVectorStoreError.invalidTier(tier)
        }
        return index
    }
}

enum LocalVectorStoreError: LocalizedError {
    case invalidTier(Int)

    var errorDescription: String? {
        switch self {
        case .invalidTier(let tier):
            return "Invalid vector store tier: \(tier)"
        }
    }
}
