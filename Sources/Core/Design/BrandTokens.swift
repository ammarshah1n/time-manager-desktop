// BrandTokens.swift — Timed macOS
// Single source of truth for brand colour, motion, type, version.
// Colours are defined in Swift (not Asset Catalog) because the repo-level
// Assets.xcassets is not wired into the SwiftPM target; AppIcon is bundled
// separately by package_app.sh. Adapt to colour scheme via BrandColor.dynamic.

import SwiftUI

// MARK: - Brand Version

enum BrandVersion {
    /// Bump when the brand/logo changes. Controls first-launch gate.
    static let current = "v1"

    /// @AppStorage key — intro plays once per brand version.
    static let introSeenKey = "hasSeenIntro_\(current)"
}

// MARK: - Brand Colour

enum BrandColor {
    /// Apple system blue — the only accent. Light #007AFF / dark #0A84FF.
    /// Use at most once per screen. Never as decoration.
    static let primary: Color = .dynamic(
        light: Color(red: 0/255,  green: 122/255, blue: 255/255),
        dark:  Color(red: 10/255, green: 132/255, blue: 255/255)
    )

    /// Alias of `primary`. Kept so existing call sites compile.
    /// New code: use `BrandColor.primary`.
    static let accent: Color = primary

    /// Page surface. Pure white (light) / pure black (dark, OLED-native).
    static let surface: Color = .dynamic(
        light: Color.white,
        dark:  Color.black
    )

    /// Foreground text / wordmark.
    static let ink: Color = .dynamic(
        light: Color.black,
        dark:  Color.white
    )

    /// Muted surface — systemGroupedBackground.
    static let mist: Color = .dynamic(
        light: Color(red: 242/255, green: 242/255, blue: 247/255),
        dark:  Color(red: 28/255,  green: 28/255,  blue: 30/255)
    )
}

// MARK: - Brand Motion

enum BrandMotion {
    static let easeStandard = Animation.easeOut(duration: 0.4)
    static let easeExpressive = Animation.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.9)
    static let durFast: Double = 0.25
    static let durBase: Double = 0.4
    static let durSlow: Double = 0.8

    /// Per-element stagger for word-by-word tagline animation.
    static let wordStagger: Double = 0.08

    /// Skip button appearance delay.
    static let skipGrace: Double = 2.0

    /// Reduce Motion target — full sequence collapses to this.
    static let reducedTotal: Double = 0.3
}

// MARK: - Brand Type

enum BrandType {
    /// Hero / logo wordmark.
    static let display = Font.system(size: 72, weight: .thin, design: .default)
        .width(.expanded)
    static let headline = Font.system(size: 28, weight: .medium, design: .default)
    static let tagline = Font.system(size: 18, weight: .regular, design: .default)
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let mono = Font.system(.body, design: .monospaced)
}

// MARK: - Brand Asset Loader

enum BrandAsset {
    /// Loads the brand logo PNG from the SwiftPM bundle. Falls back to an
    /// SF Symbol if the resource is missing (should never happen in shipped builds).
    static func logoImage() -> Image {
        if let url = Bundle.module.url(forResource: "BrandLogo", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "clock.fill")
    }
}

// MARK: - Color dynamic helper

extension Color {
    /// Builds a colour that resolves differently per appearance on macOS.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return NSColor(isDark ? dark : light)
        })
    }
}
