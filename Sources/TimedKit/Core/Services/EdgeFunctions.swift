import Foundation
import Supabase

@MainActor
final class EdgeFunctions {
    static let shared = EdgeFunctions()

    enum FnError: LocalizedError {
        case notSignedIn
        case missingURL
        case http(Int, String)

        /// Sanitised, user-safe message. Internal body text is logged separately,
        /// not surfaced to users — provider error bodies could leak prompt
        /// fragments, internal IDs, or other diagnostic content.
        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to Timed before using this feature."
            case .missingURL:  return "Timed is not properly configured. Please reinstall."
            case .http(let status, let body):
                TimedLogger.supabase.error("Edge Function HTTP \(status): \(body, privacy: .private)")
                switch status {
                case 401, 403:  return "Your session has expired. Please sign in again."
                case 413:       return "That request was too large. Please try something shorter."
                case 429:       return "Too many requests. Please wait a moment and try again."
                case 500...599: return "Timed's backend is having a moment. Please try again shortly."
                default:        return "Something went wrong talking to Timed's backend."
                }
            }
        }
    }

    private var baseURL: URL? {
        let raw = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
        return URL(string: raw)?.appendingPathComponent("functions/v1")
    }

    private var supabase: SupabaseClient? {
        SupabaseClientDependency.live().rawClient
    }

    private func accessToken() async throws -> String {
        guard let supabase else { throw FnError.notSignedIn }
        // Try the in-memory session first. If the JWT has expired (which the
        // Supabase SDK normally refreshes silently, but can fail to do while
        // the app is backgrounded), fall through to an explicit refresh before
        // declaring the user un-authed. Without this, a long sleep / lid-close
        // produces a cascade of 401s across orb / TTS / embeddings.
        if let session = try? await supabase.auth.session {
            return session.accessToken
        }
        do {
            try await supabase.auth.refreshSession()
            let session = try await supabase.auth.session
            TimedLogger.supabase.info("Supabase session auto-refreshed after expiry")
            return session.accessToken
        } catch {
            TimedLogger.supabase.warning("Supabase session refresh failed: \(error.localizedDescription, privacy: .public)")
            throw FnError.notSignedIn
        }
    }

    /// Fire-and-forget OPTIONS request against each named Edge Function so the
    /// Deno isolate is warm by the time the user's first utterance arrives.
    /// Failures (no network, function not deployed, etc.) are non-fatal.
    func preWarm(_ functionNames: [String]) async {
        guard let baseURL else { return }
        await withTaskGroup(of: Void.self) { group in
            for name in functionNames {
                group.addTask {
                    var req = URLRequest(url: baseURL.appendingPathComponent(name))
                    req.httpMethod = "OPTIONS"
                    req.timeoutInterval = 6
                    _ = try? await URLSession.shared.data(for: req)
                }
            }
        }
    }

    private func makeRequest(_ path: String, method: String = "POST") async throws -> URLRequest {
        guard let baseURL else { throw FnError.missingURL }
        let token = try await accessToken()
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90
        return req
    }

    func fetchDeepgramToken() async throws -> String {
        var req = try await makeRequest("deepgram-token")
        req.httpBody = "{}".data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkOK(response, data: data)
        struct R: Decodable { let token: String; let expires_in: Int }
        return try JSONDecoder().decode(R.self, from: data).token
    }

    func ttsBytes(text: String, voiceId: String? = nil) async throws -> AsyncThrowingStream<Data, Error> {
        var req = try await makeRequest("orb-tts")
        var body: [String: Any] = ["text": text]
        if let voiceId, !voiceId.isEmpty { body["voice_id"] = voiceId }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var body = Data()
            for try await byte in asyncBytes { body.append(byte) }
            throw FnError.http(http.statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var buffer = Data()
                    buffer.reserveCapacity(8192)
                    for try await byte in asyncBytes {
                        buffer.append(byte)
                        if buffer.count >= 4096 {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func conversationStream(messages: [[String: Any]], clientState: [String: Any]?) async throws -> URLSession.AsyncBytes {
        var req = try await makeRequest("orb-conversation")
        var body: [String: Any] = ["messages": messages]
        if let clientState { body["client_state"] = clientState }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var data = Data()
            for try await byte in asyncBytes { data.append(byte) }
            throw FnError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return asyncBytes
    }

    private static func checkOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode == 200 else {
            throw FnError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Generic Anthropic Messages relay for non-streaming client flows.
    /// The body is forwarded verbatim; the server attaches the API key.
    func anthropicRelay(body: [String: Any]) async throws -> Data {
        var req = try await makeRequest("anthropic-relay")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.checkOK(response, data: data)
        return data
    }
}
