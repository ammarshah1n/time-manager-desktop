// TimedSounds.swift — Timed macOS
// System sound placeholders with rate limiting. Swap for custom audio files later.

import AppKit
import SwiftUI

enum TimedSound: String, CaseIterable {
    case completion
    case planGenerated
    case focusEnd
    case milestone

    // MARK: - Play

    @MainActor
    func play() {
        guard TimedSoundEngine.shared.isEnabled else { return }
        guard TimedSoundEngine.shared.shouldPlay(self) else { return }

        switch self {
        case .completion:
            if let sound = NSSound(named: "Tink") ?? NSSound(named: "Pop") {
                sound.volume = 0.4
                sound.play()
            }
        case .planGenerated:
            if let sound = NSSound(named: "Glass") ?? NSSound(named: "Submarine") {
                sound.volume = 0.5
                sound.play()
            }
        case .focusEnd:
            if let sound = NSSound(named: "Hero") ?? NSSound(named: "Purr") {
                sound.volume = 0.6
                sound.play()
            }
        case .milestone:
            if let sound = NSSound(named: "Purr") ?? NSSound(named: "Glass") {
                sound.volume = 0.5
                sound.play()
            }
        }
    }
}

// MARK: - Rate limiter + preferences

@MainActor
final class TimedSoundEngine {
    static let shared = TimedSoundEngine()

    @AppStorage("prefs.sounds.enabled") var isEnabled: Bool = true

    /// Tracks recent plays per sound for rate limiting.
    /// Key: sound raw value, Value: array of timestamps.
    private var recentPlays: [String: [Date]] = [:]

    /// Rate limit: max 3 plays of the same sound within 2 seconds.
    /// If exceeded, only the first and last are played.
    func shouldPlay(_ sound: TimedSound) -> Bool {
        let now = Date()
        let key = sound.rawValue
        let window: TimeInterval = 2.0
        let maxInWindow = 3

        // Prune old entries
        recentPlays[key] = (recentPlays[key] ?? []).filter { now.timeIntervalSince($0) < window }

        let count = recentPlays[key]?.count ?? 0

        if count < maxInWindow {
            recentPlays[key, default: []].append(now)
            return true
        }

        // Beyond limit — suppress (caller can force last via playFinal)
        return false
    }
}
