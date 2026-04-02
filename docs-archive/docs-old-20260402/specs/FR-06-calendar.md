# FR-06: Calendar Read/Write

## Summary
Read both Apple Calendar and Outlook Calendar. Find free gaps. Write task blocks.

## Read Path
- **Apple Calendar**: EventKit framework (on-device, no API key)
- **Outlook Calendar**: Graph API calendarView endpoint
- Merge gaps: time slot is "free" only if free on BOTH calendars

## Write Path
- Approved schedule blocks → create events on both calendars
- EventKit for Apple Calendar, Graph API for Outlook
- Store event IDs from both in schedule_blocks table

## Acceptance Criteria
- [ ] Read all events from Apple Calendar via EventKit
- [ ] Read all events from Outlook Calendar via Graph API
- [ ] Compute free gaps per day (merged across both sources)
- [ ] Respect user constraints: "no commitments before 9am", daily hour cap
- [ ] Write approved task blocks to Apple Calendar
- [ ] Write approved task blocks to Outlook Calendar
- [ ] Colour-coded blocks: Action = one colour, Read = another
- [ ] If user deletes/moves a calendar block → task returns to unscheduled pool
- [ ] Transit window detection: consecutive events at different locations → suggest transit tasks
- [ ] Store calendar_event_id for both providers in schedule_blocks

## Data Model
- `calendar_accounts`: provider (apple|outlook), account_identifier, is_primary
- `calendar_gaps`: gap_date, start_time, end_time, duration_minutes, source
- `schedule_blocks`: task_id, start_time, end_time, calendar_event_id, calendar_source

## Dependencies
- EventKit permissions granted
- Graph API calendar scope in OAuth
