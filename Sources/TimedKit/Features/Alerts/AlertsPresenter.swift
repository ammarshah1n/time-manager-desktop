// AlertsPresenter.swift — Timed macOS
// MainActor bridge between AlertEngine (actor) and SwiftUI. The engine scores
// and decides; the presenter holds the currently-visible alert and exposes
// callbacks the AlertDeliveryView buttons fire.
//
// Wiring path (when Tier0Writer/EmailSync feeds alerts):
//   Tier0Writer → AlertEngine.evaluateRTScore → AlertsPresenter.show(scored:)
//
// Until that path lights up, this presenter just renders nothing — but it's
// instantiated on TimedRootView so the view tree is ready the instant alerts
// start firing.

import Foundation
import SwiftUI
import Combine

@MainActor
final class AlertsPresenter: ObservableObject {
    static let shared = AlertsPresenter()

    @Published var currentAlert: AlertViewModel?

    private var dismissTask: Task<Void, Never>?

    /// Convert a scored alert from the engine into a view model and surface it.
    func show(_ scored: AlertEngine.ScoredAlert) {
        currentAlert = AlertViewModel(
            id: UUID(),
            title: scored.candidate.title,
            body: scored.candidate.body,
            source: scored.candidate.source,
            compositeScore: scored.compositeScore,
            confidence: scored.confidence,
            timestamp: Date()
        )
    }

    /// Acknowledge the current alert (user found it useful).
    func acknowledge() {
        Task { await AlertEngine.shared.recordDelivery(wasActionable: true) }
        currentAlert = nil
    }

    /// Dismiss without action.
    func dismiss() {
        Task { await AlertEngine.shared.recordDelivery(wasActionable: false) }
        currentAlert = nil
    }

    /// Direct feedback (used by the actionability buttons before close).
    func recordActionable(_ wasActionable: Bool) {
        Task { await AlertEngine.shared.recordDelivery(wasActionable: wasActionable) }
    }
}
