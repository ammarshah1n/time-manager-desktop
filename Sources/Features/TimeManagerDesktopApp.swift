import ComposableArchitecture
import SwiftUI

@main
struct TimeManagerDesktopApp: App {
    @AppStorage("prefs.appearance.theme") private var theme: String = "system"
    @AppStorage(BrandVersion.introSeenKey) private var hasSeenIntro: Bool = false

    @StateObject private var auth = AuthService.shared
    @StateObject private var menuBarManager = MenuBarManager()
    private let hotkeyManager = GlobalHotkeyManager()

    /// Store for the first-launch cinematic intro. Persists for the lifetime of
    /// the scene; once `hasSeenIntro` flips the intro is not instantiated again.
    @State private var introStore = Store(initialState: IntroFeature.State()) {
        IntroFeature()
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
                hasSeenIntro: $hasSeenIntro,
                introStore: introStore,
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

/// Gates the main app behind the first-launch intro. Separated from the @main
/// struct so the intro store and environment plumbing stay contained.
private struct RootContainer: View {

    @Binding var hasSeenIntro: Bool
    let introStore: StoreOf<IntroFeature>
    let auth: AuthService
    let menuBarManager: MenuBarManager
    let colorScheme: ColorScheme?
    let onRootAppear: () -> Void
    let onRootDisappear: () -> Void

    var body: some View {
        ZStack {
            if hasSeenIntro {
                mainRoot
                    .transition(.opacity)
            } else {
                IntroView(store: introStore)
                    .transition(.opacity)
                    .onChange(of: introStore.phase) { _, phase in
                        if phase == .finished {
                            withAnimation(.easeOut(duration: 0.4)) {
                                hasSeenIntro = true
                            }
                        }
                    }
            }
        }
        .preferredColorScheme(colorScheme)
    }

    private var mainRoot: some View {
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
    }
}
