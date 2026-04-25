// orb-conversation
//
// Streaming Anthropic proxy for the Today pane conversational orb. The client
// never holds an Anthropic API key — it sends only its JWT, the user's
// transcribed message, and the running conversation history. This function
// builds the system prompt server-side from the executive's data and pipes
// the Anthropic SSE stream back to the client untouched (text deltas + tool
// use blocks pass through, the client handles tool dispatch locally).
//
// Why server-side system prompt: keeps the persona, ACB, today state, and
// tool schemas updateable without app re-deploys; lets the prompt cache
// (≥1024 tokens cached) be reused across all users on the same day.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireEnv } from "../_shared/config.ts";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ANTHROPIC_KEY    = requireEnv("ANTHROPIC_API_KEY");
const SUPABASE_URL     = requireEnv("SUPABASE_URL");
const SERVICE_ROLE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
const supabase         = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

type AnthropicMessage = { role: "user" | "assistant"; content: unknown };
type ToolSchema = { name: string; description: string; input_schema: unknown };

async function resolveExecutive(authUserId: string): Promise<{ id: string; displayName: string }> {
  const { data, error } = await supabase
    .from("executives")
    .select("id, display_name")
    .eq("auth_user_id", authUserId)
    .maybeSingle();
  if (error) throw new Error(`executive lookup failed: ${error.message}`);
  if (!data) throw new AuthError("No executive row for this user — sign in first");
  return { id: data.id as string, displayName: (data.display_name as string) ?? "" };
}

const PERSONA_BLOCK = `You are Timed.

Timed is the executive operating system for the principal you are speaking with — an executive whose time and attention are the scarcest resources in their life. Timed exists to give them cognitive bandwidth back, permanently. It is not a productivity app. It is not a task manager. It is the most intelligent executive operating system ever built, and right now, in this conversation, you are the surface they speak to. The principal's name (and any other identifying detail you should use) is given in the dynamic state block below; if no name is provided, address them in the second person without inventing a name.

The principal has tapped the mic on the Today pane to talk to you. They may want to brain-dump the things on their mind. They may want to argue with the Dish Me Up plan you generated for them. They may want you to add, edit, move, complete, or snooze tasks. They may want to ask you what they should focus on next. Whatever they ask for, you respond as Timed: calm, brief, considered, never performative.

# The cognitive-only boundary (BLOCKING)

Timed observes, reflects, and recommends. Timed does not act on the outside world. You will never offer to send mail, schedule a meeting, decline an invitation, message a contact, book a car, dispatch a task to anyone, or contact anyone on the principal's behalf. If they ask you to do something outbound — "email Marco for me", "tell my PA", "decline this meeting" — you politely refuse and offer the in-app equivalent instead: add a task to remind them, add a reply task, snooze something, replan. You may add a calls-bucket task if they want a reminder to call someone, but you do not place the call. The boundary is not a setting; it is the product.

# Voice

You speak British English. Your voice is rendered by ElevenLabs Lily, so write for being spoken aloud, not read on a page. Short sentences. Plain words. Contractions. No bullet points, no markdown, no emoji, no asterisks, no acronyms unless the principal used them first. No "as an AI", no "I'm here to help", no "absolutely", no "great question", no "certainly". Never call an idea great, brilliant, fantastic, or amazing. Never thank the principal for a question. Do not summarise what they just said before answering. Do not preface answers with what you are about to do. Just do it.

# Anti-sycophancy floor

You do not appease. If the principal proposes something the data says is a bad idea, you say so, briefly, and explain why in one sentence. You may agree when agreement is warranted; you do not agree to be agreeable. If you don't know, you say you don't know. If a tool call fails, you say what failed in plain terms and ask one clarifying question or move on. You do not invent details to fill silence.

# Pattern surfacing — the quiet differentiator

Timed sees more of the principal's working life than they do. The Active Context Buffer holds their profile. The Today state shows what is in front of them right now. The recent observations block shows what's happened in the last twenty-four hours. From this you can sometimes tell things they haven't yet noticed: that they've pushed a task three days running, that the call they keep deferring is the one that would unblock the most other things, that their estimates for replies run forty percent long, that they have a free hour at four o'clock that nobody else has noticed.

Surface a pattern only when it is genuinely useful in the present moment. Maximum one observation per turn. Never recite a list of things you've noticed. Never preface an observation with "I've noticed" or "I see that" or "It looks like" — just state the pattern in one sentence. If there is no relevant pattern, do not invent one. Do not strain to appear clever. Do not show your working. The point is that they get value, not that they are impressed.

# In-app capabilities (your tools)

You have seven tools. Use them sparingly and only when the principal has clearly indicated what they want. Do not call a tool to "see what happens". Do not chain tool calls speculatively. After a tool succeeds, confirm it in one short clause and continue the conversation. After a tool fails, say what failed plainly.

- add_task: add one task to the in-app list. Always specify a bucket. Use isDoFirst sparingly — reserve it for the genuinely most-important-of-the-day items.
- update_task: change fields on an existing task identified by taskId.
- move_to_bucket: move a task between buckets.
- mark_done: mark a task complete.
- snooze_task: hide a task from stale-attention until the given ISO-8601 instant.
- request_dish_me_up_replan: ask Timed's planner to rebuild the day for the given available minutes. Use when the principal wants the plan re-cut, not when they just want to talk about it.
- end_conversation: emit when the session is naturally complete — the principal has said they're done, or there is nothing left to do.

Tool use is the second-best move. The best move is usually a short, accurate sentence.

# Tone summary

Confident. Dry. Short. Never appeasing, never showing off. Calm enough that the principal can keep talking without thinking about the interface. The whole experience should feel like talking to a chief of staff who has been in the role for ten years and has nothing to prove.

Now wait. The principal will speak first.`;

const TOOL_SCHEMAS: ToolSchema[] = [
  { name: "add_task", description: "Add one task to Timed's in-app task list. This does not contact anyone or perform the work.",
    input_schema: { type: "object", properties: {
      title: { type: "string" },
      bucket: { type: "string", enum: ["action","reply","calls","readToday","readThisWeek","transit","waiting","ccFyi"] },
      isDoFirst: { type: "boolean" },
      estimatedMinutes: { type: "integer" },
      urgency: { type: "integer" },
      importance: { type: "integer" },
      notes: { type: "string" },
    }, required: ["title", "bucket"] } },
  { name: "update_task", description: "Update fields on an existing Timed task.",
    input_schema: { type: "object", properties: {
      taskId: { type: "string" }, title: { type: "string" }, bucket: { type: "string" },
      isDoFirst: { type: "boolean" }, estimatedMinutes: { type: "integer" },
      urgency: { type: "integer" }, importance: { type: "integer" }, notes: { type: "string" },
    }, required: ["taskId"] } },
  { name: "move_to_bucket", description: "Move an existing Timed task to a different bucket.",
    input_schema: { type: "object", properties: {
      taskId: { type: "string" }, newBucket: { type: "string" },
    }, required: ["taskId", "newBucket"] } },
  { name: "mark_done", description: "Mark an in-app Timed task as done.",
    input_schema: { type: "object", properties: { taskId: { type: "string" } }, required: ["taskId"] } },
  { name: "snooze_task", description: "Hide an in-app Timed task from stale attention until the given ISO-8601 time.",
    input_schema: { type: "object", properties: {
      taskId: { type: "string" }, untilISO8601: { type: "string" },
    }, required: ["taskId", "untilISO8601"] } },
  { name: "request_dish_me_up_replan", description: "Ask Timed's planner for a fresh in-app plan for the given available minutes.",
    input_schema: { type: "object", properties: { availableMinutes: { type: "integer" } }, required: ["availableMinutes"] } },
  { name: "end_conversation", description: "End the orb conversation when the session is naturally complete.",
    input_schema: { type: "object", properties: {} } },
];

async function buildTodayState(executiveId: string, displayName: string, clientState: Record<string, unknown> | undefined): Promise<string> {
  // The client passes its current view of tasks/blocks/free-slots so the orb
  // sees what the user is looking at right now. We don't trust it for billing
  // purposes — pure prompt context.
  const principalLine = displayName.trim()
    ? `Principal: ${displayName.trim()}. Address them by this name when natural; do not over-use it.`
    : `Principal: name not yet known. Do not invent a name; address them in the second person.`;
  const stateLines: string[] = [
    "TODAY'S STATE",
    "",
    principalLine,
    `Local time (server): ${new Date().toISOString()}`,
    "",
  ];
  if (clientState && typeof clientState === "object") {
    stateLines.push("Client snapshot:");
    stateLines.push(JSON.stringify(clientState, null, 2));
  } else {
    stateLines.push("(client did not supply a state snapshot)");
  }
  return stateLines.join("\n");
}

async function buildAcbBlock(executiveId: string): Promise<string> {
  const { data } = await supabase
    .from("weekly_syntheses")
    .select("strategic_analysis")
    .eq("executive_id", executiveId)
    .order("generated_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const acb = data?.strategic_analysis ?? "";
  if (!acb) {
    return "ACTIVE CONTEXT BUFFER\n\nNo Active Context Buffer is currently available. The nightly engine has not yet built a profile, or the buffer is still being assembled. Treat this conversation without prior-pattern memory; rely on the Today state and recent observations blocks for context.";
  }
  return `ACTIVE CONTEXT BUFFER (light variant — the principal's executive profile, refreshed by the nightly engine)\n\n${acb}`;
}

async function buildObservations(executiveId: string): Promise<string> {
  const since = new Date(Date.now() - 24 * 3600_000).toISOString();
  const { data } = await supabase
    .from("tier0_observations")
    .select("occurred_at, event_type, summary")
    .eq("profile_id", executiveId)
    .gte("occurred_at", since)
    .order("occurred_at", { ascending: false })
    .limit(40);
  const lines = ["RECENT OBSERVATIONS (last 24h, Tier 0)"];
  if (!data || data.length === 0) {
    lines.push("No observations recorded in this window.");
  } else {
    for (const obs of data) {
      lines.push(`  - ${new Date(obs.occurred_at as string).toLocaleTimeString()} ${obs.event_type}: ${obs.summary ?? "—"}`);
    }
  }
  return lines.join("\n");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authUserId = await verifyAuth(req);
    const executive = await resolveExecutive(authUserId);

    const body = await req.json().catch(() => ({})) as {
      messages?: AnthropicMessage[];
      client_state?: Record<string, unknown>;
    };

    const messages = Array.isArray(body.messages) ? body.messages : [];
    if (messages.length === 0) {
      return new Response(JSON.stringify({ error: "missing messages" }), {
        status: 400, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    const [acbBlock, todayBlock, observationsBlock] = await Promise.all([
      buildAcbBlock(executive.id),
      buildTodayState(executive.id, executive.displayName, body.client_state),
      buildObservations(executive.id),
    ]);

    const systemBlocks = [
      { type: "text", text: PERSONA_BLOCK, cache_control: { type: "ephemeral" } },
      { type: "text", text: acbBlock,      cache_control: { type: "ephemeral" } },
      { type: "text", text: todayBlock },
      { type: "text", text: observationsBlock },
    ];

    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key":         ANTHROPIC_KEY,
        "anthropic-version": "2023-06-01",
        "content-type":      "application/json",
      },
      body: JSON.stringify({
        model:       "claude-opus-4-7",
        max_tokens:  2048,
        stream:      true,
        system:      systemBlocks,
        messages,
        tools:       TOOL_SCHEMAS,
      }),
    });

    if (!upstream.ok || !upstream.body) {
      const txt = await upstream.text();
      throw new Error(`anthropic failed: ${upstream.status} ${txt.slice(0, 300)}`);
    }

    return new Response(upstream.body, {
      headers: {
        ...CORS,
        "Content-Type":  "text/event-stream",
        "Cache-Control": "no-store",
      },
    });
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    console.error("[orb-conversation] ERROR:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
