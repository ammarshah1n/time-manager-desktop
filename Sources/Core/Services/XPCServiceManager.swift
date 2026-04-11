import Foundation
import ServiceManagement

/// Phase 12.01-12.02: XPC service mesh manager.
/// Manages 5 background processes: Keystroke, Voice, Accessibility, AppUsage + main coordinator.
/// Each registered as LaunchAgent via SMAppService, KeepAlive=true.
/// Handles App Nap prevention and low battery mode.
actor XPCServiceManager {
    static let shared = XPCServiceManager()

    // MARK: - Service Registry

    enum ServiceType: String, CaseIterable, Sendable {
        case keystroke = "com.timed.keystroke-xpc"
        case voice = "com.timed.voice-xpc"
        case accessibility = "com.timed.accessibility-xpc"
        case appUsage = "com.timed.appusage-xpc"
    }

    struct ServiceStatus: Sendable {
        let type: ServiceType
        let isRegistered: Bool
        let isRunning: Bool
        let lastHeartbeat: Date?
    }

    private var serviceStatuses: [ServiceType: ServiceStatus] = [:]
    private var activityToken: NSObjectProtocol?

    // MARK: - Registration (12.01)

    /// Register all XPC services as LaunchAgents via SMAppService
    func registerAll() async {
        for serviceType in ServiceType.allCases {
            await register(serviceType)
        }
        TimedLogger.dataStore.info("XPCServiceManager: all services registered")
    }

    private func register(_ type: ServiceType) async {
        if #available(macOS 13.0, *) {
            let service = SMAppService.agent(plistName: "\(type.rawValue).plist")
            do {
                try service.register()
                serviceStatuses[type] = ServiceStatus(
                    type: type, isRegistered: true, isRunning: true, lastHeartbeat: Date()
                )
            } catch {
                TimedLogger.dataStore.error("XPCServiceManager: failed to register \(type.rawValue) — \(error.localizedDescription)")
                serviceStatuses[type] = ServiceStatus(
                    type: type, isRegistered: false, isRunning: false, lastHeartbeat: nil
                )
            }
        }
    }

    /// Unregister all XPC services
    func unregisterAll() async {
        if #available(macOS 13.0, *) {
            for serviceType in ServiceType.allCases {
                let service = SMAppService.agent(plistName: "\(serviceType.rawValue).plist")
                try? await service.unregister()
            }
        }
        serviceStatuses.removeAll()
    }

    // MARK: - Health Monitoring

    /// Check health of all services
    func healthCheck() -> [ServiceStatus] {
        Array(serviceStatuses.values)
    }

    /// Record heartbeat from a service
    func recordHeartbeat(for type: ServiceType) {
        if var status = serviceStatuses[type] {
            status = ServiceStatus(
                type: type, isRegistered: status.isRegistered, isRunning: true, lastHeartbeat: Date()
            )
            serviceStatuses[type] = status
        }
    }

    // MARK: - App Nap Prevention (12.02)

    /// Prevent App Nap for the main app process
    func preventAppNap() {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Timed observation pipeline requires continuous operation"
        )
        TimedLogger.dataStore.info("XPCServiceManager: App Nap prevention active")
    }

    func allowAppNap() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    // MARK: - Low Battery Mode (12.02)

    struct PowerProfile: Sendable {
        let keystrokeInterval: TimeInterval  // seconds between aggregates
        let emailSyncInterval: TimeInterval
        let voiceEnabled: Bool
    }

    /// Get appropriate power profile based on battery state
    func powerProfile() -> PowerProfile {
        // Check battery level via IOKit
        let batteryLevel = getBatteryLevel()

        if batteryLevel < 20 {
            // Low battery: reduce sampling, pause voice
            return PowerProfile(
                keystrokeInterval: 900,  // 15 min (normal: 5 min)
                emailSyncInterval: 1800, // 30 min (normal: 5 min)
                voiceEnabled: false
            )
        }

        // Normal operation
        return PowerProfile(
            keystrokeInterval: 300,  // 5 min
            emailSyncInterval: 300,  // 5 min
            voiceEnabled: true
        )
    }

    /// Get battery percentage (simplified — full implementation uses IOKit)
    private func getBatteryLevel() -> Int {
        // IOKit battery query — simplified
        // Full implementation: IOServiceGetMatchingService + IOPSCopyPowerSourcesInfo
        return 100 // Default: assume plugged in
    }
}
