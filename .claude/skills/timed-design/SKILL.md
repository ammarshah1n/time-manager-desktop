---
name: timed-design
description: Timed visual design system — Apple Calendar / Reminders / Settings aesthetic. Use when reading, writing, or reviewing any SwiftUI view in Timed.
trigger: When working on any user-facing SwiftUI surface in /Users/integrale/time-manager-desktop — building a new pane, rebuilding an existing pane, reviewing chrome for vibecoded violations, or designing a new component.
---

# Timed Design System

## The Brief

The users are C-suite executives — the prototype's primary users are the co-founders (Yasser + Ammar Shahin). The app must read as
**first-party Apple** — Calendar, Reminders, System Settings. Not Notion-clean
— Apple-clean. Black/white dominant, monochrome chrome, a single accent per
screen, and very small bucket-coloured dots like Apple Reminders' list-color
circle. Liquid Glass preserved where it already lives. Nothing flashy.
Nothing branded. Nothing "AI-magical". *Execs don't have time for rubbish.*

Spec lives in `DESIGN.md` (tokens) and `docs/UI-RULES.md` (checklist). This
skill captures the **judgment calls** that aren't in those files — which
patterns the user accepted, which he flagged as "vibecoded SaaS crap", and
the canonical recipe extracted from panes he kept.

## The Vibecode Smell-List

Every pattern below was **explicitly rejected** in the 2026-04-25 colour-strip
session. Do not reintroduce. Full table with file:line citations →
[references/vibecode-smell-list.md](references/vibecode-smell-list.md).

- `MeshGradient` / `AngularGradient` / `RadialGradient` backgrounds
  (rejected: `DishMeUpHomeView.swift:106-134`, `MorningCheckInView.swift:198-214`)
- `Image(systemName: "sparkles")` / `wand.and.stars` / decorative `bolt.fill`
  (rejected: `DishMeUpHomeView.swift:162`, `DishMeUpSheet.swift:396`,
  `PlanPane.swift:164` & `:184`, `DishMeUpSheet.swift:43-45` mood icons)
- Hero type ≥40pt or `.weight(.black/.heavy)` on session panes
  (rejected: 52pt "TIMED" hero, all-caps tracked "DISH ME UP" label
  `DishMeUpHomeView.swift:147-150`). Cinematic 72pt is **splash only** — and
  splash itself was deleted.
- Gradient buttons + halo shadows
  (rejected: `DishMeUpHomeView.swift:168-175` — `LinearGradient` fill +
  `shadow(color: BrandColor.primary.opacity(0.28), radius: 18, y: 8)`)
- `PulsingOrb` / breathing animations not tied to real loading state
  (rejected: `DishMeUpHomeView.swift:389-413`,
  `MorningCheckInView.swift:180-240` — both use `repeatForever` without any
  signal binding)
- Multi-colour SaaS card chrome — per-bucket fill colours, opacity-tinted
  cards (`Color.green.opacity(0.06)`, `m.color.opacity(0.12)`,
  `BrandColor.primary.opacity(0.12)` numbered circles)
- Custom button styles where native `.borderedProminent` / `.bordered` /
  `.plain` would do
- Branded splash screens — deleted. macOS system apps don't have these.

## Canonical Pane Recipe

The pattern the user **kept**, extracted from `TasksPane`, `TodayPane`,
`WaitingPane`, `CalendarPane`. Full pattern catalogue →
[references/canonical-pane-recipe.md](references/canonical-pane-recipe.md).

- `List(selection:)` with `.listStyle(.plain)`. No custom separators.
- Row: `HStack(spacing: 12)` → `BucketDot` (8pt) → title 13pt → `Spacer()` →
  meta (sender 11pt secondary), right-side time pill 11pt secondary in a
  `Capsule` with `Color(.controlBackgroundColor)` fill.
- Type scale per use: row title 13pt, secondary 11pt, header stat value
  13pt semibold + 9pt label uppercase tracked 0.4. Hero is `.title` (28pt)
  via `TimedType.title`, never a hardcoded 40pt+.
- Spacing rhythm: `padding(.horizontal, 20).padding(.vertical, 12)` for
  pane headers; row internal padding `padding(.vertical, 5)`. Pane-level
  uses `TimedLayout.Spacing.lg` (20pt) screen margin.
- Single accent placement: at most one accent per screen — primary CTA
  via `.borderedProminent` with `.tint(Color.Timed.accent)`, OR active state
  on a single segmented control. **Never both.**
- `BucketDot` is the *only* place per-bucket colour appears in a pane row.
  See [references/bucket-dot-spec.md](references/bucket-dot-spec.md).
- Empty state: SF Symbol at 32pt `labelSecondary` + 15pt medium label +
  12pt secondary copy. No illustration. No CTA unless action is obvious.
- Native chrome: `.navigationTitle(...)`, `.toolbar { ToolbarItemGroup }`,
  `.swipeActions`, `.contextMenu`, native `Menu`/`Picker(.segmented)`.
- Liquid Glass placement: `.ultraThinMaterial` *only* on
  `CommandPalette.swift:233` and `QuickCapturePanel.swift:131`. Do not
  expand. Do not strip.
- Loading: native `ProgressView().controlSize(.large)` + 13–15pt
  `labelSecondary` copy. No spinners *and* skeleton; pick one.
- Contrast-first, not transparency-first. Apple uses background colour
  differentiation (`backgroundPrimary` ↔ `backgroundSecondary` ↔
  `backgroundTertiary`) before reaching for material/blur/shadow.

## Hard Rules (Non-Negotiable)

Full checklist lives in `docs/UI-RULES.md` — paste it into every PR that
touches UI. The five that get violated most:

1. Every colour through `Color.Timed.*` (or `BrandColor.*` legacy alias).
   No raw `Color.red/orange/green/teal/yellow/purple/...` outside
   `Sources/Legacy/`.
2. Every spacing/radius/height via `TimedLayout.Spacing.*` /
   `TimedLayout.Radius.*` / `TimedLayout.Height.*`.
3. Every font via `TimedType.*`. The single allowed `.system(size:)` hard
   pin is `TimedType.timerDisplay` (72pt SF Pro Rounded Thin).
4. SF Symbols only, monochrome rendering. No custom icon library.
5. One accent per screen. If you're tempted to add a second, remove the
   first. Tap targets ≥ 44×44pt.

`BucketDot` is the **only** place that colours come back in. Use the Apple
system palette (`Color(.systemBlue/Red/Green/Orange/Gray/Teal/Purple/Gray2)`)
mapped per `TaskBucket` case. Spec:
[references/bucket-dot-spec.md](references/bucket-dot-spec.md).

## When You're Tempted to Add Chrome

Before adding a gradient, an animation, a decorative card, or an icon
flourish, ask:

- Does Apple Calendar do this?
- Does System Settings do this?
- Does Reminders do this?

If the answer is no, **delete the impulse.** The user's mantra: *"Execs
don't have time for rubbish."* Calm beats loud. Native beats bespoke.
Background contrast beats shadow. Real loading state beats `repeatForever`.

If you can replace a custom view with a native control
(`.borderedProminent`, `Picker(.segmented)`, `ProgressView`, `Form`,
`List(.insetGrouped)`), do it. Less code is a feature.

## Liquid Glass Map

`.ultraThinMaterial` is reserved for floating overlay surfaces only.
Current sites — preserve, do not expand:

- `Sources/Features/CommandPalette/CommandPalette.swift:233` — ⌘K palette
- `Sources/Features/MenuBar/QuickCapturePanel.swift:131` — menu-bar capture

Anything in `Sources/Legacy/` is dead — do not reference, copy, or revive
its material usage.

## Decision Lineage

[references/timeline.md](references/timeline.md) — short journal of the
design decisions that shaped this skill. Read when you're about to undo
something and want to know why it's like that.
