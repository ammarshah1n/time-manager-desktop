import Anthropic from "@anthropic-ai/sdk";
import type {
  MessageCreateParamsNonStreaming,
  TextBlockParam,
} from "@anthropic-ai/sdk/resources/messages";
import { logger, schedules } from "@trigger.dev/sdk";

import { approxTokens } from "../lib/hash.js";
import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * T25 -- NREM entity extraction (batch submit).
 *
 * Runs nightly at 02:00. Loads every tier0_observation whose `occurred_at`
 * is strictly after the last successful run's watermark (derived from the
 * most recent `batch_jobs` row with kind='nrem-extraction' whose status is
 * either 'pending' or 'consumed'), packages one Anthropic Message Batch
 * request per observation, submits to the Batch API, and writes a single
 * `batch_jobs` row with status='pending'. It then exits.
 *
 * There is no `wait.for`, no polling, no blocking. The companion task
 * `nrem-entity-extraction-consume.ts` (T25a) drains results every 5 minutes
 * between 02:00 and 08:59.
 *
 * Model: sonnet_extract -> "claude-sonnet-4-6", max_tokens 4000, no tools,
 * no thinking. Prompt caching via cache_control: "ephemeral" on the system
 * prompt when it crosses the ~1024-token threshold (mirrors
 * `applyCacheControl` in inference.ts; T31 owns that helper and must not be
 * reimplemented here).
 */

// Concrete model id -- duplicated intentionally. The Batch API cannot route
// through inference() (that path is the real-time Messages wrapper), but the
// two must agree on Sonnet 4.6 at this version. MODEL_ROUTING in inference.ts
// remains the single source of truth for the live path.
const SONNET_EXTRACT_MODEL = "claude-sonnet-4-6";
const MAX_TOKENS = 4_000;
const CACHE_CONTROL_MIN_TOKENS = 1024;

// Cap per-run batch size. The Anthropic Batch API supports up to 100k
// requests per batch, but we cap at a sane 10k to keep a single night's
// blast radius bounded. If more observations accumulate (e.g., catch-up
// after an outage), the next run picks them up via the watermark.
const MAX_OBSERVATIONS_PER_RUN = 10_000;

const SYSTEM_PROMPT = [
  "You extract structured memory primitives from a single Tier-0 observation",
  "about an executive's day (email event, meeting, doc edit, etc).",
  "",
  "Return STRICT JSON matching this schema and NOTHING else:",
  "{",
  '  "episodes":     [ { "content": string, "content_hash": string, "reference_time": string } ],',
  '  "entities":     [ { "name": string, "type": string, "summary": string } ],',
  '  "fact_triples": [ { "subject": string, "predicate": string, "object": string, "valid_from": string } ]',
  "}",
  "",
  "Rules:",
  "- `content_hash` is a short deterministic SHA-256 prefix (16 hex chars) of the episode `content`.",
  "- `reference_time` is ISO-8601 in UTC; it MUST equal the observation's occurred_at.",
  "- `valid_from` is ISO-8601 in UTC; use the observation's occurred_at when uncertain.",
  "- If a field is unknown, OMIT the array element. Do NOT emit null.",
  "- Do not wrap the JSON in markdown. Do not add prose. Do not add trailing commas.",
  "",
  "An episode is a single narrative sentence describing what happened.",
  "An entity is a person, org, doc, project, or initiative named in the observation.",
  "A fact_triple is a single (subject, predicate, object) atomic claim.",
].join("\n");

type TierZeroObservation = {
  id: string;
  occurred_at: string;
  source: string;
  event_type: string;
  summary: string | null;
  raw_data: unknown;
};

function systemBlocks(): TextBlockParam[] | string {
  if (approxTokens(SYSTEM_PROMPT) < CACHE_CONTROL_MIN_TOKENS) {
    return SYSTEM_PROMPT;
  }
  return [
    {
      type: "text",
      text: SYSTEM_PROMPT,
      cache_control: { type: "ephemeral" },
    },
  ];
}

function buildUserPrompt(obs: TierZeroObservation): string {
  return [
    `Observation id: ${obs.id}`,
    `occurred_at: ${obs.occurred_at}`,
    `source: ${obs.source}`,
    `event_type: ${obs.event_type}`,
    obs.summary ? `summary: ${obs.summary}` : null,
    "raw_data:",
    JSON.stringify(obs.raw_data ?? {}, null, 2),
  ]
    .filter((line): line is string => line !== null)
    .join("\n");
}

/**
 * Watermark derivation: the most recent batch_jobs row with
 * kind='nrem-extraction' whose status is 'pending' or 'consumed' defines
 * "the prior run". Its `submitted_at` is the exclusive lower bound for the
 * next run's observation sweep.
 *
 * If no prior row exists, we start at epoch (Unix 0) so the first run
 * captures everything.
 */
async function loadWatermark(): Promise<string> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("batch_jobs")
    .select("submitted_at")
    .eq("kind", "nrem-extraction")
    .in("status", ["pending", "consumed"])
    .order("submitted_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw new Error(`batch_jobs watermark read failed: ${error.message}`);
  if (!data) return new Date(0).toISOString();
  return data.submitted_at as string;
}

async function loadObservationsSince(
  watermark: string,
): Promise<TierZeroObservation[]> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("tier0_observations")
    .select("id, occurred_at, source, event_type, summary, raw_data")
    .gt("occurred_at", watermark)
    .order("occurred_at", { ascending: true })
    .limit(MAX_OBSERVATIONS_PER_RUN);
  if (error) {
    throw new Error(`tier0_observations read failed: ${error.message}`);
  }
  return (data ?? []) as TierZeroObservation[];
}

type BatchRequest = {
  custom_id: string;
  params: MessageCreateParamsNonStreaming;
};

function buildBatchRequest(obs: TierZeroObservation): BatchRequest {
  const system = systemBlocks();
  const params: MessageCreateParamsNonStreaming = {
    model: SONNET_EXTRACT_MODEL,
    max_tokens: MAX_TOKENS,
    ...(typeof system === "string" ? { system } : { system }),
    messages: [
      {
        role: "user",
        content: buildUserPrompt(obs),
      },
    ],
  };
  return { custom_id: obs.id, params };
}

let _anthropic: Anthropic | undefined;
function getAnthropic(): Anthropic {
  if (_anthropic) return _anthropic;
  const apiKey = process["env"]["ANTHROPIC_API_KEY"];
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
  _anthropic = new Anthropic({ apiKey });
  return _anthropic;
}

export const nremEntityExtraction = schedules.task({
  id: "nrem-entity-extraction",
  cron: "0 2 * * *",
  maxDuration: 600,
  run: async () => {
    logger.info("nrem-entity-extraction starting");

    const watermark = await loadWatermark();
    logger.info("nrem-entity-extraction watermark", { watermark });

    const observations = await loadObservationsSince(watermark);
    if (observations.length === 0) {
      logger.info("nrem-entity-extraction: no new observations, exiting");
      return { submitted: false, observation_count: 0 };
    }

    const requests = observations.map(buildBatchRequest);
    logger.info("nrem-entity-extraction submitting batch", {
      request_count: requests.length,
    });

    const batch = await getAnthropic().messages.batches.create({ requests });

    const sb = getSupabaseServiceRole();
    const { error } = await sb.from("batch_jobs").insert({
      batch_id: batch.id,
      kind: "nrem-extraction",
      status: "pending",
      observation_count: observations.length,
    });
    if (error) {
      // The Anthropic batch has been accepted; failing to record it locally
      // means the consumer will never find it. Surface loudly.
      logger.error("nrem-entity-extraction: batch_jobs insert failed", {
        alert: true,
        batch_id: batch.id,
        error: error.message,
      });
      throw new Error(`batch_jobs insert failed: ${error.message}`);
    }

    logger.info("nrem-entity-extraction submitted", {
      batch_id: batch.id,
      observation_count: observations.length,
    });

    return {
      submitted: true,
      batch_id: batch.id,
      observation_count: observations.length,
    };
  },
});
