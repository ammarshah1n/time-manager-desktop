// AuthService.swift — Timed Core
// Manages Supabase Auth (sign in with Microsoft), executive bootstrap.
// Uses shared SupabaseClient via @Dependency (no inline client creation).
// Dual token: Supabase JWT (database) + MSAL token (Graph API).

import Foundation
import Supabase
import Dependencies
import os

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var executiveId: UUID?
    @Published var userEmail: String?
    @Published var graphAccessToken: String?
    @Published var error: String?
    /// Transient confirmation banner — set on successful sign-in / sign-up, auto-clears after a beat.
    @Published var welcomeMessage: String?

    // Backward compatibility — UI panes still reference these until DataBridge (0.04) refactor
    var profileId: UUID? { executiveId }
    var workspaceId: UUID? { executiveId }
    var emailAccountId: UUID? { executiveId }

    @Dependency(\.supabaseClient) private var supabaseClient

    private var client: SupabaseClient? { supabaseClient.rawClient }

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
            TimedLogger.supabase.info("Session restored for \(session.user.email ?? "unknown", privacy: .private)")
        } catch {
            TimedLogger.supabase.debug("No stored session — user needs to sign in")
            isSignedIn = false
        }
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
            await PlatformURLOpener.open(url)
            TimedLogger.supabase.info("OAuth URL opened for Microsoft sign-in")
        } catch {
            self.error = "Sign-in failed: \(error.localizedDescription)"
            TimedLogger.supabase.error("Microsoft sign-in failed: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
    }

    // MARK: - Handle OAuth callback (from URL scheme timed://auth/callback)

    func handleAuthCallback(url: URL) async {
        guard let client else { return }
        isLoading = true
        do {
            let session = try await client.auth.session(from: url)
            userEmail = session.user.email
            isSignedIn = true
            flashWelcome("Welcome back.")
            await bootstrapExecutive()
            TimedLogger.supabase.info("Signed in as \(session.user.email ?? "unknown", privacy: .private)")
        } catch {
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

    // MARK: - Sign in with Graph (MSAL) for Outlook access

    func signInWithGraph(loginHint: String = "") async {
        isLoading = true
        error = nil
        do {
            @Dependency(\.graphClient) var graphClient
            let token = try await graphClient.authenticate("", loginHint)
            graphAccessToken = token
            TimedLogger.graph.info("Graph OAuth succeeded")
        } catch {
            self.error = "Outlook sign-in failed: \(error.localizedDescription)"
            TimedLogger.graph.error("Graph OAuth failed: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
    }

    // MARK: - Token Provider (auto-refresh)

    func makeTokenProvider() -> @Sendable () async throws -> String {
        return { [weak self] in
            guard let self else { throw TokenProviderError.authServiceDeallocated }
            @Dependency(\.graphClient) var graphClient
            let token = try await graphClient.authenticate("", self.userEmail ?? "")
            await MainActor.run { self.graphAccessToken = token }
            return token
        }
    }

    enum TokenProviderError: Error, LocalizedError {
        case authServiceDeallocated
        var errorDescription: String? {
            switch self {
            case .authServiceDeallocated:
                return "AuthService was deallocated — cannot refresh token"
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
        UserDefaults.standard.removeObject(forKey: PlatformPaths.activeExecutiveDefaultsKey)
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
                // Auth cascade — once Supabase identity is bootstrapped, request a
                // Microsoft Graph token (silent refresh if user previously consented;
                // interactive MSAL prompt otherwise) and kick off email/calendar
                // background sync. Best-effort: graphAccessToken stays nil for
                // email-signup users who decline the MSAL prompt, and the app
                // still functions without Outlook integration.
                await connectOutlookIfPossible(executiveId: executive.id)
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
        guard let email = userEmail, !email.isEmpty else {
            TimedLogger.graph.info("connectOutlookIfPossible: no userEmail yet, skipping")
            return
        }
        await signInWithGraph(loginHint: email)
        guard graphAccessToken != nil else {
            TimedLogger.graph.info("connectOutlookIfPossible: no Graph token after signInWithGraph — Outlook integration deferred")
            return
        }
        // executiveId doubles as workspaceId / emailAccountId / profileId
        // until DataBridge introduces distinct IDs.
        let provider = makeTokenProvider()
        await EmailSyncService.shared.start(
            tokenProvider: provider,
            workspaceId: executiveId,
            emailAccountId: executiveId,
            profileId: executiveId
        )
        await CalendarSyncService.shared.start(tokenProvider: provider)
        TimedLogger.graph.info("Outlook sync started for executive \(executiveId, privacy: .private)")
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
