// AuthService.swift — Timed Core
// Manages Supabase Auth (sign in with Microsoft), executive bootstrap.
// Uses shared SupabaseClient via @Dependency (no inline client creation).
// Dual token: Supabase JWT (database) + MSAL token (Graph API).

import Foundation
import Supabase
import Dependencies
import AppKit
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
            NSWorkspace.shared.open(url)
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
            await bootstrapExecutive()
            TimedLogger.supabase.info("Signed in as \(session.user.email ?? "unknown", privacy: .private)")
        } catch {
            self.error = "Auth callback failed: \(error.localizedDescription)"
            TimedLogger.supabase.error("Auth callback failed: \(error.localizedDescription, privacy: .private)")
        }
        isLoading = false
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
                self.error = nil
                TimedLogger.supabase.info("Executive bootstrapped: \(executive.id, privacy: .private)")
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
