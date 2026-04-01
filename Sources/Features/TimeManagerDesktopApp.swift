import SwiftUI

@main
struct TimeManagerDesktopApp: App {
    @AppStorage("prefs.appearance.theme") private var theme: String = "system"
    @StateObject private var auth = AuthService.shared
    @StateObject private var menuBarManager = MenuBarManager()
    private let hotkeyManager = GlobalHotkeyManager()

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup("Timed") {
            TimedRootView()
                .environmentObject(auth)
                .environmentObject(menuBarManager)
                .preferredColorScheme(colorScheme)
                .onOpenURL { url in
                    // Handle timed://auth/callback from OAuth
                    if url.host == "auth" {
                        Task { await auth.handleAuthCallback(url: url) }
                    }
                }
                .task { await auth.restoreSession() }
                .onAppear {
                    menuBarManager.setup()
                    registerGlobalHotkey()
                }
                .onDisappear {
                    hotkeyManager.unregister()
                }
        }
        .defaultSize(width: 1240, height: 820)
    }

    private func registerGlobalHotkey() {
        hotkeyManager.register { [menuBarManager] in
            QuickCapturePanel.shared.show(onSubmit: menuBarManager.onQuickCapture)
        }
    }
}
