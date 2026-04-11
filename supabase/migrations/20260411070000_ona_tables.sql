-- Phase 6.01: ONA & Relationship Intelligence tables
-- ona_nodes: contact entities from email metadata
-- ona_edges: directional email interactions
-- relationships: per-dyad health tracking

-- ONA Nodes
CREATE TABLE IF NOT EXISTS ona_nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL,
    email TEXT NOT NULL,
    display_name TEXT,
    inferred_role TEXT,
    inferred_org TEXT,
    inferred_department TEXT,
    authority_tier TEXT CHECK (authority_tier IN ('peer','subordinate','superior','board','external')),
    relationship_type TEXT CHECK (relationship_type IN ('operational','strategic','political','social')),
    total_emails_sent INT DEFAULT 0,
    total_emails_received INT DEFAULT 0,
    avg_response_latency_seconds FLOAT,
    communication_frequency FLOAT,
    importance_tier INT DEFAULT 3,
    degree_centrality FLOAT,
    betweenness_centrality FLOAT,
    eigenvector_centrality FLOAT,
    pagerank FLOAT,
    closeness_centrality FLOAT,
    clustering_coefficient FLOAT,
    hub_score FLOAT,
    relationship_health_score FLOAT,
    health_trend TEXT CHECK (health_trend IN ('improving','stable','declining','unknown')) DEFAULT 'unknown',
    formality_trend FLOAT,
    responsiveness_symmetry FLOAT,
    engagement_depth FLOAT,
    trajectory_summary TEXT,
    first_seen_at TIMESTAMPTZ DEFAULT now(),
    last_seen_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(profile_id, email)
);

CREATE INDEX IF NOT EXISTS idx_ona_nodes_profile_seen ON ona_nodes USING BRIN (profile_id, last_seen_at);

ALTER TABLE ona_nodes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ona_nodes_select" ON ona_nodes FOR SELECT USING (profile_id = auth.uid());
CREATE POLICY "ona_nodes_insert" ON ona_nodes FOR INSERT WITH CHECK (profile_id = auth.uid());
CREATE POLICY "ona_nodes_update" ON ona_nodes FOR UPDATE USING (profile_id = auth.uid());
CREATE POLICY "ona_nodes_delete" ON ona_nodes FOR DELETE USING (profile_id = auth.uid());

-- ONA Edges
CREATE TABLE IF NOT EXISTS ona_edges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL,
    from_node_id UUID REFERENCES ona_nodes(id),
    to_node_id UUID REFERENCES ona_nodes(id),
    direction TEXT CHECK (direction IN ('sent','received')) NOT NULL,
    edge_timestamp TIMESTAMPTZ NOT NULL,
    response_latency_seconds FLOAT,
    thread_id TEXT,
    thread_depth INT,
    recipient_position TEXT CHECK (recipient_position IN ('to','cc','bcc')),
    is_initiated BOOLEAN DEFAULT false,
    has_attachment BOOLEAN DEFAULT false,
    message_graph_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ona_edges_profile_ts ON ona_edges USING BRIN (profile_id, edge_timestamp);

ALTER TABLE ona_edges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ona_edges_select" ON ona_edges FOR SELECT USING (profile_id = auth.uid());
CREATE POLICY "ona_edges_insert" ON ona_edges FOR INSERT WITH CHECK (profile_id = auth.uid());
CREATE POLICY "ona_edges_update" ON ona_edges FOR UPDATE USING (profile_id = auth.uid());
CREATE POLICY "ona_edges_delete" ON ona_edges FOR DELETE USING (profile_id = auth.uid());

-- Relationships (per-dyad health tracking)
CREATE TABLE IF NOT EXISTS relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL,
    node_id UUID REFERENCES ona_nodes(id) NOT NULL,
    strength FLOAT DEFAULT 0.5,
    decay_rate FLOAT DEFAULT 0.05,
    reciprocity FLOAT DEFAULT 0.5,
    rdi_score FLOAT DEFAULT 0.0,
    sws_score FLOAT DEFAULT 0.0,
    health_score FLOAT DEFAULT 50.0,
    health_trajectory TEXT CHECK (health_trajectory IN ('active','cooling','at_risk','dormant')) DEFAULT 'active',
    last_contact_at TIMESTAMPTZ,
    maintenance_alert_threshold INT DEFAULT 30,
    contact_frequency_baseline FLOAT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(profile_id, node_id)
);

ALTER TABLE relationships ENABLE ROW LEVEL SECURITY;

CREATE POLICY "relationships_select" ON relationships FOR SELECT USING (profile_id = auth.uid());
CREATE POLICY "relationships_insert" ON relationships FOR INSERT WITH CHECK (profile_id = auth.uid());
CREATE POLICY "relationships_update" ON relationships FOR UPDATE USING (profile_id = auth.uid());
CREATE POLICY "relationships_delete" ON relationships FOR DELETE USING (profile_id = auth.uid());
