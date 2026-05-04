import Testing
import Foundation
@testable import TimedKit

@Suite("Pending invite resume", .serialized)
@MainActor
struct PendingInviteResumeTests {
    @Test("loads pending invite code from defaults and clears it")
    func loadAndClearPendingInvite() {
        let auth = AuthService.shared
        auth.clearPendingInviteCode()
        UserDefaults.standard.set("ABC", forKey: "pendingInviteCode")

        auth.loadPendingInviteCodeFromDefaults()
        #expect(auth.pendingInviteCode == "ABC")

        auth.clearPendingInviteCode()
        #expect(auth.pendingInviteCode == nil)
        #expect(UserDefaults.standard.string(forKey: "pendingInviteCode") == nil)
    }

    @Test("setPendingInviteCode normalises lowercase")
    func normalisesInviteCode() {
        let auth = AuthService.shared
        auth.clearPendingInviteCode()

        auth.setPendingInviteCode("  ABC  ")
        #expect(auth.pendingInviteCode == "abc")

        auth.clearPendingInviteCode()
    }
}
