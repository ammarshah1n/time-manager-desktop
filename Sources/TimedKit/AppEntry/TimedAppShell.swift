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
                if url.host == "auth" {
                    Task { await auth.handleAuthCallback(url: url) }
                }
            }
            .task { await auth.restoreSession() }
    }

    @ViewBuilder
    private var rootContent: some View {
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
