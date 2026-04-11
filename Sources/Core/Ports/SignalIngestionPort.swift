import Foundation

/// Port for recording raw signal observations into the Tier 0 data store.
/// Implementors: Tier0Writer (Supabase + offline SQLite queue).
protocol SignalIngestionPort: Sendable {
    func recordObservation(_ observation: Tier0Observation) async throws
    func recordObservations(_ observations: [Tier0Observation]) async throws
}
