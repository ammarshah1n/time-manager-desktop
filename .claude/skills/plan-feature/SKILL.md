---
name: plan-feature
description: Use this skill when starting implementation of any new Timed feature
---

Before writing any code:
1. Read docs/01-architecture.md to confirm which layer this feature belongs to
2. Read docs/07-data-models.md to check if any new data types are needed
3. Read docs/08-decisions-log.md to check for relevant architectural decisions
4. Write a 5-point implementation plan: data model → service layer → view model → view → tests
5. Ask: "Does this plan violate the observation-only constraint? Does it couple layers that should be separate?"
6. Only proceed to implementation after the plan is confirmed.

Never write code without a confirmed plan for features that touch:
- The memory store
- The reflection engine
- The Microsoft Graph integration
- Any new data model
