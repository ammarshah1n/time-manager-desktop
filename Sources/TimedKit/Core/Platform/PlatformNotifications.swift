// PlatformNotifications.swift — Timed Core / Platform
// Cross-platform notification surface for AlertEngine output.
//
// macOS: in-app banner + dock badge (handled inside the SwiftUI views; this
//        file only defines a passthrough so the call sites stay platform-clean).
// iOS:   UNUserNotificationCenter local + remote (APNs) delivery. Permission
//        request fires once on first sign-in.
//
// AlertEngine 5-dimension scoring (salience × confidence × timeSensitivity ×
// actionability × cognitiveStatePermit) and the existing 0.90 / 0.80 / 0.75
// thresholds are unchanged — this file only governs *delivery*, never scoring.

import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
public final class PlatformNotifications {

    public static let shared = PlatformNotifications()
    private init() {}

    public enum Tier: String {
        case interrupt    // score >= 0.90 — immediate banner
        case preliminary  // 0.80–0.89 — labelled "Preliminary"
        case batch        // 0.75–0.79 — morning briefing only
    }

    /// Request permission. Idempotent: safe to call repeatedly. On macOS the
    /// system shows the standard prompt only once; subsequent calls just
    /// return the cached authorization status.
    public func requestPermission() async -> Bool {
        #if canImport(UserNotifications)
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
        #else
        return true
        #endif
    }

    /// Deliver a scored alert. Routing is the caller's responsibility — the
    /// AlertEngine decides which tier each alert lands in.
    public func deliver(
        title: String,
        body: String,
        tier: Tier,
        identifier: String = UUID().uuidString,
        userInfo: [String: String] = [:]
    ) async {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        content.categoryIdentifier = "timed.alert.\(tier.rawValue)"
        switch tier {
        case .interrupt:
            content.interruptionLevel = .timeSensitive
            content.sound = .default
        case .preliminary:
            content.interruptionLevel = .active
            content.sound = .default
        case .batch:
            content.interruptionLevel = .passive
        }
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // immediate
        )
        try? await UNUserNotificationCenter.current().add(request)
        #endif
    }

    /// Update the dock / app icon badge count. macOS uses NSApp.dockTile;
    /// iOS uses applicationIconBadgeNumber. UNUserNotificationCenter exposes
    /// a unified API on both since macOS 11 — we use that.
    public func setBadgeCount(_ count: Int) async {
        #if canImport(UserNotifications)
        try? await UNUserNotificationCenter.current().setBadgeCount(max(0, count))
        #endif
    }

    /// Register the standard category set (View / Dismiss / Snooze 1h)
    /// referenced by `deliver(...)` above. Call once during app launch on iOS.
    public func registerCategories() async {
        #if canImport(UserNotifications)
        let view = UNNotificationAction(
            identifier: "timed.action.view",
            title: "View",
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: "timed.action.dismiss",
            title: "Dismiss",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: "timed.action.snooze",
            title: "Snooze 1h",
            options: []
        )
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(
                identifier: "timed.alert.interrupt",
                actions: [view, snooze, dismiss],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "timed.alert.preliminary",
                actions: [view, snooze, dismiss],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "timed.alert.batch",
                actions: [view, dismiss],
                intentIdentifiers: [],
                options: []
            ),
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
        #endif
    }
}
