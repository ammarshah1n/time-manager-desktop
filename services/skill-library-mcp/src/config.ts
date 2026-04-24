/**
 * Runtime configuration for skill-library-mcp. Only this module reads process
 * env vars — everything else takes `Config` by parameter.
 */

export interface Config {
  port: number;
  mcpToken: string;
  supabaseUrl: string;
  supabaseServiceRoleKey: string;
  voyageApiKey: string;
  voyageModel: string;
  voyageDim: number;
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
    mcpToken: required("SKILL_LIBRARY_MCP_TOKEN"),
    supabaseUrl: required("SUPABASE_URL"),
    supabaseServiceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"),
    voyageApiKey: required("VOYAGE_API_KEY"),
    voyageModel: optional("VOYAGE_MODEL", "voyage-3"),
    voyageDim: Number.parseInt(optional("VOYAGE_DIM", "1024"), 10),
  };
}
