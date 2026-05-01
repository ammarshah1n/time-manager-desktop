// TimediOSAppMain.swift — TimediOS executable target
// Thin @main shim. App-level concerns:
//   - KeychainStore legacy migration (one-shot)
//   - BGTaskScheduler handler registration (must run *before* scene becomes active)
//   - APNs permission + registration scaffold
//   - URL handling for the orb-launch deep link `timed://capture`
//
// All UI lives in TimedKit.TimedAppShell which dispatches to TimediOSRootView
// (TabView for iPhone, NavigationSplitView for iPad) on iOS.

import SwiftUI
import TimedKit
import UIKit

@main
struct TimediOSAppMain: App {

    @AppStorage("prefs.appearance.theme") private var theme: String = "system"
    @UIApplicationDelegateAdaptor(TimediOSAppDelegate.self) private var appDelegate

    init() {
        KeychainStore.migrateLegacyKeysIfNeeded()
        // BGTaskScheduler handlers must register before the app finishes launching.
        TimedBackgroundTasks.registerHandlers()
        TimedBackgroundTasks.scheduleNextEmailRefresh()
    }

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            TimedAppShell()
                .preferredColorScheme(colorScheme)
                .task {
                    // Current scaffold requests once the UI is up. Move this
                    // behind onboarding before treating iOS notifications as
                    // production-ready.
                    await IOSPushManager.shared.requestPermissionAndRegister()
                }
        }
    }
}

// MARK: - AppDelegate (only for APNs + remote notification callbacks)

// `@preconcurrency` on the UNUserNotificationCenterDelegate conformance
// lets Swift 6 strict concurrency accept the inherited @MainActor isolation
// from UIApplicationDelegate without flagging every delegate method.
@MainActor
final class TimediOSAppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // APNs token returned ⇒ forward to IOSPushManager.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await IOSPushManager.shared.handle(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            IOSPushManager.shared.handle(registrationError: error)
        }
    }

    // Silent push (content-available: 1) ⇒ trigger one delta sync.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Defer to the main app's installed sync worker; if none, no-op.
        Task { @MainActor in
            // No-op for now — wired in Step 9 final pass once the
            // EmailSyncServiceProvider has a sync sink installed.
            completionHandler(.noData)
        }
    }

    // Foreground notifications — show banner + play sound by default.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    // Notification action handlers (View / Dismiss / Snooze 1h).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        switch action {
        case "timed.action.snooze":
            // Push snooze-until into App Group UserDefaults; the running app
            // observes and updates `staleAlertSnoozedUntil` on next foreground.
            UserDefaults(suiteName: "group.com.timed.shared")?
                .set(Date().addingTimeInterval(60 * 60), forKey: "alert.snoozedUntil")
        case "timed.action.dismiss", UNNotificationDismissActionIdentifier:
            break
        default:
            break  // .view falls through to default-foreground behaviour
        }
        _ = userInfo  // hook point — Step 9 final wiring uses userInfo to route
        completionHandler()
    }
}
