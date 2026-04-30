// generate-embedding — DISABLED per Dish Me Up Model Routing Amendment.
//
// This function previously called OpenAI text-embedding-3-large and Voyage
// voyage-3. The Claude-only stack (Model Routing Amendment) removes OpenAI
// from the inference path and replaces semantic embeddings with structured
// Haiku-generated tags + Postgres array overlap at query time.
//
// Re-enable only if retrieval quality is insufficient after 200+ real corrections
// have accumulated (Ship-It.md, Part 2).

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";

const CORS = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "null",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Content-Type":                 "application/json",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const body = await req.json().catch(() => ({})) as { texts?: string[] };
  const n = body.texts?.length ?? 0;
  return new Response(JSON.stringify({
    embeddings: [],
    dimension: 0,
    count: n,
    disabled: true,
    reason: "generate-embedding is disabled until Haiku-tag retrieval is wired (Model Routing Amendment, Option B).",
  }), { status: 200, headers: CORS });
});
