// GoogleClient.swift — Timed Core
// ============================================================
// Owns the GIDSignIn lifecycle for Google (Gmail + Calendar).
// Parallel to MSAL setup in GraphClient.swift.
//
// Mirrors the closure-based token-provider pattern used by the
// Microsoft path: AuthService holds the @Published googleAccessToken
// and exposes `makeGoogleTokenProvider()` for sync services.
//
// GoogleSignIn-iOS handles silent refresh internally via
// `restorePreviousSignIn` + `refreshTokensIfNeeded` — we wrap those.
// ============================================================

import Foundation
import Dependencies
import os
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Google App Config

enum GoogleConfig {
    /// Google OAuth 2.0 client ID. Read from env var GOOGLE_CLIENT_ID, then
    /// from Info.plist GIDClientID, then a placeholder that surfaces a clear
    /// error at sign-in time so misconfiguration fails loudly.
    /// Must match the OAuth client ID registered in GCP for this app's bundle ID.
    static var clientID: String {
        if let env = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"], !env.isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String, !plist.isEmpty {
            return plist
        }
        return "GOOGLE_CLIENT_ID_NOT_CONFIGURED.apps.googleusercontent.com"
    }

    /// Read-only scopes — Timed observes / reflects / recommends and NEVER
    /// acts on the world. No send, no compose, no calendar write.
    /// `openid` / `email` / `profile` give us identity for AuthService bridging.
    static let scopes: [String] = [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/calendar.readonly"
    ]

    static var isConfigured: Bool {
        !clientID.contains("NOT_CONFIGURED")
    }
}

// MARK: - File-scoped diagnostic log

/// Mirrors graphFileLog — same purpose. ad-hoc-signed builds on macOS Tahoe
/// drop os.Logger output; this writes to /tmp/timed-google.log.
@Sendable
func googleFileLog(_ msg: String) {
    let logURL = URL(fileURLWithPath: "/tmp/timed-google.log")
    let stamp = ISO8601DateFormatter().string(from: Date())
    let payload = "[\(stamp)] \(msg)\n"
    guard let data = payload.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logURL.path),
       let h = try? FileHandle(forWritingTo: logURL) {
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: data)
    } else {
        try? data.write(to: logURL)
    }
}

// MARK: - Errors

enum GoogleAuthError: Error, LocalizedError {
    case notConfigured
    case signInFailed(String)
    case noActiveUser
    case noPresentingWindow
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google sign-in is not configured. Set GOOGLE_CLIENT_ID env var or GIDClientID in Info.plist."
        case .signInFailed(let detail):
            return "Google sign-in failed: \(detail)"
        case .noActiveUser:
            return "No Google account currently signed in."
        case .noPresentingWindow:
            return "Could not find a window to present the Google sign-in sheet."
        case .unsupportedPlatform:
            return "Google sign-in is unavailable on this platform."
        }
    }
}

// MARK: - GoogleAuth (interactive sign-in + restore + token refresh)

/// Static facade around GoogleSignIn-iOS. All access is on @MainActor because
/// GIDSignIn's APIs are documented as main-thread only.
@MainActor
enum GoogleAuth {
    /// Email of the currently signed-in Google account, nil if none.
    static var currentUserEmail: String? {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.currentUser?.profile?.email
        #else
        return nil
        #endif
    }

    /// Currently cached access token. nil if no user signed in.
    static var currentAccessToken: String? {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString
        #else
        return nil
        #endif
    }

    /// Restores a previously-signed-in user from Keychain on app launch.
    /// Returns the email if restored, nil if no prior session.
    static func restorePreviousSignIn() async -> String? {
        #if canImport(GoogleSignIn)
        googleFileLog("GoogleAuth.restorePreviousSignIn: ENTER")
        guard GoogleConfig.isConfigured else {
            googleFileLog("GoogleAuth.restorePreviousSignIn: SKIP — not configured")
            return nil
        }
        // Extract email inside the callback so the non-Sendable GIDGoogleUser
        // never crosses an actor boundary (StrictConcurrency).
        let email = await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                cont.resume(returning: user?.profile?.email)
            }
        }
        if let email {
            googleFileLog("GoogleAuth.restorePreviousSignIn: restored \(email)")
            return email
        }
        googleFileLog("GoogleAuth.restorePreviousSignIn: no prior session")
        return nil
        #else
        return nil
        #endif
    }

    /// Presents the Google sign-in sheet and requests Gmail + Calendar read scopes.
    /// Returns the signed-in email on success.
    static func signInInteractive() async throws -> String {
        #if canImport(GoogleSignIn) && canImport(AppKit)
        guard GoogleConfig.isConfigured else { throw GoogleAuthError.notConfigured }
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            throw GoogleAuthError.noPresentingWindow
        }
        // Configure the shared signer with our client ID.
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: GoogleConfig.clientID)
        googleFileLog("GoogleAuth.signInInteractive: presenting sheet, clientID=\(GoogleConfig.clientID.prefix(20))…")
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: window,
            hint: nil,
            additionalScopes: GoogleConfig.scopes.filter { !["openid", "email", "profile"].contains($0) }
        )
        let email = result.user.profile?.email ?? "unknown"
        googleFileLog("GoogleAuth.signInInteractive: SUCCESS \(email)")
        return email
        #else
        throw GoogleAuthError.unsupportedPlatform
        #endif
    }

    /// Returns a fresh access token, calling refresh if expired. Throws if no
    /// user is currently signed in.
    static func freshAccessToken() async throws -> String {
        #if canImport(GoogleSignIn)
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleAuthError.noActiveUser
        }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
        #else
        throw GoogleAuthError.unsupportedPlatform
        #endif
    }

    /// Disconnects and clears the cached Google session.
    static func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        googleFileLog("GoogleAuth.signOut: cleared session")
        #endif
    }
}
