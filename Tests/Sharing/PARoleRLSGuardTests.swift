import Testing
import Foundation
@testable import TimedKit

@Suite("PA role RLS deny-list")
struct PARoleRLSGuardTests {
    static let denyListTables = [
        "email_messages", "email_accounts", "email_triage_corrections",
        "sender_rules", "behaviour_events", "behaviour_rules",
        "user_profiles", "estimation_history", "waiting_items",
        "bucket_completion_stats", "bucket_estimates",
        "voice_capture_items", "voice_captures",
        "estimate_priors", "ai_pipeline_runs"
    ]

    @Test("PA deny migration declares each table")
    func eachTablePresent() throws {
        let content = try source("supabase/migrations/20260504100001_pa_role_policies.sql")
        for table in Self.denyListTables {
            #expect(content.contains("'\(table)'"), "PA deny-list missing table: \(table)")
        }
    }

    @Test("PA deny migration uses RESTRICTIVE policies, not permissive overlay")
    func usesRestrictive() throws {
        let content = try source("supabase/migrations/20260504100001_pa_role_policies.sql").lowercased()
        #expect(content.contains("as restrictive"),
                "PA deny migration must declare 'as restrictive' — permissive policies would be OR'd and ineffective")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }
}
