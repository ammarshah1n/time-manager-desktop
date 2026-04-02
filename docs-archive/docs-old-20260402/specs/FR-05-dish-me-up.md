# FR-05: "Dish Me Up" — Daily Planning Engine

## Summary
THE PRODUCT. User says "I have X hours" → gets an optimal ordered task list.

## Core Interactions
1. **Morning flow**: App presents draft plan. User confirms/adjusts via swipe yes/no/defer.
2. **On-demand**: "I have 1 hour right now" → bin-pack optimal tasks into time window.
3. **Voice**: "Give me 3 hours of work" → transcribe → plan generated.

## Fixed Daily Priorities (always first)
- "daily update" subject email → first every day
- Family surname replies → second
- Travel schedule check → third

## Ordering Rules
```
overdue → Action before Read → deadline proximity → quick wins → estimated duration
```

## Acceptance Criteria
- [ ] generatePlan(availableMinutes, userId) returns ordered task list
- [ ] Fixed daily items always appear first
- [ ] Bin-packing: tasks fit within time budget with 5-min buffers
- [ ] "I have X hours" input via text or voice
- [ ] Voice input: Apple Speech transcription → parsed to time constraint
- [ ] Draft plan: user can approve, reject, or reorder individual items
- [ ] Staleness: items unactioned 3+ weeks → nudge notification
- [ ] 30-min block every 3 weeks suggested for clearing stale items
- [ ] Items requiring reply that haven't been replied to in 1 day → flagged
- [ ] Plan completion tracking: tick off → actual_minutes logged → estimation improves

## Edge Function
- `generate-daily-plan`: Claude Opus — tasks + calendar gaps + voice input + constraints → schedule

## Dependencies
- FR-01, FR-02, FR-03, FR-04 (all must be working)
- FR-06 (calendar gaps needed for scheduling)
