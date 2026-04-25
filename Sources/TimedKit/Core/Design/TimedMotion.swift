// TimedMotion.swift — Timed macOS
// Centralised animation curves. Every animation in the app should reference these.

import SwiftUI

enum TimedMotion {
    /// 90-140ms — checkboxes, toggles, icon swaps
    static let micro = Animation.easeOut(duration: 0.12)

    /// 180-240ms — row transitions, content crossfades
    static let smooth = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)

    /// 240-420ms — sheet presentations, large layout shifts
    static let springy = Animation.spring(response: 0.34, dampingFraction: 0.82)
}
