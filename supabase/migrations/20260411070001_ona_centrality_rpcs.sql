-- Phase 6.03-6.04: ONA centrality metrics + relationship health RPCs

-- Compute degree centrality for all nodes belonging to an executive
CREATE OR REPLACE FUNCTION compute_degree_centrality(exec_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    total_nodes INT;
BEGIN
    SELECT COUNT(*) INTO total_nodes FROM ona_nodes WHERE profile_id = exec_id;
    IF total_nodes <= 1 THEN RETURN; END IF;

    UPDATE ona_nodes n
    SET degree_centrality = sub.dc,
        updated_at = now()
    FROM (
        SELECT
            node_id,
            CAST(edge_count AS FLOAT) / GREATEST(total_nodes - 1, 1) AS dc
        FROM (
            SELECT from_node_id AS node_id, COUNT(DISTINCT to_node_id) AS edge_count
            FROM ona_edges WHERE profile_id = exec_id
            GROUP BY from_node_id
            UNION ALL
            SELECT to_node_id AS node_id, COUNT(DISTINCT from_node_id) AS edge_count
            FROM ona_edges WHERE profile_id = exec_id
            GROUP BY to_node_id
        ) edges
        GROUP BY node_id, edge_count
    ) sub
    WHERE n.id = sub.node_id AND n.profile_id = exec_id;
END;
$$;

-- Compute relationship health scores and trajectories
CREATE OR REPLACE FUNCTION compute_relationship_health(exec_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE relationships r
    SET
        health_trajectory = CASE
            WHEN EXTRACT(EPOCH FROM now() - r.last_contact_at) / 86400 < 14 THEN 'active'
            WHEN EXTRACT(EPOCH FROM now() - r.last_contact_at) / 86400 < 30 THEN 'cooling'
            WHEN EXTRACT(EPOCH FROM now() - r.last_contact_at) / 86400 < 60 THEN 'at_risk'
            ELSE 'dormant'
        END,
        health_score = LEAST(100, GREATEST(0,
            r.reciprocity * 40.0
            + (1.0 - r.decay_rate) * 30.0
            + GREATEST(0.0, 1.0 - EXTRACT(EPOCH FROM now() - r.last_contact_at) / 86400.0 / 90.0) * 30.0
        )),
        updated_at = now()
    WHERE r.profile_id = exec_id
      AND r.last_contact_at IS NOT NULL;

    -- Also update ona_nodes health from relationships
    UPDATE ona_nodes n
    SET
        relationship_health_score = r.health_score,
        health_trend = CASE
            WHEN r.health_trajectory = 'active' THEN 'stable'
            WHEN r.health_trajectory = 'cooling' THEN 'declining'
            WHEN r.health_trajectory IN ('at_risk', 'dormant') THEN 'declining'
            ELSE 'unknown'
        END,
        updated_at = now()
    FROM relationships r
    WHERE r.node_id = n.id AND r.profile_id = exec_id AND n.profile_id = exec_id;
END;
$$;
