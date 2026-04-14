import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";
import { createRequestLogger } from "../_shared/logger.ts";
import { requireEnv } from "../_shared/config.ts";

// Phase 10.01: Voice Feature Extraction via Gemini Audio API
// Replaces openSMILE C++ bridge — 10-15 lines vs weeks of interop
// Audio segments (30-second chunks) → structured acoustic features
// Cost: ~$0.0015/minute, 8h/day ≈ $0.72/day

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");

serve(async (req: Request) => {
  const log = createRequestLogger("extract-voice-features");
  try {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  try {
    await verifyAuth(req);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    throw err;
  }

  if (!GEMINI_API_KEY) {
    return new Response(JSON.stringify({ error: "GEMINI_API_KEY not configured" }), { status: 500 });
  }

  // Accept audio as base64 or reference
  let body: {
    executive_id: string;
    audio_base64?: string;
    audio_url?: string;
    duration_seconds?: number;
  } | null = null;

  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid request body" }), { status: 400 });
  }

  if (!body?.executive_id || (!body.audio_base64 && !body.audio_url)) {
    return new Response(JSON.stringify({ error: "executive_id and audio_base64 or audio_url required" }), { status: 400 });
  }

  // Prepare Gemini request
  const audioContent = body.audio_base64
    ? { inline_data: { mime_type: "audio/wav", data: body.audio_base64 } }
    : { file_data: { mime_type: "audio/wav", file_uri: body.audio_url! } };

  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{
          parts: [
            audioContent,
            {
              text: `Analyse this audio segment and extract the following acoustic features. Return ONLY a JSON object, no explanation.

{
  "f0_mean_hz": <fundamental frequency mean>,
  "f0_variance": <F0 variance>,
  "f0_contour": "rising|falling|flat|variable",
  "jitter_percent": <cycle-to-cycle F0 variation>,
  "shimmer_percent": <cycle-to-cycle amplitude variation>,
  "hnr_db": <harmonics-to-noise ratio>,
  "speech_rate_syllables_per_sec": <syllables per second>,
  "disfluency_rate": <filled pauses + restarts per minute>,
  "spectral_centroid_hz": <brightness of voice>,
  "speaking_time_ratio": <fraction of segment with speech>,
  "confidence": <0.0-1.0 overall feature extraction confidence>,
  "cognitive_indicators": {
    "stress_level": "low|moderate|high",
    "fatigue_indicators": true/false,
    "engagement_level": "low|moderate|high"
  }
}`
            },
          ],
        }],
        generationConfig: {
          temperature: 0.0,
          maxOutputTokens: 1024,
        },
      }),
    }
  );

  if (!geminiResponse.ok) {
    const error = await geminiResponse.text();
    return new Response(JSON.stringify({ error: "Gemini API error", detail: error }), {
      status: geminiResponse.status,
    });
  }

  const geminiResult = await geminiResponse.json();
  const text = geminiResult.candidates?.[0]?.content?.parts?.[0]?.text ?? "";

  let features;
  try {
    features = JSON.parse(text);
  } catch {
    // Try to extract JSON from markdown code block
    const match = text.match(/```json?\s*([\s\S]*?)```/);
    if (match) {
      try { features = JSON.parse(match[1]); } catch { features = { raw: text }; }
    } else {
      features = { raw: text };
    }
  }

  log.info("complete", { executive_id: body.executive_id, duration_seconds: body.duration_seconds });
  return new Response(JSON.stringify({
    status: "ok",
    executive_id: body.executive_id,
    duration_seconds: body.duration_seconds,
    features,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    log.error("unhandled", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Internal error", request_id: log.request_id }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
