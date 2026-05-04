# Timed UI Rules

Strict, short, include in every Claude / Cursor session that touches UI.
`DESIGN.md` is the spec; this file is the enforcement checklist.

---

## Hard rules (never break)

1. **Never hardcode a colour.** Use `Color.Timed.*` tokens (accent,
   `backgroundPrimary/Secondary/Tertiary`, `labelPrimary/Secondary/Tertiary/
   Quaternary`, `separator`, `destructive`, `success`). Legacy aliases
   (`windowBackground`, `primaryText`, `danger`, etc.) are kept for
   compilation but new code MUST use the semantic names above.
2. **Never hardcode a spacing, radius, or height.** Use `TimedLayout.Spacing.*`,
   `TimedLayout.Radius.*`, `TimedLayout.Height.*`.
3. **Never hardcode a font size.** Use `TimedType.*`. The only exception is the
   single hero numeral `TimedType.timerDisplay`.
4. **Never introduce a custom icon library.** SF Symbols only, monochrome
   rendering.
5. **Never add the accent colour to more than one element per screen.** If
   you're tempted to add a second, remove it from the first.
6. **Never add a gradient.** Anywhere.
7. **Never add a decorative illustration.** No floating shapes, no emoji-art,
   no abstract blobs.
8. **Never add a shadow heavier than** `color: .black.opacity(0.08), radius: 12,
   y: 4`. In dark mode prefer background contrast over shadow entirely.
9. **Always support Dynamic Type.** Use `TimedType.*` (which uses the
   semantic text-style constructors). Never pin a size without a
   `relativeTo:` in the hand-rolled case.
10. **Always support both light and dark mode.** Preview both in every new
    view. Every new colour must be adaptive via `Color.dynamic(light:dark:)`.
11. **All tap targets ≥ 44×44 pt.** Use `TimedLayout.Height.iconButton` for
    icon buttons.
12. **Never override the system navigation bar / tab bar appearance** unless
    `DESIGN.md` explicitly specifies otherwise.
13. **Voice first.** Any new user-facing capture / onboarding / setup flow
    STARTS as a voice-led experience. Form fields only for OAuth, file upload,
    or input voice cannot capture.
14. **No empty rows.** Cognitive load is the cost. If a labelled field has no
    meaningful value (no sender, no waiting-on, no due date, no notes), HIDE
    the row entirely — don't render `—`, `(none)`, or a placeholder. The
    executive opens the sheet to read signal, not to scroll past holes. The
    only exception is when the row is itself the affordance to ADD that
    value (e.g., a Notes editor that's empty but tappable). Provenance the
    user might need (AI/Manual/Voice/Email) lives on the TaskRow pill, not
    duplicated as a row.
15. **No bloat, period.** Every section, row, label, and chip costs the
    executive a glance. When in doubt, cut. This is the hardest rule because
    it requires saying no to features that look helpful. Anchor: an executive
    in a 5-second context-switch should grasp the entire pane. If they
    can't, something has to go.

---

## Pre-PR checklist

Paste this at the top of any PR that touches UI.

- [ ] No hardcoded colour (grep: `Color(red:` or `Color("` outside
      `TimedColors.swift` / `BrandTokens.swift`)
- [ ] No hardcoded spacing / radius / height (grep: `padding(.\{3,5\})` with a
      numeric literal — if new, add to `TimedLayout`)
- [ ] No `.font(.system(size:`) outside `TimedType.swift` (timerDisplay is
      the only allowed exception)
- [ ] Accent (`Color.Timed.accent` or `BrandColor.primary`) appears on at most
      one element per screen
- [ ] No gradients, no decorative illustrations, no shadows >0.08 alpha
- [ ] Dark mode tested in simulator / previews
- [ ] Dynamic Type tested at Accessibility XL
- [ ] All interactive elements meet 44×44 pt
- [ ] Haptic added to every primary action (`.impactOccurred(.medium)` on
      commit, `.notificationOccurred(.success)` on completion)
- [ ] Previews for every new SwiftUI view (light + dark)
- [ ] `swift build` clean

---

## Timed-specific additions

- **The cinematic 72pt display type is for the Splash only.** Panes seen every
  session use the 28pt / 22pt / 17pt scale.
- **Sidebar rows do not carry per-row colour.** Icons render in
  `labelSecondary`; selected rows promote the icon to `labelPrimary`. Never
  reintroduce per-bucket colour in the sidebar.
- **Offline / network-state indicators** are `labelSecondary` text, never a
  coloured pill.

---

## Design Guard Ratchet

`Tests/TimedDesignGuardTests.swift` is a ratchet, not an exemption baseline.
Files touched by a UI change must move toward these rules; do not add new
allowlist entries to make violations pass.

Current cleanup targets for Phase 2:

- `Sources/TimedKit/Features/Tasks/TasksPane.swift`
- `Sources/TimedKit/Features/TimedRootView.swift`

When a target file is touched for UI work, replace raw fonts, colours, spacing,
radii, and fixed dimensions with `TimedType.*`, `Color.Timed.*`, and
`TimedLayout.*`, then remove that file from this list.
