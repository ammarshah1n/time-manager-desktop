// TimedType.swift — Timed macOS
// SF Pro scale per DESIGN.md. Every Font exposed here maps to a semantic role;
// new UI code must never specify `.system(size:)` directly. Dynamic Type is
// honoured automatically because we use the semantic text-style constructors
// (`.system(.title, design:)`) — the system resolves point sizes, weights, and
// tracking per the active content-size category.
//
// `.timerDisplay` is the single hero numeral style — SF Pro Rounded, Thin, at
// 72pt. It is the only place in the app where a numeric font size is hard-coded
// by design; the display behaves as a cinematic element, not body copy.

import SwiftUI

enum TimedType {
    // MARK: - Semantic scale (Dynamic Type respected)

    /// 34pt Regular. Top-of-screen page titles.
    static let largeTitle    = Font.system(.largeTitle,   design: .default)
    /// 28pt Regular. Headline block on onboarding and empty states.
    static let title         = Font.system(.title,        design: .default)
    /// 22pt Regular. Section headings inside a pane.
    static let title2        = Font.system(.title2,       design: .default)
    /// 20pt Regular. Minor section headings.
    static let title3        = Font.system(.title3,       design: .default)
    /// 17pt Semibold. Primary-button labels, card titles.
    static let headline      = Font.system(.headline,     design: .default)
    /// 17pt Regular. Standard reading text.
    static let body          = Font.system(.body,         design: .default)
    /// 16pt Regular. Secondary reading text.
    static let callout       = Font.system(.callout,      design: .default)
    /// 15pt Regular. Sidebar rows, list row subtitles.
    static let subheadline   = Font.system(.subheadline,  design: .default)
    /// 13pt Regular. Metadata, footnotes.
    static let footnote      = Font.system(.footnote,     design: .default)
    /// 12pt Regular. Captions, timestamps.
    static let caption       = Font.system(.caption,      design: .default)
    /// 11pt Regular. Micro-labels only.
    static let caption2      = Font.system(.caption2,     design: .default)

    // MARK: - Timer display

    /// 72pt Thin, SF Pro Rounded. The hero timer numeral. The one allowed
    /// hard-sized display style in the app.
    static let timerDisplay  = Font.system(size: 72, weight: .thin, design: .rounded)

    /// 48pt Thin, SF Pro Rounded. Compact timer variant (menu bar, focus pill).
    static let timerCompact  = Font.system(size: 48, weight: .thin, design: .rounded)

    // MARK: - Wordmark

    /// 24pt Regular, Default. The "Timed" wordmark on the splash.
    static let wordmark      = Font.system(size: 24, weight: .regular, design: .default)
}
