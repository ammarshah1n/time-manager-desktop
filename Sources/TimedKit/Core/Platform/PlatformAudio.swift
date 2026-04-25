// PlatformAudio.swift — Timed Core / Platform
// Cross-platform AVAudioSession wrapper.
//
// macOS: no-op. AVAudioSession is iOS-only; on macOS the Deepgram WebSocket
//        and AVAudioPlayer just work without session configuration.
// iOS:   configures `.playAndRecord` with `.duckOthers + .allowBluetoothA2DP +
//        .defaultToSpeaker`, activates before mic capture starts, deactivates
//        once both STT capture and TTS playback are idle. Without this,
//        Deepgram WS silently fails to capture mic input on iOS.
//
// Reference-counted activation lets DeepgramSTTService and
// StreamingTTSService each call activate / deactivate without stepping on
// each other — only the last release deactivates the session.

import Foundation
#if canImport(AVFAudio) && os(iOS)
import AVFAudio
#endif

@MainActor
public final class PlatformAudio {

    public static let shared = PlatformAudio()

    private var activeRefs: Int = 0
    private init() {}

    /// Activate the play-and-record session. Idempotent: safe to call
    /// repeatedly from multiple components; the matching `release()` count
    /// drops the session.
    ///
    /// Reference-count rollback: if `setCategory` or `setActive` throws, we
    /// undo the increment so a failed acquire doesn't leak a phantom ref
    /// (which would keep the session "active" forever in our accounting and
    /// silently swallow the next caller's release).
    public func acquirePlayAndRecord() throws {
        activeRefs += 1
        guard activeRefs == 1 else { return }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.duckOthers, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true, options: [])
        } catch {
            activeRefs -= 1
            throw error
        }
        #endif
    }

    /// Drop one reference. When the count reaches zero, the iOS session is
    /// deactivated so other apps regain audio focus.
    public func release() {
        guard activeRefs > 0 else { return }
        activeRefs -= 1
        guard activeRefs == 0 else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    /// Microphone permission. macOS implicit (Info.plist string + first
    /// AVCaptureDevice access prompts); iOS must explicitly request.
    public func requestMicPermission() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return true
        #endif
    }
}
