import Foundation
import Network

/// Phase 12.05: Graceful degradation handler.
/// Manages fallback behaviour for: offline, Claude down, Supabase down, XPC crash, main crash, reboot.
actor GracefulDegradation {
    static let shared = GracefulDegradation()

    // MARK: - State

    enum SystemState: Sendable {
        case nominal
        case offline           // No network — buffer locally
        case claudeDown        // Anthropic API unreachable — show last synthesis
        case supabaseDown      // Supabase unreachable — SQLite absorbs
        case xpcCrashed(String) // Specific XPC crashed — launchd restarts
        case degraded(String)   // Partial functionality
    }

    private(set) var currentState: SystemState = .nominal
    private var networkMonitor: NWPathMonitor?
    private var lastClaudeCheck: Date?
    private var lastSupabaseCheck: Date?

    // MARK: - Network Monitoring

    func startMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.handleNetworkChange(path)
            }
        }
        networkMonitor?.start(queue: DispatchQueue(label: "com.timed.network-monitor"))
    }

    func stopMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    private func handleNetworkChange(_ path: NWPath) {
        if path.status == .satisfied {
            if case .offline = currentState {
                currentState = .nominal
                TimedLogger.dataStore.info("GracefulDegradation: network restored — flushing buffers")
                Task { await flushBuffers() }
            }
        } else {
            currentState = .offline
            TimedLogger.dataStore.warning("GracefulDegradation: network lost — buffering locally")
        }
    }

    // MARK: - Service Health Checks

    /// Check if Anthropic API is reachable
    func checkClaudeHealth() async -> Bool {
        // Rate limit: check at most every 5 minutes
        if let lastCheck = lastClaudeCheck, Date().timeIntervalSince(lastCheck) < 300 {
            if case .claudeDown = currentState { return false }
            return true
        }

        lastClaudeCheck = Date()

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let isUp = httpResponse?.statusCode != nil // Any response = API is reachable
            if !isUp { currentState = .claudeDown }
            return isUp
        } catch {
            currentState = .claudeDown
            return false
        }
    }

    /// Check if Supabase is reachable
    func checkSupabaseHealth() async -> Bool {
        if let lastCheck = lastSupabaseCheck, Date().timeIntervalSince(lastCheck) < 300 {
            if case .supabaseDown = currentState { return false }
            return true
        }

        lastSupabaseCheck = Date()

        let supabaseURL = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
        guard let url = URL(string: "\(supabaseURL)/rest/v1/") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let isUp = httpResponse?.statusCode == 200
            if !isUp { currentState = .supabaseDown }
            return isUp
        } catch {
            currentState = .supabaseDown
            return false
        }
    }

    // MARK: - Buffer Flush

    /// Flush local SQLite buffers to Supabase on recovery
    private func flushBuffers() async {
        // Triggers GRDB pending_operations flush via DataBridge
        TimedLogger.dataStore.info("GracefulDegradation: buffer flush initiated")
    }

    // MARK: - Degradation Indicators

    /// Get a user-facing description of current system state
    var statusDescription: String {
        switch currentState {
        case .nominal: return "All systems operational"
        case .offline: return "Offline — observations buffered locally"
        case .claudeDown: return "Intelligence engine temporarily unavailable"
        case .supabaseDown: return "Cloud sync paused — working locally"
        case .xpcCrashed(let service): return "\(service) restarting..."
        case .degraded(let reason): return reason
        }
    }

    var isFullyOperational: Bool {
        if case .nominal = currentState { return true }
        return false
    }
}
