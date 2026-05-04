// supabase/functions/accept-invite/index.ts
// Thin wrapper around accept_workspace_invite() RPC.
// Calls RPC with the user's Bearer token (NOT service role) so RLS + auth.uid() apply.
// All atomic logic lives in the RPC; this Edge Function just does CORS, auth check, and shape.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { AuthError, authErrorResponse, verifyAuth } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/config.ts";
import { CORS_HEADERS as corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_ANON_KEY = requireEnv("SUPABASE_ANON_KEY");

export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type AcceptRequest = { code: string };

type AcceptInviteRow = {
  workspace_id: string;
  workspace_name: string;
  owner_email: string;
  role: string;
  already_member: boolean;
};

export const ERRCODE_TO_MSG: Record<string, { msg: string; status: number }> = {
  P0001: { msg: "This invite was revoked.", status: 410 },
  P0002: { msg: "This invite has already been used.", status: 410 },
  P0003: { msg: "This invite has expired.", status: 410 },
  P0004: { msg: "You are already a member of this workspace with a different role.", status: 409 },
  P0005: { msg: "This invite is no longer valid.", status: 410 },
  P0404: { msg: "Invite not found.", status: 404 },
  "22023": { msg: "You can't accept your own invite.", status: 400 },
  "42501": { msg: "Sign in first.", status: 401 },
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(corsHeaders)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function acceptInviteRow(data: unknown): AcceptInviteRow {
  const row = Array.isArray(data) ? data[0] : data;
  if (!isRecord(row)) {
    throw new Error("RPC returned no invite result");
  }

  const {
    workspace_id: workspaceId,
    workspace_name: workspaceName,
    owner_email: ownerEmail,
    role,
    already_member: alreadyMember,
  } = row;

  if (
    typeof workspaceId !== "string" ||
    typeof workspaceName !== "string" ||
    typeof ownerEmail !== "string" ||
    typeof role !== "string" ||
    typeof alreadyMember !== "boolean"
  ) {
    throw new Error("RPC returned malformed invite result");
  }

  return {
    workspace_id: workspaceId,
    workspace_name: workspaceName,
    owner_email: ownerEmail,
    role,
    already_member: alreadyMember,
  };
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), {
      status: 405,
      headers: {
        ...corsHeaders,
        "Allow": "POST, OPTIONS",
        "Content-Type": "application/json",
      },
    });
  }

  try {
    await verifyAuth(req); // ensures Bearer token exists + valid; user_id unused here

    const body = (await req.json().catch(() => ({}))) as Partial<AcceptRequest>;
    const code = typeof body.code === "string" ? body.code.toLowerCase() : "";
    if (!UUID_RE.test(code)) {
      throw new AuthError("Invalid invite code format", 400);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new AuthError("Missing Authorization header");
    }

    // Build a per-request client with the user's JWT so the RPC sees auth.uid().
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data, error } = await userClient.rpc("accept_workspace_invite", {
      p_code: code,
    });

    if (error) {
      const mapped = ERRCODE_TO_MSG[error.code ?? ""];
      if (mapped) {
        return jsonResponse(
          { error: mapped.msg, code: error.code },
          mapped.status,
        );
      }
      throw new Error(error.message ?? "RPC failed");
    }

    return jsonResponse(acceptInviteRow(data));
  } catch (err) {
    if (err instanceof AuthError) return withCors(authErrorResponse(err));
    const message = err instanceof Error ? err.message : "Internal error";
    return jsonResponse({ error: message }, 500);
  }
}

if (import.meta.main) {
  serve(handler);
}
