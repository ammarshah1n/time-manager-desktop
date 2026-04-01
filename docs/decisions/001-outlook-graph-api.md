# ADR-001: Use Microsoft Graph API for Email

## Decision
Use Microsoft Graph API (OAuth2, delta sync) for all Outlook email access.

## Context
Executive uses Outlook/365 as primary email. Need real-time email access with folder operations.

## Alternatives Considered
- **IMAP**: Simpler but lacks folder operations, webhooks, delta sync. Would need polling.
- **Exchange Web Services (EWS)**: Deprecated by Microsoft. Graph is the replacement.

## Consequences
- Must implement OAuth2 flow (MSAL or raw)
- Delta sync provides incremental updates (efficient)
- Webhooks for push notifications (Graph subscriptions expire every 3 days)
- Need pg_cron backup for missed webhooks (delta sync every 15 min)
