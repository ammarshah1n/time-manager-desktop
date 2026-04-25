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
// Caller auth: Supabase anon JWT (Authorization: Bearer <ANON_KEY>).
// Body — pick one:
//   { audio_url: string,   model?: string, language?: string, smart_format?: bool }
//   { audio_base64: string, mime?: string, model?: string, language?: string, smart_format?: bool }
// Response: { transcript: string, confidence: number, duration_seconds: number, raw: <deepgram response> }

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireEnv } from "../_shared/config.ts";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const DEEPGRAM_KEY = requireEnv("DEEPGRAM_API_KEY");

type Payload = {
  audio_url?: string;
  audio_base64?: string;
  mime?: string;          // e.g. "audio/wav", "audio/mpeg" — required when sending base64
  model?: string;         // default "nova-3"
  language?: string;      // default "en"
  smart_format?: boolean; // default true
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: CORS });
  }

  const payload = await req.json().catch(() => null) as Payload | null;
  if (!payload || (!payload.audio_url && !payload.audio_base64)) {
    return new Response("Provide `audio_url` or `audio_base64`", {
      status: 400, headers: { ...CORS, "Content-Type": "text/plain" },
    });
  }

  const params = new URLSearchParams({
    model:        payload.model ?? "nova-3",
    language:     payload.language ?? "en",
    smart_format: String(payload.smart_format ?? true),
  });
  const dgURL = `https://api.deepgram.com/v1/listen?${params.toString()}`;

  let dgResponse: Response;
  if (payload.audio_url) {
    dgResponse = await fetch(dgURL, {
      method: "POST",
      headers: {
        "Authorization": `Token ${DEEPGRAM_KEY}`,
        "Content-Type":  "application/json",
      },
      body: JSON.stringify({ url: payload.audio_url }),
    });
  } else {
    const mime = payload.mime ?? "audio/wav";
    const audioBytes = Uint8Array.from(atob(payload.audio_base64!), c => c.charCodeAt(0));
    dgResponse = await fetch(dgURL, {
      method: "POST",
      headers: {
        "Authorization": `Token ${DEEPGRAM_KEY}`,
        "Content-Type":  mime,
      },
      body: audioBytes,
    });
  }

  if (!dgResponse.ok) {
    const detail = await dgResponse.text().catch(() => "(no body)");
    return new Response(`Deepgram ${dgResponse.status}: ${detail}`, {
      status: 502, headers: { ...CORS, "Content-Type": "text/plain" },
    });
  }

  const raw = await dgResponse.json();
  const channel  = raw?.results?.channels?.[0];
  const alt      = channel?.alternatives?.[0];
  const transcript = alt?.transcript ?? "";
  const confidence = alt?.confidence ?? 0;
  const duration   = raw?.metadata?.duration ?? 0;

  return new Response(JSON.stringify({ transcript, confidence, duration_seconds: duration, raw }), {
    status: 200,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
});
