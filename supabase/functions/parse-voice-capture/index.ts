// parse-voice-capture/index.ts
// Parses a raw voice transcript into structured task items using Claude Haiku.
// Model: claude-haiku-4-5-20251001
// Called after VoiceCaptureService records a session.
// Saves extracted items to voice_capture_items, updates voice_captures.status.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.27.0";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);
const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! });

interface ExtractedItem {
  title: string;
  bucket_type: "action" | "calls" | "reply_email" | "read_today" | "other";
  estimated_minutes: number | null;
  due_date: string | null;
}

serve(async (req: Request) => {
  const { voiceCaptureId, workspaceId, profileId, transcript } = await req.json();

  if (!voiceCaptureId || !workspaceId || !profileId || !transcript) {
    return new Response(
      JSON.stringify({ error: "Missing required fields: voiceCaptureId, workspaceId, profileId, transcript" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const startTime = Date.now();

  try {
    // Call Claude Haiku to extract task items
    const message = await anthropic.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 512,
      system: [
        {
          type: "text",
          text: `You are a task extraction assistant for an executive. Given a voice transcript, extract each distinct task as a JSON array. Each item: { "title": string, "bucket_type": "action"|"calls"|"reply_email"|"read_today"|"other", "estimated_minutes": integer|null, "due_date": ISO8601 string|null }. Return ONLY valid JSON array, no prose.`,
          // @ts-ignore
          cache_control: { type: "ephemeral" },
        },
      ],
      messages: [
        {
          role: "user",
          content: transcript,
        },
      ],
    });

    const text = message.content.find((b) => b.type === "text")?.text ?? "[]";
    const jsonMatch = text.match(/\[[\s\S]*\]/);
    if (!jsonMatch) {
      throw new Error("Claude returned no valid JSON array");
    }
    const items: ExtractedItem[] = JSON.parse(jsonMatch[0]);

    // Insert each extracted item into voice_capture_items
    const insertPayload = items.map((item) => ({
      voice_capture_id: voiceCaptureId,
      workspace_id: workspaceId,
      title: item.title,
      bucket_type: item.bucket_type,
      estimated_minutes: item.estimated_minutes,
      due_date: item.due_date,
      extraction_confidence: 0.75,
      is_converted: false,
    }));

    const { error: insertError } = await supabase
      .from("voice_capture_items")
      .insert(insertPayload);

    if (insertError) throw new Error(`Insert voice_capture_items failed: ${insertError.message}`);

    // Update voice_captures status to 'parsed'
    const { error: updateError } = await supabase
      .from("voice_captures")
      .update({
        status: "parsed",
        parsed_at: new Date().toISOString(),
      })
      .eq("id", voiceCaptureId);

    if (updateError) throw new Error(`Update voice_captures failed: ${updateError.message}`);

    // Log to ai_pipeline_runs
    await supabase.from("ai_pipeline_runs").insert({
      workspace_id: workspaceId,
      profile_id: profileId,
      function_name: "parse-voice-capture",
      model: "claude-haiku-4-5-20251001",
      input_tokens: message.usage.input_tokens,
      output_tokens: message.usage.output_tokens,
      cached_tokens: (message.usage as { cache_read_input_tokens?: number }).cache_read_input_tokens ?? 0,
      latency_ms: Date.now() - startTime,
      status: "success",
    });

    return new Response(
      JSON.stringify({ itemCount: items.length, items }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error("[parse-voice-capture] error:", errorMsg);

    // Update voice_captures status to 'parse_failed'
    await supabase
      .from("voice_captures")
      .update({ status: "parse_failed" })
      .eq("id", voiceCaptureId);

    // Log failure to ai_pipeline_runs
    await supabase.from("ai_pipeline_runs").insert({
      workspace_id: workspaceId,
      profile_id: profileId,
      function_name: "parse-voice-capture",
      model: "claude-haiku-4-5-20251001",
      input_tokens: 0,
      output_tokens: 0,
      cached_tokens: 0,
      latency_ms: Date.now() - startTime,
      status: "error",
      error_message: errorMsg,
    });

    return new Response(
      JSON.stringify({ error: errorMsg }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
