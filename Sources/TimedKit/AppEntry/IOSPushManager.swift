// IOSPushManager.swift — Timed Core / AppEntry (iOS only)
// UNUserNotificationCenter permission flow + APNs device-token round-trip.
//
// Flow:
//   1. App launches → IOSPushManager.requestPermissionAndRegister()
//   2. If granted → UIApplication.shared.registerForRemoteNotifications()
//   3. AppDelegate's didRegisterForRemoteNotifications → IOSPushManager.handle(deviceToken:)
//   4. handle(...) calls the installed `tokenSink` closure. No production
//      token sink or `register-push-token` Edge Function is wired yet.
//
// AlertEngine scoring stays unchanged; this file only governs delivery.

#if os(iOS)
import Foundation
import UIKit
import UserNotifications

@MainActor
public final class IOSPushManager {

    public static let shared = IOSPushManager()
    private init() {}

    /// Optional sink for the hex-encoded APNs device token. Default is a no-op
    /// until the main app and backend token-registration path are wired.
    public var tokenSink: @Sendable (String) async -> Void = { _ in }

    /// Request notification permission + start APNs registration.
    /// Idempotent — safe to call multiple times.
    public func requestPermissionAndRegister() async {
        let granted = await PlatformNotifications.shared.requestPermission()
        guard granted else { return }
        await PlatformNotifications.shared.registerCategories()
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Called by the AppDelegate when APNs returns the device token.
    public func handle(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        await tokenSink(hex)
        TimedLogger.supabase.info("APNs token forwarded to sink (len=\(deviceToken.count))")
    }

    public func handle(registrationError: Error) {
        TimedLogger.supabase.error("APNs registration failed: \(registrationError.localizedDescription, privacy: .private)")
    }
}
#endif
