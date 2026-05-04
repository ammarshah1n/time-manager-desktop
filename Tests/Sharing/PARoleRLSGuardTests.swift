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

    @Test("PA hardening migration blocks forged profile writes")
    func hardeningPolicyBlocksForgedProfileWrites() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("column_name = 'profile_id'"),
                "PA hardening must detect denied tables that carry profile ownership")
        #expect(sql.contains("profile_id is null or profile_id = any(private.user_profile_ids())"),
                "Denied cognitive tables must reject rows owned by another profile")
        #expect(sql.contains("_pa_profile_deny"),
                "Profile ownership guard must be installed as a restrictive policy")
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
        #expect(sql.contains("attname = 'profile_id'"),
                "Behaviour event partitions must also guard profile ownership")
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

    @Test("Active context buffer RPCs are caller scoped")
    func activeContextBufferRPCsAreCallerScoped() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("create or replace function public.get_acb_full"),
                "PA hardening must override get_acb_full")
        #expect(sql.contains("create or replace function public.get_acb_light"),
                "PA hardening must override get_acb_light")
        #expect(sql.contains("exec_id = public.get_executive_id(auth.uid())"),
                "ACB RPCs must only expose the caller's own executive context")
    }

    @Test("Tier0 match RPC is caller scoped")
    func tier0MatchRPCIsCallerScoped() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("create or replace function public.match_tier0_observations"),
                "PA hardening must override match_tier0_observations")
        #expect(sql.contains("match_profile_id is distinct from public.get_executive_id(auth.uid())"),
                "Tier0 match must reject arbitrary owner profile ids")
        #expect(sql.contains("raise exception 'tier0 observation match denied'"),
                "Tier0 match must deny non-service callers outside their own profile")
    }

    @Test("Estimation history match RPC is caller and workspace scoped")
    func estimationHistoryMatchRPCIsCallerScoped() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("create or replace function public.match_estimation_history"),
                "PA hardening must override match_estimation_history")
        #expect(sql.contains("match_profile_id = public.get_executive_id(auth.uid())"),
                "Estimation history match must only expose the caller's own profile")
        #expect(sql.contains("match_workspace_id = any(public.current_workspace_ids())"),
                "Estimation history match must require caller membership in the workspace")
        #expect(sql.contains("match_workspace_id <> all(public.pa_workspace_ids())"),
                "Estimation history match must not expose PA workspaces")
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
        #expect(sql.contains("em.workspace_id = new.workspace_id"),
                "Task completion trigger must not copy email metadata across workspaces under SECURITY DEFINER")
    }

    @Test("PA cannot transfer task ownership out of workspace")
    func paCannotTransferTaskOwnershipOutOfWorkspace() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("create or replace function public.prevent_pa_task_ownership_transfer()"),
                "PA hardening must add a task trigger that blocks ownership transfer bypasses")
        #expect(sql.contains("old.workspace_id = any(public.pa_workspace_ids())"),
                "Task ownership transfer guard must identify PA-origin tasks")
        #expect(sql.contains("new.workspace_id is distinct from old.workspace_id"),
                "PA task updates must not move tasks into another workspace")
        #expect(sql.contains("new.profile_id is distinct from old.profile_id"),
                "PA task updates must not reassign task profile ownership")
        #expect(sql.contains("before update of workspace_id, profile_id on public.tasks"),
                "Ownership transfer guard must fire before task workspace/profile changes")
    }

    @Test("Task profile ids cannot be forged through direct writes")
    func taskProfileIdsCannotBeForgedThroughDirectWrites() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("create or replace function public.prevent_task_profile_forgery()"),
                "PA hardening must block callers from writing tasks for another profile")
        #expect(sql.contains("caller_profile_id uuid := public.get_executive_id(auth.uid())"),
                "Task profile guard must bind task ownership to the authenticated caller")
        #expect(sql.contains("if tg_op = 'insert' then"),
                "Task profile guard must cover new task inserts, not only profile updates")
        #expect(sql.contains("new.profile_id = caller_profile_id"),
                "New tasks must be owned by the caller profile")
        #expect(sql.contains("where t.id = new.id"),
                "Existing task upserts must be identified before conflict update")
        #expect(sql.contains("new.workspace_id is not distinct from existing_workspace_id"),
                "Existing task upserts must not change workspace ownership")
        #expect(sql.contains("new.profile_id is not distinct from existing_profile_id"),
                "Existing task upserts must not change profile ownership")
        #expect(sql.contains("before insert or update of profile_id on public.tasks"),
                "Task profile guard must fire for inserts and direct profile changes")
    }

    @Test("Task section ownership cannot be transferred through upserts")
    func taskSectionOwnershipCannotBeTransferredThroughUpserts() throws {
        let sql = try source(Self.hardeningMigration).lowercased()
        #expect(sql.contains("create or replace function public.prevent_task_section_ownership_transfer()"),
                "PA hardening must block task section ownership transfer")
        #expect(sql.contains("caller_profile_ids uuid[] := private.user_profile_ids()"),
                "Task section guard must bind new sections to authenticated caller profile ids")
        #expect(sql.contains("from public.task_sections s"),
                "Existing task section upserts must be identified before conflict update")
        #expect(sql.contains("where s.id = new.id"),
                "Existing task section upsert allowance must be id-bound")
        #expect(sql.contains("new.workspace_id is not distinct from existing_workspace_id"),
                "Existing task section upserts must not change workspace ownership")
        #expect(sql.contains("new.profile_id is not distinct from existing_profile_id"),
                "Existing task section upserts must not change profile ownership")
        #expect(sql.contains("new.workspace_id is distinct from old.workspace_id"),
                "Direct task section updates must not move workspaces")
        #expect(sql.contains("new.profile_id is distinct from old.profile_id"),
                "Direct task section updates must not reassign profile ownership")
        #expect(sql.contains("before insert or update of workspace_id, profile_id, is_system on public.task_sections"),
                "Task section ownership guard must fire before inserts and ownership flag changes")
        #expect(sql.contains("drop policy if exists \"task_sections_update_member\" on public.task_sections"),
                "Task section update policy must be replaced after the ownership trigger is installed")
        #expect(sql.contains("create policy \"task_sections_update_member\"\non public.task_sections\nfor update"),
                "Task section updates must keep a member update policy")
        #expect(sql.contains("with check (\n  is_system = false\n  and workspace_id = any(private.user_workspace_ids())\n);"),
                "Task section update WITH CHECK must allow preserved owner profile ids")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }
}
