import Foundation

/// Phase 11.01: Consent state machine for progressive observation permissions.
/// DORMANT → CALENDAR_ONLY → CAL_EMAIL → CAL_EMAIL_APPS → FULL_OBSERVATION
/// PARTIAL_REVOKE, PAUSED, DELETED as terminal/pause states.
struct ConsentStateMachine: Sendable {

    enum ConsentState: String, Sendable, Codable {
        case dormant          // No permissions granted
        case calendarOnly     // Calendar read only
        case calEmail         // Calendar + Email
        case calEmailApps     // Calendar + Email + App usage
        case fullObservation  // All signals including keystroke + voice

        case partialRevoke    // Specific streams revoked
        case paused           // All observation stopped, model frozen, data encrypted
        case deleted          // KEK destroyed, terminal state
    }

    struct ConsentSnapshot: Sendable {
        let currentState: ConsentState
        let daysInCurrentState: Int
        let morningOpenRate: Double
        let insightsInteracted: Int
        let daysSinceLastRevocation: Int?
        let revokedStreams: Set<String>
    }

    struct TransitionResult: Sendable {
        let allowed: Bool
        let reason: String
        let newState: ConsentState?
    }

    // MARK: - Transition Gates

    /// Check if a transition to the next state is allowed
    func canTransition(from snapshot: ConsentSnapshot, to target: ConsentState) -> TransitionResult {
        // Terminal states
        if snapshot.currentState == .deleted {
            return TransitionResult(allowed: false, reason: "Account deleted — permanent state", newState: nil)
        }

        // Paused can resume to previous state or delete
        if snapshot.currentState == .paused {
            if target == .deleted {
                return TransitionResult(allowed: true, reason: "Deletion from paused state", newState: .deleted)
            }
            // Resume requires 7+ days paused
            if snapshot.daysInCurrentState >= 7 {
                return TransitionResult(allowed: true, reason: "Resume after 7+ day pause", newState: target)
            }
            return TransitionResult(allowed: false, reason: "Must wait 7 days before resuming (day \(snapshot.daysInCurrentState)/7)", newState: nil)
        }

        // Any state can pause or delete
        if target == .paused {
            return TransitionResult(allowed: true, reason: "Pause is always available", newState: .paused)
        }
        if target == .deleted {
            return TransitionResult(allowed: true, reason: "Deletion is always available", newState: .deleted)
        }

        // Progressive escalation gates
        switch (snapshot.currentState, target) {
        case (.dormant, .calendarOnly):
            return TransitionResult(allowed: true, reason: "Initial calendar permission", newState: .calendarOnly)

        case (.calendarOnly, .calEmail):
            return checkGate(snapshot: snapshot, minDays: 7, minOpenRate: 0.6, minInteractions: 1)

        case (.calEmail, .calEmailApps):
            return checkGate(snapshot: snapshot, minDays: 7, minOpenRate: 0.6, minInteractions: 1)

        case (.calEmailApps, .fullObservation):
            return checkGate(snapshot: snapshot, minDays: 7, minOpenRate: 0.6, minInteractions: 1)

        case (.partialRevoke, _):
            // Can re-grant from partial revoke after 14 days since revocation
            if let daysSinceRevoke = snapshot.daysSinceLastRevocation, daysSinceRevoke >= 14 {
                return TransitionResult(allowed: true, reason: "Re-grant after 14-day cooling period", newState: target)
            }
            return TransitionResult(allowed: false, reason: "Must wait 14 days after revocation before re-granting", newState: nil)

        default:
            // Downgrade is always allowed
            if isDowngrade(from: snapshot.currentState, to: target) {
                return TransitionResult(allowed: true, reason: "Downgrade permitted", newState: target)
            }
            return TransitionResult(allowed: false, reason: "Invalid transition: \(snapshot.currentState.rawValue) → \(target.rawValue)", newState: nil)
        }
    }

    // MARK: - Helpers

    private func checkGate(snapshot: ConsentSnapshot, minDays: Int, minOpenRate: Double, minInteractions: Int) -> TransitionResult {
        if snapshot.daysInCurrentState < minDays {
            return TransitionResult(allowed: false, reason: "Need \(minDays)+ days in current state (day \(snapshot.daysInCurrentState))", newState: nil)
        }
        if snapshot.morningOpenRate < minOpenRate {
            return TransitionResult(
                allowed: false,
                reason: "Morning open rate \(Int(snapshot.morningOpenRate * 100))% below \(Int(minOpenRate * 100))% threshold",
                newState: nil
            )
        }
        if snapshot.insightsInteracted < minInteractions {
            return TransitionResult(allowed: false, reason: "Need \(minInteractions)+ insight interactions", newState: nil)
        }

        // Also check no recent revocation
        if let daysSinceRevoke = snapshot.daysSinceLastRevocation, daysSinceRevoke < 14 {
            return TransitionResult(allowed: false, reason: "Recent revocation — wait \(14 - daysSinceRevoke) more days", newState: nil)
        }

        return TransitionResult(allowed: true, reason: "All gates passed", newState: nil)
    }

    private func isDowngrade(from: ConsentState, to: ConsentState) -> Bool {
        let order: [ConsentState] = [.dormant, .calendarOnly, .calEmail, .calEmailApps, .fullObservation]
        guard let fromIdx = order.firstIndex(of: from), let toIdx = order.firstIndex(of: to) else { return false }
        return toIdx < fromIdx
    }

    /// Get the set of active observation streams for a consent state
    func activeStreams(for state: ConsentState) -> Set<String> {
        switch state {
        case .dormant, .paused, .deleted:
            return []
        case .calendarOnly:
            return ["calendar"]
        case .calEmail:
            return ["calendar", "email"]
        case .calEmailApps:
            return ["calendar", "email", "app_usage", "system"]
        case .fullObservation:
            return ["calendar", "email", "app_usage", "system", "keystroke", "voice", "healthkit"]
        case .partialRevoke:
            return [] // Managed externally via revokedStreams
        }
    }
}
