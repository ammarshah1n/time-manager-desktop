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

-- get_top_observations(p_exec_id, p_hours, p_limit)
--
-- Live caller for score_memory(). Called by orb-conversation's buildObservations
-- via a Supabase RPC so the orb sees observations ranked by relevance, not just
-- recency. Without this wrapper, score_memory() would be a schema orphan
-- (Comet evaluation gap C.2).
CREATE OR REPLACE FUNCTION public.get_top_observations(
    p_exec_id UUID,
    p_hours INTEGER DEFAULT 24,
    p_limit INTEGER DEFAULT 40
) RETURNS TABLE (
    id UUID,
    occurred_at TIMESTAMPTZ,
    event_type TEXT,
    summary TEXT,
    score FLOAT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        obs.id,
        obs.occurred_at,
        obs.event_type,
        obs.summary,
        public.score_memory(obs)::float AS score
    FROM public.tier0_observations obs
    WHERE obs.profile_id = p_exec_id
      AND obs.occurred_at >= now() - (p_hours || ' hours')::interval
    ORDER BY public.score_memory(obs) DESC
    LIMIT GREATEST(1, LEAST(p_limit, 200));
$$;

COMMENT ON FUNCTION public.get_top_observations IS
  'Live caller for score_memory(). Returns recent tier0 observations ordered by composite retrieval score. Used by orb-conversation buildObservations.';

GRANT EXECUTE ON FUNCTION public.get_top_observations(UUID, INTEGER, INTEGER) TO authenticated, service_role;
