import Foundation
import ComposableArchitecture
import OSLog

/// Wraps the estimate-time Edge Function. Best-effort — never blocks task creation.
actor EstimationService {
    static let shared = EstimationService()

    private let logger = Logger(subsystem: "com.timed.kit", category: "EstimationService")

    /// Estimates time for a task asynchronously and writes back to Supabase.
    /// - The Edge Function itself updates tasks.estimated_minutes_ai/source/basis.
    /// - Caller does NOT need to await this. Errors are logged, never thrown.
    func estimate(task: TimedTask) async {
        let authContext = await MainActor.run {
            (workspaceId: AuthService.shared.workspaceId, profileId: AuthService.shared.profileId)
        }
        guard let wsId = authContext.workspaceId,
              let profileId = authContext.profileId
        else {
            logger.debug("Skipping estimate: no auth context.")
            return
        }
        @Dependency(\.supabaseClient) var supa

        let req = EstimateTimeRequest(
            taskId: task.id,
            workspaceId: wsId,
            profileId: profileId,
            title: task.title,
            bucketType: task.bucket.dbValue,
            description: task.notes,
            fromAddress: task.sender.isEmpty || task.sender == "Manual" ? nil : task.sender
        )

        do {
            let resp = try await supa.estimateTime(req)
            logger.info("Estimated task \(task.id) → \(resp.estimatedMinutes ?? -1)m (source=\(resp.source ?? "unknown"), basis=\(resp.basis ?? "none"))")
        } catch {
            logger.error("Estimate failed for task \(task.id): \(error.localizedDescription)")
        }
    }
}
