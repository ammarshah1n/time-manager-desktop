// classify-email/index.ts
// Classifies a single email message into: inbox | later | black_hole | cc_fyi
// Model: Claude Haiku 4.5 (fast + cheap for high-volume classification)
// Uses prompt caching: system instructions + sender rules + corrections cached
// See: ~/Timed-Brain/06 - Context/prompt-engineering-ai-calls.md

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.27.0";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);
const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! });

serve(async (req: Request) => {
  const { emailMessageId, workspaceId, profileId } = await req.json();
  if (!emailMessageId || !workspaceId || !profileId) {
    return new Response(
      JSON.stringify({ error: "Missing required fields" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Log pipeline start
  const { data: run } = await supabase
    .from("ai_pipeline_runs")
    .insert({
      workspace_id: workspaceId,
      pipeline_name: "classify-email",
      entity_type: "email_message",
      entity_id: emailMessageId,
      model: "claude-haiku-4-5-20251001",
      status: "running",
    })
    .select()
    .single();

  const startTime = Date.now();

  try {
    // Fetch email + sender rules + recent corrections
    const [emailResult, senderRulesResult, correctionsResult] =
      await Promise.all([
        supabase
          .from("email_messages")
          .select("id,from_address,subject,snippet,to_addresses,cc_addresses")
          .eq("id", emailMessageId)
          .single(),
        supabase
          .from("sender_rules")
          .select("from_address,rule_type")
          .eq("workspace_id", workspaceId)
          .eq("profile_id", profileId),
        supabase
          .from("email_triage_corrections")
          .select("from_address,old_bucket,new_bucket,subject_snippet")
          .eq("workspace_id", workspaceId)
          .order("created_at", { ascending: false })
          .limit(15),
      ]);

    const email = emailResult.data!;
    const senderRules = senderRulesResult.data ?? [];
    const corrections = correctionsResult.data ?? [];

    // Check CC-only rule first (deterministic, no AI needed)
    const toPrimary = email.to_addresses as string[];
    const ccList = email.cc_addresses as string[];
    // TODO: check if profile email is only in CC, not TO → route to cc_fyi

    // Build sender rule maps
    const inboxAlways = senderRules
      .filter((r: { rule_type: string }) => r.rule_type === "inbox_always")
      .map((r: { from_address: string }) => r.from_address);
    const blackHole = senderRules
      .filter((r: { rule_type: string }) => r.rule_type === "black_hole")
      .map((r: { from_address: string }) => r.from_address);

    // Format corrections for few-shot
    const correctionText = corrections
      .map(
        (c: { from_address: string; old_bucket: string; new_bucket: string; subject_snippet: string }) =>
          `From: ${c.from_address} | Subject: ${c.subject_snippet ?? "?"} | ${c.old_bucket} → ${c.new_bucket}`
      )
      .join("\n");

    // System prompt — CACHED (stable per user, refreshed daily)
    const systemPrompt = `You are an email classifier for an executive productivity assistant.

Classify each email into exactly one bucket:
- inbox: Requires action, decision, or reply. Known/important sender.
- later: Informational, FYI, newsletters, receipts. No action needed now.
- black_hole: Marketing, automated alerts, notifications the user never acts on.
- cc_fyi: User is only in CC/BCC, not in TO field.

CRITICAL RULES:
1. If sender in INBOX_ALWAYS → return inbox regardless of content.
2. If sender in BLACK_HOLE → return black_hole regardless of content.
3. Uncertain between inbox/later → choose later (conservative).
4. Uncertain between later/black_hole → choose black_hole.
5. NEVER black_hole if: urgent, action required, invoice, payment, legal, deadline.
6. Confidence: 0.95+ for sender-rule match. 0.70-0.85 for content-only.`;

    const userMessage = `INBOX_ALWAYS senders: ${inboxAlways.join(", ") || "none"}
BLACK_HOLE senders: ${blackHole.join(", ") || "none"}

PAST CORRECTIONS (recent training signal):
${correctionText || "none yet"}

---
CLASSIFY THIS EMAIL:
From: ${email.from_address}
Subject: ${email.subject ?? "(no subject)"}
Preview: ${email.snippet ?? "(empty)"}`;

    // Claude Haiku call with prompt caching
    const message = await anthropic.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 256,
      system: [
        {
          type: "text",
          text: systemPrompt,
          // @ts-ignore — cache_control is a valid Anthropic API field
          cache_control: { type: "ephemeral" },
        },
      ],
      messages: [{ role: "user", content: userMessage }],
      tools: [
        {
          name: "classify",
          description: "Return classification result",
          input_schema: {
            type: "object",
            properties: {
              bucket: {
                type: "string",
                enum: ["inbox", "later", "black_hole", "cc_fyi"],
              },
              confidence: { type: "number" },
              reasoning: { type: "string" },
            },
            required: ["bucket", "confidence", "reasoning"],
            additionalProperties: false,
          },
        },
      ],
      tool_choice: { type: "tool", name: "classify" },
    });

    const toolResult = message.content.find((b) => b.type === "tool_use");
    if (!toolResult || toolResult.type !== "tool_use") {
      throw new Error("No tool_use block in response");
    }
    const result = toolResult.input as {
      bucket: string;
      confidence: number;
      reasoning: string;
    };

    // Update email classification
    await supabase
      .from("email_messages")
      .update({
        triage_bucket: result.bucket,
        triage_confidence: result.confidence,
        triage_source: "ai",
        updated_at: new Date().toISOString(),
      })
      .eq("id", emailMessageId);

    // Update pipeline run
    await supabase
      .from("ai_pipeline_runs")
      .update({
        status: "success",
        input_tokens: message.usage.input_tokens,
        output_tokens: message.usage.output_tokens,
        cached_tokens: (message.usage as { cache_read_input_tokens?: number })
          .cache_read_input_tokens ?? 0,
        duration_ms: Date.now() - startTime,
        completed_at: new Date().toISOString(),
      })
      .eq("id", run?.id);

    return new Response(JSON.stringify({ bucket: result.bucket, confidence: result.confidence }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    await supabase
      .from("ai_pipeline_runs")
      .update({
        status: "failed",
        error_message: errorMsg,
        duration_ms: Date.now() - startTime,
        completed_at: new Date().toISOString(),
      })
      .eq("id", run?.id);

    return new Response(JSON.stringify({ error: errorMsg }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
