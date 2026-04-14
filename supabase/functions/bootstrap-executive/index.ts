// bootstrap-executive/index.ts
// Called on first sign-in to create the executives row from Microsoft profile.
// Idempotent: returns existing row if auth_user_id already exists.
// Auth: JWT verified via _shared/auth.ts
// Uses service_role to INSERT (RLS allows service role inserts).

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyAuth, AuthError, authErrorResponse } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/config.ts";

const supabaseAdmin = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY")
);

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
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
      return new Response(JSON.stringify(existing), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // Get user metadata from Supabase Auth (populated from Microsoft provider)
    const { data: { user }, error: userError } = await supabaseAdmin.auth.admin.getUserById(userId);
    if (userError || !user) throw new Error("Failed to fetch user profile");

    const meta = user.user_metadata ?? {};
    const displayName = meta.full_name ?? meta.name ?? meta.preferred_username ?? "Executive";
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

    return new Response(JSON.stringify(created), {
      status: 201,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    if (err instanceof AuthError) return authErrorResponse(err);
    return new Response(
      JSON.stringify({ error: err.message ?? "Internal error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
