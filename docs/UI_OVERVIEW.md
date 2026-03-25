# Timed UI Overview

Timed is a three-column macOS workspace built around one question: what should I do next?

## Layout

### Left column

- Task library
- Import panel
- Fast manual task entry access

### Center column

- Prompt suggestions
- Ranked tasks grouped by band
- Schedule blocks with approve/remove controls
- Planner / quiz chat
- Bottom floating composer

### Right column

- Subject-filtered context list
- Full context detail
- One-click quiz launch from context items

## Glass system

- Window background uses `NSVisualEffectView` with `.behindWindow` blur.
- Every floating surface is a shared `TimedCard`.
- Cards use `ultraThinMaterial`, a 1px white border, and compact macOS spacing.

## Ranking bands

- `Do now`
- `Today`
- `This week`
- `Later`

## Chat states

- Planner mode: task and schedule guidance
- Quiz mode: tutor/student back-and-forth with one question at a time

## Keyboard / system notes

- `Cmd+,` opens Settings
- Calendar export only writes approved blocks
- Completed tasks drop out of ranked planning immediately
