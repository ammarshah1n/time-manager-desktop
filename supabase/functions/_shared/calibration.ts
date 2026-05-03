export interface CalibrationContext {
  yesterdayOverrides: Array<{
    task_id: string;
    old_minutes: number;
    new_minutes: number;
    delta_pct: number;
    occurred_at: string;
    reason?: string;
  }>;
  thirtyDayDriftPct: number | null;
  perBucketBias: Array<{
    bucket_type: string;
    bias_minutes: number;
    n_samples: number;
  }>;
}

export async function loadCalibrationContext(
  supabase: any,
  executiveId: string,
): Promise<CalibrationContext> {
  const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

  const [overridesRes, profileRes, bucketsRes] = await Promise.all([
    supabase.from("behaviour_events")
      .select("task_id, old_value, new_value, occurred_at, event_metadata")
      .eq("profile_id", executiveId)
      .eq("event_type", "estimate_override")
      .gte("occurred_at", yesterday)
      .order("occurred_at", { ascending: false }),
    supabase.from("user_profiles")
      .select("avg_estimate_error_pct")
      .eq("profile_id", executiveId)
      .maybeSingle(),
    supabase.from("estimation_history")
      .select("bucket_type, estimated_minutes_ai, actual_minutes")
      .eq("profile_id", executiveId)
      .not("actual_minutes", "is", null)
      .not("estimated_minutes_ai", "is", null)
      .gte("created_at", thirtyDaysAgo),
  ]);

  if (overridesRes.error) {
    throw new Error(`Failed to load estimate overrides: ${overridesRes.error.message}`);
  }
  if (profileRes.error) {
    throw new Error(`Failed to load profile calibration: ${profileRes.error.message}`);
  }
  if (bucketsRes.error) {
    throw new Error(`Failed to load bucket calibration: ${bucketsRes.error.message}`);
  }

  const overrides = (overridesRes.data ?? []).map((r: any) => {
    const oldM = parseInt(r.old_value || "0", 10);
    const newM = parseInt(r.new_value || "0", 10);
    return {
      task_id: r.task_id,
      old_minutes: oldM,
      new_minutes: newM,
      delta_pct: oldM > 0 ? Math.round(((newM - oldM) / oldM) * 100) : 0,
      occurred_at: r.occurred_at,
      reason: r.event_metadata?.reason,
    };
  });

  const buckets: Record<string, { bias: number; n: number }> = {};
  for (const row of (bucketsRes.data ?? [])) {
    const bias = (row.actual_minutes ?? 0) - (row.estimated_minutes_ai ?? 0);
    const b = buckets[row.bucket_type] ??= { bias: 0, n: 0 };
    b.bias = (b.bias * b.n + bias) / (b.n + 1);
    b.n += 1;
  }
  const perBucketBias = Object.entries(buckets)
    .filter(([_, v]) => v.n >= 5)
    .map(([bucket_type, v]) => ({
      bucket_type,
      bias_minutes: Math.round(v.bias * 10) / 10,
      n_samples: v.n,
    }));

  return {
    yesterdayOverrides: overrides,
    thirtyDayDriftPct: profileRes.data?.avg_estimate_error_pct ?? null,
    perBucketBias,
  };
}

export function formatCalibrationForPrompt(c: CalibrationContext): string {
  const ovText = c.yesterdayOverrides.length === 0
    ? "(no overrides yesterday)"
    : c.yesterdayOverrides.map(o =>
        `- ${o.old_minutes}m → ${o.new_minutes}m (${o.delta_pct >= 0 ? "+" : ""}${o.delta_pct}%)${o.reason ? ` — ${o.reason}` : ""}`
      ).join("\n");
  const drift = c.thirtyDayDriftPct === null
    ? "(not yet computed)"
    : `${c.thirtyDayDriftPct >= 0 ? "+" : ""}${c.thirtyDayDriftPct.toFixed(1)}% (positive = overestimating, negative = underestimating)`;
  const buckets = c.perBucketBias.length === 0
    ? "(insufficient samples for any bucket)"
    : c.perBucketBias.map(b =>
        `- ${b.bucket_type}: ${b.bias_minutes >= 0 ? "+" : ""}${b.bias_minutes}m bias (n=${b.n_samples})`
      ).join("\n");
  return `\nESTIMATE CALIBRATION (last 24h + 30d drift):\nYesterday's overrides:\n${ovText}\n30-day average error: ${drift}\nPer-bucket bias (30d, ≥5 samples):\n${buckets}\n`;
}
