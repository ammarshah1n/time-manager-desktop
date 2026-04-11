// OuraRingAgent.swift — Timed Core
// Stub: Oura Ring v2 API integration (optional, enriches HealthKit).
// Falls back gracefully — HealthKit alone is sufficient.

import Foundation
import os

actor OuraRingAgent {
    static let shared = OuraRingAgent()

    var isAvailable: Bool { false }

    func start() {
        TimedLogger.dataStore.info("OuraRingAgent: not yet implemented — optional enrichment agent")
    }

    func stop() {}
}
