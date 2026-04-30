// _shared/cors.ts
// Canonical CORS headers for all Edge Functions.
//
// These functions are called exclusively from the native Timed macOS / iOS
// client via URLSession, which does not enforce or care about CORS. CORS
// only matters when a browser is in the loop. There is no browser client
// today, so we lock the Allow-Origin down to a value that no browser will
// accept. Set the ALLOWED_ORIGIN env var per-function only if a future
// browser caller is intentionally added.
//
// Previous state was Access-Control-Allow-Origin: "*" copy-pasted across
// 15 functions, which would have permitted cross-origin browser calls
// against any endpoint the moment a JWT was exposed to a browser context.
//
// Legacy functions still define their own inline CORS block but read the
// same ALLOWED_ORIGIN env var, so the policy is centralised even where
// the import surface is not. Migrate inline blocks to this module when
// you happen to be in the file for another reason.

const ALLOWED = Deno.env.get("ALLOWED_ORIGIN") ?? "null";

export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": ALLOWED,
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
