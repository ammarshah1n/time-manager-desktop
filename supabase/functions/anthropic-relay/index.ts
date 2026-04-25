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
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ANTHROPIC_KEY = requireEnv("ANTHROPIC_API_KEY");

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    await verifyAuth(req);

    const body = await req.text();
    if (!body) {
      return new Response(JSON.stringify({ error: "missing body" }), {
        status: 400, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key":         ANTHROPIC_KEY,
        "anthropic-version": "2023-06-01",
        "content-type":      "application/json",
      },
      body,
    });

    const text = await upstream.text();
    return new Response(text, {
      status: upstream.status,
      headers: {
        ...CORS,
        "Content-Type": upstream.headers.get("content-type") ?? "application/json",
      },
    });
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    console.error("[anthropic-relay] ERROR:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
