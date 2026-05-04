// AuthService.swift — Timed Core
// Manages Supabase Auth (sign in with Microsoft), executive bootstrap.
// Uses shared SupabaseClient via @Dependency (no inline client creation).
// Dual token: Supabase JWT (database) + MSAL token (Graph API).

import Foundation
import Supabase
import Dependencies
import os
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var executiveId: UUID?
    @Published var userEmail: String?
    @Published var graphAccessToken: String?
    /// Email of the currently signed-in Google account (Gmail + Calendar).
    /// nil until `signInWithGoogle()` succeeds or `restoreSession` finds a
    /// prior GoogleSignIn keychain entry.
    @Published var googleEmail: String?
    /// Cached most-recent Google access token. Sync services should NOT use
    /// this directly — call `makeGoogleTokenProvider()` instead so refresh
    /// happens silently before each request.
    @Published var googleAccessToken: String?
    @Published var error: String?
    /// Transient confirmation banner — set on successful sign-in / sign-up, auto-clears after a beat.
    @Published var welcomeMessage: String?
    @Published var pendingInviteCode: String?
    @Published var availableWorkspaces: [UserWorkspaceRow] = []
    @Published var activeWorkspaceId: UUID?

    // Backward compatibility — UI panes still reference these until DataBridge (0.04) refactor
    var profileId: UUID? { executiveId }
    var workspaceId: UUID? { executiveId }
    var activeOrPrimaryWorkspaceId: UUID? { activeWorkspaceId ?? workspaceId }
    var emailAccountId: UUID? { executiveId }

    @Dependency(\.supabaseClient) private var supabaseClient

    private var client: SupabaseClient? { supabaseClient.rawClient }
    private let pendingInviteKey = "pendingInviteCode"
    private let activeWorkspaceKey = "activeWorkspaceId"

    /// Last URL successfully passed through `handleAuthCallback`. Prevents the
    /// double-exchange race where ASWebAuthenticationSession's completion AND
    /// the OS scheme handler both fire `handleAuthCallback` for the same
    /// redirect URL — the second call would attempt to exchange an already-
    /// redeemed code, fail, and flip `isSignedIn=false` mid-bootstrap.
    private var lastHandledCallbackURL: URL?

    // MARK: - Restore session on launch

    func restoreSession() async {
        guard let client else {
            TimedLogger.supabase.info("No Supabase configured — local-only mode")
            return
        }
        do {
            let session = try await client.auth.session
            userEmail = session.user.email
            isSignedIn = true
            await bootstrapExecutive()
            await finishBootstrapSideEffects()
            TimedLogger.supabase.info("Session restored for \(session.user.email ?? "unknown", privacy: .private)")
        } catch {
            TimedLogger.supabase.debug("No stored session — user needs to sign in")
            isSignedIn = false
        }
        // Attempt Google silent restore in parallel with the Supabase session.
        // Independent of the Supabase identity — a user can have Google linked
        // even before Supabase Auth is set up (single-user dev path).
        if let email = await GoogleAuth.restorePreviousSignIn() {
            googleEmail = email
            do {
                googleAccessToken = try await GoogleAuth.freshAccessToken()
                googleFileLog("AuthService.restoreSession: Google session restored for \(email)")
                if let executiveId {
                    await connectGmailIfPossible(executiveId: executiveId)
                }
            } catch {
                googleFileLog("AuthService.restoreSession: Google token refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func setPendingInviteCode(_ code: String) {
        let normalised = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalised.isEmpty else { return }
        pendingInviteCode = normalised
        UserDefaults.standard.set(normalised, forKey: pendingInviteKey)
    }

    func clearPendingInviteCode() {
        pendingInviteCode = nil
        UserDefaults.standard.removeObject(forKey: pendingInviteKey)
    }

    func loadPendingInviteCodeFromDefaults() {
        if let code = UserDefaults.standard.string(forKey: pendingInviteKey), !code.isEmpty {
            pendingInviteCode = code
        }
    }

    func reloadAvailableWorkspaces() async {
        do {
            let rows = try await supabaseClient.fetchUserWorkspaces()
            availableWorkspaces = rows
            if activeWorkspaceId == nil || !rows.contains(where: { $0.id == activeWorkspaceId }) {
                if let saved = UserDefaults.standard.string(forKey: activeWorkspaceKey),
                   let id = UUID(uuidString: saved),
                   rows.contains(where: { $0.id == id }) {
                    activeWorkspaceId = id
                } else {
                    activeWorkspaceId = rows.first(where: { $0.role == "owner" })?.id ?? rows.first?.id ?? executiveId
                }
            }
        } catch {
            TimedLogger.supabase.error("reloadAvailableWorkspaces failed: \(error.localizedDescription, privacy: .private)")
            if activeWorkspaceId == nil { activeWorkspaceId = executiveId }
        }
    }

    func switchWorkspace(to id: UUID) async {
        guard activeWorkspaceId != id else { return }
        // Order matters: clear caches first, then flip the active workspace id.
        await DataBridge.shared.handleWorkspaceSwitch()
        activeWorkspaceId = id
        UserDefaults.standard.set(id.uuidString, forKey: activeWorkspaceKey)
    }

    private func finishBootstrapSideEffects() async {
        await reloadAvailableWorkspaces()
        loadPendingInviteCodeFromDefaults()
    }

    // MARK: - Sign in with Microsoft (Azure provider via Supabase OAuth)

    func signInWithMicrosoft() async {
        guard let client else {
            self.error = "Supabase not configured"
            return
        }
        isLoading = true
        error = nil
        do {
            let url = try await client.auth.getOAuthSignInURL(
                provider: .azure,
                scopes: "email profile openid Mail.Read Calendars.Read offline_access",
                redirectTo: URL(string: "timed://auth/callback")
            )

            #if canImport(AuthenticationServices) && os(macOS)
            // Replaces the previous "open in default browser" path. Default-browser
            // OAuth caches state across attempts (HANDOFF.md known issue: same
            // `code` value reproduces every click → Supabase rejects code exchange).
            // ASWebAuthenticationSession with prefersEphemeralWebBrowserSession=true
            // gives every attempt a clean cookie jar, and the callback comes back
            // through the completion handler rather than relying on the URL scheme
            // handler (which still works as a fallback for any external return).
            let callbackURL = try await Self.startWebAuthSession(
                authURL: url,
                callbackScheme: "timed",
                presentationContext: AuthService.SharedPresentationContext.shared
            )
            await handleAuthCallback(url: callbackURL)
            TimedLogger.supabase.info("ASWebAuthenticationSession completed for Microsoft sign-in")
            #else
            await PlatformURLOpener.open(url)
            TimedLogger.supabase.info("OAuth URL opened for Microsoft sign-in (legacy browser path)")
            #endif
        } catch {
            self.error = "Sign-in failed: \(error.localizedDescription)"
            TimedLogger.supabase.error("Microsoft sign-in failed: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
    }

    #if canImport(AuthenticationServices) && os(macOS)
    /// Wraps `ASWebAuthenticationSession` start/completion in a checked
    /// continuation. The session is created and started on `@MainActor`
    /// (Apple requires this), but the completion handler is invoked from a
    /// background XPC reply queue (`com.apple.NSXPCConnection.m-user.com.apple.SafariLaunchAgent`).
    /// The completion closure must therefore be `@Sendable` — without the
    /// explicit type annotation Swift 6 inherits the enclosing function's
    /// `@MainActor` isolation onto the closure, and the XPC dispatch trips
    /// `_swift_task_checkIsolatedSwift` → `dispatch_assert_queue` → SIGTRAP.
    @MainActor
    private static func startWebAuthSession(
        authURL: URL,
        callbackScheme: String,
        presentationContext: ASWebAuthenticationPresentationContextProviding
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            // Explicit @Sendable closure type — breaks MainActor isolation
            // inheritance from the enclosing @MainActor static func.
            // CheckedContinuation is Sendable, so capture is safe.
            let completionHandler: @Sendable (URL?, Error?) -> Void = { url, error in
                if let url = url {
                    cont.resume(returning: url)
                } else if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(throwing: URLError(.badServerResponse))
                }
            }
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme,
                completionHandler: completionHandler
            )
            session.presentationContextProvider = presentationContext
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }

    /// Tiny shim so `ASWebAuthenticationSession` knows which window to anchor
    /// to. Returns the key window from the active NSApplication.
    /// `presentationAnchor(for:)` is documented to be invoked on the main
    /// thread by ASWebAuthenticationSession — `MainActor.assumeIsolated`
    /// asserts that contract instead of deadlocking via `DispatchQueue.main.sync`.
    final class SharedPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
        static let shared = SharedPresentationContext()
        nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            #if canImport(AppKit)
            return MainActor.assumeIsolated {
                NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
            }
            #else
            return ASPresentationAnchor()
            #endif
        }
    }
    #endif

    // MARK: - Handle OAuth callback (from URL scheme timed://auth/callback)

    func handleAuthCallback(url: URL) async {
        guard let client else { return }
        // Idempotency: drop duplicate callbacks for the same URL. ASWebAuth
        // completion + OS scheme handler may both fire; we only want to
        // exchange the OAuth code once.
        if let last = lastHandledCallbackURL, last == url {
            TimedLogger.supabase.info("handleAuthCallback: duplicate URL ignored")
            return
        }
        lastHandledCallbackURL = url
        isLoading = true
        do {
            let session = try await client.auth.session(from: url)
            userEmail = session.user.email
            isSignedIn = true
            flashWelcome("Welcome back.")
            await bootstrapExecutive()
            await finishBootstrapSideEffects()
            TimedLogger.supabase.info("Signed in as \(session.user.email ?? "unknown", privacy: .private)")
        } catch {
            // Reset to a clean signed-out state so LoginView re-renders cleanly
            // and a fresh attempt isn't blocked by the idempotency guard.
            lastHandledCallbackURL = nil
            isSignedIn = false
            userEmail = nil
            self.error = "Auth callback failed: \(error.localizedDescription)"
            TimedLogger.supabase.error("Auth callback failed: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
    }

    /// Show a brief welcome banner that auto-clears after ~1.4s. Cancels any pending clear.
    private func flashWelcome(_ message: String) {
        welcomeMessage = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            // Only clear if it's still the same message — don't stomp on a newer one.
            guard let self, self.welcomeMessage == message else { return }
            self.welcomeMessage = nil
        }
    }

    // MARK: - Email + password sign in / sign up

    func signInWithEmail(_ email: String, password: String) async {
        guard let client else {
            self.error = "Sign-in is unavailable right now."
            return
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !password.isEmpty else {
            self.error = "Enter your email and password."
            return
        }
        isLoading = true
        error = nil
        do {
            let session = try await client.auth.signIn(email: trimmed, password: password)
            userEmail = session.user.email
            isSignedIn = true
            flashWelcome("Welcome back.")
            await bootstrapExecutive()
            await finishBootstrapSideEffects()
            TimedLogger.supabase.info("Signed in (email) as \(session.user.email ?? "unknown", privacy: .private)")
        } catch {
            self.error = friendlyMessage(for: error, fallback: "Sign-in failed. Check your email and password.")
            TimedLogger.supabase.error("Email sign-in failed: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
    }

    func signUpWithEmail(_ email: String, password: String) async {
        guard let client else {
            self.error = "Account creation is unavailable right now."
            return
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, password.count >= 8 else {
            self.error = "Use a valid email and a password of at least 8 characters."
            return
        }
        isLoading = true
        error = nil
        do {
            let response = try await client.auth.signUp(email: trimmed, password: password)
            if response.session != nil {
                userEmail = response.user.email
                isSignedIn = true
                flashWelcome("Welcome to Timed.")
                await bootstrapExecutive()
                await finishBootstrapSideEffects()
                TimedLogger.supabase.info("Account created + signed in (email) as \(response.user.email ?? "unknown", privacy: .private)")
            } else {
                self.error = "Account created. Check your inbox to confirm your email, then sign in."
                TimedLogger.supabase.info("Account created, awaiting email confirmation")
            }
        } catch {
            self.error = friendlyMessage(for: error, fallback: "Couldn't create the account. Try a different email.")
            TimedLogger.supabase.error("Email sign-up failed: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
    }

    func sendPasswordReset(email: String) async {
        guard let client else {
            self.error = "Password reset is unavailable right now."
            return
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            self.error = "Enter your email first."
            return
        }
        isLoading = true
        error = nil
        do {
            try await client.auth.resetPasswordForEmail(
                trimmed,
                redirectTo: URL(string: "timed://auth/callback")
            )
            self.error = "Password reset email sent. Check your inbox."
            TimedLogger.supabase.info("Password reset emailed to \(trimmed, privacy: .private)")
        } catch {
            self.error = friendlyMessage(for: error, fallback: "Couldn't send reset email.")
            TimedLogger.supabase.error("Password reset failed: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
    }

    private func friendlyMessage(for error: Error, fallback: String) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("invalid login") || raw.contains("invalid_credentials") {
            return "That email and password don't match an account."
        }
        if raw.contains("already registered") || raw.contains("user already") {
            return "An account with that email already exists. Try signing in."
        }
        if raw.contains("rate") {
            return "Too many attempts. Wait a moment and try again."
        }
        return fallback
    }

    // MARK: - Sign in with Google (Gmail + Calendar)

    /// Presents the Google sign-in sheet and stores the resulting access token.
    /// Best-effort: does not bridge into Supabase identity (Phase B-2.5 work).
    /// Once a token is stored, callers should fire `connectGmailIfPossible` to
    /// kick off the background sync services.
    func signInWithGoogle() async {
        isLoading = true
        error = nil
        googleFileLog("AuthService.signInWithGoogle: ENTER")
        do {
            let email = try await GoogleAuth.signInInteractive()
            googleEmail = email
            googleAccessToken = try await GoogleAuth.freshAccessToken()
            googleFileLog("AuthService.signInWithGoogle: token set ✅ (email=\(email))")
            TimedLogger.graph.info("Google OAuth succeeded")
            // If we already have an executive, kick off Gmail sync now —
            // otherwise bootstrapExecutive will pick this up on its next
            // cascade.
            if let executiveId {
                await connectGmailIfPossible(executiveId: executiveId)
            }
        } catch {
            self.error = friendlyGoogleMessage(for: error)
            googleFileLog("AuthService.signInWithGoogle: THREW: \(error.localizedDescription)")
            TimedLogger.graph.error("Google OAuth failed: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
    }

    private func friendlyGoogleMessage(for error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("cancel") {
            return "Gmail connection was cancelled."
        }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return "Couldn't connect Gmail. Try again."
    }

    /// Returns a Google token provider closure that auto-refreshes via
    /// `GoogleAuth.freshAccessToken()` before each call. Mirrors
    /// `makeTokenProvider()` for Microsoft, but with a critical difference:
    /// GoogleSignIn-iOS handles silent refresh internally and works on
    /// ad-hoc-signed builds (different keychain partition), so we do NOT
    /// need the in-memory band-aid the Microsoft side carries.
    func makeGoogleTokenProvider() -> @Sendable () async throws -> String {
        return { [weak self] in
            guard self != nil else { throw TokenProviderError.authServiceDeallocated }
            // Always go through GoogleAuth.freshAccessToken so silent refresh
            // happens before each request. The @Published googleAccessToken
            // is just for UI debug surface; sync services use this closure.
            let token = try await GoogleAuth.freshAccessToken()
            // Update the published mirror on MainActor so PrefsPane stays
            // in sync, but don't await it for performance.
            Task { @MainActor [weak self] in
                self?.googleAccessToken = token
            }
            return token
        }
    }

    // MARK: - Sign in with Graph (MSAL) for Outlook access

    func signInWithGraph(loginHint: String = "") async {
        isLoading = true
        error = nil
        graphFileLog("AuthService.signInWithGraph: ENTER (hint='\(loginHint)')")
        do {
            @Dependency(\.graphClient) var graphClient
            let token = try await graphClient.authenticate("", loginHint)
            graphAccessToken = token
            graphFileLog("AuthService.signInWithGraph: token set ✅ (len=\(token.count))")
            TimedLogger.graph.info("Graph OAuth succeeded")
        } catch {
            self.error = "Outlook sign-in failed: \(error.localizedDescription)"
            graphFileLog("AuthService.signInWithGraph: THREW: \(error.localizedDescription)")
            TimedLogger.graph.error("Graph OAuth failed: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
    }

    // MARK: - Token Provider (auto-refresh)

    func makeTokenProvider() -> @Sendable () async throws -> String {
        return { [weak self] in
            guard let self else { throw TokenProviderError.authServiceDeallocated }
            // Return the in-memory token. Calling MSAL `authenticate` here
            // would trigger a fresh interactive sheet because ad-hoc-signed
            // builds on macOS Tahoe cannot write to the MSAL keychain group
            // (the silent-refresh cache that should have been populated by
            // the initial sign-in fails with `-34018 / Failed to find
            // keychain item`). Without this guard, every Graph API call
            // re-fired the MSAL interactive flow, looping the user through
            // "trust this app" prompts.
            //
            // Trade-off: when the access token expires (~1 h) Graph calls
            // start returning 401. The user re-connects via Settings →
            // Connect Outlook (or by re-launching). Switch to silent refresh
            // after Apple Developer Program enrollment lands proper
            // code-signing + keychain entitlements (HANDOFF Chain C).
            let cached = await MainActor.run { self.graphAccessToken }
            guard let token = cached, !token.isEmpty else {
                throw TokenProviderError.tokenUnavailable
            }
            return token
        }
    }

    enum TokenProviderError: Error, LocalizedError {
        case authServiceDeallocated
        case tokenUnavailable
        var errorDescription: String? {
            switch self {
            case .authServiceDeallocated:
                return "AuthService was deallocated — cannot refresh token"
            case .tokenUnavailable:
                return "Microsoft access token unavailable — sign in via Settings → Connect Outlook"
            }
        }
    }

    // MARK: - Sign out

    func signOut() async {
        // Halt every background loop that holds session-bearing state BEFORE
        // we tear down the Supabase session, so no in-flight sync writes leak
        // post-sign-out events. Order matters: stop producers, then sign out.
        await EmailSyncService.shared.stop()
        await CalendarSyncService.shared.stop()
        await GmailSyncService.shared.stop()
        await GmailCalendarSyncService.shared.stop()
        GoogleAuth.signOut()

        guard let client else { return }
        do {
            try await client.auth.signOut()
        } catch {
            TimedLogger.supabase.error("Sign-out error: \(error.localizedDescription, privacy: .private)")
        }
        isSignedIn = false
        executiveId = nil
        userEmail = nil
        graphAccessToken = nil
        googleAccessToken = nil
        googleEmail = nil
        activeWorkspaceId = nil
        availableWorkspaces = []
        lastHandledCallbackURL = nil
        UserDefaults.standard.removeObject(forKey: PlatformPaths.activeExecutiveDefaultsKey)
        UserDefaults.standard.removeObject(forKey: activeWorkspaceKey)
    }

    // MARK: - Bootstrap executive on first sign-in

    private func bootstrapExecutive() async {
        guard let client else { return }
        // Retry with exponential backoff — cold-start Edge Functions can fail on first call
        let delays: [UInt64] = [2_000_000_000, 4_000_000_000, 8_000_000_000] // 2s, 4s, 8s
        for attempt in 0...2 {
            do {
                let executive: ExecutiveResponse = try await client.functions.invoke(
                    "bootstrap-executive",
                    options: .init(method: .post)
                )
                executiveId = executive.id
                UserDefaults.standard.set(
                    executive.id.uuidString,
                    forKey: PlatformPaths.activeExecutiveDefaultsKey
                )
                // Track first-bootstrap timestamp so cold-start UX surfaces (Today's
                // empty state, MorningBriefing copy) can distinguish "still backfilling
                // their inbox" from "genuinely-empty Day 3 morning".
                if UserDefaults.standard.object(forKey: "auth.firstBootstrappedAt") == nil {
                    UserDefaults.standard.set(Date(), forKey: "auth.firstBootstrappedAt")
                }
                self.error = nil
                TimedLogger.supabase.info("Executive bootstrapped: \(executive.id, privacy: .private)")
                // Do not auto-present Microsoft Graph auth here. On current
                // ad-hoc builds MSAL cannot persist its keychain cache, so
                // bootstrap would ask for Outlook again on every launch.
                // Settings -> Connect Outlook remains the explicit path.
                // Parallel cascade for Google. Best-effort; if no Google
                // session is restored / signed-in, this is a no-op.
                await connectGmailIfPossible(executiveId: executive.id)
                return
            } catch {
                TimedLogger.supabase.error("Executive bootstrap attempt \(attempt + 1) failed: \(error.localizedDescription, privacy: .private)")
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: delays[attempt])
                }
            }
        }
        self.error = "Could not reach Timed servers. Check your connection and restart the app."
    }

    /// Manual retry for bootstrap — callable from Settings or error banner
    func retryBootstrap() async {
        isLoading = true
        error = nil
        await bootstrapExecutive()
        await finishBootstrapSideEffects()
        isLoading = false
    }

    /// Re-presents the voice onboarding sheet on the next view update by clearing
    /// the AppStorage flag. Used by Preferences → "Resume voice setup".
    func replayOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(false, forKey: "pendingVoiceOnboarding")
    }

    /// Auth cascade — fires Graph (MSAL) sign-in and starts email + calendar
    /// background sync. Called from bootstrapExecutive() and the explicit
    /// "Connect Outlook" Preferences action. Idempotent and best-effort: if
    /// MSAL fails or the user declines, graphAccessToken stays nil and the
    /// app proceeds without Outlook integration.
    func connectOutlookIfPossible(executiveId: UUID) async {
        graphFileLog("connectOutlookIfPossible: ENTER (exec=\(executiveId))")
        guard let email = userEmail, !email.isEmpty else {
            graphFileLog("connectOutlookIfPossible: SKIP — no userEmail")
            return
        }
        graphFileLog("connectOutlookIfPossible: calling signInWithGraph(hint=\(email))")
        await signInWithGraph(loginHint: email)
        guard graphAccessToken != nil else {
            graphFileLog("connectOutlookIfPossible: no Graph token → Outlook deferred (graphAccessToken is nil)")
            return
        }
        graphFileLog("connectOutlookIfPossible: starting EmailSync + CalendarSync")
        let provider = makeTokenProvider()
        await EmailSyncService.shared.start(
            tokenProvider: provider,
            workspaceId: executiveId,
            emailAccountId: executiveId,
            profileId: executiveId
        )
        await CalendarSyncService.shared.start(tokenProvider: provider)
        graphFileLog("connectOutlookIfPossible: SYNC STARTED ✅")
    }

    /// Auth cascade for Google. Mirror of `connectOutlookIfPossible` —
    /// idempotent and best-effort. Assumes the user has already signed in
    /// to Google (either earlier in the session or via restore on launch).
    /// If `googleAccessToken` is nil, this is a no-op.
    func connectGmailIfPossible(executiveId: UUID) async {
        googleFileLog("connectGmailIfPossible: ENTER (exec=\(executiveId)) googleEmail=\(googleEmail ?? "nil")")
        guard googleAccessToken != nil else {
            googleFileLog("connectGmailIfPossible: SKIP — no Google access token (user must sign in)")
            return
        }
        if let email = googleEmail, !email.isEmpty {
            await recordGoogleAccountLink(email: email, executiveId: executiveId)
        }
        let provider = makeGoogleTokenProvider()
        await GmailSyncService.shared.start(
            tokenProvider: provider,
            workspaceId: executiveId,
            emailAccountId: executiveId,
            profileId: executiveId
        )
        await GmailCalendarSyncService.shared.start(tokenProvider: provider)
        googleFileLog("connectGmailIfPossible: SYNC STARTED ✅")
    }

    private func recordGoogleAccountLink(email: String, executiveId: UUID) async {
        guard let client else { return }
        struct GoogleAccountLinkUpdate: Encodable, Sendable {
            let google_email: String
        }
        do {
            try await client
                .from("executives")
                .update(GoogleAccountLinkUpdate(google_email: email))
                .eq("id", value: executiveId.uuidString)
                .execute()
            googleFileLog("recordGoogleAccountLink: saved google_email for \(executiveId)")
        } catch {
            googleFileLog("recordGoogleAccountLink: failed \(error.localizedDescription)")
            TimedLogger.graph.warning("Failed to save linked Gmail address: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Response types

private struct ExecutiveResponse: Codable, Sendable {
    let id: UUID
    let displayName: String
    let email: String
    let timezone: String
    let onboardedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email, timezone
        case onboardedAt = "onboarded_at"
    }
}
