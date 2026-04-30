// anthropic-relay
//
// Generic JWT-authed proxy for Anthropic Messages API. Used by the non-streaming
// client paths (capture extraction, morning interview, onboarding name extraction)
// that construct their own prompts and tool schemas client-side. The server only
// adds the API key + protocol headers and forwards the body verbatim.
//
// Why exists: keeps the Anthropic key off the desktop client. Clients post their
// Messages API request body under their JWT; this function attaches the secret
// header and returns the upstream response.
//
// What this is NOT: a place for prompt construction or business logic. Bespoke
// flows (orb, generate-dish-me-up, voice-llm-proxy) build their prompts server-side
// and have their own functions. This relay is for the legacy single-purpose clients.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireEnv } from "../_shared/config.ts";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";

const CORS = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "null",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ANTHROPIC_KEY = requireEnv("ANTHROPIC_API_KEY");

// Hard guardrails — without these, any signed-in user could spend the
// company Anthropic key as a general-purpose API.
const ALLOWED_MODELS = new Set([
  "claude-opus-4-7",
  "claude-opus-4-6",
  "claude-sonnet-4-6",
  "claude-haiku-4-5-20251001",
]);
const MAX_BODY_BYTES   = 256 * 1024;  // 256 KB
const MAX_MESSAGES     =  40;
const MAX_TOOLS        =   8;
const MAX_MAX_TOKENS   = 4096;
const MAX_SYSTEM_BYTES = 200 * 1024;

interface RelayBody {
  model?: string;
  max_tokens?: number;
  messages?: unknown[];
  tools?: unknown[];
  system?: unknown;
  stream?: boolean;
  [k: string]: unknown;
}

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status, headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function validate(parsed: RelayBody): string | null {
  if (typeof parsed.model !== "string" || !ALLOWED_MODELS.has(parsed.model)) {
    return `model must be one of: ${[...ALLOWED_MODELS].join(", ")}`;
  }
  if (typeof parsed.max_tokens !== "number" || parsed.max_tokens <= 0 || parsed.max_tokens > MAX_MAX_TOKENS) {
    return `max_tokens must be 1..${MAX_MAX_TOKENS}`;
  }
  if (!Array.isArray(parsed.messages) || parsed.messages.length === 0 || parsed.messages.length > MAX_MESSAGES) {
    return `messages must be 1..${MAX_MESSAGES} entries`;
  }
  if (parsed.tools !== undefined) {
    if (!Array.isArray(parsed.tools) || parsed.tools.length > MAX_TOOLS) {
      return `tools may not exceed ${MAX_TOOLS} entries`;
    }
  }
  if (parsed.stream === true) {
    return "streaming is not allowed via this relay; use orb-conversation for streaming";
  }
  if (parsed.system !== undefined) {
    const sysBytes = new TextEncoder().encode(JSON.stringify(parsed.system)).length;
    if (sysBytes > MAX_SYSTEM_BYTES) {
      return `system block exceeds ${MAX_SYSTEM_BYTES} bytes`;
    }
  }
  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    await verifyAuth(req);

    const raw = await req.text();
    if (!raw) return jsonError(400, "missing body");
    if (raw.length > MAX_BODY_BYTES) return jsonError(413, `body exceeds ${MAX_BODY_BYTES} bytes`);

    let parsed: RelayBody;
    try {
      parsed = JSON.parse(raw) as RelayBody;
    } catch {
      return jsonError(400, "invalid JSON body");
    }
    const validationError = validate(parsed);
    if (validationError) return jsonError(400, validationError);

    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key":         ANTHROPIC_KEY,
        "anthropic-version": "2023-06-01",
        "content-type":      "application/json",
      },
      body: JSON.stringify(parsed),
    });

    if (!upstream.ok) {
      // Surface a generic upstream error; do not echo provider body to client.
      console.error(`[anthropic-relay] upstream ${upstream.status}`);
      return jsonError(502, `upstream provider returned ${upstream.status}`);
    }

    const text = await upstream.text();
    return new Response(text, {
      status: 200,
      headers: {
        ...CORS,
        "Content-Type": upstream.headers.get("content-type") ?? "application/json",
      },
    });
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    console.error("[anthropic-relay] ERROR:", err);
    return jsonError(500, "internal error");
  }
});
