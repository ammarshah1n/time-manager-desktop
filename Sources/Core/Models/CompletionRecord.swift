// CompletionRecord.swift — Timed Core
// Tracks actual time spent vs estimated for learning loop.

import Foundation

struct CompletionRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let taskId: UUID
    let bucket: TaskBucket
    let estimatedMinutes: Int
    var actualMinutes: Int?
    let completedAt: Date
    let wasDeferred: Bool
    let deferredCount: Int
}
