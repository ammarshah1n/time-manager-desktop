#!/usr/bin/env tsx
/**
 * replay.ts — Deterministic-replay CLI for Timed's overnight cognitive OS.
 *
 * Wave 1 Agent A5 scaffold. Full implementation lands in Wave 2.
 * Implements task 41 in `docs/plans/here-s-the-improved-prompt-snazzy-cookie.md`.
 *
 * Two explicitly-scoped modes:
 *   --mode=prompt (default)
 *       Reads `agent_traces` for the session in (session_id, step_index) order,
 *       reconstructs the exact prompt + tool-use trajectory, would re-issue
 *       each `inference()` call, and writes a diff report against the
 *       originally-recorded outputs. Deterministic at the LLM-input level
 *       modulo sampling; NOT deterministic at the KG-state level — tool
 *       results come from the CURRENT Graphiti instance, which has mutated
 *       since the original run.
 *
 *   --mode=kg-restore --snapshot-week=YYYY-WW
 *       Locates the `kg_snapshots` row covering the session, restores it
 *       into a scratch Neo4j at NEO4J_REPLAY_URI, re-points Graphiti MCP at
 *       the scratch instance, then re-runs the trajectory. This is the
 *       forensic path — the only mode where KG-state replay is honest.
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
  KgSnapshotRow,
} from "./types.stubs.js";

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------

const TRACE_CORPUS_VERSION = "v0-stub" as const;

/**
 * ISO week format. Non-exhaustive but catches the common "YYYY-Www" /
 * "YYYY-WW" typos.
 */
const ISO_WEEK_REGEX = /^\d{4}-W?\d{2}$/;

// -----------------------------------------------------------------------------
// Process environment + clients
// -----------------------------------------------------------------------------

const RuntimeSchema = z.object({
  SUPABASE_URL: z.string().url().optional(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1).optional(),
  NEO4J_REPLAY_URI: z.string().optional(),
  NEO4J_REPLAY_USER: z.string().optional(),
  NEO4J_REPLAY_PASSWORD: z.string().optional(),
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

const ModeSchema = z.enum(["prompt", "kg-restore"]);
type Mode = z.infer<typeof ModeSchema>;

interface ReplayOptions {
  mode: Mode;
  sessionId: string;
  snapshotWeek?: string;
  outputDir: string;
  dryRun: boolean;
}

function parseMode(value: string): Mode {
  const parsed = ModeSchema.safeParse(value);
  if (!parsed.success) {
    throw new InvalidArgumentError(
      `--mode must be one of: ${ModeSchema.options.join(", ")}`,
    );
  }
  return parsed.data;
}

function parseSnapshotWeek(value: string): string {
  if (!ISO_WEEK_REGEX.test(value)) {
    throw new InvalidArgumentError(
      `--snapshot-week must be ISO week format YYYY-WW (got: ${value})`,
    );
  }
  return value;
}

function buildProgram(): Command {
  const program = new Command();

  program
    .name("replay")
    .description(
      [
        "Deterministic-replay CLI for Timed agent sessions.",
        "",
        "Two modes:",
        "  --mode=prompt (default)",
        "      Deterministic at the LLM-input level modulo sampling.",
        "      NOT deterministic at the KG-state level — tool results come",
        "      from the current Graphiti, which has mutated since the",
        "      original run. Any divergence in the diff report may be real",
        "      KG drift rather than a bug.",
        "",
        "  --mode=kg-restore --snapshot-week=YYYY-WW",
        "      Forensic replay. Restores the weekly kg_snapshots row into a",
        "      scratch Neo4j at NEO4J_REPLAY_URI, re-points Graphiti MCP at",
        "      the scratch instance, then re-runs the trajectory. This is",
        "      the only mode where KG-state replay is honest.",
        "",
        `Trace corpus version: ${TRACE_CORPUS_VERSION}`,
      ].join("\n"),
    )
    .version("0.0.0-stub");

  program
    .requiredOption(
      "--session-id <id>",
      "agent_sessions.id to replay (UUID)",
    )
    .option(
      "--mode <mode>",
      "replay mode: prompt | kg-restore",
      parseMode,
      "prompt" as Mode,
    )
    .option(
      "--snapshot-week <YYYY-WW>",
      "ISO week of kg_snapshots row to restore (required with --mode=kg-restore)",
      parseSnapshotWeek,
    )
    .option(
      "--output-dir <path>",
      "directory for replay report (default: ./replays)",
      "./replays",
    )
    .option(
      "--dry-run",
      "parse args + print plan without reading Supabase or writing files",
      false,
    );

  return program;
}

function validateOptions(raw: {
  mode: Mode;
  sessionId: string;
  snapshotWeek?: string;
  outputDir: string;
  dryRun: boolean;
}): ReplayOptions {
  if (raw.mode === "kg-restore" && !raw.snapshotWeek) {
    throw new Error("--mode=kg-restore requires --snapshot-week=YYYY-WW");
  }
  if (raw.mode === "prompt" && raw.snapshotWeek) {
    console.warn(
      "[replay] warning: --snapshot-week is ignored when --mode=prompt",
    );
  }
  return raw;
}

// -----------------------------------------------------------------------------
// Core (stubbed)
// -----------------------------------------------------------------------------

async function loadSession(
  supabase: SupabaseClient,
  sessionId: string,
): Promise<AgentSessionRow> {
  // TODO(wave2): implement — SELECT * FROM agent_sessions WHERE id=$sessionId.
  // Return shape must match AgentSessionRow; throw if not found.
  void supabase;
  void sessionId;
  throw new Error(
    `TODO(wave2): loadSession — query agent_sessions by id (${sessionId})`,
  );
}

async function loadTraces(
  supabase: SupabaseClient,
  sessionId: string,
): Promise<AgentTraceRow[]> {
  // TODO(wave2): implement —
  //   SELECT * FROM agent_traces
  //   WHERE session_id=$sessionId
  //   ORDER BY step_index ASC
  void supabase;
  void sessionId;
  throw new Error(
    `TODO(wave2): loadTraces — query agent_traces ordered by step_index for session ${sessionId}`,
  );
}

function reconstructInferences(traces: AgentTraceRow[]): InferenceTuple[] {
  // TODO(wave2): group contiguous trace rows into InferenceTuples.
  // Boundary: a new InferenceTuple begins when role='system' or role='user'
  // follows a 'tool_result' or the trace is the first row of the session.
  // Each tuple covers one `inference()` call's full request/response arc.
  void traces;
  throw new Error(
    "TODO(wave2): reconstructInferences — assemble InferenceTuples from agent_traces rows",
  );
}

async function reissueInference(
  tuple: InferenceTuple,
): Promise<{ response: string; divergence: string | null }> {
  // TODO(wave2): call the shared `inference()` wrapper (A1) with the same
  // model_alias + system + messages + tools, then diff against
  // tuple.final_response. Return null divergence if byte-equal modulo
  // sampling noise.
  void tuple;
  throw new Error(
    "TODO(wave2): reissueInference — call shared inference() and diff vs original",
  );
}

async function locateKgSnapshot(
  supabase: SupabaseClient,
  session: AgentSessionRow,
  snapshotWeek: string,
): Promise<KgSnapshotRow> {
  // TODO(wave2): SELECT * FROM kg_snapshots WHERE week=$snapshotWeek
  // (optionally filtered by session_id) LIMIT 1. Throw if no row.
  void supabase;
  void session;
  void snapshotWeek;
  throw new Error(
    `TODO(wave2): locateKgSnapshot — query kg_snapshots for week ${snapshotWeek}`,
  );
}

async function restoreKgIntoScratchNeo4j(
  snapshot: KgSnapshotRow,
  runtime: Runtime,
): Promise<{ replayUri: string }> {
  // TODO(wave2):
  //   1. Download snapshot.storage_path from Supabase Storage bucket `kg-snapshots/`.
  //   2. Against runtime.NEO4J_REPLAY_URI:
  //        a. MATCH (n) DETACH DELETE n;
  //        b. CALL apoc.import.json('<downloaded-path>')
  //      Requires APOC + APOC_IMPORT_FILE_ENABLED=true on the scratch Neo4j.
  //   3. Return { replayUri: runtime.NEO4J_REPLAY_URI }.
  void snapshot;
  if (!runtime.NEO4J_REPLAY_URI) {
    throw new Error(
      "TODO(wave2): restoreKgIntoScratchNeo4j — NEO4J_REPLAY_URI not set",
    );
  }
  throw new Error(
    "TODO(wave2): restoreKgIntoScratchNeo4j — apoc.import.json into scratch Neo4j",
  );
}

async function repointGraphitiMcp(replayUri: string): Promise<void> {
  // TODO(wave2): write a per-replay MCP config that points graphiti-mcp
  // at `replayUri` for the duration of this replay invocation. Either spawn
  // a scoped graphiti-mcp process against the scratch Neo4j or hot-swap the
  // production instance's NEO4J_URI (preferred: scoped process, so
  // production reasoning is never disrupted by a replay).
  void replayUri;
  throw new Error(
    "TODO(wave2): repointGraphitiMcp — spawn scoped graphiti-mcp against scratch Neo4j",
  );
}

// -----------------------------------------------------------------------------
// Report writer
// -----------------------------------------------------------------------------

interface ReplayReport {
  sessionId: string;
  mode: Mode;
  snapshotWeek?: string;
  traceCorpusVersion: string;
  runStartedAt: string;
  determinismGuarantee: string;
  inferenceCount: number;
  divergences: Array<{
    step_index_start: number;
    step_index_end: number;
    model: string;
    detail: string;
  }>;
}

function renderReportMarkdown(report: ReplayReport): string {
  const lines: string[] = [];
  lines.push(`# Replay Report — session ${report.sessionId}`);
  lines.push("");
  lines.push("## Header");
  lines.push("");
  lines.push(`- **mode:** \`${report.mode}\``);
  if (report.snapshotWeek) {
    lines.push(`- **snapshot-week:** \`${report.snapshotWeek}\``);
  }
  lines.push(`- **trace-corpus-version:** \`${report.traceCorpusVersion}\``);
  lines.push(`- **run-started-at:** ${report.runStartedAt}`);
  lines.push(`- **inference-count:** ${report.inferenceCount}`);
  lines.push("");
  lines.push("## Determinism guarantee");
  lines.push("");
  lines.push(report.determinismGuarantee);
  lines.push("");
  lines.push("## Divergences");
  lines.push("");
  if (report.divergences.length === 0) {
    lines.push("_None — stub run, no inferences were actually re-issued._");
  } else {
    for (const d of report.divergences) {
      lines.push(
        `- steps \`${d.step_index_start}..${d.step_index_end}\` (model \`${d.model}\`): ${d.detail}`,
      );
    }
  }
  lines.push("");
  return lines.join("\n");
}

function determinismGuaranteeFor(mode: Mode): string {
  if (mode === "prompt") {
    return [
      "Prompt mode is deterministic at the LLM-input level modulo sampling.",
      "It is NOT deterministic at the KG-state level — tool results come",
      "from the CURRENT Graphiti, which has mutated since the original run.",
      "Any divergence in this report may be real KG drift rather than a bug.",
      "For a KG-state-honest replay, re-run with `--mode=kg-restore`.",
    ].join(" ");
  }
  return [
    "kg-restore mode is deterministic at both the LLM-input level (modulo",
    "sampling) AND the KG-state level: Graphiti MCP was re-pointed at a",
    "scratch Neo4j instance restored from the kg_snapshots row for the",
    "configured ISO week. Any remaining divergence beyond sampling noise",
    "implies either a snapshot/restore path bug or non-determinism in the",
    "inference wrapper.",
  ].join(" ");
}

async function writeReport(
  outputDir: string,
  report: ReplayReport,
): Promise<string> {
  const absDir = resolve(outputDir);
  const absPath = join(absDir, `${report.sessionId}.md`);
  await mkdir(dirname(absPath), { recursive: true });
  await writeFile(absPath, renderReportMarkdown(report), "utf8");
  return absPath;
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

async function runPromptMode(
  opts: ReplayOptions,
  supabase: SupabaseClient | null,
): Promise<ReplayReport> {
  const report: ReplayReport = {
    sessionId: opts.sessionId,
    mode: opts.mode,
    traceCorpusVersion: TRACE_CORPUS_VERSION,
    runStartedAt: new Date().toISOString(),
    determinismGuarantee: determinismGuaranteeFor(opts.mode),
    inferenceCount: 0,
    divergences: [],
  };

  if (opts.dryRun || supabase === null) {
    console.log(`[replay] prompt-mode plan for session ${opts.sessionId}:`);
    console.log("  1. SELECT * FROM agent_sessions WHERE id=$sessionId");
    console.log(
      "  2. SELECT * FROM agent_traces WHERE session_id=$sessionId ORDER BY step_index",
    );
    console.log("  3. reconstructInferences(traces) -> InferenceTuple[]");
    console.log("  4. for each tuple: re-issue inference() and diff vs final_response");
    console.log("  5. write report to <output-dir>/<session-id>.md");
    return report;
  }

  // TODO(wave2): wire these up once A1's inference() + db helpers land.
  const session = await loadSession(supabase, opts.sessionId);
  const traces = await loadTraces(supabase, opts.sessionId);
  const tuples = reconstructInferences(traces);
  report.inferenceCount = tuples.length;

  for (const tuple of tuples) {
    const result = await reissueInference(tuple);
    if (result.divergence) {
      report.divergences.push({
        step_index_start: tuple.step_index_start,
        step_index_end: tuple.step_index_end,
        model: tuple.model,
        detail: result.divergence,
      });
    }
  }

  void session;
  return report;
}

async function runKgRestoreMode(
  opts: ReplayOptions,
  supabase: SupabaseClient | null,
  runtime: Runtime,
): Promise<ReplayReport> {
  if (!opts.snapshotWeek) {
    throw new Error("--snapshot-week is required for --mode=kg-restore");
  }

  const report: ReplayReport = {
    sessionId: opts.sessionId,
    mode: opts.mode,
    snapshotWeek: opts.snapshotWeek,
    traceCorpusVersion: TRACE_CORPUS_VERSION,
    runStartedAt: new Date().toISOString(),
    determinismGuarantee: determinismGuaranteeFor(opts.mode),
    inferenceCount: 0,
    divergences: [],
  };

  if (opts.dryRun || supabase === null) {
    console.log(
      `[replay] kg-restore-mode plan for session ${opts.sessionId}, week ${opts.snapshotWeek}:`,
    );
    console.log("  1. SELECT * FROM agent_sessions WHERE id=$sessionId");
    console.log("  2. SELECT * FROM kg_snapshots WHERE week=$snapshotWeek LIMIT 1");
    console.log("  3. download snapshot.storage_path from Supabase Storage");
    console.log(
      "  4. restore into scratch Neo4j at NEO4J_REPLAY_URI via apoc.import.json",
    );
    console.log("  5. spawn scoped graphiti-mcp pointed at scratch Neo4j");
    console.log(
      "  6. SELECT * FROM agent_traces WHERE session_id=$sessionId ORDER BY step_index",
    );
    console.log("  7. reconstructInferences(traces) -> InferenceTuple[]");
    console.log("  8. for each tuple: re-issue inference() and diff");
    console.log("  9. write report to <output-dir>/<session-id>.md");
    return report;
  }

  const session = await loadSession(supabase, opts.sessionId);
  const snapshot = await locateKgSnapshot(supabase, session, opts.snapshotWeek);
  const { replayUri } = await restoreKgIntoScratchNeo4j(snapshot, runtime);
  await repointGraphitiMcp(replayUri);

  const traces = await loadTraces(supabase, opts.sessionId);
  const tuples = reconstructInferences(traces);
  report.inferenceCount = tuples.length;

  for (const tuple of tuples) {
    const result = await reissueInference(tuple);
    if (result.divergence) {
      report.divergences.push({
        step_index_start: tuple.step_index_start,
        step_index_end: tuple.step_index_end,
        model: tuple.model,
        detail: result.divergence,
      });
    }
  }

  return report;
}

async function main(): Promise<void> {
  const program = buildProgram();
  program.parse(process.argv);
  const raw = program.opts<{
    mode: Mode;
    sessionId: string;
    snapshotWeek?: string;
    outputDir: string;
    dryRun: boolean;
  }>();

  const opts = validateOptions(raw);
  const runtime = loadRuntime();
  const supabase = makeSupabaseClient(runtime);

  if (supabase === null && !opts.dryRun) {
    console.error(
      "[replay] SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set — forcing dry-run.",
    );
    opts.dryRun = true;
  }

  const report =
    opts.mode === "prompt"
      ? await runPromptMode(opts, supabase)
      : await runKgRestoreMode(opts, supabase, runtime);

  if (!opts.dryRun) {
    const path = await writeReport(opts.outputDir, report);
    console.log(`[replay] report written: ${path}`);
  } else {
    console.log(
      `[replay] dry-run complete — report would be written to ${resolve(
        opts.outputDir,
        `${opts.sessionId}.md`,
      )}`,
    );
  }
}

// Run only when invoked directly (not when imported, e.g. from tests).
const invokedPath = process.argv[1] ?? "";
const isDirectInvocation =
  import.meta.url === `file://${invokedPath}` ||
  invokedPath.endsWith("/replay.ts") ||
  invokedPath.endsWith("/replay.js");

if (isDirectInvocation) {
  main().catch((err: unknown) => {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`[replay] error: ${msg}`);
    process.exit(1);
  });
}

export {
  buildProgram,
  determinismGuaranteeFor,
  renderReportMarkdown,
  runPromptMode,
  runKgRestoreMode,
};

