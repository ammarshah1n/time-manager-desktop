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

    @Test("sharing pane ignores stale reload completions")
    func ignoresStaleReloadCompletions() throws {
        let content = try source("Sources/TimedKit/Features/Sharing/SharingPane.swift")
        #expect(content.contains("let fetchedMembers = try await SharingService.shared.fetchPAMembers(workspaceId: workspaceId)"),
                "Member reloads must fetch into a local value before assigning state")
        #expect(content.contains("let fetchedInvites = try await SharingService.shared.fetchInvites(workspaceId: workspaceId)"),
                "Invite reloads must fetch into a local value before assigning state")
        #expect(occurrences(of: "guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }", in: content) >= 2,
                "Member and invite reloads must ignore stale completions after workspace switches")
        #expect(content.contains("members = fetchedMembers"),
                "Member state must only receive the guarded fetch result")
        #expect(content.contains("activeInvites = fetchedInvites"),
                "Invite state must only receive the guarded fetch result")
    }

    @Test("sharing pane clears workspace-scoped state")
    func clearsWorkspaceScopedState() throws {
        let content = try source("Sources/TimedKit/Features/Sharing/SharingPane.swift")
        #expect(content.contains("resetWorkspaceScopedSharingState()"),
                "Workspace switches must clear stale member, invite, and generated-link state before reload")
        #expect(content.contains("members = []"),
                "SharingPane must be able to clear stale member rows")
        #expect(occurrences(of: "activeInvites = []", in: content) >= 2,
                "SharingPane must clear stale invite rows on switch and failed/current non-owner reloads")
        #expect(content.contains("inviteURL = \"\""),
                "Generated invite links must not carry across workspace switches")
        #expect(content.contains("guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }\n            members = []"),
                "Current-workspace member reload failures must clear stale member rows")
        #expect(content.contains("guard auth.activeOrPrimaryWorkspaceId == workspaceId else { return }\n            activeInvites = []"),
                "Current-workspace invite reload failures must clear stale invite rows")
    }

    @Test("PA leave uses auth user id")
    func paLeaveUsesAuthUserId() throws {
        let content = try source("Sources/TimedKit/Features/Sharing/SharingPane.swift")
        #expect(content.contains("let myId = auth.authUserId"),
                "PA leave must delete the workspace_members row keyed by auth.uid(), not executiveId")
        #expect(!content.contains("let myId = auth.executiveId"),
                "PA leave must not use the executive id as workspace_members.profile_id")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
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
