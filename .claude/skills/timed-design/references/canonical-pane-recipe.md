# Canonical Pane Recipe

The pattern the user accepted, extracted from `TasksPane.swift`,
`TodayPane.swift`, `WaitingPane.swift`, `CalendarPane.swift`. Every new
session pane should compose from this recipe — deviations need a reason
that maps back to a `DESIGN.md` rule.

## The Skeleton

```swift
struct ExamplePane: View {
    @Binding var items: [Item]

    var body: some View {
        VStack(spacing: 0) {
            paneHeader               // 1. compact header (20pt H, 12pt V padding)
            Divider()                // 2. native divider, no custom separator

            if items.isEmpty {
                emptyState           // 3. SF Symbol + 15pt label + 12pt copy
            } else {
                List(selection: $selected) {
                    ForEach(items) { item in
                        ItemRow(item: item)
                            .tag(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { detail = item }
                            .contextMenu { rowMenu(item) }
                    }
                    .onDelete { /* … */ }
                }
                .listStyle(.plain)   // 4. .plain on macOS panes; .insetGrouped is iOS Settings idiom
            }
        }
        .navigationTitle("Section name")  // 5. native nav title carries identity — no in-pane brand label
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Action") { … }    // 6. native Button, no custom style on toolbar
            }
        }
        .sheet(item: $detail) { item in
            DetailSheet(item: item)       // 7. detail flows go in sheets, not push navigation
        }
    }
}
```

## 1. Pane Header

`TasksPane.swift:137-160` is the canonical example.

- Layout: `HStack(spacing: 16)`
- Left: `HStack(spacing: 8) { Image(systemName: …) ; Text(...) }`
  - Icon `.font(.system(size: 14, weight: .medium))` foreground
    `Color.Timed.labelSecondary` (already monochrome — bucket.color now
    returns `labelSecondary`)
  - Title `.font(.system(size: 14, weight: .semibold))` (no `.font(...)`
    explicit colour — defaults to `labelPrimary`)
- Right: stat group `HStack(spacing: 16)` with each stat as
  `VStack(alignment: .trailing, spacing: 1)`:
  - Value: `13pt` semibold
  - Label: `9pt` medium, `Color.Timed.labelSecondary`,
    `.textCase(.uppercase)`, `.tracking(0.4)`
- Padding: `.padding(.horizontal, 20).padding(.vertical, 12)`

## 2. List Style

- `.listStyle(.plain)` on macOS — matches Apple Mail / Reminders rows.
- `.insetGrouped` is the iOS Settings idiom; only use for `Settings (Prefs)`
  pane on macOS where the grouped form makes sense.
- Never set custom row separators. Let the system draw.
- Selection: `List(selection: $selectedId)` — never draw a custom
  selection pill.

## 3. Row Layout (the heart of the recipe)

`TasksPane.swift:338-441` (TaskRow). The shape every row converges to:

```swift
HStack(spacing: 12) {
    BucketDot(color: item.bucket.dotColor)        // 8pt category anchor
    VStack(alignment: .leading, spacing: 3) {
        Text(item.title)                          // 13pt, default labelPrimary
            .font(.system(size: 13))
            .lineLimit(1)
        HStack(spacing: 6) {                      // metadata line
            Text(item.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            // optional bullet "·" + secondary detail
        }
    }
    Spacer()
    HStack(spacing: 10) {
        // staleness pill, batch count, time pill, action button
        // each at 11pt or smaller, secondary foreground
    }
}
.padding(.vertical, 5)
```

Key proportions:

- Title: 13pt regular, default colour (labelPrimary)
- Subtitle / metadata: 11pt secondary
- Right-side pills: 11pt secondary in a `Capsule` with
  `Color(.controlBackgroundColor)` fill and an optional 0.5pt
  `Color(.separatorColor)` stroke
- Time pills: `.monospacedDigit()`
- Tap target: row is the tap surface (`.contentShape(Rectangle())`)

## 4. Type Scale per Use

| Use | Token | Size |
|-----|-------|------|
| Pane nav title | `.navigationTitle` (system) | system large title |
| Pane in-header label | `.font(.system(size: 14, weight: .semibold))` | 14pt |
| Section header in pane (e.g. "OVERFLOW") | `.font(TimedType.caption2)` `.tracking(1.2)` `Color.Timed.labelTertiary` | 11pt |
| Row title | 13pt regular | 13pt |
| Row subtitle / metadata | 11pt regular `.secondary` | 11pt |
| Pill / time label | 11pt medium `.monospacedDigit()` `.secondary` | 11pt |
| Stat header value | 13pt semibold | 13pt |
| Stat header label | 9pt medium uppercase tracked 0.4 `.secondary` | 9pt |
| Empty state title | 15pt medium | 15pt |
| Empty state body | 12pt `.secondary` | 12pt |
| Hero in-pane headline (rare) | `TimedType.title` (28pt) | 28pt — never higher on a session pane |
| Splash / timer hero | `TimedType.timerDisplay` (72pt) | 72pt — splash + focus only |

For greenfield code, prefer the `TimedType.*` semantic tokens; the explicit
sizes above are the legacy values you'll see in the canonical panes and
should match.

## 5. Spacing Rhythm

| Where | Value | Token |
|-------|-------|-------|
| Pane H padding | 20 | `TimedLayout.Spacing.lg` / `Spacing.screenMargin` |
| Pane V padding (header) | 12 | `TimedLayout.Spacing.sm` |
| Row internal V padding | 5 | (custom, falls between `xxs` and `xs`) |
| Inter-row spacing | system default in `List(.plain)` | — |
| Section gap inside scroll | 24 | `TimedLayout.Spacing.xl` |
| Card inner padding | 16 | `TimedLayout.Spacing.md` / `Spacing.cardPadding` |
| Pane-section vertical rhythm | 22–28pt | `Spacing.xl` / custom |
| Sheet H padding | 24 | `Spacing.xl` |
| Hero-screen padding (onboarding) | 40 | `Spacing.xxxl` |

## 6. Accent Placement (one per screen)

The single accent (`Color.Timed.accent` = Apple system blue) appears at most
once per visible screen. The hierarchy of where it goes:

1. **Active timer ring fill** (Focus pane only)
2. **Single primary CTA per screen** (`.borderedProminent` button)
3. **Active selected segment** of a `Picker(.segmented)` or single tab
4. **Active toggle / slider in active state** (system-rendered automatically)

If a row has a primary CTA AND a selected segmented control, choose one to
demote to neutral. Sidebar selection uses macOS native highlight, not accent.

## 7. BucketDot Anchor

Every category-bearing row gets a single 8pt `BucketDot` at the start of the
HStack. Spec → [bucket-dot-spec.md](bucket-dot-spec.md).

## 8. Empty States

```swift
VStack(spacing: 12) {
    Image(systemName: bucket.icon)
        .font(.system(size: 32, weight: .light))
        .foregroundStyle(Color.Timed.labelSecondary.opacity(0.5))
    Text("No \(bucket.rawValue.lowercased()) tasks")
        .font(.system(size: 15, weight: .medium))
    Text("Triage emails to fill this bucket")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

- **No illustration.** Symbol only.
- **No CTA** unless the action is the only meaningful next step (rare).
- 32pt SF Symbol at `.light` weight, half-opacity secondary.
- 15pt medium headline, 12pt secondary subhead. That's it.

## 9. Loading States

- Native `ProgressView()` is the macOS loading idiom. Use `.controlSize(.large)`
  for a hero load, default for inline.
- Skeleton rectangles in `Color.Timed.labelQuaternary` are allowed for
  list rows where you can predict shape.
- **Never both.** Pick one.
- **Never custom motion** (no orbs, no breathing, no spinners-with-text).

```swift
VStack(spacing: TimedLayout.Spacing.md) {
    ProgressView().controlSize(.large)
    Text("Reading your day…")
        .font(TimedType.body)
        .foregroundStyle(Color.Timed.labelSecondary)
}
```

## 10. Native Chrome — Use It All

| Apple-native API | Use for |
|------------------|---------|
| `.navigationTitle` | Pane identity |
| `.toolbar { ToolbarItemGroup }` | Pane actions (Select, Done, Add) |
| `.swipeActions` | Per-row destructive / quick actions |
| `.contextMenu` | Right-click row menu — rich, hierarchical OK |
| `.sheet` / `.sheet(item:)` | Detail and modal flows |
| `.fullScreenCover` | First-launch onboarding only |
| `Form` + `Section` | Settings pane |
| `Picker(.segmented)` | Mutually-exclusive choice (≤6 options) |
| `Menu` | Hierarchical action group |
| `ProgressView` | Any loading state |
| `List(.plain)` | macOS row lists (Mail, Reminders style) |
| `List(.insetGrouped)` | Settings-style grouped form |
| `.borderedProminent` / `.bordered` / `.plain` | Button hierarchy |
| `.controlSize(.small/.regular/.large)` | Button size |
| `.tint(Color.Timed.accent)` | Single-accent override on a `.borderedProminent` |
| `.symbolEffect(.variableColor.iterative)` | State-bound symbol animation |
| Native window chrome | Sheets / windows already have close, drag, resize |

## 11. The Sheet Recipe

`DishMeUpSheet.swift` (post-rebuild target) shows the sheet shape:

- Header: `HStack` with `VStack` of title (18pt semibold) + subtitle (12pt
  secondary), `Spacer()`, optional close button (drop on macOS — system
  chrome handles it).
- Body: `ScrollView` with `VStack(alignment: .leading, spacing: 22)`
  containing labelled sections. Each section: `VStack(alignment: .leading,
  spacing: 10)` → `Text(...).sectionLabel()` (10pt semibold tracked 1.2
  secondary) → control row.
- Footer: `HStack` with cancel / primary action. Primary uses
  `.borderedProminent.controlSize(.large)` with `.tint(Color.Timed.accent)`.
- Width: `.frame(width: 560)` is the established sheet width. 720 max.
- H padding: 24-28pt; V padding: 18-22pt.

## 12. Contrast-First, Not Transparency-First

Apple panes layer surfaces with **background colour tiers**, not blur:

- `backgroundPrimary` (white / black) — root pane background
- `backgroundSecondary` (#F2F2F7 / #1C1C1E) — grouped surfaces, sheet bg,
  pill backgrounds
- `backgroundTertiary` (white / #2C2C2E) — cards on grouped background

`.ultraThinMaterial` is reserved for floating overlays (`CommandPalette`,
`QuickCapturePanel`). Don't reach for material to "give it depth" — reach
for the next background tier.

## 13. Haptics on Primary Actions

- `.impactOccurred(intensity: 0.6)` (medium) on every primary commit
  (start timer, submit form, accept plan)
- `.notificationOccurred(.success)` on completion
- `.impactOccurred(intensity: 0.4)` (light) on voice input confirmation
- `.notificationOccurred(.warning)` on destructive

macOS does have haptic feedback via `NSHapticFeedbackManager` on
trackpad-equipped Macs — wire it on every primary CTA.
