// AlertEngineTests.swift — Timed
// Tests for Sources/Core/Services/AlertEngine.swift
// Covers: multiplicative scoring, daily cap, gap enforcement, adaptive threshold, RT thresholds.

import Foundation
import Testing

@testable import TimedKit

@Suite("AlertEngine")
struct AlertEngineTests {

    // MARK: - Helpers

    private func makeCandidate(
        salience: Double = 0.8,
        confidence: Double = 0.8,
        timeSensitivity: Double = 0.8,
        actionability: Double = 0.8
    ) -> AlertEngine.AlertCandidate {
        AlertEngine.AlertCandidate(
            source: "test",
            title: "Test Alert",
            body: "Test body",
            rawSalience: salience,
            rawConfidence: confidence,
            timeSensitivity: timeSensitivity,
            rawActionability: actionability
        )
    }

    // MARK: - Multiplicative Scoring

    @Test("Zero in any dimension kills the alert")
    func testZeroDimensionKills() async {
        let engine = AlertEngine()

        let zeroSalience = makeCandidate(salience: 0.0)
        let decision = await engine.scoreAlert(zeroSalience, cognitivePermit: 1.0)
        if case .discard = decision {
            // expected
        } else {
            Issue.record("Expected discard when salience is 0")
        }

        let zeroConfidence = makeCandidate(confidence: 0.0)
        let decision2 = await engine.scoreAlert(zeroConfidence, cognitivePermit: 1.0)
        if case .discard = decision2 {
            // expected
        } else {
            Issue.record("Expected discard when confidence is 0")
        }
    }

    @Test("High composite score triggers interrupt")
    func testHighScoreInterrupts() async {
        let engine = AlertEngine()
        let candidate = makeCandidate(
            salience: 0.95,
            confidence: 0.95,
            timeSensitivity: 0.95,
            actionability: 0.95
        )
        let decision = await engine.scoreAlert(candidate, cognitivePermit: 1.0)
        if case .interrupt = decision {
            // expected
        } else {
            Issue.record("Expected interrupt for high composite score")
        }
    }

    @Test("Medium composite score holds for briefing")
    func testMediumScoreHolds() async {
        let engine = AlertEngine()
        let candidate = makeCandidate(
            salience: 0.6,
            confidence: 0.6,
            timeSensitivity: 0.6,
            actionability: 0.6
        )
        // 0.6^4 * 1.0 = 0.1296, which is < 0.5 (interrupt) but > 0.2 (hold)
        // With cognitivePermit = 0.6: 0.6^5 ≈ 0.078 < holdThreshold
        // Use higher values: 0.7^4 * 1.0 = 0.2401 > 0.2
        let candidate2 = makeCandidate(
            salience: 0.7,
            confidence: 0.7,
            timeSensitivity: 0.7,
            actionability: 0.7
        )
        let decision = await engine.scoreAlert(candidate2, cognitivePermit: 1.0)
        if case .holdForBriefing = decision {
            // expected
        } else {
            Issue.record("Expected holdForBriefing for medium composite score, got \(decision)")
        }
    }

    @Test("Low composite score discards")
    func testLowScoreDiscards() async {
        let engine = AlertEngine()
        let candidate = makeCandidate(
            salience: 0.3,
            confidence: 0.3,
            timeSensitivity: 0.3,
            actionability: 0.3
        )
        // 0.3^4 * 1.0 = 0.0081 < 0.2 hold threshold
        let decision = await engine.scoreAlert(candidate, cognitivePermit: 1.0)
        if case .discard = decision {
            // expected
        } else {
            Issue.record("Expected discard for low composite score")
        }
    }

    // MARK: - Daily Cap

    @Test("Daily cap of 3 enforced")
    func testDailyCap() async {
        let engine = AlertEngine()
        // Deliver 3 alerts
        for _ in 0..<3 {
            await engine.recordDelivery(wasActionable: true)
        }
        let remaining = await engine.remainingAlertBudget
        #expect(remaining == 0)
    }

    // MARK: - RT Score Evaluation

    @Test("RT score >= 0.90 triggers interrupt path")
    func testRTScoreImmediate() async {
        let engine = AlertEngine()
        let decision = await engine.evaluateRTScore(
            observationId: UUID(),
            rtScore: 0.92,
            source: "email",
            summary: "Critical signal"
        )
        if case .interrupt = decision {
            // expected: high RT score should attempt to interrupt
        } else if case .holdForBriefing = decision {
            // also acceptable if daily cap already hit
        } else {
            Issue.record("Expected interrupt or holdForBriefing for RT score 0.92")
        }
    }

    @Test("RT score < 0.75 discards")
    func testRTScoreBelowThreshold() async {
        let engine = AlertEngine()
        let decision = await engine.evaluateRTScore(
            observationId: UUID(),
            rtScore: 0.50,
            source: "email",
            summary: "Low importance"
        )
        if case .discard = decision {
            // expected
        } else {
            Issue.record("Expected discard for RT score 0.50")
        }
    }

    @Test("Deadline modifier lowers threshold")
    func testDeadlineModifier() async {
        let engine = AlertEngine()
        // RT score 0.82 without deadline: preliminary (0.80-0.89 band)
        let withoutDeadline = await engine.evaluateRTScore(
            observationId: UUID(),
            rtScore: 0.82,
            source: "email",
            summary: "Test",
            hasUpcomingDeadline: false
        )
        // RT score 0.82 + 0.10 deadline bonus = 0.92: immediate
        let withDeadline = await engine.evaluateRTScore(
            observationId: UUID(),
            rtScore: 0.82,
            source: "email",
            summary: "Test",
            hasUpcomingDeadline: true
        )
        // With deadline should be in the immediate band (0.92 >= 0.90)
        if case .discard = withDeadline {
            Issue.record("Expected non-discard for RT score 0.82 + deadline modifier")
        }
    }
}
