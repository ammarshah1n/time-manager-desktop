// TimedAppShell.swift — Timed Core / AppEntry
// Public Scene-shell exposed to platform-specific @main targets.
// All references to internal TimedKit types (AuthService, MenuBarManager,
// GlobalHotkeyManager, QuickCapturePanel, TimedRootView) live here so that
// TimedMacApp / TimediOS / extensions only need a single public API surface.

import SwiftUI

@MainActor
public struct TimedAppShell: View {

    @StateObject private var auth = AuthService.shared

    #if canImport(AppKit)
    @StateObject private var menuBarManager = MenuBarManager()
    private let hotkeyManager = GlobalHotkeyManager()
    #endif

    public init() {}

    public var body: some View {
        rootContent
            .onOpenURL { url in
                routeIncoming(url: url)
            }
            .task { await auth.restoreSession() }
    }

    /// Strict URL gate. The previous `host == "auth"` check accepted any
    /// scheme — including the MSAL fallback `msauth.com.timed.app://auth` —
    /// and routed it into the Supabase callback. Lock down to:
    ///   timed://auth/callback?code=…  → Supabase OAuth (only)
    ///   timed://capture                → orb-launch (no params)
    /// Anything else is dropped silently.
    @MainActor
    private func routeIncoming(url: URL) {
        guard url.scheme == "timed" else { return }
        switch (url.host, url.path) {
        case ("auth", "/callback"):
            Task { await auth.handleAuthCallback(url: url) }
        case ("capture", _), (.some(""), "/capture"):
            // Set the App-Group flag the iOS root view consumes-and-clears.
            UserDefaults(suiteName: "group.com.timed.shared")?
                .set(true, forKey: "intent.openCapture")
        default:
            return
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if auth.isSignedIn {
            authenticatedContent
        } else {
            LoginView()
                .environmentObject(auth)
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        #if canImport(AppKit)
        TimedRootView()
            .environmentObject(auth)
            .environmentObject(menuBarManager)
            .onAppear {
                menuBarManager.setup()
                hotkeyManager.register { [menuBarManager] in
                    QuickCapturePanel.shared.show(onSubmit: menuBarManager.onQuickCapture)
                }
            }
            .onDisappear {
                hotkeyManager.unregister()
            }
        #elseif os(iOS)
        TimediOSRootView()
            .environmentObject(auth)
        #endif
    }
}
