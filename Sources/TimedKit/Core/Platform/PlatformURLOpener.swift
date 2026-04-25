// PlatformURLOpener.swift — Timed Core / Platform
// Cross-platform shim for "open a URL in the user's default browser".
// macOS: NSWorkspace.shared.open(url)
// iOS:   await UIApplication.shared.open(url)
//
// Used by AuthService for OAuth redirect. The async method on iOS returns a
// completion bool — ignored here; failure surfaces as the AuthService never
// receiving the timed:// callback, which the user retries from the sign-in
// button as today.

import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
public enum PlatformURLOpener {
    public static func open(_ url: URL) async {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        await UIApplication.shared.open(url)
        #endif
    }
}
