# Vibecode Smell-List

Patterns the user has explicitly flagged as "vibecoded SaaS crap" with real
file:line citations. Do not reintroduce. If you find yourself writing one of
these, stop and reach for the canonical pane recipe instead.

## 1. Animated gradient backgrounds

| Pattern | Where it was used | Why it's wrong | Replacement |
|---------|------------------|----------------|-------------|
| `MeshGradient` driven by `TimelineView` | `Sources/Features/DishMeUp/DishMeUpHomeView.swift:106-134` (`background` + `meshGradient(drift:)`) | Apple Calendar / Settings / Reminders have flat backgrounds. The drift reads as a SaaS "AI is thinking" tell. | `Color.Timed.backgroundPrimary.ignoresSafeArea()` |
| `RadialGradient` halo around an orb | `Sources/Features/MorningCheckIn/MorningCheckInView.swift:53-58` and `:214-218` | Decorative, not communicating state. | Solid `Color.Timed.backgroundPrimary` |
| `AngularGradient` rotating ring | `Sources/Features/MorningCheckIn/MorningCheckInView.swift:198-205` | "Magical AI" aesthetic; first-party Apple apps use solid + system materials only. | SF Symbol `mic.fill` / `waveform` with `.symbolEffect(.variableColor.iterative)` driven by real audio level. |
| `LinearGradient` button fill | `Sources/Features/DishMeUp/DishMeUpHomeView.swift:168-174` | Native macOS buttons are solid-tinted. Gradients are a Stripe / Notion AI pattern. | `Button(...) { }.buttonStyle(.borderedProminent).controlSize(.large)` |

**Rule:** Zero gradients in `Sources/` (excluding `Sources/Legacy/`).
`grep -rn "MeshGradient\|AngularGradient\|RadialGradient\|LinearGradient" Sources/`
should return zero hits outside Legacy.

## 2. Decorative iconography

| Icon | Where | Why it's wrong | Replacement |
|------|-------|----------------|-------------|
| `sparkles` | `DishMeUpHomeView.swift:162` (Dish Me Up button), `DishMeUpSheet.swift:396` (footer button), `PlanPane.swift:164` (primary CTA), `PlanPane.swift:184` (preview card) | "AI sparkle" iconography is the canonical SaaS-AI tell. Apple's first-party apps never use it on action buttons. | Plain text label. The button name carries the meaning. |
| `wand.and.stars` | (none currently — flag as smell) | Same as sparkles. | Plain text. |
| `bolt.fill` decorative | `DishMeUpSheet.swift:43-45` (`DishMeUpMood.easyWins`) | Decorative tint icon paired with `.green` / `.orange` colour. | Either drop the icon, or keep as monochrome `labelSecondary` with no decorative colour. |
| `flame.fill` for "avoidance" | `DishMeUpSheet.swift:43-45` (`DishMeUpMood.avoidance`) | Same — decorative + `.orange` violates single-accent. | Drop colour; keep icon as `labelSecondary` if useful. |
| `brain.head.profile` for "deep focus" | `DishMeUpSheet.swift:43-45` | Decorative cuteness. | Drop or neutralise. |

**Rule:** No icon used purely for decoration. Every SF Symbol must communicate
state, type, or category — never "this thing is exciting".

## 3. Hero-sized type on session panes

| Pattern | Where | Why it's wrong | Replacement |
|---------|-------|----------------|-------------|
| All-caps tracked label "DISH ME UP" | `DishMeUpHomeView.swift:147-150` (11pt semibold tracking 1.6, `BrandColor.primary.opacity(0.75)`) | This is brochure typography. Apple panes use `.navigationTitle` for identity, not in-pane brand labels. | `.navigationTitle("Dish Me Up")` and a single body subhead. |
| 28pt headline "What should you do next?" centered with hero spacing | `DishMeUpHomeView.swift:151-154` | Hero composition reads as marketing. Tasks/Today/Waiting use 13pt rows + nav title. | One `TimedType.body` line in `labelSecondary` below the nav title. |
| 52pt+ display type on session panes | (deleted from IntroView; do not reintroduce on panes) | The 72pt display is splash-only — and splash itself was deleted 2026-04-25. | Use `TimedType.title` (28pt) max for in-pane headlines. |
| `.weight(.black)` / `.weight(.heavy)` | (none currently) | macOS system apps cap at semibold. | `.weight(.semibold)` is the heaviest weight allowed. |

**Rule:** Cinematic 72pt is splash only. Panes use the `TimedType` semantic
scale: `largeTitle` (34pt) for nav-title surface, `title` (28pt) max for
in-pane headlines, `body` (17pt) / `subheadline` (15pt) for content,
`caption2` (11pt) for tracked metadata.

## 4. Halo / glow shadows

| Pattern | Where | Why it's wrong | Replacement |
|---------|-------|----------------|-------------|
| `shadow(color: BrandColor.primary.opacity(0.28), radius: 18, y: 8)` | `DishMeUpHomeView.swift:175` | DESIGN.md caps shadow at `alpha 0.08, radius 12, y 4`. Coloured halos are a SaaS-AI motion language. | Drop entirely. Native `.borderedProminent` already provides the right elevation. In dark mode prefer background contrast over any shadow. |

**Rule:** `TimedLayout.Shadow.alpha = 0.08` is the cap. No coloured shadows.

## 5. Breathing / pulsing animations not bound to real state

| Pattern | Where | Why it's wrong | Replacement |
|---------|-------|----------------|-------------|
| `PulsingOrb` — `RadialGradient` + `repeatForever` scale 0.85→1.05 | `DishMeUpHomeView.swift:389-413` | The orb pulses regardless of whether anything is loading. Decoration cosplaying as state. | `ProgressView().controlSize(.large)` — Apple's native loading idiom. |
| `OrbView` — angular + radial gradient + 10s `hueRotation` + 1.4s `repeatForever` scale | `MorningCheckInView.swift:180-240` | Same — animated chrome dressed up as activity. | State-aware system mic indicator: `mic` (idle, `labelTertiary`), `mic.fill` (listening, scale modulated by real `voiceCapture.audioLevel`), `waveform` with `.symbolEffect(.variableColor.iterative)` (speaking). |

**Rule:** No `repeatForever` animation unless it's bound to a live signal
(real audio level, real progress, real timer). Static + state-changes only
otherwise.

## 6. Multi-colour SaaS card chrome

| Pattern | Where | Why it's wrong | Replacement |
|---------|-------|----------------|-------------|
| `m.color.opacity(0.12)` selected mood background | `DishMeUpSheet.swift:245` | Per-mood colour fills (green / orange / primary). Violates one-accent rule. | `Color.Timed.accent.opacity(0.10)` selected, `Color.Timed.backgroundSecondary` unselected. |
| `Color.green.opacity(0.06)` / `.teal` icon tints | `DishMeUpSheet.swift:350` (`.foregroundStyle(.teal)`), `:356` (`.green`/`.orange`) | Coloured icons in stats rows. | `Color.Timed.labelSecondary` for the icon. Use weight (semibold) for urgency, not colour. |
| `BrandColor.primary.opacity(0.12)` numbered circles | `DishMeUpHomeView.swift:340` (`PlanCard` index circle) | Colour-tinted index circles read as branded. | Plain text index + `BucketDot` for category. |
| Per-bucket colour fill on cards | (already stripped 2026-04-25) | Each row screaming its own colour is SaaS taxonomy. | `BucketDot` (8pt) carries the only colour anchor. |
| `.background(.primary, in: RoundedRectangle(cornerRadius: 10))` custom button bg | `DishMeUpSheet.swift:403` | Reinventing `.borderedProminent`. | `.buttonStyle(.borderedProminent).controlSize(.large).tint(Color.Timed.accent)`. |
| `RoundedRectangle().strokeBorder()` on every card | `DishMeUpHomeView.swift:380-383` (every PlanCard), `DishMeUpSheet.swift:248-251` (every mood pill) | Apple uses background contrast (`backgroundTertiary` over `backgroundSecondary`). Borders everywhere is a Tailwind tell. | Drop the stroke. Rely on background tier difference. |

**Rule:** Card differentiation comes from `Color.Timed.backgroundTertiary`
on `backgroundSecondary`, not stroke + tint + shadow. The only colour on a
row is the 8pt `BucketDot`.

## 7. Reinventing native controls

| Pattern | Where | Why it's wrong | Replacement |
|---------|-------|----------------|-------------|
| Custom `.plain` button with bespoke `Capsule` background | `DishMeUpHomeView.swift:182-196` (Voice check-in button) | macOS has `.bordered` / `.borderedProminent` / `.plain` — the ladder. Custom capsule = chrome reinvented. | `Button("Voice check-in") { }.buttonStyle(.bordered)` or move to `.toolbar`. |
| Capsule preset row for minute selection | `DishMeUpHomeView.swift:207-231` | Hand-rolled segmented control. | `Picker("", selection: $minutes) { ForEach(presets, id: \.self) }.pickerStyle(.segmented)`. |
| `.plain` button styled to look like `.bordered` | `DishMeUpSheet.swift:158-174` (presets), `:204-222` (context picker) | Same as above. | `.bordered` / `.borderedProminent` with `.controlSize(.small)`. |
| Hand-rolled close button `xmark.circle.fill` in `.plain` style | `DishMeUpSheet.swift:140-145` | Sheets have a system close — and on macOS the window chrome already has one. | Drop entirely, or use `.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") {…} } }`. |
| Custom `Slider().tint(task.bucket.color)` | `TasksPane.swift:482, :493` (BlockTimeSheet) | Now that bucket.color is monochrome it's harmless, but the pattern of tinting a slider per bucket is the smell. | `.tint(Color.Timed.accent)` if a tint is needed. |
| Branded splash screen | `Sources/Features/Intro/IntroView.swift` (deleted 2026-04-25) | macOS system apps (Calendar, Settings, Notes, Mail) launch directly into content. | App launches direct into root view. |

**Rule:** Reach for native first. If you're writing >5 lines of view code to
recreate something AppKit/SwiftUI already gives you, stop and use the native
control.

## 8. The "AI is special" smell

| Pattern | Why it's wrong |
|---------|----------------|
| Any "Powered by Opus / GPT / Claude" badge | Yasser does not care which model. Hide the model. |
| Sparkle anywhere near AI output | See section 2. |
| Hero "AI is thinking" loading screens with custom motion | See sections 1 + 5. ProgressView is the answer. |
| Result cards with "AI Suggestion" labels | The output is the suggestion. Don't label it. |
| Disclaimers / "AI may make mistakes" inline copy | Trust the product or don't ship it. |

**Rule:** AI is plumbing, not theatre. The user should think "this is
intelligent" because the *output* is intelligent — not because the *chrome*
performs intelligence.
