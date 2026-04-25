// FocusSessionRecord.swift — Timed Core
// Persisted record of a focus session for history, ML feedback, and Pomodoro tracking.

import Foundation

struct FocusSessionRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let taskId: UUID?
    let startedAt: Date
    var pausedAt: Date?
    var endedAt: Date?
    var totalSeconds: Int
    var wasCompleted: Bool
    var pomodoroIndex: Int
}
