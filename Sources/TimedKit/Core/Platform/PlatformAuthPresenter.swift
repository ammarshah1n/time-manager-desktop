// PlatformAuthPresenter.swift — Timed Core / Platform
// Returns platform-appropriate MSAL webview parameters. Both macOS and iOS
// MSAL slices construct via `init(authPresentationViewController:)`, but the
// view-controller type and how to obtain "the right" one differ:
//
//   macOS: NSApp.keyWindow?.contentViewController
//   iOS:   top-most presented UIViewController of the key UIWindowScene
//
// AuthService / GraphClient call this at the moment they need to present
// MSAL UI. Without it, MSAL crashes (macOS) or simply never presents (iOS).

import Foundation
import MSAL
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
public enum PlatformAuthPresenter {

    public static func msalWebviewParameters() -> MSALWebviewParameters {
        #if canImport(AppKit)
        // MSAL needs a presenter VC backed by a real on-screen window. Fall
        // back from keyWindow → mainWindow → first visible window before
        // resorting to an empty VC (which presents from nowhere and the auth
        // sheet never appears).
        let presenterVC: NSViewController = {
            if let vc = NSApp.keyWindow?.contentViewController { return vc }
            if let vc = NSApp.mainWindow?.contentViewController { return vc }
            if let vc = NSApp.windows.first(where: { $0.isVisible })?.contentViewController { return vc }
            return NSViewController()
        }()
        let params = MSALWebviewParameters(authPresentationViewController: presenterVC)
        // ASWebAuthenticationSession is the most reliable webview path on
        // macOS — system-managed sheet, ephemeral cookie jar, no flaky
        // wkWebView quirks. Same transport we use for the Supabase OAuth
        // (already proven working in this app).
        params.webviewType = .authenticationSession
        // Force a clean cookie jar per attempt. Without this, macOS may
        // re-prompt the system trust alert on each auth attempt, and stale
        // SSO cookies from earlier failed attempts can replay back into the
        // OAuth dance and trigger code-exchange failures. Mirrors the
        // setting on the Supabase ASWebAuth flow at AuthService.swift:141.
        params.prefersEphemeralWebBrowserSession = true
        return params
        #elseif canImport(UIKit)
        let vc = topMostViewController() ?? UIViewController()
        return MSALWebviewParameters(authPresentationViewController: vc)
        #endif
    }

    #if canImport(UIKit)
    private static func topMostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
        let key = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        var top = key?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif
}
