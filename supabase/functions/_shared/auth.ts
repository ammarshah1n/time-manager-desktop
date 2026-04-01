// _shared/auth.ts
// JWT verification for all edge functions.
// Extracts Bearer token from Authorization header, verifies via Supabase Auth.
// Returns userId on success, throws 401-style error on failure.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_ANON_KEY")!
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
    throw new AuthError("Malformed Authorization header — expected Bearer <token>");
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
    { status: err.status, headers: { "Content-Type": "application/json" } }
  );
}
