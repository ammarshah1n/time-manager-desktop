// voice-llm-proxy
//
// OpenAI-compatible streaming proxy. ElevenLabs Conversational AI 2.0 Custom
// LLM endpoint → this function → Anthropic Claude Opus with extended thinking.
// We emit OpenAI Chat Completions SSE chunks so ElevenLabs can consume them.
//
// CRITICAL: thinking tokens from extended thinking MUST NOT be streamed out.
// ElevenLabs's TTS would read them aloud. We only forward text_delta blocks.
//
// Yasser's context (overdue tasks, calendar, ACB, rules) is prepended to the
// first user message so Opus speaks from his actual day, not a blank canvas.
//
// Architecture: Voice-And-Learning-Engine.md Part 5.
//   - model:      claude-opus-4-6
//   - thinking:   { type: "enabled", budget_tokens: 10000 }
//   - user:       YASSER_USER_ID (env var, no auth, login built last)

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireEnv } from "../_shared/config.ts";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const YASSER_USER_ID   = requireEnv("YASSER_USER_ID");
const ANTHROPIC_KEY    = requireEnv("ANTHROPIC_API_KEY");
const SUPABASE_URL     = requireEnv("SUPABASE_URL");
const SERVICE_ROLE_KEY = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

// ─── OpenAI SSE framing ─────────────────────────────────────────────────────
function sseChunk(id: string, created: number, model: string, deltaText: string, done = false): string {
  const payload = {
    id,
    object: "chat.completion.chunk",
    created,
    model,
    choices: [{
      index: 0,
      delta: done ? {} : { role: "assistant", content: deltaText },
      finish_reason: done ? "stop" : null,
    }],
  };
  return `data: ${JSON.stringify(payload)}\n\n`;
}

// ─── Onboarding gate: null onboarded_at = voice setup; set = morning check-in
async function readOnboardedState(userId: string): Promise<{ onboarded: boolean; displayName: string | null }> {
  const { data } = await supabase.from("executives")
    .select("onboarded_at, display_name")
    .eq("id", userId)
    .maybeSingle();
  return {
    onboarded: !!data?.onboarded_at,
    displayName: data?.display_name ?? null,
  };
}

// ─── Context read (small, so the first response is fast) ────────────────────
async function readContext(userId: string) {
  const nowIso  = new Date().toISOString();
  const in12h   = new Date(Date.now() + 12 * 3600_000).toISOString();
  const yesterdayStart = new Date(Date.now() - 24 * 3600_000).toISOString();

  const [tasks, calendar, acb, rules, yesterdayCompletions] = await Promise.all([
    supabase.from("tasks")
      .select("id,title,bucket_type,due_at,deferred_count,last_viewed_at,is_overdue")
      .or(`workspace_id.eq.${userId},profile_id.eq.${userId}`)
      .eq("status", "pending")
      .order("due_at", { ascending: true, nullsFirst: false })
      .limit(20),
    supabase.from("calendar_events")
      .select("title,description,starts_at,ends_at")
      .eq("user_id", userId)
      .gte("starts_at", nowIso)
      .lte("starts_at", in12h)
      .order("starts_at", { ascending: true })
      .limit(8),
    supabase.from("weekly_syntheses")
      .select("strategic_analysis")
      .eq("executive_id", userId)
      .order("generated_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase.from("behaviour_rules")
      .select("rule_key,evidence,confidence,sample_size")
      .or(`workspace_id.eq.${userId},profile_id.eq.${userId}`)
      .eq("is_active", true)
      .order("confidence", { ascending: false })
      .limit(5),
    supabase.from("behaviour_events")
      .select("bucket_type,occurred_at")
      .or(`workspace_id.eq.${userId},profile_id.eq.${userId}`)
      .eq("event_type", "task_completed")
      .gte("occurred_at", yesterdayStart)
      .limit(20),
  ]);

  return {
    tasks: tasks.data ?? [],
    calendar: calendar.data ?? [],
    acb: acb.data?.strategic_analysis ?? null,
    rules: rules.data ?? [],
    yesterdayDone: yesterdayCompletions.data ?? [],
  };
}

function buildOnboardingSystemPrompt(displayName: string | null): string {
  // Strip surname — first name only reads warmer than full name in spoken address.
  const firstName = displayName?.trim().split(/\s+/)[0] ?? null;
  return `You are Timed — Yasser's executive operating system. This is Yasser's FIRST
conversation with you. You are introducing yourself and collecting the setup
you need. Voice-first. No lists. No menus. Conversation.

${firstName ? `Yasser's first name is "${firstName}" — address him by first name only, never the full name. DO NOT ask what to call him.` : "You do not know his name yet — ask it as the FIRST collected field."}

OPENING — FIRST THING YOU SAY (one fluid spoken paragraph, not multi-step):
You MUST do all three of these in one continuous turn, no pauses for acknowledgement:
  1. Greet by name (if known) or identify yourself.
  2. Briefly frame what you are (one short clause — "the operating system that
     thinks alongside you" or similar) and that this takes 60 seconds.
  3. Add ONE short privacy reassurance — that everything he says stays between
     the two of you and never leaves his account.
  4. Then ask the FIRST setup question.

Example (adapt, do not copy verbatim — but keep the "Let's get into it" bridge
exactly, it's the handoff into the first question):
"${displayName ?? "Hey"}, I'm Timed — the operating system that thinks alongside
you. I watch your day, learn how you work, and tell you what to do next when
you ask. I never send anything or act for you — I only ever suggest. Quick
sixty-second setup, nothing here leaves your account. Let's get into it — what
time does your work day usually start?"

DO NOT:
- Say "Hello! How can I help you today?" or any generic assistant greeting.
- Separate the intro from the first question into two turns — it must flow.
- Over-explain what Timed does. He'll learn by using it.

WHAT TIMED IS (ABSOLUTE — these are the only things you may describe as what Timed does):
 - OBSERVES his inbox, calendar, and workflow.
 - REFLECTS and builds a model of how he thinks and operates.
 - RECOMMENDS what to do next, at his request.
 - REMEMBERS everything so tomorrow's recommendations are sharper than today's.

WHAT TIMED NEVER DOES (hard constraints — you must NEVER imply any of these):
 - Never sends email. Never replies to email. Never drafts email on his behalf.
 - Never "delegates" or "sends delegations" to anyone, ever.
 - Never CCs anyone. Never loops people in. Never contacts anyone for him.
 - Never books, schedules, confirms, cancels, or modifies anything external.
 - Never acts "on your behalf". Never "handles" anything. It only suggests.
If you are ever tempted to describe a feature that touches the outside world,
STOP — that feature doesn't exist. Rephrase around observation/recommendation.

WHAT YOU NEED TO COLLECT — a checklist of exactly 3 fields. No more, no less.
Before each of your turns, scan the conversation history and determine which
of these fields the user has already answered. Then ask about the FIRST
uncollected field. When all three are collected, emit the completion tag and
stop.

 1. work_hours — his work day start and end (24h, e.g. 8 and 18)
 2. email_cadence_pref — how often he likes to review his own inbox.
    Phrase it as "how often do you like to look at email" (never "how often
    should I check for you"). Normalise to one of:
    "twice_daily" | "three_times_daily" | "hourly" | "realtime"
 3. transit_modes — modes of travel he uses. Subset of
    ["drive","train","plane","chauffeur"]. Default ["drive"] if he's vague.

That's the entire list. Do NOT invent a fourth question. Do NOT ask about a PA,
an assistant, delegation, CCs, anyone else's email, his role, his industry,
his goals, his calendar today, or his current tasks. After field 3 is filled,
you are DONE — say your closing line and emit the completion tag.

NEVER reference or narrate his calendar, his tasks, or anything from "today".
During onboarding you have no access to that data. If you describe it, you
are hallucinating. Stay on the checklist.

ONE TURN = ONE UTTERANCE. Non-negotiable.
 - After the opening turn, each of your replies is ONE brief acknowledgement
   (≤8 words) followed by ONE question. Then STOP.
 - Never chain a second sentence after the question. Never "follow up" before
   the user has spoken. Never add filler like "while you're thinking about that"
   or "also" or "by the way". Never speak twice in a row.
 - Never preemptively confirm back what he said in a long sentence — trust he
   heard himself. A one-word "Got it." is the maximum acknowledgement.
 - End every turn with a QUESTION (or, if the checklist is complete, your
   closing line + the completion tag). Nothing else.

OTHER RULES:
 - If he says something vague, ask a tight clarifying question ("eight or nine?").
 - If he tries to skip setup ("just get me in", "whatever, defaults"), honour that —
   acknowledge, then ask explicitly: "I'll use defaults: 9 to 6, twice-daily email
   review. Sound right?" and proceed when he confirms.
 - Do NOT ask about his role, his industry, his goals, or his workflow. That is
   learned from behaviour, not asked.
 - Do NOT read back everything he said. Trust the transcript.
 - Do NOT invent features. If a phrase you are about to say requires Timed to
   take an action in the world, rewrite it around observation + recommendation.

WHEN YOU'RE DONE:
Say one closing sentence that tells him what's next and that you're about to end
the setup. Example: "Got it — kicking you into Dish Me Up now." Then STOP.

CRITICAL — when you have everything you need, OR when he has given you permission
to use defaults, emit this line on its own at the very end (after your closing
sentence), so the app can parse it:

[[ONBOARDING_COMPLETE]]

No JSON. No markdown. Just the literal tag on its own line. The app sees that tag
and pivots.`;
}

function buildSystemPrompt(acb: string | null, rules: Array<any>): string {
  const rulesBlock = rules.length
    ? rules.map((r: any) => ` • ${r.evidence ?? r.rule_key} (confidence ${Number(r.confidence ?? 0).toFixed(2)})`).join("\n")
    : " • (no strong patterns yet — ask open questions)";

  return `You are the voice of Yasser's operating system during his morning check-in.
You know him deeply. You speak briefly and directly. You never sound scripted.
You never greet him with "Hello" — launch straight into context.

ABSOLUTE BOUNDARY: Timed observes, reflects, and recommends. Timed never sends
email, never CCs anyone, never delegates, never books, never contacts anyone
on Yasser's behalf, never "handles" anything in the outside world. If you are
about to describe a Timed action that touches the world, stop — that feature
doesn't exist. Rephrase as observation or recommendation only.

WHO YASSER IS:
${acb ?? "(no synthesis yet — reason from first principles)"}

HIS PATTERNS:
${rulesBlock}

MORNING CHECK-IN OBJECTIVES (complete at least 2, max 5 minutes, max 4 questions):
1. PERCEIVED PRIORITY: Ask what he sees as most important today and why.
   Listen for mismatches between his answer and what his task list / calendar
   suggests. Note the mismatch if it exists.
2. HIDDEN CONTEXT: If he mentions anything with no matching task or calendar
   event, probe once. New information belongs in the system.
3. ANXIETY SURFACE: If he uses "worried", "need to", "should have",
   "behind on" — name the thing directly.
4. AVOIDANCE PROBE: If any task shows deferred_count >= 3, mention it once,
   casually: "You've pushed the legal review 4 times — priority mismatch
   or something you need help breaking down?"

CONSTRAINTS:
- Never list all his tasks out loud.
- Never ask more than one question at a time.
- When he's given you enough to improve today's Dish Me Up plan, say a short
  wrap-up sentence and stop talking. The system will take it from there.
- Speak like a trusted colleague who just walked in — not an assistant.`;
}

function buildContextIntro(ctx: Awaited<ReturnType<typeof readContext>>): string {
  const cal = ctx.calendar.length
    ? ctx.calendar.map((e: any) => ` • ${e.title ?? "(untitled)"} @ ${e.starts_at}`).join("\n")
    : " • (nothing on the calendar in the next 12 hours)";
  const avoided = ctx.tasks.filter((t: any) => (t.deferred_count ?? 0) >= 3);
  const overdue = ctx.tasks.filter((t: any) => t.is_overdue);
  const avoidedLine = avoided.length
    ? avoided.map((t: any) => ` • ${t.title} (deferred ${t.deferred_count}×)`).join("\n")
    : " • (nothing being dodged)";
  const overdueLine = overdue.length
    ? overdue.map((t: any) => ` • ${t.title}`).join("\n")
    : " • (no overdue tasks)";

  return `TODAY'S CONTEXT (do not read back unless asked):

CALENDAR:
${cal}

OVERDUE:
${overdueLine}

AVOIDED (deferred 3+ times):
${avoidedLine}

YESTERDAY'S COMPLETIONS: ${ctx.yesterdayDone.length} tasks done.

Open the check-in with a specific observation about today — something concrete.
Then ask your first question.`;
}

// ─── Convert OpenAI-format messages → Anthropic format ──────────────────────
type OAIMsg = { role: "system" | "user" | "assistant"; content: string };

function convertMessages(messages: OAIMsg[], contextIntro: string): { role: "user" | "assistant"; content: string }[] {
  // Strip OpenAI system messages (we set our own). Keep only user/assistant.
  // Prepend the context intro to the first user message so Opus has today's state.
  const dialog = messages.filter(m => m.role !== "system") as { role: "user" | "assistant"; content: string }[];
  if (dialog.length === 0) {
    return [{ role: "user", content: `${contextIntro}\n\n(Yasser just opened the app — start the check-in.)` }];
  }
  const first = dialog[0];
  const rest  = dialog.slice(1);
  return [
    { role: first.role, content: `${contextIntro}\n\n${first.content}` },
    ...rest,
  ];
}

// ─── Handler ────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const body = await req.json().catch(() => ({})) as {
    messages?: OAIMsg[];
    stream?: boolean;
    model?: string;
  };

  // Branch on onboarded_at: null = voice setup; set = morning check-in.
  // Onboarding = Haiku (no thinking) for snappy <1s first-token latency.
  // Morning check-in = Opus with lowered thinking budget (4k) — the reasoning
  // matters for perceived priority and avoidance, but 10k was overkill.
  const state = await readOnboardedState(YASSER_USER_ID);

  let systemPrompt: string;
  let anthropicMessages: { role: "user" | "assistant"; content: string }[];
  let modelCfg: { model: string; max_tokens: number; thinking: { type: "enabled"; budget_tokens: number } | undefined };
  if (!state.onboarded) {
    systemPrompt = buildOnboardingSystemPrompt(state.displayName);
    const dialog = (body.messages ?? []).filter(m => m.role !== "system") as { role: "user" | "assistant"; content: string }[];
    anthropicMessages = dialog.length > 0
      ? dialog
      : [{ role: "user", content: "(Yasser just opened the app for the first time — greet him and start the setup.)" }];
    modelCfg = { model: "claude-haiku-4-5-20251001", max_tokens: 600, thinking: undefined };
  } else {
    const ctx = await readContext(YASSER_USER_ID);
    systemPrompt = buildSystemPrompt(ctx.acb, ctx.rules);
    const contextIntro = buildContextIntro(ctx);
    anthropicMessages = convertMessages(body.messages ?? [], contextIntro);
    modelCfg = {
      model: "claude-opus-4-6",
      max_tokens: 6000,
      thinking: { type: "enabled", budget_tokens: 4000 },
    };
  }

  const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type":      "application/json",
      "x-api-key":         ANTHROPIC_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: modelCfg.model,
      max_tokens: modelCfg.max_tokens,
      ...(modelCfg.thinking ? { thinking: modelCfg.thinking } : {}),
      stream: true,
      system: [{ type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } }],
      messages: anthropicMessages,
    }),
  });

  if (!anthropicRes.ok || !anthropicRes.body) {
    const detail = await anthropicRes.text().catch(() => "(no body)");
    return new Response(`Anthropic ${anthropicRes.status}: ${detail}`, {
      status: 502,
      headers: { ...CORS, "Content-Type": "text/plain" },
    });
  }

  const id      = `chatcmpl-${crypto.randomUUID()}`;
  const created = Math.floor(Date.now() / 1000);
  const model   = modelCfg.model;

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  const out = new ReadableStream({
    async start(controller) {
      const reader = anthropicRes.body!.getReader();
      let buffer = "";
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          let lineBreak;
          while ((lineBreak = buffer.indexOf("\n")) !== -1) {
            const line = buffer.slice(0, lineBreak).trim();
            buffer = buffer.slice(lineBreak + 1);
            if (!line.startsWith("data: ")) continue;
            const payload = line.slice(6);
            if (payload === "[DONE]") break;
            try {
              const evt = JSON.parse(payload);
              // Filter: thinking deltas must NOT reach ElevenLabs TTS.
              if (evt.type === "content_block_delta"
                && evt.delta?.type === "text_delta"
                && typeof evt.delta.text === "string") {
                controller.enqueue(encoder.encode(sseChunk(id, created, model, evt.delta.text)));
              }
            } catch {
              // Ignore malformed SSE lines during streaming.
            }
          }
        }
        // Signal completion to ElevenLabs.
        controller.enqueue(encoder.encode(sseChunk(id, created, model, "", true)));
        controller.enqueue(encoder.encode("data: [DONE]\n\n"));
      } finally {
        controller.close();
      }
    },
  });

  return new Response(out, {
    headers: {
      ...CORS,
      "Content-Type":      "text/event-stream",
      "Cache-Control":     "no-cache",
      "Connection":        "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
});
