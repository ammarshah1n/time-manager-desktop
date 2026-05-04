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

private actor AcceptInviteRecorder {
    private var recordedCodes: [String] = []

    func record(_ code: String) {
        recordedCodes.append(code)
    }

    func codes() -> [String] {
        recordedCodes
    }
}
