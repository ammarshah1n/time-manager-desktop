// HealthKitAgent.swift — Timed Core
// Stub: HealthKit macOS access patterns unresolved (research gap #12).
// Will bridge HRV, HR, sleep data once iOS companion or Apple Watch sync path confirmed.

import Foundation
import os

actor HealthKitAgent {
    static let shared = HealthKitAgent()

    var isAvailable: Bool { false }

    func start() {
        TimedLogger.dataStore.info("HealthKitAgent: not yet implemented — requires HealthKit research (gap #12)")
    }

    func stop() {}
}
