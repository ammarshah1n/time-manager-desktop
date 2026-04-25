# Design Decision Timeline

Short journal of the choices that shaped this skill. Read when you're about
to undo something and want to know why it's like that.

---

## 2026-04-25 — The Apple-clean reset (current branch: `ui/apple-v1-restore`)

**Context.** The session started from a UI that had drifted toward
SaaS-AI aesthetics: a cinematic 72pt "TIMED" splash, per-bucket coloured
chrome on every list, gradient hero buttons with halo shadows, a pulsing
gradient orb on Dish Me Up, animated MeshGradient backgrounds. The user
called all of it "vibecoded SaaS crap" and asked for a hard pivot: read
as Apple Calendar / Reminders / System Settings. First-party Apple, not
Notion-clean.

**Decisions made and committed.**

1. **Splash deleted.** macOS system apps (Calendar, Settings, Notes, Mail)
   launch direct into content. `IntroView` / `IntroFeature` /
   `BrandVersion.introSeenKey` left on disk but unmounted. The 72pt display
   type is now reserved for the Focus pane's timer numeral, nowhere else.
2. **Global colour strip.** `TaskBucket.color`, `ReplyMedium.color`,
   `TriageItem.avatarColor`, `CalendarBlock.categoryColor` all return
   `Color.Timed.labelSecondary`. The single exception: focus calendar
   blocks keep accent. Zero raw `Color.red/orange/green/teal/yellow/
   purple/...` in `Sources/` outside `Sources/Legacy/` and
   `Color.Timed.destructive` (semantic — overdue, recording, due-today).
3. **Sidebar neutralised.** Bucket icons render in `labelSecondary`;
   selected rows promote the icon to `labelPrimary`. No per-row colour.
4. **Onboarding chrome stripped.** No hero gradient, no 50pt black display
   type. Voice orb + AI conversation flow preserved.
5. **Apple system blue accent confirmed** — `#007AFF` light / `#0A84FF`
   dark, the Apple-native interactive cue. Avoid purple
   (`#AF52DE` / Notion / Cursor) — overused in AI/productivity apps and
   reads as generic.

**Decisions made for next round (planned, in
`/Users/integrale/.claude/plans/i-dont-like-what-hidden-locket.md`).**

6. **`BucketDot` to be introduced** — 8pt circle, configurable colour,
   the only colour anchor per row. Apple Reminders' list-color circle as
   reference. Mapped per `TaskBucket` case to the Apple system palette
   (`Color(.systemBlue/Red/Green/Orange/Gray/Teal/Purple/Gray2)`).
7. **Dish Me Up rebuild planned** — strip MeshGradient, gradient hero
   button, halo shadow, sparkle iconography, all-caps tracked label,
   PulsingOrb. Convert to `.borderedProminent` button, `Picker(.segmented)`
   minute selector, native `ProgressView` loading, and to-do row recipe
   for the plan list.
8. **`MorningCheckIn` orb to be replaced** — the AngularGradient +
   RadialGradient + 10s `hueRotation` + `repeatForever` orb is
   decoration cosplaying as state. Replace with state-aware system mic
   indicator: idle → `mic` `labelTertiary`, listening → `mic.fill`
   `destructive` with scale modulated by real `voiceCapture.audioLevel`,
   speaking → `waveform` with `.symbolEffect(.variableColor.iterative)`.
9. **`PlanPane` sparkles dropped** — both `Image(systemName: "sparkles")`
   call sites (lines 164, 184) become plain text labels.
10. **Liquid Glass preserved at current sites only** —
    `CommandPalette.swift:233`, `QuickCapturePanel.swift:131`. Don't add,
    don't strip. Anything in `Sources/Legacy/` is dead.

**The mantra to remember.** *Execs don't have time for rubbish.* Calm
beats loud. Native beats bespoke. Background contrast beats shadow. Real
loading state beats `repeatForever`. If Apple Calendar / Settings /
Reminders doesn't do it, Timed doesn't do it.

**Why this skill exists.** `DESIGN.md` codifies the tokens and rules.
`docs/UI-RULES.md` is the strict checklist. But the **judgments** —
which patterns are Apple-clean vs vibecoded, which tempting decorations
to delete on sight, which native control to reach for instead — those
live in the head of whoever ran this session. This skill is that head,
externalised, so the next session inherits it.

---

## Future entries

When you make a non-trivial visual decision, add an entry here. Format:

```
## YYYY-MM-DD — One-line summary

**Context.** What was the state.
**Decision.** What changed.
**Why.** The reason a future reader needs.
```

Keep entries short. Detail goes in the relevant references file.
