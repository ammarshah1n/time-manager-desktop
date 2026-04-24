// extract-voice-learnings
//
// Post-check-in Haiku extraction. Input: raw transcript. Output: structured JSON
// that matches the voice_session_learnings schema. Persisted for Dish Me Up
// later today and weekly synthesis on Sunday.
//
// Haiku, not Opus — this is structured extraction, not reasoning.
// No extended thinking. Fast, cheap, deterministic enough.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireEnv } from "../_shared/config.ts";
import { callAnthropic, extractText } from "../_shared/anthropic.ts";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const YASSER_USER_ID   = requireEnv("YASSER_USER_ID");
const SUPABASE_URL     = requireEnv("SUPABASE_URL");
const SERVICE_ROLE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const SYSTEM_PROMPT = `You extract structured learnings from a morning voice check-in transcript.
You return ONLY a JSON object. No markdown fences. No prose outside the JSON.

Schema:
{
  "perceived_priorities": [ { "title": string, "perceived_rank": int, "reason": string } ],
  "hidden_context":       string | null,
  "new_tasks_to_create":  [ { "title": string, "bucket": string, "estimated_minutes": int | null } ],
  "acb_delta":            string | null,
  "rule_updates":         [ { "rule_key": string, "direction": "strengthen"|"weaken"|"new", "evidence": string } ]
}

Rules:
- perceived_priorities: if Yasser said which task/topic he feels is most important today, capture up to 3 in his stated order.
- hidden_context: one sentence of information NOT already in tasks or calendar (e.g. "co-founder is coming in unannounced this afternoon"). null if nothing new.
- new_tasks_to_create: tasks he explicitly said he needs to do but that likely don't exist in his system yet.
- acb_delta: one sentence describing a change in how Yasser described himself or his priorities compared to what you'd expect.
- rule_updates: behavioural rules this session confirms, contradicts, or suggests anew. "rule_key" follows the pattern category.short_handle (e.g. "timing.legal_morning_avoidance").

If a field has no content, return an empty array or null — never omit keys.`;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const body = await req.json().catch(() => ({})) as {
      session_date?: string;
      transcript?: string;
    };

    const transcript = (body.transcript ?? "").trim();
    if (!transcript) {
      return new Response(JSON.stringify({ ok: false, reason: "empty transcript" }), {
        status: 400,
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    const response = await callAnthropic({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 1500,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: `TRANSCRIPT:\n${transcript}\n\nReturn JSON.` }],
    });

    const raw = extractText(response).replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
    let parsed: any;
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      console.error("[extract-voice-learnings] JSON parse failed:", raw);
      throw new Error(`Haiku returned non-JSON: ${(e as Error).message}`);
    }

    const sessionDate = (body.session_date ?? new Date().toISOString().slice(0, 10));

    const insert = {
      executive_id:         YASSER_USER_ID,
      session_date:         sessionDate,
      perceived_priorities: parsed.perceived_priorities ?? [],
      hidden_context:       parsed.hidden_context ?? null,
      new_tasks_to_create:  parsed.new_tasks_to_create ?? [],
      acb_delta:            parsed.acb_delta ?? null,
      rule_updates:         parsed.rule_updates ?? [],
      transcript,
    };

    const { error } = await supabase.from("voice_session_learnings").insert(insert);
    if (error) throw new Error(`voice_session_learnings insert failed: ${error.message}`);

    return new Response(JSON.stringify({ ok: true, learnings: insert }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("[extract-voice-learnings] ERROR:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
