# Timed UI Specification

Living source of truth for every user-facing screen. Every decision here traces
back to a rule in `DESIGN.md`. If a rule does not exist, default to Apple HIG —
then add the rule here rather than inventing a local one.

---

## Screen Index

1. **Splash** — single animated mark on appearance, hands off to root or onboarding
2. **Onboarding (Voice)** — voice-led setup flow, no form fields
3. **Dish Me Up (Home)** — root pane; Opus-generated plan delivered on command
4. **Today** — calendar + tasks summary for the current day
5. **Tasks (bucket)** — a single work bucket (Action, Calls, Reply, etc.)
6. **Focus** — active-timer sheet, hero numeral + ring
7. **Capture** — quick-entry pane (voice or text)
8. **Calendar** — read-only calendar blocks pane
9. **Settings (Prefs)** — app preferences
10. **Morning Interview** — scheduled daily check-in sheet
11. **Command Palette** — `⌘K` overlay

---

## Screen Specs

### Splash

- **Route / presentation**: Root gate. Owned by `TimeManagerDesktopApp`. Shows
  until `hasSeenIntro_<version>` flips true.
- **Navigation**: None. No title bar (`.windowStyle(.hiddenTitleBar)`).
- **Purpose**: Set the tone — calm, precise, purposeful — in under 1.5s.
- **Layout**: Vertically centered composition. A 270° arc (3pt stroke, accent)
  with a small filled dot at the endpoint, then the wordmark "Timed"
  (`TimedType.wordmark`, `labelPrimary`, tracked +0.02em) below at
  `TimedLayout.Spacing.xl` above the baseline.
- **Components used**: `SplashView` (bespoke). Arc is drawn with
  `Path` + `.trim(from: 0, to: progress)`. Wordmark is plain `Text`.
- **Empty state**: N/A.
- **Loading state**: The splash *is* the loading state.
- **Edge cases**: `accessibilityReduceMotion` → skip the arc draw, present the
  static composition for the 1.0s hold, then fade.
- **Transitions in/out**: In — arc animates 0→270° over 0.6s ease-in-out. Out —
  fade + scale to 1.02 over 0.4s once the store reports `.finished`.
- **DESIGN.md rules applied**: Single accent (on the arc only). No gradient.
  No shadow. SF Pro Display 24pt Regular wordmark with -0.02em tracking.
  Background = `backgroundPrimary`.

### Onboarding (Voice)

- **Route / presentation**: `.sheet` from `TimedRootView` when
  `hasCompletedOnboarding` is false. `interactiveDismissDisabled()`.
- **Navigation**: None. The voice agent drives progression.
- **Purpose**: Capture executive profile without a single form field.
- **Layout**: Full-bleed surface (`backgroundPrimary`). Centered orb/waveform.
  Single hint line at the bottom in `labelSecondary`.
- **Components used**: `TimedWaveform` (`.listening` state animated on appear),
  `TimedPrimaryButton` for the OAuth escape hatch ("Connect Outlook"),
  `TimedGhostButton` for "Skip for now".
- **Empty state**: N/A — entered only on first launch.
- **Loading state**: Orb remains in `.listening` state while ElevenLabs speaks.
- **Edge cases**: If mic permission is denied, present the system settings link
  in plain text (not a popup) and keep the waveform static.
- **Transitions in/out**: Sheet slides up. On complete, dismisses with
  `success` haptic.
- **DESIGN.md rules applied**: No form fields. Voice is the primary input. No
  decorative illustration. Accent appears only on the waveform bars (single
  accent element).

### Dish Me Up (Home)

- **Route / presentation**: Root detail pane. Default `NavSection`.
- **Navigation bar**: Large title "Dish Me Up" or equivalent.
- **Purpose**: Deliver a dish — the Opus-generated ordered plan for now.
- **Layout**: Hero card center-canvas. Empty-state prompt when no plan yet.
- **Components used**: `TimedCard` for each dish line, `TimedPrimaryButton`
  ("Dish me up"), `TimedTimerRing` (small, 32pt) per scheduled block.
- **Empty state**: Plain headline + subhead + the button. No illustration.
- **Loading state**: Skeleton card — three grey `labelQuaternary` rounded
  rectangles. No spinner.
- **Edge cases**: Stale plan (>2h old) shows a "Refresh" ghost button.
- **Transitions**: Card fade-in over 0.22s.
- **DESIGN.md rules applied**: Accent only on the primary button. Cards use
  `backgroundTertiary` on grouped background. No shadows.

### Tasks (bucket)

- **Route / presentation**: Root detail when a work bucket is selected.
- **Navigation bar**: Large title — the bucket name (e.g., "Reply", "Calls").
- **Purpose**: Show and action the tasks in a single bucket.
- **Layout**: `.insetGrouped` list. 44pt row minimum. System chevron.
- **Components used**: System list, native row style.
- **Empty state**: `labelSecondary` "No tasks in <bucket>". No art.
- **Loading state**: Skeleton rows.
- **Edge cases**: Completed tasks animate into a collapsed section.
- **Transitions**: System push.
- **DESIGN.md rules applied**: Native list style. No custom separators.

### Focus

- **Route / presentation**: `.sheet`, 600×680 minimum.
- **Navigation bar**: None. The numeral is the screen.
- **Purpose**: Host a single focus session — the hero timer.
- **Layout**: Centered `TimedTimerRing` (256pt) with `TimedType.timerDisplay`
  inside it. Task title above, one accent-tinted primary action below.
- **Components used**: `TimedTimerRing`, `TimedPrimaryButton` (Pause/Resume),
  `TimedGhostButton` (End session).
- **Empty state**: N/A — always entered with a task.
- **Loading state**: N/A.
- **Edge cases**: App backgrounded → the ring pauses animation, the numeral
  keeps ticking.
- **Transitions**: Sheet up. Close on completion with `success` haptic.
- **DESIGN.md rules applied**: Accent only on the ring. Haptics required at
  start (`.medium`) and completion (`.success`).

### Settings (Prefs)

- **Route / presentation**: Root detail.
- **Navigation bar**: Large title "Settings".
- **Purpose**: App preferences.
- **Layout**: `.insetGrouped` list of grouped sections.
- **Components used**: Native `Form` rows.
- **DESIGN.md rules applied**: Pure native. No customization.

---

## Component Library

Every component lives in `Sources/Core/Design/Components/`.

| Component             | Height / size   | Radius       | Accent? | Notes |
|-----------------------|-----------------|--------------|---------|-------|
| `TimedPrimaryButton`  | 50pt            | 14pt         | Yes     | Full-width; fills with `accent`. |
| `TimedSecondaryButton`| 50pt            | 14pt         | Tinted  | `accent` at 10% background, `accent` text. |
| `TimedGhostButton`    | 44pt            | —            | No      | No fill, `labelSecondary` text. |
| `TimedCard`           | content-sized   | 16pt         | No      | `backgroundTertiary` fill. |
| `TimedTimerRing`      | caller-sized    | Circle       | Yes     | Stroke only. |
| `TimedWaveform`       | 80×32pt default | —            | Yes     | 7 bars, animates in `.listening`. |
| `TimedVoicePill`      | 44pt H, 200pt W | Capsule      | Yes     | Floating; spring in/out. |

---

## Interaction Patterns

- **Haptics** — required on every primary action. `.medium` impact for a
  commit (start timer, submit form); `.success` notification for a completion.
- **Selection** — sidebar relies on macOS native selection highlight. Never
  draw a bespoke selection pill.
- **Loading** — skeleton rectangles in `labelQuaternary`. Never a spinner in
  the main surface; spinners are allowed inside a button while an async action
  is pending.
- **Empty states** — headline (`TimedType.title2`) + subhead
  (`TimedType.body`, `labelSecondary`) + one primary action. No illustration.
- **Error states** — inline, not modal. `labelSecondary` text with a ghost
  "Retry" beside it.

---

## Status

- ✅ Phase 1 — colour tokens re-pointed to DESIGN.md (Apple system blue accent).
- ✅ Phase 2 — `TimedType` and `TimedLayout` added.
- ✅ Phase 5 — sidebar neutralised (monochrome icons, single accent).
- ✅ Splash killed — app launches direct into `TimedRootView`, mirroring Apple
  Calendar / System Settings. `IntroView` / `IntroFeature` / `BrandVersion.introSeenKey`
  left on disk but unmounted.
- ✅ Onboarding chrome stripped — no hero gradient, no 50pt black display type;
  voice orb + AI conversation flow preserved.
- ✅ Global colour strip — `TaskBucket.color`, `ReplyMedium.color`,
  `TriageItem.avatarColor`, `CalendarBlock.categoryColor` all return
  `labelSecondary` (focus blocks keep accent). Zero raw `Color.red/orange/green/
  teal/yellow/purple/...` in `Sources/` — only `Color.Timed.destructive` remains
  for true semantic (overdue, recording, due-today).

## Design decisions (new)

- **No splash.** macOS system apps (Calendar, Settings, Notes, Mail) do not
  show a cinematic intro — neither does Timed.
- **Accent is `.focus` only.** Focus calendar blocks and the single primary CTA
  per screen are the only places Apple system blue appears. Every other bucket,
  category, and indicator is monochrome.
- **Destructive semantic red is preserved.** It only shows when data is truly
  overdue, a mic is actively recording, or a task is due today.
