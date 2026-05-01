// _shared/auth.ts
// JWT verification for all edge functions.
// Extracts Bearer token from Authorization header, verifies via Supabase Auth.
// Returns userId on success, throws 401-style error on failure.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireEnv } from "./config.ts";

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_ANON_KEY"),
);

export class AuthError extends Error {
  status: number;
  constructor(message: string, status = 401) {
    super(message);
    this.name = "AuthError";
    this.status = status;
  }
}

/**
 * Verify the JWT from the Authorization header.
 * Returns the authenticated user's ID.
 * Throws AuthError if missing, malformed, or invalid.
 */
export async function verifyAuth(req: Request): Promise<string> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    throw new AuthError("Missing Authorization header");
  }

  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw new AuthError(
      "Malformed Authorization header — expected Bearer <token>",
    );
  }

  const token = match[1];

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser(token);

  if (error || !user) {
    throw new AuthError(error?.message ?? "Invalid or expired token");
  }

  return user.id;
}

/**
 * Helper to return a JSON 401 response from an AuthError.
 */
export function authErrorResponse(err: AuthError): Response {
  return new Response(
    JSON.stringify({ error: err.message }),
    { status: err.status, headers: { "Content-Type": "application/json" } },
  );
}

/**
 * Verify the request was issued with the Supabase SERVICE-ROLE JWT.
 *
 * Used by cron-triggered Edge Functions (nightly-*, weekly-*, monthly-*,
 * acb-refresh, multi-agent-council, thin-slice-inference, generate-morning-
 * briefing, etc.) which take an `executive_id` from the body and run with the
 * service-role key. Without this check, anyone with a valid Supabase JWT (any
 * signed-in user) could POST `{"executive_id": "<uuid>"}` and trigger Opus runs
 * or read service-role-derived insights for any executive.
 *
 * The pg_cron migrations already pass `Bearer <service_role_key>` (see e.g.
 * supabase/migrations/20260414000001_weekly_syntheses.sql) so this check is
 * zero-cost for legitimate callers.
 *
 * Note on signature verification: Supabase Edge Functions has platform-level
 * JWT verification on by default (no `--no-verify-jwt` is used at deploy
 * time). By the time a request reaches our handler, the JWT signature is
 * already verified — we only need to inspect the `role` claim. We decode the
 * payload with atob; we do NOT re-verify the signature.
 */
export function verifyServiceRole(req: Request): void {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    throw new AuthError("Missing Authorization header", 401);
  }

  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw new AuthError(
      "Malformed Authorization header — expected Bearer <token>",
      401,
    );
  }

  const parts = match[1].split(".");
  if (parts.length !== 3) {
    throw new AuthError("Malformed JWT", 401);
  }

  let payload: { role?: string };
  try {
    // base64url → base64 → JSON
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    payload = JSON.parse(atob(padded));
  } catch {
    throw new AuthError("Could not decode JWT payload", 401);
  }

  if (payload.role !== "service_role") {
    throw new AuthError("This endpoint requires the service-role key", 403);
  }
}

type SupabaseLike = {
  from: (table: string) => any;
};

export async function resolveExecutiveId(
  supabaseAdmin: SupabaseLike,
  authUserId: string,
): Promise<string> {
  const { data, error } = await supabaseAdmin
    .from("executives")
    .select("id")
    .eq("auth_user_id", authUserId)
    .maybeSingle();

  if (error) {
    throw new AuthError(error.message ?? "Executive lookup failed", 500);
  }
  if (!data || typeof data.id !== "string") {
    throw new AuthError("No executive row for this user", 401);
  }
  return data.id;
}

export function assertOwnedTenant(
  executiveId: string,
  workspaceId: unknown,
  profileId?: unknown,
): void {
  if (
    workspaceId !== executiveId ||
    (profileId !== undefined && profileId !== executiveId)
  ) {
    throw new AuthError("Tenant mismatch", 403);
  }
}
