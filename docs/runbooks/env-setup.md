# Environment Variables — Single Source of Truth

## Supabase
SUPABASE_URL=               # From: supabase status (local) or Supabase dashboard (prod)
SUPABASE_ANON_KEY=          # From: same
SUPABASE_SERVICE_ROLE_KEY=  # From: same — NEVER expose to client

## Microsoft Graph (Azure App Registration)
GRAPH_CLIENT_ID=            # From: Azure Portal → App Registrations → Timed → Application (client) ID
GRAPH_TENANT_ID=            # From: Azure Portal → App Registrations → Timed → Directory (tenant) ID

## AI
ANTHROPIC_API_KEY=          # From: console.anthropic.com → API Keys

## Sentry (post-MVP)
SENTRY_DSN=                 # From: sentry.io → Settings → Client Keys

## Local Development
Run `supabase start` to get local SUPABASE_URL and keys.
Copy `.env.example` to `.env.local` and fill in values.
Never commit .env.local. It's in .gitignore.
