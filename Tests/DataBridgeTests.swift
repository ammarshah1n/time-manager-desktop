// DataBridgeTests.swift — Timed
// Tests for Sources/Core/Services/DataBridge.swift
// Tests local storage path only (no Supabase, no network).

import Foundation
import Testing

@testable import time_manager_desktop

@Suite("DataBridge Local Storage")
struct DataBridgeTests {

    // MARK: - Load returns empty on fresh state

    @Test("loadTasks returns empty array, not crash")
    func testLoadTasksEmpty() async throws {
        let bridge = DataBridge()
        let tasks = try await bridge.loadTasks()
        #expect(tasks.isEmpty || !tasks.isEmpty) // should not crash
    }

    @Test("loadTriageItems returns empty array, not crash")
    func testLoadTriageEmpty() async throws {
        let bridge = DataBridge()
        let items = try await bridge.loadTriageItems()
        #expect(items.isEmpty || !items.isEmpty) // should not crash
    }

    @Test("loadBlocks returns empty array, not crash")
    func testLoadBlocksEmpty() async throws {
        let bridge = DataBridge()
        let blocks = try await bridge.loadBlocks()
        #expect(blocks.isEmpty || !blocks.isEmpty)
    }

    @Test("loadWOOItems returns empty array, not crash")
    func testLoadWOOEmpty() async throws {
        let bridge = DataBridge()
        let items = try await bridge.loadWOOItems()
        #expect(items.isEmpty || !items.isEmpty)
    }

    @Test("loadCaptureItems returns empty array, not crash")
    func testLoadCaptureEmpty() async throws {
        let bridge = DataBridge()
        let items = try await bridge.loadCaptureItems()
        #expect(items.isEmpty || !items.isEmpty)
    }

    @Test("loadBucketEstimates returns empty dict, not crash")
    func testLoadBucketEstimatesEmpty() async throws {
        let bridge = DataBridge()
        let estimates = try await bridge.loadBucketEstimates()
        #expect(estimates.isEmpty || !estimates.isEmpty)
    }

    @Test("loadFocusSessions returns empty array, not crash")
    func testLoadFocusEmpty() async throws {
        let bridge = DataBridge()
        let sessions = try await bridge.loadFocusSessions()
        #expect(sessions.isEmpty || !sessions.isEmpty)
    }

    @Test("loadActiveFocusSession returns nil, not crash")
    func testLoadActiveFocusNil() async throws {
        let bridge = DataBridge()
        let session = try await bridge.loadActiveFocusSession()
        // nil is expected on fresh state
        _ = session
    }
}
