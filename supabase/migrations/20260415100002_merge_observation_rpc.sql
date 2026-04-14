-- RPC for atomic jsonb merge on tier0_observations.raw_data
-- Avoids stale read-modify-write when multiple processes update raw_data concurrently

CREATE OR REPLACE FUNCTION public.merge_observation_raw_data(obs_id UUID, merge_data JSONB)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.tier0_observations
  SET raw_data = COALESCE(raw_data, '{}'::jsonb) || merge_data
  WHERE id = obs_id;
END;
$$;
