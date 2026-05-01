// deepgram-transcribe
//
// Server-side proxy for Deepgram BATCH transcription. Holds DEEPGRAM_API_KEY
// so the client never ships it. Currently UNUSED in the live app — parked here
// because we have a Deepgram subscription and may want to use it for
// non-conversational paths later (e.g. recorded voice memos, meeting captures,
// long-form audio where Deepgram's accuracy + cost-per-minute beats Scribe).
//
// The conversational orb does NOT use this — it uses ElevenLabs Conversational
// AI (Scribe v2 Turbo for ASR, voice-llm-proxy for LLM, ElevenLabs voice for
// TTS) because that platform doesn't support external ASR providers.
//
// Caller auth: Supabase user JWT (Authorization: Bearer <access_token>).
// Body — pick one:
//   { audio_url: string,   model?: string, language?: string, smart_format?: bool }
//   { audio_base64: string, mime?: string, model?: string, language?: string, smart_format?: bool }
// Response: { transcript: string, confidence: number, duration_seconds: number, raw: <deepgram response> }

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireEnv } from "../_shared/config.ts";
import { AuthError, authErrorResponse, verifyAuth } from "../_shared/auth.ts";

const CORS = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "null",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const DEEPGRAM_KEY = requireEnv("DEEPGRAM_API_KEY");
const MAX_BASE64_CHARS = 20 * 1024 * 1024;
const ALLOWED_MODELS = new Set([
  "nova-3",
  ...((Deno.env.get("DEEPGRAM_ALLOWED_MODELS") ?? "")
    .split(",")
    .map((model) => model.trim())
    .filter(Boolean)),
]);

type Payload = {
  audio_url?: string;
  audio_base64?: string;
  mime?: string; // e.g. "audio/wav", "audio/mpeg" — required when sending base64
  model?: string; // default "nova-3"
  language?: string; // default "en"
  smart_format?: boolean; // default true
};

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

function isValidAudioUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:";
  } catch {
    return false;
  }
}

function isValidLanguage(value: string): boolean {
  return /^[a-z]{2}(-[A-Z]{2})?$/.test(value);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: CORS });
  }

  try {
    await verifyAuth(req);

    const payload = await req.json().catch(() => null) as Payload | null;
    if (!payload || (!payload.audio_url && !payload.audio_base64)) {
      return jsonError(400, "Provide `audio_url` or `audio_base64`");
    }
    if (payload.audio_url && payload.audio_base64) {
      return jsonError(400, "Provide only one audio source");
    }

    const model = payload.model ?? "nova-3";
    const language = payload.language ?? "en";
    if (!ALLOWED_MODELS.has(model)) {
      return jsonError(400, "model is not allowed");
    }
    if (!isValidLanguage(language)) {
      return jsonError(400, "language is invalid");
    }

    const params = new URLSearchParams({
      model,
      language,
      smart_format: String(payload.smart_format ?? true),
    });
    const dgURL = `https://api.deepgram.com/v1/listen?${params.toString()}`;

    let dgResponse: Response;
    if (payload.audio_url) {
      if (!isValidAudioUrl(payload.audio_url)) {
        return jsonError(400, "audio_url must be https");
      }
      dgResponse = await fetch(dgURL, {
        method: "POST",
        headers: {
          "Authorization": `Token ${DEEPGRAM_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ url: payload.audio_url }),
      });
    } else {
      if (payload.audio_base64!.length > MAX_BASE64_CHARS) {
        return jsonError(
          413,
          `audio_base64 exceeds ${MAX_BASE64_CHARS} characters`,
        );
      }
      const mime = payload.mime ?? "audio/wav";
      if (!mime.startsWith("audio/")) {
        return jsonError(400, "mime must be audio/*");
      }
      let audioBytes: Uint8Array;
      try {
        audioBytes = Uint8Array.from(
          atob(payload.audio_base64!),
          (c) => c.charCodeAt(0),
        );
      } catch {
        return jsonError(400, "audio_base64 is invalid");
      }
      dgResponse = await fetch(dgURL, {
        method: "POST",
        headers: {
          "Authorization": `Token ${DEEPGRAM_KEY}`,
          "Content-Type": mime,
        },
        body: audioBytes,
      });
    }

    if (!dgResponse.ok) {
      console.error(`[deepgram-transcribe] upstream ${dgResponse.status}`);
      return jsonError(502, `upstream provider returned ${dgResponse.status}`);
    }

    const raw = await dgResponse.json();
    const channel = raw?.results?.channels?.[0];
    const alt = channel?.alternatives?.[0];
    const transcript = alt?.transcript ?? "";
    const confidence = alt?.confidence ?? 0;
    const duration = raw?.metadata?.duration ?? 0;

    return new Response(
      JSON.stringify({
        transcript,
        confidence,
        duration_seconds: duration,
        raw,
      }),
      {
        status: 200,
        headers: { ...CORS, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    if (err instanceof AuthError) return withCors(authErrorResponse(err));
    console.error("[deepgram-transcribe] ERROR:", err);
    return jsonError(500, "internal error");
  }
});
