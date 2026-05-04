import Testing
import Foundation
import Dependencies
@testable import TimedKit

@Suite("SharingService.acceptInvite")
struct SharingServiceAcceptTests {
    @Test("forwards code to SupabaseClient and returns response")
    func forwardsCode() async throws {
        let recorder = AcceptInviteRecorder()
        let stub = AcceptInviteResponse(
            workspaceId: UUID(),
            workspaceName: "Yasser Workspace",
            ownerEmail: "y@example.com",
            role: "pa",
            alreadyMember: false
        )

        try await withDependencies {
            var dependency = SupabaseClientDependency()
            dependency.acceptInvite = { code in
                await recorder.record(code)
                return stub
            }
            $0.supabaseClient = dependency
        } operation: {
            let response = try await SharingService.shared.acceptInvite(code: "abc")
            #expect(await recorder.codes() == ["abc"])
            #expect(response.workspaceName == "Yasser Workspace")
            #expect(response.role == "pa")
        }
    }
}

@Suite("SharingPane role guards")
struct SharingPaneRoleGuardTests {
    @Test("member removal is owner gated")
    func memberRemovalIsOwnerGated() throws {
        let content = try source("Sources/TimedKit/Features/Sharing/SharingPane.swift")
        #expect(content.contains("isActiveWorkspaceOwner"),
                "SharingPane must derive the active workspace role")
        #expect(content.contains("if isActiveWorkspaceOwner && member.role != \"owner\""),
                "Remove button must be owner-only")
    }

    @Test("sharing pane reloads when active workspace changes")
    func reloadsOnWorkspaceChange() throws {
        let content = try source("Sources/TimedKit/Features/Sharing/SharingPane.swift")
        #expect(content.contains(".onChange(of: auth.activeWorkspaceId)"),
                "SharingPane must reload members and invites after workspace switch")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }
}

private actor AcceptInviteRecorder {
    private var recordedCodes: [String] = []

    func record(_ code: String) {
        recordedCodes.append(code)
    }

    func codes() -> [String] {
        recordedCodes
    }
}

@Suite("WorkspaceMemberRow decoding")
struct WorkspaceMemberRowDecodingTests {
    @Test("decodes nested profiles join")
    func decodesNestedProfilesJoin() throws {
        let json = """
        [{
          "id": "11111111-1111-4111-8111-111111111111",
          "workspace_id": "22222222-2222-4222-8222-222222222222",
          "profile_id": "33333333-3333-4333-8333-333333333333",
          "role": "pa",
          "profiles": {
            "email": "pa@example.com",
            "full_name": "Karen PA"
          }
        }]
        """.data(using: .utf8)!

        let rows = try JSONDecoder().decode([WorkspaceMemberRow].self, from: json)

        #expect(rows.first?.email == "pa@example.com")
        #expect(rows.first?.fullName == "Karen PA")
    }
}
