# Timed — Design System

## Brand Philosophy

Ultra-clean, native iOS. Every element earns its place. The aesthetic goal is: if Apple built a time management app, this is what it looks like. No vibe-coded gradients, no purple accents, no decorative flourishes. Black, white, space, and precision.

Reference apps: Apple Calendar, Apple Clock, Notion, Things 3.

---

## Typography

### Fonts

Use Apple's system font exclusively. Never specify a custom font unless absolutely necessary.

- **In SwiftUI/UIKit**: Always use `.font(.system(...))` or semantic text styles (`.title`, `.body`, `.caption`) — this automatically resolves to SF Pro Text (< 20pt) and SF Pro Display (≥ 20pt) with correct optical sizing and tracking applied by the system.
- **In Stitch / Figma prompts**: Specify `SF Pro Display` for anything 20pt and above, `SF Pro Text` for anything below 20pt. For the timer numeral display specifically, use `SF Pro Rounded` — it gives the numerals a slightly warmer, more purposeful feel without deviating from Apple's system.
- **Never** use Inter, Geist, or any third-party font. The goal is indistinguishable from a first-party Apple app.

### Type Scale (Default / Large Dynamic Type size)

| Role | Style Token | Size | Weight | Tracking |
|------|------------|------|--------|---------|
| Large Title | `.largeTitle` | 34pt | Regular | -0.4pt |
| Title 1 | `.title` | 28pt | Regular | -0.4pt |
| Title 2 | `.title2` | 22pt | Regular | -0.35pt |
| Title 3 | `.title3` | 20pt | Regular | -0.45pt |
| Headline | `.headline` | 17pt | Semibold | -0.43pt |
| Body | `.body` | 17pt | Regular | -0.43pt |
| Callout | `.callout` | 16pt | Regular | -0.32pt |
| Subheadline | `.subheadline` | 15pt | Regular | -0.24pt |
| Footnote | `.footnote` | 13pt | Regular | -0.08pt |
| Caption 1 | `.caption` | 12pt | Regular | 0pt |
| Caption 2 | `.caption2` | 11pt | Regular | 0.07pt |
| Timer Display | custom | 64–80pt | Thin/Light | -1.5pt |

**Timer display note**: Use SF Pro Rounded at large sizes (64pt+) at Thin or Light weight. This is the hero element — it should feel precise and calm, not heavy.

### Rules
- Support Dynamic Type. Use semantic text style tokens, not hardcoded sizes.
- Never bold body copy. Bold and Semibold are reserved for headlines and primary labels only.
- Line height: 120–130% for body text, 110% for display sizes.

---

## Colour System

### Philosophy

Black and white first. Colour only when it provides meaning — never decoration. No accent on more than one element per screen at a time. When in doubt, the accent does not appear.

### Palette

```
-- Light Mode --

Background (Primary):    #FFFFFF   (pure white — system background)
Background (Secondary):  #F2F2F7   (Apple systemGroupedBackground)
Background (Tertiary):   #FFFFFF   (card surfaces on grouped bg)

Label (Primary):         #000000   (100% opacity)
Label (Secondary):       rgba(60, 60, 67, 0.60)
Label (Tertiary):        rgba(60, 60, 67, 0.30)
Label (Quaternary):      rgba(60, 60, 67, 0.18)

Separator:               rgba(60, 60, 67, 0.29)
Separator (Opaque):      #C6C6C8

-- Dark Mode --

Background (Primary):    #000000   (pure black — OLED-native)
Background (Secondary):  #1C1C1E   (Apple secondarySystemBackground)
Background (Tertiary):   #2C2C2E

Label (Primary):         #FFFFFF
Label (Secondary):       rgba(235, 235, 245, 0.60)
Label (Tertiary):        rgba(235, 235, 245, 0.30)
Label (Quaternary):      rgba(235, 235, 245, 0.18)

Separator:               rgba(84, 84, 88, 0.60)
Separator (Opaque):      #38383A
```

### Accent Colour

The single accent colour for Timed. Used exclusively for:
- The active timer ring fill
- The single primary action button per screen
- Active/selected tab indicator
- Interactive controls when in active state (toggles on, sliders)

**Nothing else.** If you are considering adding accent colour to a second element on the same screen, remove it from one.

```
Accent (Light):  #007AFF   (Apple system blue — identical to iOS system blue)
Accent (Dark):   #0A84FF   (Apple's dark mode system blue — slightly lighter for OLED)
```

**Why system blue and not a custom colour:** The entire goal is to look like an Apple app. Apple's system blue is deeply embedded in user recognition as "the interactive thing." Using it means Timed reads as native on first glance. Avoid purple (`#AF52DE` and its derivatives) — it is overused in AI/productivity apps and reads as generic.

### Semantic Token Names

Use these names in Stitch DESIGN.md, Figma variables, and code:

```
color/background/primary
color/background/secondary
color/background/tertiary
color/label/primary
color/label/secondary
color/label/tertiary
color/label/quaternary
color/separator/default
color/separator/opaque
color/accent/primary
color/destructive           →  #FF3B30 (light) / #FF453A (dark)  [errors/delete only]
color/success               →  #34C759 (light) / #30D158 (dark)  [completion states only]
```

Destructive and success colours appear only in their specific semantic contexts — never as accent or branding.

---

## Spacing & Layout

### Grid
- **Base unit**: 8pt
- All spacing values are multiples of 4pt (4, 8, 12, 16, 20, 24, 32, 40, 48)

### Margins
- Screen edge margin: **20pt** (matches iOS system apps)
- Content safe area: respect `safeAreaInsets` — never place interactive content outside safe area

### Padding
- Card inner padding: **16pt** all sides
- Compact cell padding: **12pt** vertical, **16pt** horizontal
- Button inner padding: **16pt** horizontal, **14pt** vertical (for full-width buttons: 16pt vertical)

### Component Heights
- Navigation bar: system default (~44pt, or ~96pt with large title)
- Tab bar: system default (~83pt including safe area)
- Standard list row: **44pt** minimum (Apple tap target minimum)
- Full-width primary button: **50pt** height
- Input field: **44pt** height

---

## Corner Radius

```
App icon:              Follow Apple squircle — corner radius = width × 0.222, smoothness 61%
Cards / Sheets:        16pt
Buttons (full-width):  14pt
Buttons (inline):      10pt
Input fields:          10pt
Tags / Chips:          Fully rounded (pill — use .clipShape(Capsule()))
Alert dialogs:         System default (do not override)
Context menus:         System default (do not override)
Timer ring:            Circle (infinite radius)
```

---

## Elevation & Shadows

Apple's design language uses elevation very sparingly. Timed follows suit.

```
Default cards (on white bg):     No shadow. Use background contrast only.
Floating action elements:        shadow(color: rgba(0,0,0,0.08), radius: 12, x: 0, y: 4)
Sheets / modals:                 System default presentation shadow
Navigation bar (scrolled):       System default border/blur
```

**Rule**: If a shadow feels heavy or obvious, reduce it. iOS shadows are whispers, not statements. In dark mode, use background colour differentiation instead of shadows entirely.

---

## Motion & Animation

```
Standard transition:     0.28s, ease-in-out
Spring entrance:         mass: 1, stiffness: 180, damping: 20  (SwiftUI: .spring(response: 0.4, dampingFraction: 0.75))
Button tap feedback:     scale to 0.96 on press, spring back on release
Timer ring progress:     Spring animation on every update tick — not linear
Screen push:             System NavigationStack default (horizontal slide)
Modal presentation:      System sheet default (vertical slide up)
```

**Haptics** (required for native feel):
- Timer start: `.impactOccurred(intensity: 0.6)` (UIImpactFeedbackGenerator, .medium)
- Timer complete: `.notificationOccurred(.success)` (UINotificationFeedbackGenerator)
- Voice input confirmed: `.impactOccurred(intensity: 0.4)` (.light)
- Destructive action: `.notificationOccurred(.warning)`

---

## Iconography

Use **SF Symbols** exclusively. No custom icon library, no Heroicons, no Lucide.

```
Weight:     Match icon weight to surrounding text weight (e.g. body text → regular symbol weight)
Size:       Use symbol scales (.small, .medium, .large) or point sizes matching text hierarchy
Rendering:  .monochrome for navigation/toolbar icons. .hierarchical or .multicolor only for illustrated states (e.g. completion screen)
```

**Key symbols for Timed:**
- Timer: `timer` or `stopwatch`
- Play: `play.fill`
- Pause: `pause.fill`
- Stop: `stop.fill`
- Add task: `plus` or `plus.circle.fill` (accent colour, primary only)
- Voice: `mic` (inactive), `mic.fill` (active/listening)
- Settings: `gearshape` (not `gearshape.fill` — too heavy)
- Tasks list: `list.bullet`
- Complete/checkmark: `checkmark.circle.fill` (success colour)

---

## Buttons

### Primary (Full-width CTA)
```
Background:     color/accent/primary
Text:           White, .headline weight (17pt semibold)
Height:         50pt
Corner radius:  14pt
Width:          Screen width minus 40pt margins (fill with 20pt padding each side)
State/pressed:  Opacity 0.85, scale 0.98
```

### Secondary (Outlined or tinted)
```
Background:     color/accent/primary at 10% opacity (Apple tinted button style)
Text:           color/accent/primary, .headline weight
Corner radius:  14pt
```

### Destructive
```
Background:     color/destructive at 10% opacity
Text:           color/destructive, .headline weight
```

### Ghost / Tertiary
```
Background:     None
Text:           color/label/secondary, .body weight
Used for:       "Maybe Later", "Skip", "Cancel" — always below a primary button, never alone
```

### Icon Buttons (Navigation bar / Toolbar)
```
Size:           44×44pt tap target minimum
Icon:           SF Symbol, .body scale, color/accent/primary or color/label/secondary
No background:  Do not add background fill to icon buttons in navigation bars
```

---

## Lists & Table Views

Follow Apple's native grouped list style.

```
Style:              .insetGrouped (iOS default for modern apps — Apple Calendar, Settings)
Row height:         44pt minimum
Disclosure:         System chevron (>) — do not use custom arrows
Separators:         System default — do not hide unless the design has no adjacent rows
Section headers:    .caption weight, color/label/secondary, uppercase optional but avoid heavy styling
```

---

## Navigation

```
Navigation bar:     Large title on root screens, standard title on pushed screens
Tab bar:            Up to 5 items. Active: color/accent/primary. Inactive: color/label/tertiary
Back button:        System default — never override the back button label or icon
Modal presentation: Use .sheet for contextual flows (voice setup, settings). Use .fullScreenCover only for onboarding.
```

---

## Stitch Prompting Context

When using Google Stitch, open every session with this context block:

```
App: Timed — iOS time management app. Apple-native aesthetic.
Font: SF Pro (Text <20pt, Display ≥20pt, Rounded for timer numerals)
Colors: Black/white primary. Single accent: #007AFF (light) / #0A84FF (dark). No purple, no gradients.
Spacing: 8pt grid. 20pt screen margins. 16pt card padding.
Radius: Cards 16pt, buttons 14pt, inputs 10pt, chips fully rounded.
Shadows: Minimal — rgba(0,0,0,0.08) only on floating elements.
Icons: SF Symbols only, monochrome rendering.
Reference: Apple Calendar, Apple Clock, Notion, Things 3.
Rule: Every element must earn its place. If unsure, remove it.
```

---

## What This Design System Is Not

- Not a gradient system — no linear or radial gradients anywhere
- Not a glassmorphism system — no blurred background cards (system materials only where iOS uses them natively, e.g. navigation bars)
- Not a colourful system — the accent appears once per screen, maximum
- Not an illustration system — no decorative illustrations, only functional UI
- Not a shadow-heavy system — flat or near-flat surfaces throughout

---

*Version 1.0 — Timed. Last updated April 2026.*
