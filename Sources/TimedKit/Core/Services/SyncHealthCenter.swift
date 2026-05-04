import Foundation
import Combine

@MainActor
final class SyncHealthCenter: ObservableObject {
    static let shared = SyncHealthCenter()

    struct Issue: Identifiable, Equatable, Sendable {
        let id = UUID()
        let operationType: String
        let message: String
        let occurredAt: Date
    }

    @Published private(set) var lastIssue: Issue?
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var activePendingCount: Int = 0
    @Published private(set) var permanentFailureCount: Int = 0

    private init() {}

    var hasIssue: Bool {
        lastIssue != nil || permanentFailureCount > 0
    }

    func recordFailure(operationType: String, message: String) {
        lastIssue = Issue(operationType: operationType, message: message, occurredAt: Date())
    }

    func recordSuccess(operationType: String) {
        if lastIssue?.operationType == operationType {
            lastIssue = nil
        }
    }

    func update(diagnostics: OfflineSyncQueue.Diagnostics) {
        pendingCount = diagnostics.pendingCount
        activePendingCount = diagnostics.activePendingCount
        permanentFailureCount = diagnostics.permanentFailureCount
        if diagnostics.permanentFailureCount == 0, pendingCount == 0 {
            lastIssue = nil
        }
    }
}
