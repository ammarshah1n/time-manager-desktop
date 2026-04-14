// SignalSourceTests.swift — Timed
// Tests the SignalSource enum's custom Codable with unknown fallback.

import Foundation
import Testing

@testable import time_manager_desktop

@Suite("SignalSource Codable")
struct SignalSourceTests {

    @Test("Known sources decode correctly")
    func testKnownSources() throws {
        let json = Data(#""email""#.utf8)
        let source = try JSONDecoder().decode(SignalSource.self, from: json)
        #expect(source == .email)

        let json2 = Data(#""app_usage""#.utf8)
        let source2 = try JSONDecoder().decode(SignalSource.self, from: json2)
        #expect(source2 == .appUsage)
    }

    @Test("Unknown source decodes to .unknown with raw value preserved")
    func testUnknownSource() throws {
        let json = Data(#""biometric_scan""#.utf8)
        let source = try JSONDecoder().decode(SignalSource.self, from: json)
        if case .unknown(let raw) = source {
            #expect(raw == "biometric_scan")
        } else {
            Issue.record("Expected .unknown, got \(source)")
        }
    }

    @Test("Known sources roundtrip through encode/decode")
    func testRoundtrip() throws {
        let sources: [SignalSource] = [.email, .calendar, .appUsage, .system, .keystroke, .voice, .healthkit, .oura, .composite, .engagement]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for source in sources {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(SignalSource.self, from: data)
            #expect(decoded == source)
        }
    }

    @Test("Unknown source roundtrips correctly")
    func testUnknownRoundtrip() throws {
        let source = SignalSource.unknown("future_sensor")
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(SignalSource.self, from: data)
        #expect(decoded == source)
    }

    @Test("Tier0Observation with unknown source decodes without crash")
    func testObservationWithUnknownSource() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "profile_id": "550e8400-e29b-41d4-a716-446655440001",
            "occurred_at": "2026-04-14T10:00:00Z",
            "source": "new_sensor_type",
            "event_type": "test",
            "importance_score": 0.5,
            "is_processed": false,
            "created_at": "2026-04-14T10:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let obs = try decoder.decode(Tier0Observation.self, from: json)
        if case .unknown(let raw) = obs.source {
            #expect(raw == "new_sensor_type")
        } else {
            Issue.record("Expected .unknown source, got \(obs.source)")
        }
    }
}
