# Codex Task: Index Session Transcripts

**Run this in Codex (not Claude). Reads session transcripts and extracts structured data.**

## Context
- Session transcripts live at: `~/Timed-Brain/05 - Dev Log/sessions/*.md`
- Output files:
  - `~/Timed-Brain/06 - Context/prompts-log.md` — Ammar's prompts as AIF artifacts
  - `~/Timed-Brain/06 - Context/decision-log.md` — problem IDs and decisions
  - `~/time-manager-desktop/docs/rules/corrections-log.md` — corrections received
  - `~/time-manager-desktop/CHANGELOG.md` — backfill any missing session entries

## Instructions

Read every `.md` file in `~/Timed-Brain/05 - Dev Log/sessions/`.

For each file, identify messages from the **HUMAN** role.

---

### Step 1: Extract Ammar's Prompts → prompts-log.md

Find every HUMAN message that:
- Is longer than 50 words
- Starts a new direction (not just "yes", "ok", "do it")
- Identifies a problem before asking AI to fix it
- Sets a quality standard ("must be", "like the pros", "every single")
- Frames architecture or system design

For each, create a prompts-log.md table row:
```
| P-NNN | YYYY-MM-DD | [one-line summary in quotes] | [problem Ammar identified] | [what it built] | [AIF tags] |
```

And a `<details>` block with:
- Problem Ammar identified (his perspective, not AI's framing)
- Verbatim excerpt of the prompt (up to 200 words)
- What this demonstrates about Ammar's capability
- AIF criteria (PA1, PA2, PA3, E1, E2, A1, A2)

AIF signal words to look for:
- Problem: "why do I have", "does this capture", "there's a gap", "this isn't", "what about", "shouldn't this"
- Standard: "must be", "every", "never", "always", "like the pros", "world's best", "perfect"
- Synthesis: connecting multiple tools/systems into one
- Orchestration: "parallel", "4 terminals", "which window", "at the same time"

**Skip:** AI responses. AI choosing between options. Routine confirmations.

---

### Step 2: Extract Problem Identifications → decision-log.md

Find HUMAN messages where Ammar identifies a gap or problem BEFORE the AI mentions it.

Signals:
- "why do I have two..."
- "this isn't capturing..."
- "there's a gap in..."
- "does this also handle..."
- "what about..."
- "I notice..."
- Any question that reveals Ammar spotted something the AI missed

For each, append to decision-log.md as:
```
| D-NNN | YYYY-MM-DD | Problem Identification | Accepted | We will [fix identified] | [context] | High | [AIF] | Transcript session-DATE.md |
```

---

### Step 3: Extract Corrections → corrections-log.md

Find HUMAN messages that correct or redirect the AI:
- "no", "wrong", "that's not what I said"
- Any profanity followed by redirection
- "I already told you", "don't do that", "stop"
- "I said X not Y"

For each, append to `docs/rules/corrections-log.md`:
```
### [DATE] Correction: [one-line summary]
- What AI did: [the mistake]
- What Ammar wanted: [the correct behaviour]
- Rule: [permanent rule to prevent recurrence]
```

---

### Step 4: Extract Installs → CHANGELOG.md

Find any HUMAN message mentioning:
- `brew install`, `npm install`, `pip install`, `cargo add`
- Creating accounts on external services
- Configuring services, enabling extensions
- `claude mcp add`, `npx skills add`

For each, add to CHANGELOG.md under the relevant session:
```
### Added
- `YYYY-MM-DDTHH:MM` install: [tool name] via [method] — [why]
  Command: [exact command]
  Version: [version or "latest"]
  Needed for: [which FR or system]
```

---

### Step 5: Backfill CHANGELOG Gaps

Look at CHANGELOG.md. For each session file in sessions/:
- If there's no corresponding `## [Session YYYY-MM-DD]` entry, create one
- Derive Added/Changed/Fixed/Decided from the transcript
- Keep entries concise (max 20 lines per session)

---

### Step 6: Deduplicate

Before appending anything, check if the entry already exists.
- For prompts-log: check if prompt summary already in table
- For decision-log: check if decision already has a row
- For corrections-log: check if correction already documented
- Skip duplicates silently

---

### Output Report

After processing all files, print:
```
=== Codex Indexer Report ===
Sessions processed: N
Prompts extracted: N
Problems identified: N
Corrections found: N
Installs logged: N
CHANGELOG gaps filled: N
Duplicates skipped: N
===========================
```
