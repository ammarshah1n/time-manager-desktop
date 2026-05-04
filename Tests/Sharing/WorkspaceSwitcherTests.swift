import Testing
import Foundation
@testable import TimedKit

@Suite("WorkspaceSwitcher wiring")
struct WorkspaceSwitcherTests {
    @Test("switcher routes through AuthService.switchWorkspace")
    func switcherUsesSafeSwitchAPI() throws {
        let content = try source("Sources/TimedKit/Features/Sharing/WorkspaceSwitcher.swift")
        #expect(content.contains("auth.switchWorkspace(to:"))
        #expect(!content.contains("auth.activeWorkspaceId ="))
    }

    @Test("root sidebar mounts workspace switcher")
    func rootMountsSwitcher() throws {
        let content = try source("Sources/TimedKit/Features/TimedRootView.swift")
        #expect(content.contains("WorkspaceSwitcher()"))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path))
    }
}
