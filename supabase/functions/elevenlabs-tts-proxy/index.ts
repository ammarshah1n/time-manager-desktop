// elevenlabs-tts-proxy
//
// Server-side proxy for ElevenLabs one-shot TTS. Lets the Swift app speak
// without shipping ELEVENLABS_API_KEY in the binary. Streams MP3 back to the
// client so playback can start before the full audio is ready.
//
// Caller auth: Supabase user JWT (Authorization: Bearer <access_token>).
// Body: { text: string, voice_id?: string, model_id?: string }
// Response: audio/mpeg byte stream.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireEnv } from "../_shared/config.ts";
import { AuthError, authErrorResponse, verifyAuth } from "../_shared/auth.ts";

const CORS = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "null",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const ELEVENLABS_KEY = requireEnv("ELEVENLABS_API_KEY");
const DEFAULT_VOICE = "pFZP5JQG7iQjIQuC4Bku"; // Lily — warm female
const DEFAULT_MODEL = "eleven_turbo_v2_5";
const MAX_TEXT_CHARS = 5_000;
const ALLOWED_VOICES = new Set([
  DEFAULT_VOICE,
  ...((Deno.env.get("ELEVENLABS_ALLOWED_VOICE_IDS") ?? "")
    .split(",")
    .map((voice) => voice.trim())
    .filter(Boolean)),
]);
const ALLOWED_MODELS = new Set([
  DEFAULT_MODEL,
  ...((Deno.env.get("ELEVENLABS_ALLOWED_MODEL_IDS") ?? "")
    .split(",")
    .map((model) => model.trim())
    .filter(Boolean)),
]);

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

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: CORS });
  }

  try {
    await verifyAuth(req);

    const payload = await req.json().catch(() => null) as
      | { text?: string; voice_id?: string; model_id?: string }
      | null;
    if (!payload?.text) return jsonError(400, "Missing `text`");
    if (payload.text.length > MAX_TEXT_CHARS) {
      return jsonError(413, `text exceeds ${MAX_TEXT_CHARS} characters`);
    }

    const voiceId = payload.voice_id ?? DEFAULT_VOICE;
    const modelId = payload.model_id ?? DEFAULT_MODEL;
    if (!ALLOWED_VOICES.has(voiceId)) {
      return jsonError(400, "voice_id is not allowed");
    }
    if (!ALLOWED_MODELS.has(modelId)) {
      return jsonError(400, "model_id is not allowed");
    }

    const upstream = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
      {
        method: "POST",
        headers: {
          "xi-api-key": ELEVENLABS_KEY,
          "Content-Type": "application/json",
          "Accept": "audio/mpeg",
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
      },
    );

    if (!upstream.ok) {
      console.error(`[elevenlabs-tts-proxy] upstream ${upstream.status}`);
      return jsonError(502, `upstream provider returned ${upstream.status}`);
    }

    return new Response(upstream.body, {
      status: 200,
      headers: {
        ...CORS,
        "Content-Type": "audio/mpeg",
        "Cache-Control": "no-cache",
      },
    });
  } catch (err) {
    if (err instanceof AuthError) return withCors(authErrorResponse(err));
    console.error("[elevenlabs-tts-proxy] ERROR:", err);
    return jsonError(500, "internal error");
  }
});
