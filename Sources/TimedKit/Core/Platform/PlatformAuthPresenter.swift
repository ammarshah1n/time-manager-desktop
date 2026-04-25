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
        return MSALWebviewParameters(
            authPresentationViewController: NSApp.keyWindow?.contentViewController
                ?? NSViewController()
        )
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
