// elevenlabs-tts-proxy
//
// Server-side proxy for ElevenLabs one-shot TTS. Lets the Swift app speak
// without shipping ELEVENLABS_API_KEY in the binary. Streams MP3 back to the
// client so playback can start before the full audio is ready.
//
// Caller auth: Supabase anon JWT (Authorization: Bearer <ANON_KEY>).
// Body: { text: string, voice_id?: string, model_id?: string }
// Response: audio/mpeg byte stream.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireEnv } from "../_shared/config.ts";

const CORS = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "null",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ELEVENLABS_KEY = requireEnv("ELEVENLABS_API_KEY");
const DEFAULT_VOICE  = "pFZP5JQG7iQjIQuC4Bku"; // Lily — warm female
const DEFAULT_MODEL  = "eleven_turbo_v2_5";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: CORS });
  }

  const payload = await req.json().catch(() => null) as
    | { text?: string; voice_id?: string; model_id?: string }
    | null;
  if (!payload?.text) {
    return new Response("Missing `text`", { status: 400, headers: CORS });
  }

  const voiceId = payload.voice_id ?? DEFAULT_VOICE;
  const modelId = payload.model_id ?? DEFAULT_MODEL;

  const upstream = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: "POST",
    headers: {
      "xi-api-key":   ELEVENLABS_KEY,
      "Content-Type": "application/json",
      "Accept":       "audio/mpeg",
    },
    body: JSON.stringify({
      text: payload.text,
      model_id: modelId,
      voice_settings: {
        stability: 0.6,
        similarity_boost: 0.75,
        style: 0.15,
        use_speaker_boost: true,
      },
    }),
  });

  if (!upstream.ok) {
    const detail = await upstream.text().catch(() => "(no body)");
    return new Response(`ElevenLabs ${upstream.status}: ${detail}`, {
      status: 502,
      headers: { ...CORS, "Content-Type": "text/plain" },
    });
  }

  return new Response(upstream.body, {
    status: 200,
    headers: {
      ...CORS,
      "Content-Type":  "audio/mpeg",
      "Cache-Control": "no-cache",
    },
  });
});
