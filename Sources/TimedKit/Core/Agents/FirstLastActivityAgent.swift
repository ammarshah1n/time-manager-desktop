#if os(macOS)
import ApplicationServices
import CoreGraphics
import Foundation

private let firstLastActivityNotification = Notification.Name("FirstLastActivityAgent.keyDown")

private func firstLastActivityEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .keyDown {
        NotificationCenter.default.post(
            name: firstLastActivityNotification,
            object: nil,
            userInfo: ["timestamp": Date()]
        )
    }

    return Unmanaged.passUnretained(event)
}

@MainActor
private final class FirstLastActivityTapController {
    static let shared = FirstLastActivityTapController()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var observer: NSObjectProtocol?

    func start() -> Bool {
        guard eventTap == nil else { return true }

        observer = NotificationCenter.default.addObserver(
            forName: firstLastActivityNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let timestamp = notification.userInfo?["timestamp"] as? Date else { return }
            Task {
                await FirstLastActivityAgent.shared.recordActivity(at: timestamp)
            }
        }

        let eventsOfInterest = CGEventMask(1) << CGEventType.keyDown.rawValue

        guard
            let eventTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventsOfInterest,
                callback: firstLastActivityEventTapCallback,
                userInfo: nil
            )
        else {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        return true
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }
}

actor FirstLastActivityAgent {
    static let shared = FirstLastActivityAgent()

    private let pollInterval: Duration = .seconds(60)
    private var monitorTask: Task<Void, Never>? = nil
    private var firstActivityToday: Date?
    private var lastActivityToday: Date?
    private var trackedDayStart = Calendar.current.startOfDay(for: Date())

    func start() async {
        guard monitorTask == nil else { return }

        guard AXIsProcessTrusted() else {
            TimedLogger.dataStore.warning("FirstLastActivityAgent unavailable — Accessibility permission not granted")
            return
        }

        let started = await MainActor.run(body: { FirstLastActivityTapController.shared.start() })
        guard started else {
            TimedLogger.dataStore.warning("FirstLastActivityAgent failed to create event tap")
            return
        }

        TimedLogger.dataStore.info("FirstLastActivityAgent started")

        let pollInterval = pollInterval
        monitorTask = Task {
            while !Task.isCancelled {
                await self.handlePossibleDayRollover(at: Date())
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    func stop() async {
        guard let monitorTask else { return }

        await emitLastActivityIfNeeded()
        monitorTask.cancel()
        self.monitorTask = nil

        await MainActor.run(body: { FirstLastActivityTapController.shared.stop() })
        TimedLogger.dataStore.info("FirstLastActivityAgent stopped")
    }

    func recordActivity(at timestamp: Date) async {
        await handlePossibleDayRollover(at: timestamp)

        if firstActivityToday == nil {
            firstActivityToday = timestamp
            await recordObservation(
                eventType: "system.first_activity",
                occurredAt: timestamp
            )
        }

        lastActivityToday = timestamp
    }

    private func handlePossibleDayRollover(at timestamp: Date) async {
        let currentDayStart = Calendar.current.startOfDay(for: timestamp)
        guard currentDayStart != trackedDayStart else { return }

        await emitLastActivityIfNeeded()
        trackedDayStart = currentDayStart
        firstActivityToday = nil
        lastActivityToday = nil
    }

    private func emitLastActivityIfNeeded() async {
        guard let lastActivityToday else { return }

        await recordObservation(
            eventType: "system.last_activity",
            occurredAt: lastActivityToday
        )

        self.lastActivityToday = nil
    }

    private func recordObservation(eventType: String, occurredAt: Date) async {
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else {
            return
        }

        let observation = Tier0Observation(
            profileId: executiveId,
            occurredAt: occurredAt,
            source: .system,
            eventType: eventType,
            rawData: [
                "activity_at": AnyCodable(ISO8601DateFormatter().string(from: occurredAt))
            ]
        )

        try? await Tier0Writer.shared.recordObservation(observation)
    }
}

#endif
