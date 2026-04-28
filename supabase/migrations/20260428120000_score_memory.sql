-- score_memory(obs, query_time)
--
-- Minimal-viable retrieval ranking using existing tier0_observations columns.
-- Replaces the (deferred) Voyage embedding cosine path until Haiku-tag retrieval
-- lands. Caller passes the observation row + a reference time; the function
-- returns a [0,1]-ish composite score that prioritises recent + important +
-- voice-channel signals over older / lower-importance / passive ones.
--
-- Weights chosen for sane Day-1 ordering, not tuned. Adjust once we have at
-- least 200 retrieval/correction pairs to back-test against.
--
-- NOT a substitute for true embedding similarity; it is a stop-gap so callers
-- have *something* to ORDER BY when assembling ACB / briefing context.

CREATE OR REPLACE FUNCTION public.score_memory(
    obs public.tier0_observations,
    query_time TIMESTAMPTZ DEFAULT now()
) RETURNS FLOAT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT (
        0.35 * COALESCE(obs.importance_score, 0.5)
      + 0.30 * exp(-EXTRACT(EPOCH FROM (query_time - obs.occurred_at)) / 86400.0)
      + 0.20 * COALESCE(obs.baseline_deviation, 0.0)
      + 0.15 * CASE obs.source
                  WHEN 'voice'    THEN 1.0
                  WHEN 'calendar' THEN 0.8
                  WHEN 'email'    THEN 0.6
                  ELSE                 0.5
              END
    )::float
$$;

COMMENT ON FUNCTION public.score_memory IS
  'Composite retrieval score for tier0_observations rows. Importance × recency × deviation × source-tier. Stop-gap until embedding retrieval is re-enabled.';
