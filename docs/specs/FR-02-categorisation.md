# FR-02: Email Categorisation (Action / Read)

## Summary
Emails classified as "Inbox" get a second pass: Action (needs work) or Read (informational).

## Sub-categories
- **Action → Quick Reply**: sub-2-min response emails
- **Action → Task**: 10 min to 4 hours of work
- **Action → Call**: phone call needed
- **Read → To Read**: informational, review when time allows
- **Read → CC/FYI**: auto-detected from CC field

## Acceptance Criteria
- [ ] Every Inbox email gets categorised as Action or Read
- [ ] Quick Reply detection: short emails, no attachments, conversational tone
- [ ] Task detection: requests for analysis, recommendation, deliverable
- [ ] Call detection: "call me", "let's discuss", phone-related keywords
- [ ] CC/FYI: auto-detected from To vs CC field (no AI needed)
- [ ] PFF team subject-line parser: extract deadline + estimate from structured subjects
- [ ] Category visible in task list UI with colour coding

## Dependencies
- FR-01 (emails must be classified as Inbox first)
