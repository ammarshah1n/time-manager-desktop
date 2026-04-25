// deepgram-token
//
// Issues a short-lived (60s TTL) Deepgram temporary key scoped to "usage:write"
// so the desktop client can open a streaming WebSocket directly to Deepgram
// without ever holding the long-lived project key.
//
// Auth: JWT verified via _shared/auth.ts. The temp key is bound to the request,
// not the user, so we don't store it.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireEnv } from "../_shared/config.ts";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const DEEPGRAM_PROJECT_KEY = requireEnv("DEEPGRAM_API_KEY");
const DEEPGRAM_PROJECT_ID  = requireEnv("DEEPGRAM_PROJECT_ID");

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    // Auth is the only check we need — this function does not touch the
    // database, so there is no reason to resolve the executive row here.
    await verifyAuth(req);

    const ttl = 60; // seconds
    const dgRes = await fetch(
      `https://api.deepgram.com/v1/projects/${DEEPGRAM_PROJECT_ID}/keys`,
      {
        method: "POST",
        headers: {
          "Authorization": `Token ${DEEPGRAM_PROJECT_KEY}`,
          "Content-Type":  "application/json",
        },
        body: JSON.stringify({
          // Use opaque tags — internal tenant UUIDs should not leak to
          // Deepgram's audit log. The Edge Function logs the executiveId
          // privately if correlation is needed for support.
          comment:       "timed-orb-session",
          scopes:        ["usage:write"],
          time_to_live_in_seconds: ttl,
          tags:          ["timed", "orb"],
        }),
      }
    );

    if (!dgRes.ok) {
      const text = await dgRes.text();
      console.error(`[deepgram-token] upstream ${dgRes.status}: ${text.slice(0, 200)}`);
      return new Response(JSON.stringify({ error: "transcription service unavailable" }), {
        status: 502, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    const json = await dgRes.json() as { key: string; expiration_date?: string };
    return new Response(JSON.stringify({
      token: json.key,
      expires_in: ttl,
    }), { headers: { ...CORS, "Content-Type": "application/json" } });
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    console.error("[deepgram-token] ERROR:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
