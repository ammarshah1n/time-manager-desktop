// MicActivityBar.swift — Timed macOS
//
// Visual indicator that the orb is hearing you. Three bars that
// fluctuate while the user is speaking (agent is NOT speaking AND
// the conversation phase is active). Synthetic — driven by a mix of
// sinusoids — because ElevenLabs owns the mic and exposing the raw
// level from the SDK varies across versions. Good-enough visual
// presence beats a brittle SDK reach-through.

import SwiftUI

struct MicActivityBar: View {
    let isListening: Bool

    @State private var t: Double = 0
    private let barCount = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isListening)) { ctx in
            let time = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { i in
                    let level = synthLevel(time: time, index: i)
                    Capsule()
                        .fill(BrandColor.primary.opacity(isListening ? 0.85 : 0.25))
                        .frame(width: 3, height: 6 + CGFloat(level) * 22)
                        .animation(.easeOut(duration: 0.08), value: level)
                }
            }
            .frame(height: 30, alignment: .center)
            .opacity(isListening ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.25), value: isListening)
        }
        .accessibilityHidden(true)
    }

    /// Pseudo-audio envelope: different phase + frequency per bar, clamped 0..1.
    /// Looks like speech amplitude without touching the hardware mic.
    private func synthLevel(time: Double, index: Int) -> Double {
        let phase = Double(index) * 0.9
        let fast  = sin(time * 6.5 + phase) * 0.5 + 0.5
        let slow  = sin(time * 1.8 + phase * 1.7) * 0.5 + 0.5
        let noise = sin(time * 17 + phase * 3.1) * 0.2 + 0.8
        let v = (fast * 0.55 + slow * 0.35) * noise
        return max(0, min(1, v))
    }
}
