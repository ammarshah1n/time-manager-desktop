import { defineConfig } from "@trigger.dev/sdk";

/**
 * Timed overnight cognitive OS — Trigger.dev v3 configuration.
 *
 * The `project` reference is intentionally an env-driven placeholder; Ammar fills
 * it in on the Trigger.dev org side (manual Task 2 prerequisite). Every other
 * knob below is encoded here so the eventual `trigger.dev deploy` is a no-arg
 * operation.
 */
const TRIGGER_PROJECT_REF = process.env.TRIGGER_PROJECT_REF;
if (!TRIGGER_PROJECT_REF) {
  throw new Error(
    "TRIGGER_PROJECT_REF env var is required. Set it in the Trigger.dev org → Project settings, or export it locally before running `trigger.dev deploy`.",
  );
}

export default defineConfig({
  project: TRIGGER_PROJECT_REF,
  dirs: ["./src/tasks"],
  runtime: "node",
  logLevel: "info",
  // 15 min hard cap per task — nightly reflection tasks that exceed this must
  // split into separate orchestrated runs rather than balloon.
  maxDuration: 900,
  machine: "small-1x",
  retries: {
    enabledInDev: false,
    default: {
      maxAttempts: 3,
      minTimeoutInMs: 1000,
      maxTimeoutInMs: 30_000,
      factor: 2,
      randomize: true,
    },
  },
  build: {
    // Packages we never want Trigger.dev to bundle — the Anthropic + MCP SDKs
    // do runtime imports (TLS, sockets, native modules) that must stay external.
    external: [
      "@anthropic-ai/sdk",
      "@anthropic-ai/claude-agent-sdk",
      "@modelcontextprotocol/sdk",
      "@supabase/supabase-js",
    ],
  },
});
