import ApplicationServices
import CoreGraphics
import Foundation

/// Captures keystroke *timing* only — never key values or characters.
/// Computes 5-minute aggregates: mean IKI, dwell time, backspace rate, WPM, pause patterns.
/// Requires Accessibility permission (TCC). Built as in-process agent; XPC isolation deferred to Phase 12.
actor KeystrokeAgent {
    static let shared = KeystrokeAgent()

    private let windowDuration: TimeInterval = 300 // 5-minute windows
    private var monitorTask: Task<Void, Never>?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Per-window accumulators (actor-isolated)
    private var keyDownTimestamps: [TimeInterval] = []
    private var keyUpTimestamps: [TimeInterval] = []
    private var backspaceCount: Int = 0
    private var pauseCount: Int = 0 // pauses > 2 seconds
    private var windowStart: Date = Date()

    func start() async {
        guard monitorTask == nil else { return }
        guard AXIsProcessTrusted() else {
            TimedLogger.dataStore.info("KeystrokeAgent: Accessibility permission not granted, skipping")
            return
        }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // Store self reference for callback
        let unmanagedSelf = Unmanaged.passUnretained(self)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let agent = Unmanaged<KeystrokeAgent>.fromOpaque(userInfo).takeUnretainedValue()
                let timestamp = ProcessInfo.processInfo.systemUptime
                let isKeyDown = type == .keyDown
                let isKeyUp = type == .keyUp
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

                Task { @Sendable in
                    if isKeyDown {
                        await agent.recordKeyDown(at: timestamp, keyCode: keyCode)
                    } else if isKeyUp {
                        await agent.recordKeyUp(at: timestamp)
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: unmanagedSelf.toOpaque()
        )

        guard let eventTap else {
            TimedLogger.dataStore.error("KeystrokeAgent: Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        windowStart = Date()
        TimedLogger.dataStore.info("KeystrokeAgent started")

        monitorTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(windowDuration))
                await self.flushWindow()
            }
        }
    }

    func stop() async {
        monitorTask?.cancel()
        monitorTask = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil

        await flushWindow()
        TimedLogger.dataStore.info("KeystrokeAgent stopped")
    }

    private func recordKeyDown(at timestamp: TimeInterval, keyCode: Int64) {
        // Detect backspace (keyCode 51)
        if keyCode == 51 {
            backspaceCount += 1
        }

        // Detect pauses > 2 seconds
        if let lastDown = keyDownTimestamps.last, (timestamp - lastDown) > 2.0 {
            pauseCount += 1
        }

        keyDownTimestamps.append(timestamp)
    }

    private func recordKeyUp(at timestamp: TimeInterval) {
        keyUpTimestamps.append(timestamp)
    }

    private func flushWindow() async {
        let downCount = keyDownTimestamps.count
        guard downCount >= 5 else {
            resetWindow()
            return
        }

        // Compute inter-key intervals (IKI)
        var ikis: [TimeInterval] = []
        for i in 1..<keyDownTimestamps.count {
            ikis.append(keyDownTimestamps[i] - keyDownTimestamps[i - 1])
        }

        // Compute dwell times (keyDown to keyUp pairs)
        var dwellTimes: [TimeInterval] = []
        let pairCount = min(keyDownTimestamps.count, keyUpTimestamps.count)
        for i in 0..<pairCount {
            let dwell = keyUpTimestamps[i] - keyDownTimestamps[i]
            if dwell > 0 && dwell < 2.0 {
                dwellTimes.append(dwell)
            }
        }

        let meanIKI = ikis.isEmpty ? 0 : ikis.reduce(0, +) / Double(ikis.count)
        let meanDwell = dwellTimes.isEmpty ? 0 : dwellTimes.reduce(0, +) / Double(dwellTimes.count)
        let windowSeconds = Date().timeIntervalSince(windowStart)
        let wpm = windowSeconds > 0 ? Double(downCount) / windowSeconds * 60.0 / 5.0 : 0
        let backspaceRate = downCount > 0 ? Double(backspaceCount) / Double(downCount) : 0

        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else {
            resetWindow()
            return
        }

        let observation = Tier0Observation(
            profileId: executiveId,
            occurredAt: Date(),
            source: .keystroke,
            eventType: "keystroke.window",
            rawData: [
                "mean_iki_ms": AnyCodable(meanIKI * 1000),
                "mean_dwell_ms": AnyCodable(meanDwell * 1000),
                "wpm": AnyCodable(wpm),
                "backspace_rate": AnyCodable(backspaceRate),
                "pause_count": AnyCodable(pauseCount),
                "keypress_count": AnyCodable(downCount),
                "window_duration_seconds": AnyCodable(windowSeconds),
            ]
        )

        try? await Tier0Writer.shared.recordObservation(observation)
        resetWindow()
    }

    private func resetWindow() {
        keyDownTimestamps.removeAll()
        keyUpTimestamps.removeAll()
        backspaceCount = 0
        pauseCount = 0
        windowStart = Date()
    }
}
