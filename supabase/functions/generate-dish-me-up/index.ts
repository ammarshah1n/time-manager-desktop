// generate-dish-me-up
//
// The ONE intelligent call. The principal taps a button. 7 parallel DB reads.
// One Opus call with extended thinking. 3–6 tasks in priority order with
// honest per-task reasoning. Knapsack only fits; Opus orders.
//
// Architecture: Dish-Me-Up-Intelligence-Architecture.md + Ship-It.md
//   - budget_tokens: 10000 (user prompt override)
//   - ephemeral cache on system prompt (7-day TTL)
//   - JWT-verified; executive resolved from auth_user_id
//   - last_viewed_at stamp after plan returns (Signal 7)
//   - no Zod; JSON.parse throws = plenty of signal during dev
//
// Run:  supabase functions deploy generate-dish-me-up

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

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

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

// ─── System prompt (cached block) ──────────────────────────────────────────
// Changes only when ACB summary or rules change → long cache hits.
function buildSystemPrompt(
  displayName: string,
  acbSummary: string | null,
  rules: Array<{ rule_key: string; evidence: string | null; confidence: number; sample_size: number }>,
): string {
  const rulesBlock = rules.length
    ? rules.map(r =>
        ` • ${r.evidence ?? r.rule_key} (confidence: ${r.confidence.toFixed(2)}, ${r.sample_size} sessions)`
      ).join("\n")
    : " • (no high-confidence rules yet — be honest about this in your reasoning when relevant)";

  const principal = displayName?.trim() ? displayName.trim() : "the principal";

  return `You are ${principal}'s operating system — not a task manager, not a scheduler.
You know them deeply. You make calls they'd make if they could see everything at once.

WHO ${principal.toUpperCase()} IS:
${acbSummary ?? "(no weekly synthesis yet — reason from first principles)"}

THEIR PATTERNS (confidence-weighted):
${rulesBlock}

YOUR CONSTRAINTS:
- Only suggest tasks from the provided list. Never invent tasks.
- Never suggest more tasks than fit in available_minutes.
- Be honest about why something is on the list. Don't flatter.
- If you see something ${principal} is avoiding, name it directly.
- If today looks reactive (inbox-heavy), say so and suggest one proactive task.
- If source mix shows >70% reactive tasks in the last 7 days, include at least one self-initiated task in the plan if one exists.

ABSOLUTE BOUNDARY: Timed observes, reflects, and recommends. It never sends
email, never CCs anyone, never contacts anyone, never books anything, never
"handles" or "delegates" anything on ${principal}'s behalf. All reasoning in the
"reason" field must describe WHY ${principal} should do a task themselves — never what
Timed will do. If the reason you're about to write implies Timed taking action,
rewrite it.

OUTPUT FORMAT (strict):
Return a single JSON object, no prose, no markdown fences:
{
  "session_framing": "<one sentence framing today's plan>",
  "plan": [
    {
      "task_id": "<uuid from the task list>",
      "title": "<task title>",
      "estimated_minutes": <int>,
      "reason": "<one honest sentence>",
      "avoidance_flag": "<optional string or null>"
    }
  ]
}`;
}

// ─── User message (not cached) ─────────────────────────────────────────────
function buildUserMessage(args: {
  displayName: string;
  availableMinutes: number;
  currentTime: string;
  tasks: any[];
  calendarEvents: any[];
  recentBehaviour: any[];
  velocity: { ratio: number | null; done: number };
  sourceMix: Array<{ bucket_type: string; completions: number }>;
}): string {
  const cal = args.calendarEvents.length
    ? args.calendarEvents.map(e => {
        const dur = e.starts_at && e.ends_at
          ? Math.round((new Date(e.ends_at).getTime() - new Date(e.starts_at).getTime()) / 60000)
          : null;
        const desc = e.description ? ` — ${String(e.description).slice(0, 100)}` : "";
        return ` • ${e.title ?? "(untitled)"}${desc} @ ${e.starts_at}${dur ? ` (${dur}m)` : ""}`;
      }).join("\n")
    : " • (nothing scheduled in the next 4 hours)";

  const recent = args.recentBehaviour.length
    ? args.recentBehaviour.map(ev =>
        ` • ${ev.event_type} ${ev.bucket_type ?? ""} at ${ev.occurred_at}`
      ).join("\n")
    : " • (no activity in the last 3 hours)";

  const velocityLine = args.velocity.ratio !== null
    ? `velocity: ${args.velocity.ratio.toFixed(2)}× estimates (${args.velocity.done} tasks done today)`
    : `velocity: not enough completions today to measure (${args.velocity.done} tasks done)`;

  const mixTotal = args.sourceMix.reduce((s, x) => s + x.completions, 0) || 1;
  const mixLine = args.sourceMix.length
    ? args.sourceMix.map(m => `${m.bucket_type}: ${Math.round(100 * m.completions / mixTotal)}%`).join(", ")
    : "no completions in the last 7 days";

  const taskList = args.tasks.map(t => ({
    id: t.id,
    title: t.title,
    bucket: t.bucket_type,
    source: t.source_type,
    estimated_minutes: t.estimated_minutes ?? 15,
    deadline: t.due_at,
    deferred_count: t.deferred_count,
    is_avoided: (t.deferred_count ?? 0) >= 3,
    is_quick_win: t.is_do_first === true || (t.estimated_minutes ?? 15) <= 5,
    first_appearance: t.last_viewed_at == null,
    last_viewed_at: t.last_viewed_at,
  }));

  return `Available: ${args.availableMinutes} minutes
Current time: ${args.currentTime}

CALENDAR (next 4 hours):
${cal}

TODAY SO FAR:
${velocityLine}
recent events:
${recent}
source mix (last 7 days): ${mixLine}

TASKS (unordered — you decide):
${JSON.stringify(taskList, null, 2)}

What should ${args.displayName?.trim() || "the principal"} do in the next ${args.availableMinutes} minutes, in order?`;
}

// ─── 7-source parallel read ────────────────────────────────────────────────
async function readAllSources(userId: string) {
  const nowIso = new Date().toISOString();
  const in4hIso = new Date(Date.now() + 4 * 3600_000).toISOString();
  const threeHoursAgo = new Date(Date.now() - 3 * 3600_000).toISOString();
  const sevenDaysAgo = new Date(Date.now() - 7 * 86400_000).toISOString();

  // Tasks: workspace_id + profile_id aliased to the same UUID per AuthService convention.
  const tasksQ = supabase.from("tasks")
    .select("id,title,bucket_type,source_type,estimated_minutes_ai,estimated_minutes_manual,due_at,deferred_count,last_viewed_at,is_overdue,is_do_first,created_at,workspace_id,profile_id")
    .or(`workspace_id.eq.${userId},profile_id.eq.${userId}`)
    .eq("status", "pending")
    .order("due_at", { ascending: true, nullsFirst: false })
    .order("created_at", { ascending: true })
    .limit(30);

  const calendarQ = supabase.from("calendar_events")
    .select("id,title,description,starts_at,ends_at,attendee_count")
    .eq("user_id", userId)
    .gte("starts_at", nowIso)
    .lte("starts_at", in4hIso)
    .order("starts_at", { ascending: true })
    .limit(6);

  const acbQ = supabase.from("weekly_syntheses")
    .select("strategic_analysis,generated_at")
    .eq("executive_id", userId)
    .order("generated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  const rulesQ = supabase.from("behaviour_rules")
    .select("rule_key,rule_value_json,confidence,sample_size,evidence")
    .or(`workspace_id.eq.${userId},profile_id.eq.${userId}`)
    .eq("is_active", true)
    .order("confidence", { ascending: false })
    .limit(5);

  const recentBehaviourQ = supabase.from("behaviour_events")
    .select("event_type,bucket_type,occurred_at")
    .or(`workspace_id.eq.${userId},profile_id.eq.${userId}`)
    .gte("occurred_at", threeHoursAgo)
    .order("occurred_at", { ascending: false })
    .limit(8);

  // Velocity + source-mix share one 7-day window of completed tasks.
  const completionsQ = supabase.from("behaviour_events")
    .select("bucket_type,new_value,occurred_at")
    .or(`workspace_id.eq.${userId},profile_id.eq.${userId}`)
    .eq("event_type", "task_completed")
    .gte("occurred_at", sevenDaysAgo);

  const started = Date.now();
  const [tasks, calendar, acb, rules, recentBehaviour, completions] = await Promise.all([
    tasksQ, calendarQ, acbQ, rulesQ, recentBehaviourQ, completionsQ,
  ]);
  const dbMs = Date.now() - started;

  // Velocity today = ratio of actual / ai-estimate on completions since local midnight UTC.
  const todayStart = new Date(); todayStart.setUTCHours(0, 0, 0, 0);
  const todayISO = todayStart.toISOString();
  const todays = (completions.data ?? []).filter(c => c.occurred_at >= todayISO);
  let ratioSum = 0, ratioN = 0;
  for (const r of todays) {
    const nv = (r.new_value ?? {}) as { actual_minutes?: number; ai_estimate?: number };
    if (nv.actual_minutes && nv.ai_estimate) {
      ratioSum += nv.actual_minutes / nv.ai_estimate;
      ratioN += 1;
    }
  }
  const velocity = { ratio: ratioN > 0 ? ratioSum / ratioN : null, done: todays.length };

  // Source-mix over 7 days.
  const mix = new Map<string, number>();
  for (const r of completions.data ?? []) {
    const k = r.bucket_type ?? "unknown";
    mix.set(k, (mix.get(k) ?? 0) + 1);
  }
  const sourceMix = [...mix.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([bucket_type, completions]) => ({ bucket_type, completions }));

  // Normalise estimated_minutes on tasks.
  const taskRows = (tasks.data ?? []).map(t => ({
    ...t,
    estimated_minutes: t.estimated_minutes_manual ?? t.estimated_minutes_ai ?? 15,
  }));

  return {
    tasks: taskRows,
    calendarEvents: calendar.data ?? [],
    acbSummary: acb.data?.strategic_analysis ?? null,
    rules: rules.data ?? [],
    recentBehaviour: recentBehaviour.data ?? [],
    velocity,
    sourceMix,
    dbMs,
  };
}

// ─── JSON extraction: Opus occasionally wraps in prose or code fences. ─────
function extractFirstJSON(text: string): unknown {
  const stripped = text.replace(/^```(?:json)?\s*/i, "").replace(/```\s*$/i, "");
  const start = stripped.indexOf("{");
  if (start < 0) throw new Error(`No JSON object found in Opus output: ${text.slice(0, 200)}`);
  let depth = 0, inString = false, escaped = false;
  for (let i = start; i < stripped.length; i++) {
    const ch = stripped[i];
    if (escaped) { escaped = false; continue; }
    if (ch === "\\") { escaped = true; continue; }
    if (ch === '"') { inString = !inString; continue; }
    if (inString) continue;
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return JSON.parse(stripped.slice(start, i + 1));
    }
  }
  throw new Error("Unbalanced JSON in Opus output");
}

// ─── Knapsack: Opus orders, this fits. ─────────────────────────────────────
function applyConstraints(
  plan: Array<{ task_id: string; title: string; estimated_minutes: number; reason: string; avoidance_flag?: string | null }>,
  availableMinutes: number,
) {
  const BUFFER = 5;
  let remaining = availableMinutes;
  const selected: typeof plan = [];
  const overflow: typeof plan = [];
  for (const item of plan) {
    const cost = (item.estimated_minutes ?? 15) + BUFFER;
    if (cost <= remaining) {
      selected.push(item);
      remaining -= cost;
    } else {
      overflow.push(item);
    }
  }
  return { selected, overflow, remainingMinutes: remaining };
}

// ─── Opus call with extended thinking + cached system prompt ───────────────
async function callOpus(systemPrompt: string, userMessage: string) {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-opus-4-6",
      // max_tokens must exceed thinking.budget_tokens (Anthropic 400 otherwise).
      // 14000 = 10000 thinking + 4000 for the plan payload.
      max_tokens: 14000,
      thinking: { type: "enabled", budget_tokens: 10000 },
      // Structured system = ephemeral cache (≈5 min TTL; Anthropic accepts 1h
      // on opt-in beta but default is fine for Ship-It — cache hits trivially
      // for any burst of Dish Me Up calls within the session).
      system: [
        {
          type: "text",
          text: systemPrompt,
          cache_control: { type: "ephemeral" },
        },
      ],
      messages: [{ role: "user", content: userMessage }],
    }),
    signal: AbortSignal.timeout(55_000),
  });
  if (!res.ok) throw new Error(`Anthropic ${res.status}: ${await res.text()}`);
  const body = await res.json() as {
    content: Array<{ type: string; text?: string }>;
    usage?: { cache_read_input_tokens?: number; cache_creation_input_tokens?: number };
  };
  const text = body.content.filter(b => b.type === "text").map(b => b.text ?? "").join("");
  return { text, usage: body.usage ?? {} };
}

// ─── Handler ───────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const t0 = Date.now();
  try {
    const authUserId = await verifyAuth(req);
    const executive = await resolveExecutive(authUserId);

    const body = await req.json().catch(() => ({}));
    const availableMinutes: number = body.available_minutes ?? 60;
    const currentTime: string = body.current_time ?? new Date().toISOString();

    const src = await readAllSources(executive.id);

    if (src.tasks.length === 0) {
      return new Response(JSON.stringify({
        session_framing: "Nothing pending. Go enjoy the break.",
        plan: [],
        overflow: [],
        debug: { db_ms: src.dbMs, total_ms: Date.now() - t0 },
      }), { headers: { ...CORS, "Content-Type": "application/json" } });
    }

    const systemPrompt = buildSystemPrompt(executive.displayName, src.acbSummary, src.rules);
    const userMessage  = buildUserMessage({
      displayName: executive.displayName,
      availableMinutes, currentTime,
      tasks: src.tasks,
      calendarEvents: src.calendarEvents,
      recentBehaviour: src.recentBehaviour,
      velocity: src.velocity,
      sourceMix: src.sourceMix,
    });

    const opusStarted = Date.now();
    const opus = await callOpus(systemPrompt, userMessage);
    const opusMs = Date.now() - opusStarted;

    // Extract the first balanced JSON object even if Opus wrote prose before/after.
    const parsed = extractFirstJSON(opus.text) as {
      session_framing: string;
      plan: Array<{ task_id: string; title: string; estimated_minutes: number; reason: string; avoidance_flag?: string | null }>;
    };

    const fitted = applyConstraints(parsed.plan ?? [], availableMinutes);

    // Signal 7: stamp everything the principal saw, even the overflow.
    const seenIds = [...fitted.selected, ...fitted.overflow].map(p => p.task_id);
    if (seenIds.length > 0) {
      await supabase.from("tasks")
        .update({ last_viewed_at: new Date().toISOString() })
        .in("id", seenIds);
    }

    return new Response(JSON.stringify({
      session_framing: parsed.session_framing,
      plan:     fitted.selected,
      overflow: fitted.overflow,
      debug: {
        db_ms: src.dbMs,
        opus_ms: opusMs,
        total_ms: Date.now() - t0,
        cache_read_tokens:     opus.usage.cache_read_input_tokens ?? 0,
        cache_creation_tokens: opus.usage.cache_creation_input_tokens ?? 0,
      },
    }), { headers: { ...CORS, "Content-Type": "application/json" } });
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    console.error("[generate-dish-me-up] ERROR:", err);
    return new Response(JSON.stringify({
      error: (err as Error).message,
      total_ms: Date.now() - t0,
    }), { status: 500, headers: { ...CORS, "Content-Type": "application/json" } });
  }
});
