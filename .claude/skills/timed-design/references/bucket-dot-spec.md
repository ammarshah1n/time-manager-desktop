# BucketDot Spec

The single, sanctioned colour-bearing component in Timed. An 8pt circle —
small enough to read as anchor, never as chrome. Modeled on Apple
Reminders' list-color circle.

## The Component

Lives at `Sources/Core/Design/Components/BucketDot.swift` (created during
the Dish Me Up rebuild, Phase 1).

```swift
struct BucketDot: View {
    var color: Color
    var size: CGFloat = 8
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)  // decorative; bucket label carries semantics
    }
}
```

Design constraints:

- Size **must default to 8pt**. 6pt allowed for sidebar density only.
  Anything ≥ 12pt is too big — it stops being an anchor and starts being
  a badge.
- Always paired with the row's text label. The dot does not carry meaning
  alone; it's an aid for fast visual scanning.
- Always at the **start** of the row's HStack, before any text.
- No stroke. No shadow. No animation.

## Apple System Palette Mapping

The dot's colour comes from a `TaskBucket.dotColor` getter (added to
`Sources/Features/PreviewData.swift`). Use the named-system-colour init
(`Color(.systemBlue)`) — these auto-adapt to light/dark, support
accessibility increase-contrast, and never violate the "no raw colour"
grep rule (which catches `Color.blue`, not `Color(.systemBlue)`).

| `TaskBucket` case | Dot colour | Why |
|-------------------|------------|-----|
| `.reply` | `Color(.systemBlue)` | Replies are the largest action class — Apple's primary colour. |
| `.action` | `Color(.systemRed)` | Action items are the most urgent class. |
| `.calls` | `Color(.systemGreen)` | Phone-green association. |
| `.readToday` | `Color(.systemOrange)` | Today-deadline urgency, lighter than red. |
| `.readThisWeek` | `Color(.systemGray)` | This-week reads are softer; gray reads as "later". |
| `.transit` | `Color(.systemTeal)` | Movement / travel association. |
| `.waiting` | `Color(.systemPurple)` | Apple uses purple for follow-up reminders in Mail. |
| `.ccFyi` | `Color(.systemGray2)` | Even softer gray — these are background-archive. |

These mappings are Apple-native semantic colours. They:

- Auto-adapt to light/dark mode (no manual `Color.dynamic(light:dark:)`
  needed)
- Support accessibility "Increase Contrast" / "Differentiate Without Color"
- Are recognised colours from the System Settings palette
- Never violate the existing `grep -rn "Color\.\(red\|orange\|green\|...\)"`
  guard (that regex catches `Color.red`, not `Color(.systemRed)`)

## The Single Allowed Exception

**Focus calendar blocks get accent, not the bucket palette.**

When a `CalendarBlock` has `category == .focus`, render its dot (or any
visual mark) using `Color.Timed.accent` (Apple system blue) — NOT
`Color(.systemBlue)`. This keeps the single accent slot tied to "focus
work", which is the system's most-elevated semantic.

```swift
let dotColor: Color =
    block.category == .focus
    ? Color.Timed.accent       // single-accent slot
    : block.bucket?.dotColor ?? Color.Timed.labelSecondary
```

Every other category, label, indicator, and decorative mark stays
monochrome. There is no second exception.

## Where BucketDot Goes

| Surface | File:line | Notes |
|---------|-----------|-------|
| Sidebar bucket rows | `Sources/Features/TimedRootView.swift` | Between icon and label |
| `TasksPane` row | `Sources/Features/Tasks/TasksPane.swift:341-343` (replaces the 3pt vertical color bar) | Start of HStack |
| `TodayPane` rows | `Sources/Features/Today/TodayPane.swift` (multiple sections) | Start of each task row |
| Dish Me Up plan rows | `Sources/Features/DishMeUp/DishMeUpHomeView.swift:336-385` (replaces numbered colored circle) | Plain index text + dot |
| Dish Me Up sheet output | `Sources/Features/DishMeUp/DishMeUpSheet.swift:289-333` (replaces `task.bucket.icon` foreground tint) | Replaces icon-with-color pattern |
| `CalendarPane` event cells | `Sources/Features/Calendar/CalendarPane.swift` | Per event; focus uses accent exception |
| `WaitingPane` rows | `Sources/Features/Waiting/WaitingPane.swift` | Already conformant — confirm dot is present |

## Where BucketDot Does NOT Go

- Hero / navigation surfaces (`.navigationTitle`, toolbar)
- Empty-state illustrations (use the bucket's SF Symbol instead)
- Buttons, pills, capsules — colour stays in the bucket dot only
- Detail sheets where the bucket is already in the title
- Cards where category is already shown via the dot in a parent row

## Anti-patterns Around BucketDot

- ❌ A dot ≥12pt — that's a badge.
- ❌ A dot with a stroke / shadow / glow — keep it flat.
- ❌ A dot animated on appear — it's a static anchor.
- ❌ Multiple dots per row (e.g. bucket + priority + medium) — one dot per
  row, max.
- ❌ Using `Color.Timed.accent` for a bucket dot — accent is exclusively
  for focus blocks + the single screen CTA.
- ❌ Using `Color.red` / `Color.orange` etc. — must be the
  `Color(.systemX)` named init (passes the grep guard).
