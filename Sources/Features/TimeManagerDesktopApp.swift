import ComposableArchitecture
import SwiftUI

@main
struct TimeManagerDesktopApp: App {
    @AppStorage("prefs.appearance.theme") private var theme: String = "system"

    @StateObject private var auth = AuthService.shared
    @StateObject private var menuBarManager = MenuBarManager()
    private let hotkeyManager = GlobalHotkeyManager()

    init() {
        KeychainStore.migrateLegacyKeysIfNeeded()
    }

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup("Timed") {
            RootContainer(
                auth: auth,
                menuBarManager: menuBarManager,
                colorScheme: colorScheme,
                onRootAppear: {
                    menuBarManager.setup()
                    registerGlobalHotkey()
                },
                onRootDisappear: {
                    hotkeyManager.unregister()
                }
            )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
    }

    private func registerGlobalHotkey() {
        hotkeyManager.register { [menuBarManager] in
            QuickCapturePanel.shared.show(onSubmit: menuBarManager.onQuickCapture)
        }
    }
}

// MARK: - RootContainer

/// Launches directly into the main app — no splash, no cinematic gate.
/// macOS system apps don't have splashes; neither does Timed.
private struct RootContainer: View {

    let auth: AuthService
    let menuBarManager: MenuBarManager
    let colorScheme: ColorScheme?
    let onRootAppear: () -> Void
    let onRootDisappear: () -> Void

    var body: some View {
        TimedRootView()
            .environmentObject(auth)
            .environmentObject(menuBarManager)
            .onOpenURL { url in
                if url.host == "auth" {
                    Task { await auth.handleAuthCallback(url: url) }
                }
            }
            .task { await auth.restoreSession() }
            .onAppear { onRootAppear() }
            .onDisappear { onRootDisappear() }
            .preferredColorScheme(colorScheme)
    }
}
