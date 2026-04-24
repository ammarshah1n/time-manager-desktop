// Task 19 companion — one-off backfill of executive_profile from existing
// AppStorage values. Ammar supplies the shape below for Yasser's profile
// (read from ~/Library/Preferences/<bundle>.plist on the Mac). The script
// upserts into public.executive_profile and is idempotent.
//
// Run with Deno: `deno run --allow-env --allow-net supabase/scripts/backfill-executive-profile.ts`
// Environment:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — required (service role bypasses RLS)
//   BACKFILL_EXEC_ID                        — executives.id for the target exec
//   BACKFILL_PAYLOAD_JSON                   — JSON matching ExecutiveProfileInput below
//
// ExecutiveProfileInput shape (mirrors AppStorage keys used by OnboardingFlow):
//   {
//     "display_name":            string,       // onboarding_userName
//     "work_hours_start":        "HH:MM",      // derived from onboarding_workStartHour
//     "work_hours_end":          "HH:MM",      // derived from onboarding_workEndHour
//     "typical_workday_hours":   number,       // onboarding_workdayHours
//     "email_cadence_mode":      0|1|2|3,      // onboarding_emailCadence
//     "transit_modes":           string[],     // parsed onboarding_transitModes CSV
//     "time_defaults":           {             // onboarding_{reply,action,call,read}Mins
//       "reply": number, "action": number, "call": number, "read": number
//     },
//     "pa_email":                string|null,  // onboarding_paEmail
//     "pa_enabled":              boolean       // onboarding_paEnabled
//   }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface ExecutiveProfileInput {
    display_name?: string | null;
    work_hours_start?: string | null;
    work_hours_end?: string | null;
    typical_workday_hours?: number | null;
    email_cadence_mode?: number | null;
    transit_modes?: string[] | null;
    time_defaults?: Record<string, number> | null;
    pa_email?: string | null;
    pa_enabled?: boolean | null;
}

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const execId = Deno.env.get("BACKFILL_EXEC_ID");
const payloadJson = Deno.env.get("BACKFILL_PAYLOAD_JSON");

if (!url || !key || !execId || !payloadJson) {
    console.error(
        "Missing required env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, BACKFILL_EXEC_ID, BACKFILL_PAYLOAD_JSON",
    );
    Deno.exit(1);
}

const input = JSON.parse(payloadJson) as ExecutiveProfileInput;
const client = createClient(url, key, { auth: { persistSession: false } });

const row = {
    exec_id: execId,
    display_name: input.display_name ?? null,
    work_hours_start: input.work_hours_start ?? null,
    work_hours_end: input.work_hours_end ?? null,
    typical_workday_hours: input.typical_workday_hours ?? null,
    email_cadence_mode: input.email_cadence_mode ?? null,
    transit_modes: input.transit_modes ?? [],
    time_defaults: input.time_defaults ?? {},
    pa_email: input.pa_email ?? null,
    pa_enabled: input.pa_enabled ?? false,
    updated_at: new Date().toISOString(),
};

const { error } = await client
    .from("executive_profile")
    .upsert(row, { onConflict: "exec_id" });

if (error) {
    console.error("Upsert failed:", error);
    Deno.exit(2);
}

console.log("executive_profile upserted for", execId);
