// BucketEstimate.swift — Timed Core
// EMA-updated posterior estimate of actual time per bucket type.

import Foundation

struct BucketEstimate: Codable, Sendable {
    var meanMinutes: Double
    var sampleCount: Int
    var lastUpdatedAt: Date
}
