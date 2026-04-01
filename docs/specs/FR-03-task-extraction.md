# FR-03: Task Extraction from Email

## Summary
Convert Action emails into structured tasks. Bundle related threads.

## Core Loop
```
Action email → extractTask() → Task record created
Multiple related emails → bundleRelated() → TaskBundle with all correspondence
```

## Acceptance Criteria
- [ ] Every Action email generates a Task record
- [ ] Task includes: title, description, source thread ID, deadline (if detected), category
- [ ] Thread bundling: Graph conversationId groups emails automatically
- [ ] Cross-thread detection: Claude identifies related matters across threads
- [ ] All related emails + attachments reference from single task record
- [ ] PFF subject-line format parsed: deadline + estimate extracted automatically
- [ ] Task list UI shows Action and Read tabs
- [ ] User can edit task title, deadline, priority after extraction

## Data Model
- `tasks` table: title, category (action|read), estimated_minutes, source_thread_id, deadline, status
- `task_bundles` + `task_bundle_members`: group multi-email tasks

## Edge Function
- `extract-tasks`: Claude Opus — detect action items, deadlines, bundle hints from thread

## Dependencies
- FR-01 (emails classified)
- FR-02 (emails categorised)
