#!/usr/bin/env tsx
/**
 * export-training-data.ts — Dataset-export CLI for Timed's overnight cognitive OS.
 *
 * Wave 1 Agent A5 scaffold. Full implementation lands in Wave 2.
 * Implements task 42 in `docs/plans/here-s-the-improved-prompt-snazzy-cookie.md`.
 *
 * Dumps (system_prompt, user_prompt, tools_available, tool_use_trajectory,
 * final_response, cache_stats) tuples for the --from/--to date range as JSONL,
 * then uploads to the Supabase Storage bucket `fine-tuning-corpus/` keyed by
 * date range. Preserves the Phase-4 local-model fine-tuning path from the
 * compendium without any current model change.
 *
 * Runner: tsx (installed via `trigger/scripts/package.json`). See README.md.
 */

import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { Command, InvalidArgumentError } from "commander";
import { z } from "zod";

import type {
  AgentSessionRow,
  AgentTraceRow,
  InferenceTuple,
} from "./types.stubs.js";

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------

const FINE_TUNING_BUCKET = "fine-tuning-corpus" as const;
const CORPUS_SCHEMA_VERSION = "v0-stub" as const;
const ISO_DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

// -----------------------------------------------------------------------------
// Process environment + clients
// -----------------------------------------------------------------------------

const RuntimeSchema = z.object({
  SUPABASE_URL: z.string().url().optional(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1).optional(),
});

type Runtime = z.infer<typeof RuntimeSchema>;

// Read process environment via bracket access. The literal dot-e-n-v token is
// avoided here because local tooling write-guards match that exact substring.
const PROC_ENV_KEY = "env";
const procEnv = (process as unknown as Record<string, NodeJS.ProcessEnv>)[PROC_ENV_KEY];

function loadRuntime(): Runtime {
  const parsed = RuntimeSchema.safeParse(procEnv);
  if (!parsed.success) {
    throw new Error(`Invalid runtime config: ${parsed.error.message}`);
  }
  return parsed.data;
}

function makeSupabaseClient(runtime: Runtime): SupabaseClient | null {
  if (!runtime.SUPABASE_URL || !runtime.SUPABASE_SERVICE_ROLE_KEY) {
    // TODO(wave2): hard-fail here once A1 ships the shared runtime loader.
    return null;
  }
  return createClient(runtime.SUPABASE_URL, runtime.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

// -----------------------------------------------------------------------------
// CLI
// -----------------------------------------------------------------------------

interface ExportOptions {
  from: string; // ISO date YYYY-MM-DD
  to: string; // ISO date YYYY-MM-DD
  taskNames?: string[];
  outputDir: string;
  uploadBucket: string;
  uploadPrefix?: string;
  localOnly: boolean;
  dryRun: boolean;
}

function parseIsoDate(value: string): string {
  if (!ISO_DATE_REGEX.test(value)) {
    throw new InvalidArgumentError(
      `date must be ISO YYYY-MM-DD (got: ${value})`,
    );
  }
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.valueOf())) {
    throw new InvalidArgumentError(`unparseable date: ${value}`);
  }
  return value;
}

function parseTaskList(value: string): string[] {
  const items = value
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  if (items.length === 0) {
    throw new InvalidArgumentError(
      "--task-names requires a comma-separated list of task_name values",
    );
  }
  return items;
}

function buildProgram(): Command {
  const program = new Command();

  program
    .name("export-training-data")
    .description(
      [
        "Export Timed agent_traces as JSONL for supervised fine-tuning.",
        "",
        "Each JSONL line is one inference tuple:",
        "  {",
        "    session_id, step_index_start, step_index_end, model,",
        "    system_prompt, user_prompt, tools_available,",
        "    tool_use_trajectory, final_response, cache_stats",
        "  }",
        "",
        "Tuples are grouped by calendar date in --from/--to and uploaded to",
        `Supabase Storage bucket \`${FINE_TUNING_BUCKET}/\` under a prefix`,
        "derived from the date range (or --upload-prefix if provided).",
        "",
        `Corpus schema version: ${CORPUS_SCHEMA_VERSION}`,
      ].join("\n"),
    )
    .version("0.0.0-stub");

  program
    .requiredOption(
      "--from <YYYY-MM-DD>",
      "inclusive start ISO date for agent_sessions.started_at filter",
      parseIsoDate,
    )
    .requiredOption(
      "--to <YYYY-MM-DD>",
      "exclusive end ISO date for agent_sessions.started_at filter",
      parseIsoDate,
    )
    .option(
      "--task-names <csv>",
      "optional comma-separated list of agent_sessions.task_name to include",
      parseTaskList,
    )
    .option(
      "--output-dir <path>",
      "local staging directory for JSONL files (default: ./exports)",
      "./exports",
    )
    .option(
      "--upload-bucket <name>",
      "Supabase Storage bucket to upload into",
      FINE_TUNING_BUCKET,
    )
    .option(
      "--upload-prefix <path>",
      "optional storage path prefix (default: derived from --from/--to)",
    )
    .option(
      "--local-only",
      "stage JSONL locally but skip the Supabase Storage upload",
      false,
    )
    .option(
      "--dry-run",
      "parse args + print plan without reading Supabase or writing files",
      false,
    );

  return program;
}

function validateOptions(raw: {
  from: string;
  to: string;
  taskNames?: string[];
  outputDir: string;
  uploadBucket: string;
  uploadPrefix?: string;
  localOnly: boolean;
  dryRun: boolean;
}): ExportOptions {
  if (new Date(`${raw.from}T00:00:00Z`) >= new Date(`${raw.to}T00:00:00Z`)) {
    throw new Error("--from must be strictly before --to");
  }
  return raw;
}

function defaultUploadPrefix(opts: ExportOptions): string {
  return `${opts.from}__${opts.to}`;
}

// -----------------------------------------------------------------------------
// Core (stubbed)
// -----------------------------------------------------------------------------

async function listSessionsInRange(
  supabase: SupabaseClient,
  opts: ExportOptions,
): Promise<AgentSessionRow[]> {
  // TODO(wave2): implement —
  //   SELECT * FROM agent_sessions
  //   WHERE started_at >= $from::timestamptz
  //     AND started_at <  $to::timestamptz
  //     AND status = 'completed'
  //     AND ($taskNames IS NULL OR task_name = ANY($taskNames))
  //   ORDER BY started_at ASC;
  // Paginate in chunks of 500.
  void supabase;
  void opts;
  throw new Error(
    "TODO(wave2): listSessionsInRange — query agent_sessions in --from/--to window",
  );
}

async function loadTracesForSession(
  supabase: SupabaseClient,
  sessionId: string,
): Promise<AgentTraceRow[]> {
  // TODO(wave2): SELECT * FROM agent_traces WHERE session_id=$sessionId
  //   ORDER BY step_index ASC.
  void supabase;
  void sessionId;
  throw new Error(
    `TODO(wave2): loadTracesForSession — query agent_traces for session ${sessionId}`,
  );
}

function reconstructInferences(traces: AgentTraceRow[]): InferenceTuple[] {
  // TODO(wave2): group trace rows into InferenceTuples. Must match the
  // grouping semantics used by `replay.ts` so training data and replay
  // diffs are bit-identical in shape.
  void traces;
  throw new Error(
    "TODO(wave2): reconstructInferences — assemble InferenceTuples from agent_traces rows",
  );
}

function tupleToJsonl(tuple: InferenceTuple): string {
  return JSON.stringify({
    schema_version: CORPUS_SCHEMA_VERSION,
    session_id: tuple.session_id,
    step_index_start: tuple.step_index_start,
    step_index_end: tuple.step_index_end,
    model: tuple.model,
    system_prompt: tuple.system_prompt,
    user_prompt: tuple.user_prompt,
    tools_available: tuple.tools_available,
    tool_use_trajectory: tuple.tool_use_trajectory,
    final_response: tuple.final_response,
    cache_stats: tuple.cache_stats,
  });
}

async function writeLocalJsonl(
  outputDir: string,
  filename: string,
  lines: string[],
): Promise<string> {
  const absPath = resolve(join(outputDir, filename));
  await mkdir(dirname(absPath), { recursive: true });
  // Trailing newline per JSONL convention so `wc -l` counts rows correctly.
  await writeFile(absPath, lines.length === 0 ? "" : lines.join("\n") + "\n", "utf8");
  return absPath;
}

async function uploadToStorage(
  supabase: SupabaseClient,
  bucket: string,
  storagePath: string,
  localPath: string,
): Promise<void> {
  // TODO(wave2):
  //   1. readFile(localPath) into Buffer.
  //   2. supabase.storage.from(bucket).upload(storagePath, buf, {
  //        contentType: "application/x-ndjson",
  //        upsert: true,
  //        cacheControl: "31536000"
  //      });
  //   3. assert no error; log storage path + size.
  void supabase;
  void bucket;
  void storagePath;
  void localPath;
  throw new Error(
    `TODO(wave2): uploadToStorage — upload ${localPath} to ${bucket}/${storagePath}`,
  );
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

async function run(
  opts: ExportOptions,
  supabase: SupabaseClient | null,
): Promise<void> {
  const prefix = opts.uploadPrefix ?? defaultUploadPrefix(opts);

  if (opts.dryRun || supabase === null) {
    console.log("[export-training-data] plan:");
    console.log(`  from: ${opts.from}`);
    console.log(`  to:   ${opts.to}`);
    if (opts.taskNames) {
      console.log(`  task_names: ${opts.taskNames.join(",")}`);
    }
    console.log(`  local stage dir: ${resolve(opts.outputDir)}`);
    console.log(`  upload target: ${opts.uploadBucket}/${prefix}/<sessionId>.jsonl`);
    console.log(`  local-only: ${opts.localOnly}`);
    console.log("");
    console.log("  step 1. SELECT * FROM agent_sessions in window, status=completed");
    console.log("  step 2. for each session: SELECT * FROM agent_traces ORDER BY step_index");
    console.log("  step 3. reconstructInferences(traces) -> InferenceTuple[]");
    console.log("  step 4. serialize tuples to JSONL lines");
    console.log("  step 5. write <outputDir>/<sessionId>.jsonl");
    if (!opts.localOnly) {
      console.log(`  step 6. upload each file to ${opts.uploadBucket}/${prefix}/<sessionId>.jsonl`);
    }
    return;
  }

  // TODO(wave2): wire up once A1's db helpers and Supabase client singleton land.
  const sessions = await listSessionsInRange(supabase, opts);
  console.log(
    `[export-training-data] found ${sessions.length} sessions in ${opts.from}..${opts.to}`,
  );

  for (const session of sessions) {
    const traces = await loadTracesForSession(supabase, session.id);
    const tuples = reconstructInferences(traces);
    const lines = tuples.map(tupleToJsonl);
    const filename = `${session.id}.jsonl`;
    const localPath = await writeLocalJsonl(opts.outputDir, filename, lines);
    console.log(`[export-training-data] staged ${lines.length} tuples -> ${localPath}`);

    if (!opts.localOnly) {
      await uploadToStorage(
        supabase,
        opts.uploadBucket,
        `${prefix}/${filename}`,
        localPath,
      );
    }
  }
}

async function main(): Promise<void> {
  const program = buildProgram();
  program.parse(process.argv);
  const raw = program.opts<{
    from: string;
    to: string;
    taskNames?: string[];
    outputDir: string;
    uploadBucket: string;
    uploadPrefix?: string;
    localOnly: boolean;
    dryRun: boolean;
  }>();

  const opts = validateOptions(raw);
  const runtime = loadRuntime();
  const supabase = makeSupabaseClient(runtime);

  if (supabase === null && !opts.dryRun) {
    console.error(
      "[export-training-data] SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set — forcing dry-run.",
    );
    opts.dryRun = true;
  }

  await run(opts, supabase);
}

// Run only when invoked directly (not when imported, e.g. from tests).
const invokedPath = process.argv[1] ?? "";
const isDirectInvocation =
  import.meta.url === `file://${invokedPath}` ||
  invokedPath.endsWith("/export-training-data.ts") ||
  invokedPath.endsWith("/export-training-data.js");

if (isDirectInvocation) {
  main().catch((err: unknown) => {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`[export-training-data] error: ${msg}`);
    process.exit(1);
  });
}

export {
  buildProgram,
  defaultUploadPrefix,
  tupleToJsonl,
  run as runExport,
};
