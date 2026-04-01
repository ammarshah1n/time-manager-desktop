# FR-04: Time Estimation Engine

## Summary
Auto-estimate task duration. Learn from user corrections over time.

## Estimation Hierarchy
1. **Historical**: similar past tasks (same sender, similar content, similar attachments)
2. **Category defaults**: Quick Reply = 2 min, Task = 30 min, Call = 10 min, Read = 3 min
3. **AI estimate**: Claude Opus based on email content, length, attachment count
4. **Ask user**: if none of the above exist, prompt for estimate before planning

## Acceptance Criteria
- [ ] Every new task gets an AI-generated time estimate
- [ ] User can override any estimate (tap → edit → save)
- [ ] Override stored alongside AI estimate in estimation_history
- [ ] When task completes, actual_minutes logged (timer or manual)
- [ ] Historical calibration: weighted average of similar past tasks
- [ ] Estimates improve over time (track AI vs actual vs override)
- [ ] Cold start: works with zero history (uses Claude + category defaults)
- [ ] Warm state: after ~2 weeks, estimates use history first

## Data Model
- `estimation_history`: ai_estimate, user_override, actual_minutes, task_type_hint per task

## Edge Function
- `estimate-time`: Claude Opus with task content + historical data

## Dependencies
- FR-03 (tasks must exist)
