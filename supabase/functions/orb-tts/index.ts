// orb-tts
//
// ElevenLabs TTS proxy. The client never holds the ElevenLabs API key.
// POST { text, voice_id? } → streams MP3 audio back as the body.
//
// Uses ElevenLabs' POST streaming endpoint (not WebSocket) for simplicity —
// the orb already buffers a full assistant turn before requesting TTS, so
// per-sentence WebSocket streaming isn't required. Per-turn POST gives
// equivalent UX with a much simpler proxy.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireEnv } from "../_shared/config.ts";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ELEVENLABS_KEY     = requireEnv("ELEVENLABS_API_KEY");
const DEFAULT_VOICE_ID   = "pFZP5JQG7iQjIQuC4Bku"; // Lily — warm British female
const DEFAULT_MODEL_ID   = "eleven_turbo_v2_5";
const MAX_TEXT_CHARS     = 4000;
const ALLOWED_VOICE_IDS  = new Set<string>([
  "pFZP5JQG7iQjIQuC4Bku", // Lily
  "21m00Tcm4TlvDq8ikWAM", // Rachel
  "AZnzlk1XvdvUeBnXmlld", // Domi
  "TX3LPaxmHKxFdv7VOQHJ", // Liam
]);

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    await verifyAuth(req);

    const body = await req.json().catch(() => ({})) as {
      text?: string;
      voice_id?: string;
    };
    const text = (body.text ?? "").trim();
    if (!text) {
      return new Response(JSON.stringify({ error: "missing text" }), {
        status: 400, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    if (text.length > MAX_TEXT_CHARS) {
      return new Response(JSON.stringify({ error: `text exceeds ${MAX_TEXT_CHARS} chars` }), {
        status: 413, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    // Server-side voice/model allowlist — clients cannot pick arbitrary
    // ElevenLabs voices or models that would shift cost or content profile.
    const requestedVoice = (body.voice_id ?? "").trim();
    const voiceId = ALLOWED_VOICE_IDS.has(requestedVoice) ? requestedVoice : DEFAULT_VOICE_ID;
    const modelId = DEFAULT_MODEL_ID;

    const elevenRes = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}/stream?output_format=mp3_44100_128`,
      {
        method: "POST",
        headers: {
          "xi-api-key":   ELEVENLABS_KEY,
          "Content-Type": "application/json",
          "Accept":       "audio/mpeg",
        },
        body: JSON.stringify({
          text,
          model_id: modelId,
          voice_settings: {
            stability: 0.6,
            similarity_boost: 0.75,
            style: 0.15,
            use_speaker_boost: true,
          },
        }),
      }
    );

    if (!elevenRes.ok || !elevenRes.body) {
      const txt = await elevenRes.text();
      console.error(`[orb-tts] upstream ${elevenRes.status}: ${txt.slice(0, 200)}`);
      return new Response(JSON.stringify({ error: "voice service unavailable" }), {
        status: 502, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    return new Response(elevenRes.body, {
      headers: {
        ...CORS,
        "Content-Type": "audio/mpeg",
        "Cache-Control": "no-store",
      },
    });
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    console.error("[orb-tts] ERROR:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
