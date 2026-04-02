---
name: handoff
description: Run at the end of every session to create handoff for the next session
---

Session handoff protocol:
1. Summarise what was accomplished in 5 bullet points
2. List any unexpected discoveries, bugs found, or design changes made
3. Update BUILD_STATE.md with current completion status
4. Append SESSION_LOG.md with today's entry:
   ### [Date] — [Main thing accomplished]
   **Done**: ...
   **In progress**: ...
   **Discovered**: ...
   **Next**: [exact file and function to start from next session]
5. Confirm docs/08-decisions-log.md is updated if any architectural decision was made
6. Identify the exact next task with file and function to start from
