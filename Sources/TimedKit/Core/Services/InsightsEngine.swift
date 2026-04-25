// InsightsEngine.swift — Timed Core
// Learning loop: compares estimated vs actual time by bucket.

import Foundation

enum InsightsEngine {
    static func accuracyByBucket(_ records: [CompletionRecord]) -> [TaskBucket: (avgEstimated: Double, avgActual: Double)] {
        var grouped: [TaskBucket: (estTotal: Double, actTotal: Double, count: Double)] = [:]
        for r in records {
            guard let actual = r.actualMinutes else { continue }
            var g = grouped[r.bucket, default: (0, 0, 0)]
            g.estTotal += Double(r.estimatedMinutes)
            g.actTotal += Double(actual)
            g.count += 1
            grouped[r.bucket] = g
        }
        return grouped.mapValues { ($0.estTotal / $0.count, $0.actTotal / $0.count) }
    }

    static func suggestedAdjustments(_ records: [CompletionRecord]) -> [(bucket: TaskBucket, message: String)] {
        accuracyByBucket(records).compactMap { bucket, avg in
            let diff = avg.avgActual - avg.avgEstimated
            guard abs(diff) > 3 else { return nil }
            let dir = diff > 0 ? "take" : "only take"
            return (bucket, "\(bucket.rawValue) tasks \(dir) \(Int(avg.avgActual))m on average (you estimate \(Int(avg.avgEstimated))m)")
        }
    }
}
