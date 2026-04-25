#if os(macOS)
import Foundation
import IOKit

actor IdleTimeAgent {
    static let shared = IdleTimeAgent()

    private let idleThresholdSeconds: TimeInterval = 600
    private let pollInterval: Duration = .seconds(60)
    private var monitorTask: Task<Void, Never>? = nil
    private var isCurrentlyIdle = false

    func start() async {
        guard monitorTask == nil else { return }

        TimedLogger.dataStore.info("IdleTimeAgent started")

        let threshold = idleThresholdSeconds
        let pollInterval = pollInterval

        monitorTask = Task {
            while !Task.isCancelled {
                let idleSeconds = Self.currentIdleTimeSeconds() ?? 0
                await self.handleIdleSample(idleSeconds, threshold: threshold, sampledAt: Date())
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    func stop() async {
        guard let monitorTask else { return }

        monitorTask.cancel()
        self.monitorTask = nil
        TimedLogger.dataStore.info("IdleTimeAgent stopped")
    }

    private func handleIdleSample(_ idleSeconds: TimeInterval, threshold: TimeInterval, sampledAt: Date) async {
        if idleSeconds > threshold, !isCurrentlyIdle {
            isCurrentlyIdle = true
            await recordTransition(
                eventType: "system.idle_start",
                occurredAt: sampledAt,
                idleSeconds: idleSeconds
            )
            return
        }

        if idleSeconds < threshold, isCurrentlyIdle {
            isCurrentlyIdle = false
            await recordTransition(
                eventType: "system.idle_end",
                occurredAt: sampledAt,
                idleSeconds: idleSeconds
            )
        }
    }

    private func recordTransition(eventType: String, occurredAt: Date, idleSeconds: TimeInterval) async {
        guard let executiveId = await MainActor.run(body: { AuthService.shared.executiveId }) else {
            return
        }

        let observation = Tier0Observation(
            profileId: executiveId,
            occurredAt: occurredAt,
            source: .system,
            eventType: eventType,
            rawData: [
                "idle_duration_seconds": AnyCodable(idleSeconds)
            ]
        )

        try? await Tier0Writer.shared.recordObservation(observation)
    }

    private static func currentIdleTimeSeconds() -> TimeInterval? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard
            let property = IORegistryEntryCreateCFProperty(
                service,
                "HIDIdleTime" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue()
        else {
            return nil
        }

        if let idleTime = property as? NSNumber {
            return idleTime.doubleValue / 1_000_000_000
        }

        return nil
    }
}

#endif
