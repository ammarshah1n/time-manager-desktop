/**
 * Environment variable validation for Supabase Edge Functions.
 * Replaces Deno.env.get("...")! non-null assertions with clear error messages.
 */
export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}
