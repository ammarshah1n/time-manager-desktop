// TimedColors.swift — Timed macOS
// Centralised dark-mode palette. Uses NSColor so values adapt correctly
// on macOS. Light mode falls back to system semantic colours via
// Environment.colorScheme checks where needed.

import SwiftUI

extension Color {
    enum Timed {
        // MARK: - Backgrounds
        static let windowBackground  = Color(nsColor: NSColor(red: 0.082, green: 0.086, blue: 0.094, alpha: 1)) // #151618
        static let elevatedSurface   = Color(nsColor: NSColor(red: 0.110, green: 0.114, blue: 0.129, alpha: 1)) // #1C1D21
        static let sidebar           = Color(nsColor: NSColor(red: 0.094, green: 0.098, blue: 0.110, alpha: 1)) // #18191C

        // MARK: - Borders & Dividers
        static let hairline          = Color.white.opacity(0.08)

        // MARK: - Text
        static let primaryText       = Color.white.opacity(0.92)
        static let secondaryText     = Color.white.opacity(0.62)
        static let tertiaryText      = Color.white.opacity(0.38)

        // MARK: - Accent & Selection
        static let accent            = Color(red: 0.298, green: 0.553, blue: 1.0)   // #4C8DFF
        static let selection         = Color(red: 0.298, green: 0.553, blue: 1.0).opacity(0.22)

        // MARK: - Semantic
        static let success           = Color(red: 0.298, green: 0.800, blue: 0.498)
        static let warning           = Color(red: 1.000, green: 0.757, blue: 0.298)
        static let danger            = Color(red: 1.000, green: 0.373, blue: 0.373)
    }
}

// MARK: - Adaptive helpers

/// Returns the Timed dark palette value when in dark mode, otherwise the
/// provided light-mode fallback. Use for surfaces that must look correct
/// in both schemes.
struct AdaptiveSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let dark: Color
    let light: Color

    func body(content: Content) -> some View {
        content.background(scheme == .dark ? dark : light)
    }
}

extension View {
    /// Convenience: apply `Color.Timed.*` in dark mode, semantic colour in light.
    func timedBackground(dark: Color, light: Color = Color(.controlBackgroundColor)) -> some View {
        modifier(AdaptiveSurface(dark: dark, light: light))
    }
}
