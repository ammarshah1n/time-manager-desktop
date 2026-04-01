// AuthService.swift — Timed Core
// Manages Supabase Auth (sign in with Microsoft), workspace + profile bootstrap.
// Stores session state. All auth flows go through here.

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
    @Published var workspaceId: UUID?
    @Published var profileId: UUID?
    @Published var emailAccountId: UUID?
    @Published var userEmail: String?
    @Published var graphAccessToken: String?
    @Published var error: String?

    private var client: SupabaseClient? {
        let urlString = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
        let anonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZwbWp1dWZlZmh0bHdiZmlueGx4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5MTMxMDEsImV4cCI6MjA5MDQ4OTEwMX0.VUtjezhFMpwrcVMXltyYmU2n0Xazi9lvhuwAQlKOTO4"
        guard let url = URL(string: urlString), !urlString.contains("fake.supabase.co") else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    // MARK: - Restore session on launch

    func restoreSession() async {
        guard let client else {
            TimedLogger.supabase.info("No Supabase configured — local-only mode")
            return
        }
        do {
            let session = try await client.auth.session
            profileId = session.user.id
            userEmail = session.user.email
            isSignedIn = true
            await bootstrapWorkspace()
            TimedLogger.supabase.info("Session restored for \(session.user.email ?? "unknown", privacy: .public)")
        } catch {
            TimedLogger.supabase.debug("No stored session — user needs to sign in")
            isSignedIn = false
        }
    }

    // MARK: - Sign in with Microsoft (Azure provider)

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
                scopes: "email profile openid",
                redirectTo: URL(string: "timed://auth/callback")
            )
            // Open the OAuth URL in default browser
            #if canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
            // The callback will be handled by handleAuthCallback
            TimedLogger.supabase.info("OAuth URL opened for Microsoft sign-in")
        } catch {
            self.error = "Sign-in failed: \(error.localizedDescription)"
            TimedLogger.supabase.error("Microsoft sign-in failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    // MARK: - Handle OAuth callback (from URL scheme timed://auth/callback)

    func handleAuthCallback(url: URL) async {
        guard let client else { return }
        isLoading = true
        do {
            let session = try await client.auth.session(from: url)
            profileId = session.user.id
            userEmail = session.user.email
            isSignedIn = true
            await bootstrapWorkspace()
            TimedLogger.supabase.info("Signed in as \(session.user.email ?? "unknown", privacy: .public)")
        } catch {
            self.error = "Auth callback failed: \(error.localizedDescription)"
            TimedLogger.supabase.error("Auth callback failed: \(error.localizedDescription, privacy: .public)")
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
            TimedLogger.graph.error("Graph OAuth failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    // MARK: - Sign out

    func signOut() async {
        guard let client else { return }
        do {
            try await client.auth.signOut()
        } catch {
            TimedLogger.supabase.error("Sign-out error: \(error.localizedDescription, privacy: .public)")
        }
        isSignedIn = false
        profileId = nil
        workspaceId = nil
        emailAccountId = nil
        userEmail = nil
        graphAccessToken = nil
    }

    // MARK: - Bootstrap workspace + profile on first sign-in

    private func bootstrapWorkspace() async {
        guard let client, let profileId else { return }
        do {
            // Check if profile exists
            let profiles: [ProfileRow] = try await client
                .from("profiles")
                .select()
                .eq("id", value: profileId)
                .execute()
                .value

            if profiles.isEmpty {
                // Create profile
                let newProfile = ProfileInsert(
                    id: profileId,
                    email: userEmail ?? "",
                    fullName: nil,
                    timezone: TimeZone.current.identifier
                )
                try await client.from("profiles").insert(newProfile).execute()
                TimedLogger.supabase.info("Created profile for \(self.userEmail ?? "unknown", privacy: .public)")
            }

            // Check for workspace membership
            let memberships: [WorkspaceMemberRow] = try await client
                .from("workspace_members")
                .select()
                .eq("profile_id", value: profileId)
                .execute()
                .value

            if let first = memberships.first {
                workspaceId = first.workspaceId
            } else {
                // Create workspace + membership
                let wsId = UUID()
                let ws = WorkspaceInsert(id: wsId, name: "My Workspace", slug: userEmail?.components(separatedBy: "@").first ?? "default", plan: "solo")
                try await client.from("workspaces").insert(ws).execute()

                let member = WorkspaceMemberInsert(workspaceId: wsId, profileId: profileId, role: "owner")
                try await client.from("workspace_members").insert(member).execute()

                workspaceId = wsId
                TimedLogger.supabase.info("Created workspace \(wsId, privacy: .public)")
            }
            // Bootstrap email account
            guard let wsId = workspaceId else { return }
            let accounts: [EmailAccountRow] = try await client
                .from("email_accounts")
                .select()
                .eq("workspace_id", value: wsId)
                .eq("profile_id", value: profileId)
                .limit(1)
                .execute()
                .value

            if let first = accounts.first {
                emailAccountId = first.id
            } else {
                let eaId = UUID()
                let ea = EmailAccountInsert(
                    id: eaId, workspaceId: wsId, profileId: profileId,
                    provider: "outlook", providerAccountId: userEmail ?? "unknown",
                    emailAddress: userEmail ?? ""
                )
                try await client.from("email_accounts").insert(ea).execute()
                emailAccountId = eaId
                TimedLogger.supabase.info("Created email account \(eaId, privacy: .public)")
            }
        } catch {
            TimedLogger.supabase.error("Bootstrap failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Row types for auth bootstrap

private struct ProfileRow: Codable, Sendable {
    let id: UUID
    let email: String
}

private struct ProfileInsert: Codable, Sendable {
    let id: UUID
    let email: String
    let fullName: String?
    let timezone: String
    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
        case timezone
    }
}

private struct WorkspaceInsert: Codable, Sendable {
    let id: UUID
    let name: String
    let slug: String
    let plan: String
}

private struct WorkspaceMemberInsert: Codable, Sendable {
    let workspaceId: UUID
    let profileId: UUID
    let role: String
    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case role
    }
}

private struct EmailAccountRow: Codable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID?
    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
    }
}

private struct EmailAccountInsert: Codable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let provider: String
    let providerAccountId: String
    let emailAddress: String
    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case provider
        case providerAccountId = "provider_account_id"
        case emailAddress = "email_address"
    }
}
