import Anthropic from "@anthropic-ai/sdk";
import type { Message, TextBlock } from "@anthropic-ai/sdk/resources/messages";
import { logger, schedules } from "@trigger.dev/sdk";

import {
  callMcpTool,
  closeAgentSession,
  openAgentSession,
  traceToolCall,
} from "../lib/trace-tool-results.js";
import { getSupabaseServiceRole } from "../lib/supabase.js";

/**
 * T25a -- NREM entity-extraction batch consumer.
 *
 * Runs every 5 minutes between 02:00 and 08:59 UTC. For each batch_jobs row
 * with kind='nrem-extraction' AND status='pending':
 *
 *   1. Retrieve the Anthropic batch. If processing_status is not 'ended':
 *        - If the batch was submitted > 26h ago, flag status='failed'
 *          with error='timeout' and log an alert.
 *        - Otherwise, leave it alone until the next tick.
 *   2. If ended, stream JSONL results, parse each succeeded message's first
 *      text block as JSON matching { episodes, entities, fact_triples }.
 *   3. For each episode, call graphiti-mcp episode_exists({ content_hash }).
 *      If present, skip. Else add_episode, then add_fact per fact_triple.
 *   4. Write one agent_sessions row per batch (task_name='nrem-extraction-
 *      consume') and one agent_traces row per MCP tool invocation via the
 *      trace-tool-results helper.
 *   5. Mark the batch_jobs row status='consumed' and consumed_at=now().
 */

const TIMEOUT_MS = 26 * 60 * 60 * 1_000; // 26 hours

// Shape we ask Sonnet to emit. Narrow parsers below defend against drift.
type ExtractionPayload = {
  episodes?: Array<{
    content?: string;
    content_hash?: string;
    reference_time?: string;
  }>;
  entities?: Array<{
    name?: string;
    type?: string;
    summary?: string;
  }>;
  fact_triples?: Array<{
    subject?: string;
    predicate?: string;
    object?: string;
    valid_from?: string;
  }>;
};

type BatchJobRow = {
  id: string;
  batch_id: string;
  submitted_at: string;
  observation_count: number | null;
};

let _anthropic: Anthropic | undefined;
function getAnthropic(): Anthropic {
  if (_anthropic) return _anthropic;
  const apiKey = process["env"]["ANTHROPIC_API_KEY"];
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
  _anthropic = new Anthropic({ apiKey });
  return _anthropic;
}

/**
 * Extract the first text block from a Messages-API `Message` and parse it as
 * JSON. Sonnet is pinned to "STRICT JSON"; if it drifts we throw so the
 * offending observation shows up as a traced failure rather than silently
 * dropping facts.
 */
function parseExtraction(message: Message): ExtractionPayload {
  const textBlock = message.content.find(
    (b): b is TextBlock => b.type === "text",
  );
  if (!textBlock) {
    throw new Error("extraction message has no text block");
  }
  try {
    return JSON.parse(textBlock.text) as ExtractionPayload;
  } catch (err) {
    throw new Error(
      `extraction JSON parse failed: ${(err as Error).message}; text head=${textBlock.text.slice(0, 200)}`,
    );
  }
}

/**
 * Retrieve pending batch jobs. We process them one at a time (not in
 * parallel) so the 5-minute tick's behaviour is easy to reason about: a
 * slow batch doesn't starve its siblings, because each subsequent tick
 * picks up where we left off.
 */
async function loadPendingBatches(): Promise<BatchJobRow[]> {
  const sb = getSupabaseServiceRole();
  const { data, error } = await sb
    .from("batch_jobs")
    .select("id, batch_id, submitted_at, observation_count")
    .eq("kind", "nrem-extraction")
    .eq("status", "pending")
    .order("submitted_at", { ascending: true });
  if (error) {
    throw new Error(`batch_jobs pending read failed: ${error.message}`);
  }
  return (data ?? []) as BatchJobRow[];
}

async function markBatchFailed(
  job_id: string,
  error_message: string,
): Promise<void> {
  const sb = getSupabaseServiceRole();
  const { error } = await sb
    .from("batch_jobs")
    .update({ status: "failed", error: error_message })
    .eq("id", job_id);
  if (error) {
    logger.error("batch_jobs failed-mark failed", {
      alert: true,
      job_id,
      error: error.message,
    });
  }
}

async function markBatchConsumed(
  job_id: string,
  session_id: string,
): Promise<void> {
  const sb = getSupabaseServiceRole();
  const { error } = await sb
    .from("batch_jobs")
    .update({
      status: "consumed",
      consumed_at: new Date().toISOString(),
      source_session_id: session_id,
    })
    .eq("id", job_id);
  if (error) {
    throw new Error(`batch_jobs consumed-mark failed: ${error.message}`);
  }
}

/**
 * Drive the per-episode graphiti writes for a single observation's payload.
 * Returns the number of episodes actually written (skipped duplicates don't
 * count) and the post-increment `step_index` so the caller can keep adding
 * trace rows in order.
 */
async function persistExtraction(
  payload: ExtractionPayload,
  observation_id: string,
  session_id: string,
  startStepIndex: number,
): Promise<{ episodes_added: number; nextStepIndex: number }> {
  let stepIndex = startStepIndex;
  let episodes_added = 0;

  const episodes = payload.episodes ?? [];
  const facts = payload.fact_triples ?? [];

  for (const episode of episodes) {
    const content_hash = episode.content_hash;
    if (!content_hash) {
      logger.warn("extraction episode missing content_hash, skipping", {
        observation_id,
      });
      continue;
    }

    const existsT0 = Date.now();
    const existsOut = await callMcpTool("episode_exists", { content_hash });
    await traceToolCall({
      session_id,
      step_index: stepIndex++,
      tool_name: "episode_exists",
      input: { content_hash },
      output: existsOut,
      latency_ms: Date.now() - existsT0,
    });

    if (isTruthyExists(existsOut)) {
      continue;
    }

    const addEpT0 = Date.now();
    const addEpMcp = {
      content: episode.content ?? "",
      content_hash,
      timestamp: episode.reference_time
        ? new Date(episode.reference_time).toISOString()
        : new Date().toISOString(),
    };
    const addEpTrace = { ...addEpMcp, source_observation_id: observation_id };
    const addEpOut = await callMcpTool("add_episode", addEpMcp);
    await traceToolCall({
      session_id,
      step_index: stepIndex++,
      tool_name: "add_episode",
      input: addEpTrace,
      output: addEpOut,
      latency_ms: Date.now() - addEpT0,
    });
    episodes_added++;

    for (const fact of facts) {
      if (!fact.subject || !fact.predicate || !fact.object) continue;
      const addFactT0 = Date.now();
      const addFactMcp = {
        subject: fact.subject,
        predicate: fact.predicate,
        object: fact.object,
        valid_from: fact.valid_from,
      };
      const addFactTrace = {
        ...addFactMcp,
        source_observation_id: observation_id,
      };
      const addFactOut = await callMcpTool("add_fact", addFactMcp);
      await traceToolCall({
        session_id,
        step_index: stepIndex++,
        tool_name: "add_fact",
        input: addFactTrace,
        output: addFactOut,
        latency_ms: Date.now() - addFactT0,
      });
    }
  }

  return { episodes_added, nextStepIndex: stepIndex };
}

/**
 * Graphiti MCP returns tool content in a CallToolResult-like shape; we only
 * care whether it signals "exists". The tool contract isn't fully nailed
 * down yet, so we treat any truthy `exists` field or a boolean `true` as
 * existence. Anything else is "add it".
 */
function isTruthyExists(output: unknown): boolean {
  if (output === true) return true;
  const rec =
    typeof output === "object" && output !== null && !Array.isArray(output)
      ? (output as Record<string, unknown>)
      : null;
  if (rec && rec["exists"] === true) return true;

  const contentArray = Array.isArray(output)
    ? output
    : Array.isArray(rec?.["content"])
      ? (rec!["content"] as unknown[])
      : null;
  if (!contentArray) return false;
  const first = contentArray[0];
  if (
    typeof first !== "object" ||
    first === null ||
    !("text" in first)
  ) {
    return false;
  }
  const text = String((first as { text: unknown }).text).trim();
  if (text.toLowerCase() === "true") return true;
  try {
    const parsed = JSON.parse(text) as unknown;
    if (
      typeof parsed === "object" &&
      parsed !== null &&
      (parsed as Record<string, unknown>)["exists"] === true
    ) {
      return true;
    }
  } catch {
    // not JSON — fall through
  }
  return false;
}

async function consumeBatch(
  job: BatchJobRow,
  trigger_run_id: string | null,
): Promise<{ episodes_added: number; observations_processed: number }> {
  const client = getAnthropic();
  const batch = await client.messages.batches.retrieve(job.batch_id);

  if (batch.processing_status !== "ended") {
    const age_ms = Date.now() - Date.parse(job.submitted_at);
    if (age_ms > TIMEOUT_MS) {
      logger.error("nrem-extraction batch timed out", {
        alert: true,
        batch_id: job.batch_id,
        processing_status: batch.processing_status,
        age_hours: age_ms / 3_600_000,
      });
      await markBatchFailed(job.id, "timeout");
    } else {
      logger.info("nrem-extraction batch still processing", {
        batch_id: job.batch_id,
        processing_status: batch.processing_status,
      });
    }
    return { episodes_added: 0, observations_processed: 0 };
  }

  const session_id = await openAgentSession(
    "nrem-extraction-consume",
    null,
    trigger_run_id,
  );

  let stepIndex = 0;
  let episodes_added = 0;
  let observations_processed = 0;

  try {
    const resultsStream = await client.messages.batches.results(job.batch_id);

    for await (const line of resultsStream) {
      if (line.result.type !== "succeeded") {
        logger.warn("nrem-extraction result non-success", {
          custom_id: line.custom_id,
          result_type: line.result.type,
        });
        continue;
      }

      let payload: ExtractionPayload;
      try {
        payload = parseExtraction(line.result.message);
      } catch (err) {
        logger.warn("nrem-extraction payload parse failed", {
          custom_id: line.custom_id,
          error: (err as Error).message,
        });
        continue;
      }

      const outcome = await persistExtraction(
        payload,
        line.custom_id,
        session_id,
        stepIndex,
      );
      stepIndex = outcome.nextStepIndex;
      episodes_added += outcome.episodes_added;
      observations_processed++;
    }

    await closeAgentSession(session_id, "completed", {
      input_tokens: 0,
      output_tokens: 0,
      cache_read_tokens: 0,
    });
    await markBatchConsumed(job.id, session_id);

    logger.info("nrem-extraction batch consumed", {
      batch_id: job.batch_id,
      observations_processed,
      episodes_added,
    });

    return { episodes_added, observations_processed };
  } catch (err) {
    await closeAgentSession(session_id, "failed", {
      input_tokens: 0,
      output_tokens: 0,
      cache_read_tokens: 0,
    });
    throw err;
  }
}

export const nremEntityExtractionConsume = schedules.task({
  id: "nrem-entity-extraction-consume",
  // Every 5 minutes from 02:00 through 08:59 UTC. Anthropic batches complete
  // within 24h -- this window covers the overwhelming majority of cases.
  cron: "*/5 2-8 * * *",
  maxDuration: 600,
  run: async (_payload, { ctx }) => {
    logger.info("nrem-entity-extraction-consume starting");

    const pending = await loadPendingBatches();
    if (pending.length === 0) {
      logger.info("nrem-entity-extraction-consume: no pending batches");
      return { consumed: 0, episodes_added: 0 };
    }

    let consumed = 0;
    let episodes_added = 0;

    for (const job of pending) {
      try {
        const outcome = await consumeBatch(job, ctx.run.id ?? null);
        if (outcome.observations_processed > 0) {
          consumed++;
          episodes_added += outcome.episodes_added;
        }
      } catch (err) {
        logger.error("nrem-extraction consume iteration failed", {
          alert: true,
          batch_id: job.batch_id,
          error: (err as Error).message,
        });
        // Don't re-throw: one bad batch shouldn't poison sibling batches.
      }
    }

    logger.info("nrem-entity-extraction-consume done", {
      consumed,
      episodes_added,
    });
    return { consumed, episodes_added };
  },
});
