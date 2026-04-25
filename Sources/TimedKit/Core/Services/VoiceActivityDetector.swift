import AVFoundation
import Foundation

struct VoiceActivityDetector {
    var speechThreshold: Float = 0.018
    var silenceWindow: TimeInterval = 0.3

    private var wasSpeaking = false
    private var silenceStartedAt: Date?

    mutating func observe(level: Float, at date: Date = Date()) -> Bool {
        if level >= speechThreshold {
            wasSpeaking = true
            silenceStartedAt = nil
            return false
        }

        guard wasSpeaking else { return false }
        if silenceStartedAt == nil {
            silenceStartedAt = date
            return false
        }
        guard let silenceStartedAt, date.timeIntervalSince(silenceStartedAt) >= silenceWindow else {
            return false
        }
        wasSpeaking = false
        self.silenceStartedAt = nil
        return true
    }

    static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += samples[index] * samples[index]
        }
        return sqrtf(sum / Float(buffer.frameLength))
    }
}
