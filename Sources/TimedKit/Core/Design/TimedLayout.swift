// TimedLayout.swift — Timed macOS
// Spacing, radius, and component heights per DESIGN.md. Every layout number in
// the app must reference one of these constants. A value not present here is a
// signal to either (a) add a named constant for the role, or (b) use the
// closest existing one — not to hard-code a magic number in the view.
//
// Base grid is 8pt. All spacing values are multiples of 4pt.

import CoreGraphics

enum TimedLayout {

    // MARK: - Spacing (8pt grid)

    enum Spacing {
        /// 4pt — tightest inline rhythm (icon to text in a chip).
        static let xxs:  CGFloat = 4
        /// 8pt — baseline grid unit.
        static let xs:   CGFloat = 8
        /// 12pt — compact padding, inline stack gap.
        static let sm:   CGFloat = 12
        /// 16pt — default card inner padding, form row gap.
        static let md:   CGFloat = 16
        /// 20pt — screen edge margin (matches iOS system apps).
        static let lg:   CGFloat = 20
        /// 24pt — section separation inside a pane.
        static let xl:   CGFloat = 24
        /// 32pt — large vertical rhythm between pane sections.
        static let xxl:  CGFloat = 32
        /// 40pt — hero top/bottom padding on onboarding screens.
        static let xxxl: CGFloat = 40
        /// 48pt — splash vertical spacing between arc and wordmark.
        static let hero: CGFloat = 48

        /// Screen edge margin. Every pane respects this.
        static let screenMargin: CGFloat = lg
        /// Card inner padding on all sides.
        static let cardPadding:  CGFloat = md
    }

    // MARK: - Corner radius

    enum Radius {
        /// 16pt — cards, sheets, surface-level containers.
        static let card:   CGFloat = 16
        /// 14pt — full-width primary and secondary buttons.
        static let button: CGFloat = 14
        /// 10pt — inline buttons, text inputs.
        static let input:  CGFloat = 10
        /// 6pt — micro chips, inline pills when not using Capsule.
        static let chip:   CGFloat = 6
    }

    // MARK: - Component heights

    enum Height {
        /// 50pt — full-width primary CTA.
        static let primaryButton: CGFloat = 50
        /// 44pt — inline buttons, list rows. Apple tap-target minimum.
        static let row:           CGFloat = 44
        /// 44pt — text field height.
        static let input:         CGFloat = 44
        /// 44pt — icon-button tap target minimum.
        static let iconButton:    CGFloat = 44
        /// 360pt — minimum Settings pane window height.
        static let settingsPane:  CGFloat = 360
        /// 32pt — Settings account provider icon tile.
        static let accountIcon:   CGFloat = 32
        /// 7pt — compact account connection status dot.
        static let statusDot:     CGFloat = 7
        /// 26pt — Settings appearance swatch.
        static let colorSwatch:   CGFloat = 26
        /// 20pt — Settings appearance selected-swatch ring.
        static let swatchRing:    CGFloat = 20
        /// 180pt — splash logo area (arc + wordmark composition).
        static let splashLogo:    CGFloat = 180
    }

    // MARK: - Component widths

    enum Width {
        /// 760pt — minimum Settings pane window width. Keeps Settings tabs out
        /// of the macOS toolbar overflow menu at launch size.
        static let settingsPane:       CGFloat = 760
        /// 280pt — standard Settings picker width.
        static let settingsPicker:     CGFloat = 280
        /// 260pt — compact Settings radio group width.
        static let settingsCompact:    CGFloat = 260
        /// 120pt — Learning confidence progress width.
        static let learningProgress:   CGFloat = 120
    }

    // MARK: - Stroke weights

    enum Stroke {
        /// 1pt — hairline dividers, card borders (rarely used — prefer background contrast).
        static let hairline: CGFloat = 1
        /// 3pt — splash arc stroke.
        static let splashArc: CGFloat = 3
        /// 6pt — active timer ring.
        static let timerRing: CGFloat = 6
    }

    // MARK: - Shadows (values referenced by views directly)

    enum Shadow {
        /// 0.08 — the only shadow alpha in the system.
        static let alpha: Double = 0.08
        /// 12pt — shadow blur radius on floating elements.
        static let radius: CGFloat = 12
        /// 4pt — shadow y-offset on floating elements.
        static let y: CGFloat = 4
    }
}
