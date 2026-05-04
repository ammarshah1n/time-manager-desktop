import Testing
import Foundation
@testable import TimedKit

@Suite("TimedDeepLink.parse")
struct TimedDeepLinkTests {
    @Test("invite with code")
    func inviteCode() {
        let url = URL(string: "timed://invite/c5e1d2f0-7c8e-4d3a-9f4b-1234567890ab")!
        #expect(TimedDeepLink.parse(url) == .invite(code: "c5e1d2f0-7c8e-4d3a-9f4b-1234567890ab"))
    }

    @Test("invite normalises uppercase to lowercase")
    func inviteLowercase() {
        let url = URL(string: "timed://invite/ABC")!
        #expect(TimedDeepLink.parse(url) == .invite(code: "abc"))
    }

    @Test("invite with no code is unknown")
    func emptyInviteIsUnknown() {
        let url = URL(string: "timed://invite/")!
        #expect(TimedDeepLink.parse(url) == .unknown)
    }

    @Test("capture")
    func capture() {
        #expect(TimedDeepLink.parse(URL(string: "timed://capture")!) == .capture)
    }

    @Test("auth callback")
    func authCallback() {
        let url = URL(string: "timed://auth/callback?code=xyz")!
        if case .authCallback(let parsedURL) = TimedDeepLink.parse(url) {
            #expect(parsedURL == url)
        } else {
            Issue.record("expected authCallback")
        }
    }

    @Test("non-timed scheme is unknown")
    func nonTimedScheme() {
        #expect(TimedDeepLink.parse(URL(string: "https://example.com/invite/x")!) == .unknown)
    }
}
