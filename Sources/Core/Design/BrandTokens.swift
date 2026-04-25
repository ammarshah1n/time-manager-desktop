// BrandTokens.swift — Timed macOS
// All brand-* tokens were retired with the splash strip; only the Color.dynamic
// helper is kept because it is used by Color.Timed.* (the active design system).

import SwiftUI

extension Color {
    /// Builds a colour that resolves differently per appearance on macOS.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return NSColor(isDark ? dark : light)
        })
    }
}
