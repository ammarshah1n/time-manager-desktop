// extract-onboarding-profile
//
// Post-onboarding Haiku extraction. Input: transcript of the voice setup
// conversation. Output: structured profile fields written to executives +
// sets onboarded_at = NOW() so subsequent voice-llm-proxy calls flip into
// morning check-in mode.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireEnv } from "../_shared/config.ts";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";

const CORS = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "null",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL     = requireEnv("SUPABASE_URL");
const SERVICE_ROLE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

async function resolveExecutiveId(authUserId: string): Promise<string> {
  const { data, error } = await supabase
    .from("executives")
    .select("id")
    .eq("auth_user_id", authUserId)
    .maybeSingle();
  if (error) throw new Error(`executive lookup failed: ${error.message}`);
  if (!data) throw new AuthError("No executive row for this user — sign in first");
  return data.id as string;
}

const SYSTEM_PROMPT = `You extract structured profile fields from a voice onboarding transcript.
Return ONLY a JSON object, no markdown, no prose.

Schema:
{
  "display_name":       string | null,
  "work_start_hour":    int | null,    // 0..23, prefer his explicit answer
  "work_end_hour":      int | null,    // 0..23
  "email_cadence_pref": "twice_daily" | "three_times_daily" | "hourly" | "realtime" | null,
  "transit_modes":      string[]       // subset of ["drive","train","plane","chauffeur"]; [] if unknown
}

Rules:
- Parse the user's words, not the agent's. If the agent confirms and the user
  agrees, use the agent's interpretation.
- If the user accepted defaults, apply sensible defaults:
  display_name=null, work_start_hour=9, work_end_hour=18,
  email_cadence_pref="twice_daily", transit_modes=["drive"].
- Fields not mentioned stay null, except transit_modes which stays [].
- NEVER produce a pa_email, assistant email, or delegation address field. Timed
  never sends mail. If such a field appears in the transcript, ignore it.`;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authUserId = await verifyAuth(req);
    const executiveId = await resolveExecutiveId(authUserId);

    const body = await req.json().catch(() => ({})) as { transcript?: string };
    const transcript = (body.transcript ?? "").trim();
    if (!transcript) {
      return new Response(JSON.stringify({ ok: false, reason: "empty transcript" }), {
        status: 400, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    const response = await callAnthropic({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 800,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: `TRANSCRIPT:\n${transcript}\n\nReturn JSON.` }],
    });

    const raw = extractText(response).replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
    const start = raw.indexOf("{");
    const end   = raw.lastIndexOf("}");
    if (start < 0 || end < 0) throw new Error(`Haiku returned no JSON: ${raw.slice(0, 200)}`);
    const profile = JSON.parse(raw.slice(start, end + 1));

    // Write to executives — only overwrite fields that Haiku actually produced.
    const updates: Record<string, unknown> = { onboarded_at: new Date().toISOString() };
    if (profile.display_name && typeof profile.display_name === "string") {
      updates.display_name = profile.display_name;
    }
    const { error } = await supabase.from("executives").update(updates).eq("id", executiveId);
    if (error) throw new Error(`executives update failed: ${error.message}`);

    return new Response(JSON.stringify({ ok: true, profile, applied: updates }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    console.error("[extract-onboarding-profile] ERROR:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
