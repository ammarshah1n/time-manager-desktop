// SupabaseEndpoints.swift — Timed Core
// Single source of truth for Supabase Edge Function URLs and the public anon JWT.
// Both values are baked-in fallbacks so a fresh install on any machine can call
// Edge Functions without env-var setup. Override locally with SUPABASE_URL /
// SUPABASE_ANON_KEY env vars (only honoured when launched from a shell).

import Foundation

enum SupabaseEndpoints {

    /// Base URL of the Supabase project. The hardcoded fallback is the public
    /// project URL — not a secret.
    static let baseURL: String = {
        ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
    }()

    /// Public anon JWT for the Supabase project. Designed to be embedded in
    /// clients — RLS policies enforce access. Override via env var for testing.
    static let anonKey: String = {
        ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZwbWp1dWZlZmh0bHdiZmlueGx4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5MTMxMDEsImV4cCI6MjA5MDQ4OTEwMX0.VUtjezhFMpwrcVMXltyYmU2n0Xazi9lvhuwAQlKOTO4"
    }()

    /// Build a URL for an Edge Function by name (e.g. `"anthropic-proxy"`).
    static func functionURL(_ name: String) -> URL? {
        URL(string: "\(baseURL)/functions/v1/\(name)")
    }

    /// Authorization header value for Edge Function calls.
    static var authHeader: String { "Bearer \(anonKey)" }
}
