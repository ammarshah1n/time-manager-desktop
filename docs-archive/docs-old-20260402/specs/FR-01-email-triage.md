# FR-01: Email Triage Engine

## Summary
SaneBox-style email classification for Outlook mailboxes via Microsoft Graph API.

## Core Loop
```
Graph delta sync → new email → classifyEmail() → Inbox | Later | BlackHole
User drags email between panes → correction logged → future classification improves
```

## Acceptance Criteria
- [ ] OAuth2 flow with Microsoft Graph for Outlook mailboxes
- [ ] Delta sync fetches new emails incrementally (not full mailbox scan)
- [ ] Each email classified into: Inbox, Later, or BlackHole
- [ ] Classification uses Claude Sonnet with correction history as few-shot context
- [ ] CC-only emails auto-routed to CC/FYI folder (rule-based, no AI)
- [ ] Emails from user's surname → auto-pinned to top
- [ ] Three-pane SwiftUI view: Inbox / Later / BlackHole
- [ ] Drag-and-drop between panes logs correction + moves email via Graph API
- [ ] Confidence threshold: <0.7 stays in Inbox (conservative)
- [ ] Supabase Realtime subscription updates UI live when new emails classified

## Data Model
- `email_threads` table: conversationId, classification, confidence, classification_source
- `email_messages` table: per-message metadata (sender, subject, preview, attachments)
- `classification_corrections` table: from→to classification, timestamp, corrected_by

## Edge Functions
- `graph-webhook`: receives Graph push notifications, returns 202, triggers pipeline
- `classify-email`: Claude Sonnet + last 100 corrections as few-shot
- `process-email-pipeline`: orchestrator (fetch → upsert → classify)

## Dependencies
- Microsoft Graph API OAuth2 setup
- Supabase project with schema deployed
- Claude API key

## Estimated Effort
3-4 days
