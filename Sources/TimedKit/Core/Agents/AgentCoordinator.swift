import ApplicationServices
import CoreGraphics
import Foundation

actor AgentCoordinator {
    static let shared = AgentCoordinator()

    private struct ManagedAgent: Sendable {
        let name: String
        let start: @Sendable () async throws -> Void
        let stop: @Sendable () async throws -> Void
    }

    private static let managedAgents: [ManagedAgent] = [
        ManagedAgent(
            name: "AppUsageAgent",
            start: { await AppUsageAgent.shared.start() },
            stop: { await AppUsageAgent.shared.stop() }
        ),
        ManagedAgent(
            name: "IdleTimeAgent",
            start: { await IdleTimeAgent.shared.start() },
            stop: { await IdleTimeAgent.shared.stop() }
        ),
        ManagedAgent(
            name: "FirstLastActivityAgent",
            start: { await FirstLastActivityAgent.shared.start() },
            stop: { await FirstLastActivityAgent.shared.stop() }
        )
    ]

    // Gated agents — activated only when permissions are granted
    private static let gatedAgents: [ManagedAgent] = [
        ManagedAgent(
            name: "KeystrokeAgent",
            start: {
                guard AXIsProcessTrusted() else { return }
                await KeystrokeAgent.shared.start()
            },
            stop: { await KeystrokeAgent.shared.stop() }
        )
    ]

    private static let healthCheckInterval: Duration = .seconds(300)
    private static let staleObservationThreshold: TimeInterval = 1_800
    private static let observationWindow: TimeInterval = 86_400
    private static let workdayStartHour = 8
    private static let workdayEndHour = 20

    private(set) var isRunning = false

    private var healthTask: Task<Void, Never>? = nil
    private var isTransitioning = false
    private var lifecycleGeneration: UInt64 = 0

    private var lastObservationProxyCount: Int?
    private var lastObservedActivityAt: Date?
    private var lastHealthWarningAt: Date?
    private var proxyObservationTimestamps: [Date] = []

    func startAll() async {
        guard !isRunning, !isTransitioning else { return }

        isTransitioning = true
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration

        for agent in Self.managedAgents {
            guard lifecycleGeneration == generation else { return }
            try? await agent.start()
        }

        // Start gated agents (permission-checked internally)
        for agent in Self.gatedAgents {
            guard lifecycleGeneration == generation else { return }
            try? await agent.start()
        }

        guard lifecycleGeneration == generation else { return }

        isRunning = true
        isTransitioning = false

        let startedAt = Date()
        resetObservationHealthState(startedAt: startedAt)
        _ = await refreshObservationProxy(at: startedAt)
        startHealthMonitoring()

        TimedLogger.dataStore.info("AgentCoordinator started")
    }

    func stopAll() async {
        guard isRunning || isTransitioning else { return }

        isRunning = false
        isTransitioning = true
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration

        healthTask?.cancel()
        healthTask = nil

        for agent in Self.gatedAgents.reversed() {
            guard lifecycleGeneration == generation else { return }
            try? await agent.stop()
        }

        for agent in Self.managedAgents.reversed() {
            guard lifecycleGeneration == generation else { return }
            try? await agent.stop()
        }

        guard lifecycleGeneration == generation else { return }

        isTransitioning = false
        resetObservationHealthState(startedAt: nil)

        TimedLogger.dataStore.info("AgentCoordinator stopped")
    }

    func observationRatePerDay() async -> Int {
        let timestamp = Date()
        _ = await refreshObservationProxy(at: timestamp)
        pruneProxyObservationTimestamps(referenceDate: timestamp)
        return proxyObservationTimestamps.isEmpty ? max(lastObservationProxyCount ?? 0, 0) : proxyObservationTimestamps.count
    }

    private func startHealthMonitoring() {
        healthTask?.cancel()
        healthTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.healthCheckInterval)
                guard !Task.isCancelled else { break }
                await self.performHealthCheck(at: Date())
            }
        }
    }

    private func performHealthCheck(at timestamp: Date) async {
        let pendingCount = await refreshObservationProxy(at: timestamp)

        guard Self.isWithinWorkHours(timestamp) else { return }
        guard let lastObservedActivityAt else { return }
        guard timestamp.timeIntervalSince(lastObservedActivityAt) >= Self.staleObservationThreshold else { return }
        guard shouldEmitHealthWarning(since: lastObservedActivityAt) else { return }

        TimedLogger.dataStore.warning(
            "AgentCoordinator health warning — no new observation proxy activity for 30 minutes during work hours (pending: \(pendingCount, privacy: .public))"
        )
        lastHealthWarningAt = timestamp
    }

    private func refreshObservationProxy(at timestamp: Date) async -> Int {
        // Tier0Writer does not currently expose buffer stats, so use the offline queue depth as the shared health proxy.
        let pendingCount = (try? await OfflineSyncQueue.shared.pendingCount()) ?? 0

        defer { lastObservationProxyCount = pendingCount }

        guard let lastObservationProxyCount else {
            if pendingCount > 0 {
                recordProxyObservations(delta: pendingCount, at: timestamp)
            }
            return pendingCount
        }

        let delta = pendingCount - lastObservationProxyCount
        if delta > 0 {
            recordProxyObservations(delta: delta, at: timestamp)
        }

        return pendingCount
    }

    private func recordProxyObservations(delta: Int, at timestamp: Date) {
        lastObservedActivityAt = timestamp
        lastHealthWarningAt = nil
        proxyObservationTimestamps.append(contentsOf: Array(repeating: timestamp, count: delta))
        pruneProxyObservationTimestamps(referenceDate: timestamp)
    }

    private func pruneProxyObservationTimestamps(referenceDate: Date) {
        proxyObservationTimestamps.removeAll {
            referenceDate.timeIntervalSince($0) > Self.observationWindow
        }
    }

    private func resetObservationHealthState(startedAt: Date?) {
        lastObservationProxyCount = nil
        lastObservedActivityAt = startedAt
        lastHealthWarningAt = nil
        proxyObservationTimestamps.removeAll(keepingCapacity: false)
    }

    private func shouldEmitHealthWarning(since lastObservedActivityAt: Date) -> Bool {
        guard let lastHealthWarningAt else { return true }
        return lastHealthWarningAt < lastObservedActivityAt
    }

    private static func isWithinWorkHours(_ timestamp: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: timestamp)
        return hour >= workdayStartHour && hour < workdayEndHour
    }
}
