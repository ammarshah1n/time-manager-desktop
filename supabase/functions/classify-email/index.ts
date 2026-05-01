// classify-email/index.ts
// Classifies a single email message into: inbox | later | black_hole | cc_fyi
// Model: Claude Haiku 3.5 (fast + cheap for high-volume 4-class classification)
// Uses prompt caching: system instructions + sender rules + corrections cached
// Auth: JWT verified via _shared/auth.ts
// Resilience: withRetry + CircuitBreaker via _shared/retry.ts
// See: ~/Timed-Brain/06 - Context/prompt-engineering-ai-calls.md

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.27.0";
import { AuthError, authErrorResponse, verifyAuth } from "../_shared/auth.ts";
import { CircuitBreaker, withRetry } from "../_shared/retry.ts";
import { requireEnv } from "../_shared/config.ts";

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
);
const anthropic = new Anthropic({ apiKey: requireEnv("ANTHROPIC_API_KEY") });

// Circuit breaker: trips after 5 Anthropic failures, resets after 2 min
const classifyBreaker = new CircuitBreaker(
  5,
  2 * 60 * 1000,
  "classify-email-anthropic",
);

serve(async (req: Request) => {
  // JWT auth + tenant resolution. Body-supplied workspaceId/profileId is
  // validated against the authenticated executive — service role bypasses
  // RLS, so we cannot trust body-supplied tenant IDs.
  let authUserId: string;
  try {
    authUserId = await verifyAuth(req);
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    return new Response(JSON.stringify({ error: "Auth failed" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: exec, error: execErr } = await supabase
    .from("executives")
    .select("id")
    .eq("auth_user_id", authUserId)
    .maybeSingle();
  if (execErr || !exec) {
    return new Response(
      JSON.stringify({ error: "No executive row for this user" }),
      {
        status: 401,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
  const executiveId = exec.id as string;

  const {
    emailMessageId,
    workspaceId,
    profileId,
    sender_importance: senderImportance,
  } = await req.json();
  if (!emailMessageId || !workspaceId || !profileId) {
    return new Response(
      JSON.stringify({ error: "Missing required fields" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }
  // Reject any cross-tenant ID in the body.
  if (workspaceId !== executiveId || profileId !== executiveId) {
    return new Response(JSON.stringify({ error: "Tenant mismatch" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Log pipeline start
  const { data: run } = await supabase
    .from("ai_pipeline_runs")
    .insert({
      workspace_id: workspaceId,
      pipeline_name: "classify-email",
      entity_type: "email_message",
      entity_id: emailMessageId,
      model: "claude-haiku-3-5-20241022",
      status: "running",
    })
    .select()
    .single();

  const startTime = Date.now();

  try {
    // Fetch email + sender rules + recent corrections
    const [emailResult, senderRulesResult] = await Promise.all([
      supabase
        .from("email_messages")
        .select("id,from_address,subject,snippet,to_addresses,cc_addresses")
        .eq("id", emailMessageId)
        .eq("workspace_id", workspaceId)
        .single(),
      supabase
        .from("sender_rules")
        .select("from_address,rule_type")
        .eq("workspace_id", workspaceId)
        .eq("profile_id", profileId),
    ]);

    const email = emailResult.data!;
    const senderRules = senderRulesResult.data ?? [];

    // Generate embedding for similarity-based correction retrieval
    const inputText = `${email.subject ?? ""} ${email.from_address} ${
      email.snippet ?? ""
    }`.trim();
    let embedding: number[] | null = null;
    const jinaKey = Deno.env.get("JINA_API_KEY");
    if (jinaKey && inputText) {
      const embResp = await fetch("https://api.jina.ai/v1/embeddings", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${jinaKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "jina-embeddings-v3",
          input: [inputText],
          task: "retrieval.passage",
          dimensions: 1024,
        }),
      });
      const embJson = await embResp.json();
      embedding = embJson.data?.[0]?.embedding ?? null;

      if (embedding) {
        await supabase.from("email_messages")
          .update({ embedding: JSON.stringify(embedding) })
          .eq("id", emailMessageId)
          .eq("workspace_id", workspaceId);
      }
    }

    // Fetch corrections: similarity-based if embedding available, recency fallback
    let corrections;
    if (embedding) {
      const { data } = await supabase.rpc("similar_corrections", {
        p_workspace_id: workspaceId,
        p_embedding: JSON.stringify(embedding),
        p_threshold: 0.5,
        p_limit: 10,
      });
      corrections = data ?? [];
    } else {
      // Fallback to recency if embedding failed
      const { data } = await supabase.from("email_triage_corrections")
        .select("from_address,old_bucket,new_bucket,subject_snippet")
        .eq("workspace_id", workspaceId)
        .order("created_at", { ascending: false })
        .limit(15);
      corrections = data ?? [];
    }

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
    const laterSenders = senderRules
      .filter((r: { rule_type: string }) => r.rule_type === "later")
      .map((r: { from_address: string }) => r.from_address);
    const delegateSenders = senderRules
      .filter((r: { rule_type: string }) => r.rule_type === "delegate")
      .map((r: { from_address: string }) => r.from_address);

    // Build soft-prior hint for THIS email's sender
    const senderAddr = email.from_address;
    const senderPriors: string[] = [];
    const matchedRule = senderRules.find(
      (r: { from_address: string }) => r.from_address === senderAddr,
    );
    if (matchedRule) {
      const ruleHints: Record<string, string> = {
        inbox_always:
          `Emails from ${senderAddr} are almost always high-priority (Do First). Classify as inbox unless content is clearly irrelevant.`,
        black_hole:
          `Emails from ${senderAddr} are almost always noise. Classify as black_hole unless content is clearly urgent or actionable.`,
        later:
          `Emails from ${senderAddr} are usually deferred/low-priority. Lean toward later unless this specific email demands action.`,
        delegate:
          `Emails from ${senderAddr} are usually delegated to someone else. Lean toward later or cc_fyi unless the user is directly asked to act.`,
        informational:
          `Emails from ${senderAddr} are usually informational. Lean toward later unless urgent action is required.`,
        do_first:
          `Emails from ${senderAddr} are usually high-priority (Do First). Lean toward inbox unless content is clearly trivial.`,
      };
      const hint = ruleHints[(matchedRule as { rule_type: string }).rule_type];
      if (hint) senderPriors.push(hint);
    }

    // Format corrections for few-shot
    const correctionText = corrections
      .map(
        (
          c: {
            from_address: string;
            old_bucket: string;
            new_bucket: string;
            subject_snippet: string;
          },
        ) =>
          `From: ${c.from_address} | Subject: ${
            c.subject_snippet ?? "?"
          } | ${c.old_bucket} → ${c.new_bucket}`,
      )
      .join("\n");

    // System prompt — CACHED (stable per user, refreshed daily)
    const systemPrompt =
      `You are an email classifier for an executive productivity assistant.

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
6. Confidence: 0.95+ for sender-rule match. 0.70-0.85 for content-only.
7. SENDER PRIORS are soft hints from learned patterns — they bias your decision but can be overridden by email content.` +
      (senderPriors.length > 0
        ? `\n\nSENDER PRIOR FOR THIS EMAIL:\n${senderPriors.join("\n")}`
        : "");

    const userMessage = `INBOX_ALWAYS senders: ${
      inboxAlways.join(", ") || "none"
    }
BLACK_HOLE senders: ${blackHole.join(", ") || "none"}
LATER senders (high probability later, but content may override): ${
      laterSenders.join(", ") || "none"
    }
DELEGATE senders (likely action, but not for this user — forward or delegate): ${
      delegateSenders.join(", ") || "none"
    }

PAST CORRECTIONS (${
      embedding ? "similarity-ranked" : "recent"
    } training signal):
${correctionText || "none yet"}

---
CLASSIFY THIS EMAIL:
From: ${email.from_address}
Subject: ${email.subject ?? "(no subject)"}
Preview: ${email.snippet ?? "(empty)"}
This sender has a historical importance score of ${
      senderImportance?.toFixed(2) ?? "unknown"
    } (0=low, 1=high based on how quickly the user replies to this sender).`;

    // Circuit breaker check — if Anthropic is down, fail fast
    if (!classifyBreaker.allowRequest()) {
      const cbState = classifyBreaker.getState();
      throw new Error(
        `Circuit breaker open (${cbState.failures} failures) — Anthropic calls blocked, retry after reset`,
      );
    }

    // Claude Haiku call with prompt caching + retry + circuit breaker
    let message: any;
    try {
      message = await withRetry(
        () =>
          anthropic.messages.create({
            model: "claude-haiku-3-5-20241022",
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
          }),
        { label: "classify-email-anthropic" },
      );
      classifyBreaker.recordSuccess();
    } catch (err) {
      classifyBreaker.recordFailure();
      throw err;
    }

    const toolResult = message.content.find((b: { type: string }) =>
      b.type === "tool_use"
    );
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
      .eq("id", emailMessageId)
      .eq("workspace_id", workspaceId);

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

    return new Response(
      JSON.stringify({ bucket: result.bucket, confidence: result.confidence }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
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
