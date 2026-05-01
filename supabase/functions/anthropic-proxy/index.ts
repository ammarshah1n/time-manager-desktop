// anthropic-proxy
//
// Server-side proxy for Anthropic Messages API. Lets Swift clients call Claude
// without shipping ANTHROPIC_API_KEY in the binary. Forwards the entire request
// body unchanged and injects the server-held API key.
//
// Caller auth: Supabase user JWT (Authorization: Bearer <access_token>).
// Body: any valid Anthropic /v1/messages payload (model, max_tokens, messages,
//       system, tools, thinking, etc.).
// Response: streamed if `stream: true`, otherwise the full JSON.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireEnv } from "../_shared/config.ts";
import { AuthError, authErrorResponse, verifyAuth } from "../_shared/auth.ts";

const CORS = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "null",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const ANTHROPIC_KEY = requireEnv("ANTHROPIC_API_KEY");

const ALLOWED_MODELS = new Set([
  "claude-opus-4-7",
  "claude-opus-4-6",
  "claude-sonnet-4-6",
  "claude-haiku-4-5-20251001",
]);
const MAX_BODY_BYTES = 256 * 1024;
const MAX_MESSAGES = 40;
const MAX_TOOLS = 8;
const MAX_MAX_TOKENS = 4096;
const MAX_SYSTEM_BYTES = 200 * 1024;

interface ProxyBody {
  model?: string;
  max_tokens?: number;
  messages?: unknown[];
  tools?: unknown[];
  system?: unknown;
  [key: string]: unknown;
}

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(CORS)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function validateBody(parsed: ProxyBody): string | null {
  if (typeof parsed.model !== "string" || !ALLOWED_MODELS.has(parsed.model)) {
    return `model must be one of: ${[...ALLOWED_MODELS].join(", ")}`;
  }
  if (
    typeof parsed.max_tokens !== "number" || parsed.max_tokens <= 0 ||
    parsed.max_tokens > MAX_MAX_TOKENS
  ) {
    return `max_tokens must be 1..${MAX_MAX_TOKENS}`;
  }
  if (
    !Array.isArray(parsed.messages) || parsed.messages.length === 0 ||
    parsed.messages.length > MAX_MESSAGES
  ) {
    return `messages must be 1..${MAX_MESSAGES} entries`;
  }
  if (
    parsed.tools !== undefined &&
    (!Array.isArray(parsed.tools) || parsed.tools.length > MAX_TOOLS)
  ) {
    return `tools may not exceed ${MAX_TOOLS} entries`;
  }
  if (parsed.system !== undefined) {
    const bytes =
      new TextEncoder().encode(JSON.stringify(parsed.system)).length;
    if (bytes > MAX_SYSTEM_BYTES) {
      return `system block exceeds ${MAX_SYSTEM_BYTES} bytes`;
    }
  }
  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: CORS });
  }

  try {
    await verifyAuth(req);

    const rawBody = await req.text();
    if (!rawBody) return jsonError(400, "missing body");
    const bodyBytes = new TextEncoder().encode(rawBody).length;
    if (bodyBytes > MAX_BODY_BYTES) {
      return jsonError(413, `body exceeds ${MAX_BODY_BYTES} bytes`);
    }

    let parsed: ProxyBody;
    try {
      parsed = JSON.parse(rawBody) as ProxyBody;
    } catch {
      return jsonError(400, "invalid JSON body");
    }

    const validationError = validateBody(parsed);
    if (validationError) return jsonError(400, validationError);

    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(parsed),
    });

    if (!upstream.ok) {
      console.error(`[anthropic-proxy] upstream ${upstream.status}`);
      return jsonError(502, `upstream provider returned ${upstream.status}`);
    }

    // Pass through SSE streams unchanged when caller asked for stream.
    const contentType = upstream.headers.get("Content-Type") ??
      "application/json";
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        ...CORS,
        "Content-Type": contentType,
        "Cache-Control": "no-cache",
      },
    });
  } catch (err) {
    if (err instanceof AuthError) return withCors(authErrorResponse(err));
    console.error("[anthropic-proxy] ERROR:", err);
    return jsonError(500, "internal error");
  }
});
