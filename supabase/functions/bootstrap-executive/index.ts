// bootstrap-executive/index.ts
// Called on first sign-in to create the executives row from Microsoft profile.
// Idempotent: returns existing row if auth_user_id already exists.
// Auth: JWT verified via _shared/auth.ts
// Uses service_role to INSERT (RLS allows service role inserts).

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { AuthError, authErrorResponse, verifyAuth } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/config.ts";

const supabaseAdmin = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
);

type ExecutiveRecord = {
  id: string;
  display_name: string;
  email: string;
  timezone: string;
  onboarded_at: string | null;
};

async function ensureBootstrapRows(
  authUserId: string,
  executive: ExecutiveRecord,
): Promise<void> {
  const nowIso = new Date().toISOString();
  const workspaceName = `${executive.display_name || "Executive"} Workspace`;

  const { error: workspaceError } = await supabaseAdmin
    .from("workspaces")
    .upsert(
      {
        id: executive.id,
        name: workspaceName,
        slug: `exec-${executive.id}`,
        updated_at: nowIso,
      },
      { onConflict: "id" },
    );
  if (workspaceError) throw workspaceError;

  const profileRows = [
    {
      id: executive.id,
      email: executive.email,
      full_name: executive.display_name,
      timezone: executive.timezone,
    },
  ];
  if (authUserId !== executive.id) {
    profileRows.push({
      id: authUserId,
      email: executive.email,
      full_name: executive.display_name,
      timezone: executive.timezone,
    });
  }

  const { error: profileError } = await supabaseAdmin
    .from("profiles")
    .upsert(profileRows, { onConflict: "id" });
  if (profileError) throw profileError;

  const memberRows = profileRows.map((profile) => ({
    workspace_id: executive.id,
    profile_id: profile.id,
    role: "owner",
  }));
  const { error: memberError } = await supabaseAdmin
    .from("workspace_members")
    .upsert(memberRows, { onConflict: "workspace_id,profile_id" });
  if (memberError) throw memberError;

  const { error: accountError } = await supabaseAdmin
    .from("email_accounts")
    .upsert(
      {
        id: executive.id,
        workspace_id: executive.id,
        profile_id: executive.id,
        provider: "outlook",
        provider_account_id: authUserId,
        email_address: executive.email,
        sync_enabled: true,
        updated_at: nowIso,
      },
      { onConflict: "id" },
    );
  if (accountError) throw accountError;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "null",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  try {
    const userId = await verifyAuth(req);

    // Check if executive already exists
    const { data: existing, error: fetchError } = await supabaseAdmin
      .from("executives")
      .select("id, display_name, email, timezone, onboarded_at")
      .eq("auth_user_id", userId)
      .maybeSingle();

    if (fetchError) throw fetchError;

    if (existing) {
      await ensureBootstrapRows(userId, existing as ExecutiveRecord);
      return new Response(JSON.stringify(existing), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // Get user metadata from Supabase Auth (populated from Microsoft provider)
    const { data: { user }, error: userError } = await supabaseAdmin.auth.admin
      .getUserById(userId);
    if (userError || !user) throw new Error("Failed to fetch user profile");

    const meta = user.user_metadata ?? {};
    const displayName = meta.full_name ?? meta.name ??
      meta.preferred_username ?? "Executive";
    const email = user.email ?? meta.email ?? "";

    // Insert new executive
    const { data: created, error: insertError } = await supabaseAdmin
      .from("executives")
      .insert({
        auth_user_id: userId,
        display_name: displayName,
        email: email,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone ?? "UTC",
      })
      .select("id, display_name, email, timezone, onboarded_at")
      .single();

    if (insertError) throw insertError;
    await ensureBootstrapRows(userId, created as ExecutiveRecord);

    return new Response(JSON.stringify(created), {
      status: 201,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    const message = err instanceof Error ? err.message : "Internal error";
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
