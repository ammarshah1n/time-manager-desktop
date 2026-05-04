import Testing
import Foundation
@testable import TimedKit

@Suite("PA role RLS boundary")
struct PARoleRLSGuardTests {
    static let hardeningMigration = "supabase/migrations/20260504101000_harden_pa_invite_boundary.sql"

    static let deniedWorkspaceTables = [
        "email_messages",
        "email_accounts",
        "email_triage_corrections",
        "sender_rules",
        "sender_social_graph",
        "behaviour_events",
        "behaviour_rules",
        "user_profiles",
        "estimation_history",
        "waiting_items",
        "bucket_completion_stats",
        "bucket_estimates",
        "voice_capture_items",
        "voice_captures",
        "estimate_priors",
        "ai_pipeline_runs",
        "daily_plans",
        "plan_items"
    ]

    @Test("PA hardening migration declares every denied workspace table")
    func everyDeniedWorkspaceTableIsDeclared() throws {
        let sql = try source(Self.hardeningMigration)
        for table in Self.deniedWorkspaceTables {
            #expect(sql.contains("'\(table)'"), "PA deny boundary missing table: \(table)")
        }
    }

    @Test("PA hardening migration blocks reads and writes")
    func hardeningPolicyBlocksAllCommands() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("as restrictive for all"),
                "PA policy must be FOR ALL so direct API writes cannot bypass the privacy boundary")
        #expect(sql.contains("with check"),
                "PA policy must include WITH CHECK so INSERT and UPDATE are denied")
    }

    @Test("Invite revocation is narrowed to an RPC")
    func inviteRevocationUsesRPC() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("drop policy if exists \"workspace_invites_update_owner\""),
                "Broad workspace_invites UPDATE policy must be removed")
        #expect(sql.contains("create or replace function public.revoke_workspace_invite"),
                "Revocation must go through a narrow RPC")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }
}
