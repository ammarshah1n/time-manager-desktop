/**
 * Runtime configuration loaded from environment. All values are required at
 * boot; boot fails fast if anything is missing. This is the only module that
 * reads process env vars — everything else takes `Config` by parameter.
 */

export interface Config {
  /** Port the HTTP server binds to. */
  port: number;
  /** Shared bearer token clients must present in Authorization header. */
  mcpToken: string;
  /** Neo4j bolt URI (AuraDB Professional or self-hosted). */
  neo4jUri: string;
  neo4jUser: string;
  neo4jPassword: string;
  /** Base URL of the sibling `graphiti` service (task 14) on Fly internal net. */
  graphitiUrl: string;
  /** Supabase credentials — service role, required for Storage uploads. */
  supabaseUrl: string;
  supabaseServiceRoleKey: string;
  /** Storage bucket used by `export_snapshot`. */
  snapshotBucket: string;
}

function required(name: string): string {
  const v = process.env[name];
  if (!v || v.length === 0) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

function optional(name: string, fallback: string): string {
  const v = process.env[name];
  return v && v.length > 0 ? v : fallback;
}

export function loadConfig(): Config {
  return {
    port: Number.parseInt(optional("PORT", "8080"), 10),
    mcpToken: required("GRAPHITI_MCP_TOKEN"),
    neo4jUri: required("NEO4J_URI"),
    neo4jUser: required("NEO4J_USER"),
    neo4jPassword: required("NEO4J_PASSWORD"),
    graphitiUrl: required("GRAPHITI_URL"),
    supabaseUrl: required("SUPABASE_URL"),
    supabaseServiceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"),
    snapshotBucket: optional("GRAPHITI_SNAPSHOT_BUCKET", "kg-snapshots"),
  };
}
