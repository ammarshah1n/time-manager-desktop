import Foundation

/// Phase 8.03: Detects whether the current moment is an appropriate interrupt window.
/// Open: app switch, post-meeting gap, idle >60s, between deep work blocks.
/// Closed: sustained focus >15 min, in meeting, back-to-back, recent interrupt <60 min.
struct InterruptWindowDetector: Sendable {

    enum WindowState: Sendable {
        case open(reason: String)
        case closed(reason: String)
    }

    struct ContextSnapshot: Sendable {
        let lastAppSwitchAgo: TimeInterval       // seconds since last app switch
        let currentFocusDuration: TimeInterval    // seconds of sustained focus
        let idleDuration: TimeInterval            // seconds idle
        let isInMeeting: Bool                     // calendar event active
        let meetingEndedAgo: TimeInterval?         // seconds since last meeting ended
        let nextMeetingIn: TimeInterval?           // seconds until next meeting
        let lastAlertAgo: TimeInterval?            // seconds since last alert delivery
        let cognitiveLoadIndex: Double?            // 0.0-1.0 from CCLI
    }

    /// Evaluate whether now is a good time to interrupt
    func evaluate(context: ContextSnapshot) -> WindowState {
        // CLOSED conditions (check first — these block alerts)

        // In a meeting
        if context.isInMeeting {
            return .closed(reason: "Currently in meeting")
        }

        // Sustained focus > 15 minutes
        if context.currentFocusDuration > 900 {
            return .closed(reason: "Sustained focus for \(Int(context.currentFocusDuration / 60)) minutes")
        }

        // Recent interrupt < 60 minutes
        if let lastAlert = context.lastAlertAgo, lastAlert < 3600 {
            return .closed(reason: "Last alert was \(Int(lastAlert / 60)) minutes ago")
        }

        // Back-to-back meetings (next meeting in < 5 minutes)
        if let nextMeeting = context.nextMeetingIn, nextMeeting < 300 {
            return .closed(reason: "Next meeting in \(Int(nextMeeting / 60)) minutes")
        }

        // High cognitive load
        if let cli = context.cognitiveLoadIndex, cli > 0.8 {
            return .closed(reason: "High cognitive load detected")
        }

        // OPEN conditions

        // Post-meeting gap (2-3 minutes after meeting ended)
        if let meetingEnded = context.meetingEndedAgo, meetingEnded > 120, meetingEnded < 300 {
            return .open(reason: "Post-meeting transition window")
        }

        // Idle > 60 seconds
        if context.idleDuration > 60 {
            return .open(reason: "System idle for \(Int(context.idleDuration)) seconds")
        }

        // Recent app switch (within last 30 seconds)
        if context.lastAppSwitchAgo < 30 {
            return .open(reason: "App switch — natural break point")
        }

        // Between deep work blocks (low focus duration + no meeting)
        if context.currentFocusDuration < 300, !context.isInMeeting {
            return .open(reason: "Between focus blocks")
        }

        // Default: cautiously closed
        return .closed(reason: "No clear interrupt window")
    }

    /// Compute cognitive state permit (0.0-1.0) for alert scoring
    func cognitiveStatePermit(context: ContextSnapshot) -> Double {
        let window = evaluate(context: context)
        switch window {
        case .closed:
            return 0.0
        case .open:
            // Scale permit by inverse cognitive load
            if let cli = context.cognitiveLoadIndex {
                return max(0.1, 1.0 - cli)
            }
            return 0.8 // Default open permit
        }
    }
}
