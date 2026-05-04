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

    @Test("PA hardening migration covers behaviour event partitions")
    func hardeningPolicyCoversBehaviourEventPartitions() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("from pg_inherits"),
                "PA deny boundary must cover direct behaviour_events partition access")
        #expect(sql.contains("inhparent = 'public.behaviour_events'::regclass"),
                "Behaviour event partition coverage must discover children from the parent relation")
        #expect(sql.contains("alter table %s force row level security"),
                "Behaviour event partitions must keep forced RLS enabled")
    }

    @Test("Top observations RPC is caller scoped")
    func topObservationsRPCIsCallerScoped() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("create or replace function public.get_top_observations"),
                "PA hardening must override the security-definer observation RPC")
        #expect(sql.contains("auth.role() = 'service_role'"),
                "Service-role jobs must remain able to call get_top_observations")
        #expect(sql.contains("p_exec_id = public.get_executive_id(auth.uid())"),
                "Authenticated users must only request their own top observations")
    }

    @Test("Invite revocation is narrowed to an RPC")
    func inviteRevocationUsesRPC() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("drop policy if exists \"workspace_invites_update_owner\""),
                "Broad workspace_invites UPDATE policy must be removed")
        #expect(sql.contains("create or replace function public.revoke_workspace_invite"),
                "Revocation must go through a narrow RPC")
    }

    @Test("PA task completion cannot write estimation side effects")
    func paTaskCompletionCannotWriteEstimationSideEffects() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("create or replace function public.trg_insert_estimation_history()"),
                "PA hardening must override the SECURITY DEFINER task completion trigger")
        #expect(sql.contains("new.workspace_id = any(public.pa_workspace_ids())"),
                "Task completion trigger must detect PA callers before writing cognitive history")
        #expect(sql.contains("old.workspace_id = any(public.pa_workspace_ids())"),
                "Task completion trigger must also block PA-origin tasks moved to another workspace")
        #expect(sql.contains("return new;\n  end if;\n\n  if new.actual_minutes is not null"),
                "Task completion trigger must exit before the estimation_history insert for PA callers")
        #expect(sql.contains("insert into public.estimation_history"),
                "Owner/service task completion history must continue to work outside the PA guard")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }
}
