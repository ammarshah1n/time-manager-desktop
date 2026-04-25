// SharingService.swift — Timed Core
// Actor managing workspace sharing: invite links, PA members, realtime subscriptions.
// All Supabase access is routed through SupabaseClientDependency — no direct imports.

import Foundation
import Dependencies
import os

// MARK: - Row Types

struct WorkspaceInviteRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let code: String
    let createdBy: UUID
    let expiresAt: Date?
    let isRevoked: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case code
        case createdBy = "created_by"
        case expiresAt = "expires_at"
        case isRevoked = "is_revoked"
    }
}

struct PAMember: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let email: String
    let fullName: String?
    let role: String  // "pa" | "owner" | "member"
}

// MARK: - Service

actor SharingService {
    static let shared = SharingService()

    private let logger = TimedLogger.sharing
    private var isConnected: Bool
    @Dependency(\.supabaseClient) private var supabase

    private init() {
        let urlString = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
        isConnected = !urlString.contains("fake.supabase.co")
    }

    // MARK: - Invite Links

    /// Generate a shareable invite link for a workspace.
    /// Returns a `timed://invite/{code}` URL.
    func generateInviteLink(workspaceId: UUID) async throws -> URL {
        guard isConnected else {
            logger.warning("Supabase not connected — cannot generate invite link")
            throw SharingError.notConnected
        }

        let code = UUID()
        logger.info("Generated invite code for workspace \(workspaceId.uuidString, privacy: .public)")

        try await supabase.insertWorkspaceInvite(workspaceId, code)

        return URL(string: "timed://invite/\(code)")!
    }

    /// Accept an invite and join a workspace.
    func acceptInvite(code: String, profileId: UUID) async throws {
        guard isConnected else {
            logger.warning("Supabase not connected — cannot accept invite")
            throw SharingError.notConnected
        }

        logger.info("Accepting invite code \(code, privacy: .private) for profile \(profileId.uuidString, privacy: .public)")

        // TODO: Validate invite code against workspace_invites table,
        // then insert workspace_members row via SupabaseClientDependency.
    }

    /// Fetch active PA members for a workspace.
    func fetchPAMembers(workspaceId: UUID) async throws -> [PAMember] {
        guard isConnected else {
            logger.warning("Supabase not connected — returning empty PA members")
            return []
        }

        logger.info("Fetching PA members for workspace \(workspaceId.uuidString, privacy: .public)")

        let rows = try await supabase.fetchWorkspaceMembers(workspaceId)
        return rows.map { row in
            PAMember(
                id: row.id,
                email: row.email ?? "unknown@example.com",
                fullName: row.fullName,
                role: row.role
            )
        }
    }

    /// Remove a member from a workspace.
    func removeMember(memberId: UUID, workspaceId: UUID) async throws {
        guard isConnected else {
            logger.warning("Supabase not connected — cannot remove member")
            throw SharingError.notConnected
        }

        logger.info("Removing member \(memberId.uuidString, privacy: .public) from workspace \(workspaceId.uuidString, privacy: .public)")

        try await supabase.deleteWorkspaceMember(memberId)
    }

    // MARK: - Realtime

    /// Subscribe to real-time task changes for PA view.
    /// The callback fires whenever tasks are inserted, updated, or deleted.
    func subscribeToTaskChanges(
        workspaceId: UUID,
        onChange: @escaping @Sendable () -> Void
    ) async {
        guard isConnected else {
            logger.warning("Supabase not connected — skipping realtime subscription")
            return
        }

        logger.info("Setting up realtime subscription for workspace \(workspaceId.uuidString, privacy: .public)")

        await supabase.subscribeToTaskChanges(workspaceId, onChange)
    }

    // MARK: - Connection Status

    var connectionStatus: Bool { isConnected }
}

// MARK: - Errors

enum SharingError: LocalizedError, Sendable {
    case notConnected
    case invalidURL
    case inviteExpired
    case inviteRevoked
    case alreadyMember

    var errorDescription: String? {
        switch self {
        case .notConnected: "Supabase is not connected. Enable Supabase to use sharing."
        case .invalidURL:   "Failed to generate a valid invite URL."
        case .inviteExpired: "This invite link has expired."
        case .inviteRevoked: "This invite link has been revoked."
        case .alreadyMember: "This user is already a member of the workspace."
        }
    }
}
