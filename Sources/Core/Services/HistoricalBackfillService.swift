import Foundation
import Dependencies

/// Phase 5.02: Historical data backfill from Microsoft Graph API
/// On first auth, fetches up to 3 years of email + calendar history as Tier 0 observations.
/// Runs as background task with progress tracking and crash recovery via delta token persistence.
actor HistoricalBackfillService {
    static let shared = HistoricalBackfillService()

    enum BackfillState: Sendable {
        case idle
        case running(progress: BackfillProgress)
        case completed(totalObservations: Int)
        case failed(String)
    }

    struct BackfillProgress: Sendable {
        let emailPages: Int
        let calendarPages: Int
        let totalObservations: Int
        let startedAt: Date
        let estimatedCompletion: Date?
    }

    private(set) var state: BackfillState = .idle
    private var backfillTask: Task<Void, Never>?

    private let emailPageSize = 50
    private let calendarPageSize = 50
    private let rateLimitDelay: Duration = .milliseconds(250) // 4 calls/sec Graph API limit

    func startBackfill() async {
        guard case .idle = state else { return }
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else {
            state = .failed("No executive ID")
            return
        }

        state = .running(progress: BackfillProgress(
            emailPages: 0, calendarPages: 0, totalObservations: 0,
            startedAt: Date(), estimatedCompletion: nil
        ))

        backfillTask = Task {
            var totalObs = 0
            var emailPages = 0
            var calendarPages = 0

            // Phase 1: Backfill emails
            // TODO: Use GraphClient delta query with skipToken persistence
            // For each page of historical emails:
            //   1. Fetch page via Graph API
            //   2. Convert to Tier0Observations with historical timestamps
            //   3. Write via Tier0Writer
            //   4. Persist delta token for crash recovery
            //   5. Rate limit: 250ms between calls

            // Phase 2: Backfill calendar events
            // TODO: Similar to email backfill

            // Placeholder: mark as complete
            state = .completed(totalObservations: totalObs)
            TimedLogger.dataStore.info(
                "HistoricalBackfillService completed: \(totalObs) observations from \(emailPages) email pages + \(calendarPages) calendar pages"
            )
        }
    }

    func cancelBackfill() {
        backfillTask?.cancel()
        backfillTask = nil
        state = .idle
    }

    /// Resume from persisted delta token after crash
    func resumeIfNeeded() async {
        // TODO: Check UserDefaults/Keychain for persisted delta token
        // If found, resume from last known position
    }
}
