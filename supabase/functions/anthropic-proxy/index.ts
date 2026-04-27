// anthropic-proxy
//
// Server-side proxy for Anthropic Messages API. Lets Swift clients call Claude
// without shipping ANTHROPIC_API_KEY in the binary. Forwards the entire request
// body unchanged and injects the server-held API key.
//
// Caller auth: Supabase anon JWT (Authorization: Bearer <ANON_KEY>).
// Body: any valid Anthropic /v1/messages payload (model, max_tokens, messages,
//       system, tools, thinking, etc.).
// Response: streamed if `stream: true`, otherwise the full JSON.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireEnv } from "../_shared/config.ts";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ANTHROPIC_KEY = requireEnv("ANTHROPIC_API_KEY");

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: CORS });
  }

  const body = await req.text();

  const upstream = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type":      "application/json",
      "x-api-key":         ANTHROPIC_KEY,
      "anthropic-version": "2023-06-01",
    },
    body,
  });

  // Pass through SSE streams unchanged when caller asked for stream.
  const contentType = upstream.headers.get("Content-Type") ?? "application/json";
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      ...CORS,
      "Content-Type":  contentType,
      "Cache-Control": "no-cache",
    },
  });
});
