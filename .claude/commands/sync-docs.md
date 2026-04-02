---
name: sync-docs
description: Update BUILD_STATE.md from current conversation state
---

Documentation sync protocol:
1. Review all changes made in the current conversation
2. Update BUILD_STATE.md:
   - Move completed items from "In Progress" to "What Exists and Works"
   - Add any newly discovered issues to "Known Issues / Landmines"
   - Update "Next Phase" if the current phase is complete
3. If any architectural decisions were made, add them to docs/08-decisions-log.md
4. If any new data models were created, update docs/07-data-models.md
5. Confirm all docs reflect the current state of the codebase
