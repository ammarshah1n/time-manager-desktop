-- similar_corrections() — retrieves corrections most similar to a given embedding
-- Used by classify-email edge function for few-shot learning from user corrections.

CREATE OR REPLACE FUNCTION public.similar_corrections(
    p_workspace_id uuid,
    p_embedding vector(1536),
    p_limit int DEFAULT 10
)
RETURNS TABLE(from_address text, old_bucket text, new_bucket text, subject_snippet text)
LANGUAGE sql STABLE AS $$
    SELECT etc.from_address, etc.old_bucket, etc.new_bucket, etc.subject_snippet
    FROM public.email_triage_corrections etc
    JOIN public.email_messages em ON em.id = etc.email_message_id
    WHERE etc.workspace_id = p_workspace_id
      AND em.embedding IS NOT NULL
    ORDER BY em.embedding <=> p_embedding
    LIMIT p_limit;
$$;
