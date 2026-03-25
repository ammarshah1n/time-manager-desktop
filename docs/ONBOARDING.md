# Timed Onboarding

## Install

1. Download the latest `timed.app.zip` from the repo’s Releases page.
2. Unzip it.
3. Move `timed.app` into `/Applications`.
4. Launch `Timed`.

## First launch

Timed opens straight into the planning workspace. There is no blocking onboarding flow.

## Set up the AI bridge

1. Press `Cmd+,` to open Settings.
2. Check the Codex executable path.
3. If needed, click `Configure AI path` and choose the local `codex` binary.

Default path:

```text
/Applications/Codex.app/Contents/Resources/codex
```

## Load work

### Import Seqta

1. Open the left sidebar.
2. Paste Seqta task text into the Import card.
3. Choose `Seqta`.
4. Click `Parse import`.
5. Review the imported tasks in the quick-edit sheet.

### Import TickTick

1. Paste either plain TickTick text or the CSV export.
2. Choose `TickTick`.
3. Click `Parse import`.
4. Review subject, due date, importance, confidence, and estimate before applying.

### Add a manual task

1. Click `Add Task` in the header or `+` in the task library.
2. Fill the title, subject, estimate, due date, energy, and notes.
3. Save.

## Plan mode

Use the bottom composer to ask:

- `What should I do now?`
- `Plan my next 3 hours`
- `Rank my tasks`

Timed injects ranked tasks and relevant context into the local Codex CLI and returns a plain-English plan.

## Quiz mode

Start a quiz by:

- Clicking `Quiz me` on a context card, or
- Typing `Quiz me on English` in the composer.

While quiz mode is active:

- Tutor and student messages render differently in chat.
- `End quiz` returns the app to planning mode.

## Calendar export

1. Approve the schedule blocks you want.
2. Click `Export`.
3. Timed writes those approved blocks into the `Timed` Apple Calendar.
4. If calendar access is denied, Timed writes a timestamped ICS fallback instead.

## Daily loop

1. Import fresh school work.
2. Ask Timed what matters now.
3. Approve the schedule blocks that fit.
4. Export the plan to Calendar.
5. Use quiz mode before revision blocks.
