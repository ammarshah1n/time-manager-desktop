import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Service-role Supabase client. Trigger.dev tasks run server-side and must use
 * the service role key so inserts into `agent_traces` / `agent_sessions`
 * bypass RLS (`traces are Timed-internal diagnostic data, never user-facing`).
 *
 * NEVER use the anon key here — the intended write surface is privileged.
 */
let _client: SupabaseClient | undefined;

export function getSupabaseServiceRole(): SupabaseClient {
  if (_client) return _client;

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url) throw new Error("SUPABASE_URL not set (required for Trigger.dev tasks)");
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_KEY not set (required for Trigger.dev tasks)");

  _client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    db: { schema: "public" },
  });
  return _client;
}
