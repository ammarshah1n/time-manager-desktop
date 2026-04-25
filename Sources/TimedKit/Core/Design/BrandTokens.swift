// BrandTokens.swift — Timed Core / Design
// Cross-platform Color.dynamic(light:dark:) helper. On macOS it resolves the
// best-matching appearance; on iOS it uses traitCollection.userInterfaceStyle.
// All brand-* tokens were retired with the splash strip; only this helper is
// kept because Color.Timed.* (the active design system) consumes it.

import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Builds a colour that resolves differently per appearance.
    static func dynamic(light: Color, dark: Color) -> Color {
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [
                .darkAqua,
                .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark
            ]) != nil
            return NSColor(isDark ? dark : light)
        })
        #elseif canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        return light
        #endif
    }
}
