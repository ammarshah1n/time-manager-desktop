---
name: sync-docs
description: Sync all documentation with current codebase state. Run at end of every build session.
---

Documentation sync protocol — run through ALL steps:

## 1. BUILD_STATE.md
- Review all changes made in the current conversation
- Move completed items from "To build" to "What Exists and Works" with line counts
- Add any newly discovered issues to "Known Issues / Landmines"
- Update the Build Phases table — mark completed phases, update current phase
- Update the Research Library section if new research was added

## 2. Architecture Docs (only update what changed)
- If memory/reflection/prediction code was written → update `research/ARCHITECTURE-MEMORY.md` with actual implementation notes (what was built vs what was spec'd, any deviations and why)
- If signal ingestion code was written → update `research/ARCHITECTURE-SIGNALS.md` similarly
- If delivery/privacy/cold-start code was written → update `research/ARCHITECTURE-DELIVERY.md` similarly
- Add a `## Implementation Status` section at the top of any ARCHITECTURE doc that was built against, showing what's done vs remaining

## 3. Architecture Decisions
- If any architectural decisions were made that deviate from the ARCHITECTURE docs, add them to `docs/08-decisions-log.md` with rationale

## 4. Data Models
- If any new Swift types or Supabase tables were created, update `docs/07-data-models.md`

## 5. Obsidian Vault
- Update `~/Timed-Brain/06 - Context/research-v2-index.md` if any architecture docs changed
- Write a session walkthrough to `~/Timed-Brain/01 - Walkthroughs/` documenting what was built

## 6. CLAUDE.md
- If any new files/directories were created that future sessions need to know about, update the File Map section

Confirm all docs reflect the actual current state of the codebase — not what was planned, what IS.
