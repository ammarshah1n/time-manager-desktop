# Coding Standards

## Implementation Boundaries
- `GraphClient.swift`: REAL MSAL OAuth + all Graph API methods
- `SupabaseClient.swift`: REAL Supabase queries for 12 operations

<important>
## Build & Test Tools
- XcodeBuildMCP: `build_sim` / `build_device` for builds, `test_sim` for tests, `debug_attach_sim` / `debug_stack` / `debug_variables` for debugging — structured JSON errors, prefer over raw `xcodebuild`
- `xcrun mcpbridge`: `DocumentationSearch` for Apple API questions, `ExecuteSnippet` to verify Swift API behaviour, `RenderPreview` for headless SwiftUI preview
- Supabase MCP: deploy edge functions, fetch logs, generate TypeScript types — uses service role key, bypasses RLS, never `always_allow` destructive ops
</important>
