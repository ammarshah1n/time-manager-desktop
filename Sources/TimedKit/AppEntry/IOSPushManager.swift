// IOSPushManager.swift — Timed Core / AppEntry (iOS only)
// UNUserNotificationCenter permission flow + APNs device-token round-trip.
//
// Flow:
//   1. App launches → IOSPushManager.requestPermissionAndRegister()
//   2. If granted → UIApplication.shared.registerForRemoteNotifications()
//   3. AppDelegate's didRegisterForRemoteNotifications → IOSPushManager.handle(deviceToken:)
//   4. handle(...) calls the installed `tokenSink` closure, which the main
//      app provides — typically POSTs to Supabase Edge Function
//      `register-push-token` with `{ device_token, platform: "ios", … }`.
//      The Edge Function must verifyAuth(req) and bind to executive_id from
//      the JWT — body-supplied tenant IDs are rejected per ai-assistant-rules.
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

    /// Optional sink installed by the main app at launch — receives the
    /// hex-encoded APNs device token. Default is a no-op so the registration
    /// flow doesn't break before the main app wires its sink.
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
