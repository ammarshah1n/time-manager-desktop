-- Backfill durable workspace/profile/email-account rows for the current
-- executives.id-based Swift identity model.

INSERT INTO public.workspaces (id, name, slug, updated_at)
SELECT
    e.id,
    COALESCE(NULLIF(e.display_name, ''), 'Executive') || ' Workspace',
    'exec-' || e.id::text,
    now()
FROM public.executives e
ON CONFLICT (id) DO UPDATE
SET
    name = EXCLUDED.name,
    slug = EXCLUDED.slug,
    updated_at = now();

WITH profile_rows AS (
    SELECT
        e.id AS id,
        e.email,
        e.display_name AS full_name,
        e.timezone
    FROM public.executives e

    UNION

    SELECT
        e.auth_user_id AS id,
        e.email,
        e.display_name AS full_name,
        e.timezone
    FROM public.executives e
)
INSERT INTO public.profiles (id, email, full_name, timezone)
SELECT id, email, full_name, timezone
FROM profile_rows
ON CONFLICT (id) DO UPDATE
SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    timezone = EXCLUDED.timezone;

WITH member_rows AS (
    SELECT
        e.id AS workspace_id,
        e.id AS profile_id,
        'owner'::text AS role
    FROM public.executives e

    UNION

    SELECT
        e.id AS workspace_id,
        e.auth_user_id AS profile_id,
        'owner'::text AS role
    FROM public.executives e
)
INSERT INTO public.workspace_members (workspace_id, profile_id, role)
SELECT workspace_id, profile_id, role
FROM member_rows
ON CONFLICT (workspace_id, profile_id) DO UPDATE
SET role = EXCLUDED.role;

UPDATE public.email_accounts ea
SET
    workspace_id = e.id,
    profile_id = e.id,
    provider = 'outlook',
    provider_account_id = e.auth_user_id::text,
    email_address = e.email,
    sync_enabled = true,
    updated_at = now()
FROM public.executives e
WHERE ea.id = e.id;

INSERT INTO public.email_accounts (
    id,
    workspace_id,
    profile_id,
    provider,
    provider_account_id,
    email_address,
    sync_enabled,
    updated_at
)
SELECT
    e.id,
    e.id,
    e.id,
    'outlook',
    e.auth_user_id::text,
    e.email,
    true,
    now()
FROM public.executives e
WHERE NOT EXISTS (
    SELECT 1
    FROM public.email_accounts ea
    WHERE ea.id = e.id
)
AND NOT EXISTS (
    SELECT 1
    FROM public.email_accounts ea
    WHERE ea.workspace_id = e.id
      AND ea.provider = 'outlook'
      AND ea.provider_account_id = e.auth_user_id::text
);
