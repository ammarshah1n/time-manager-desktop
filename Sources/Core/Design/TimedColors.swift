// TimedColors.swift — Timed macOS
// Design tokens per DESIGN.md. Black/white first. A single accent — Apple system
// blue — used at most once per screen. Every semantic role below is adaptive
// light/dark. Back-compat aliases at the bottom map old token names onto the
// new semantic roles so call sites continue to compile unchanged.

import SwiftUI

extension Color {
    enum Timed {
        // MARK: - Accent (single, adaptive)

        /// Apple system blue — light #007AFF / dark #0A84FF.
        /// Use at most once per screen. Never for decoration.
        static let accent = Color.dynamic(
            light: Color(red: 0/255,  green: 122/255, blue: 255/255),
            dark:  Color(red: 10/255, green: 132/255, blue: 255/255)
        )

        // MARK: - Backgrounds

        /// Pure white (light) / pure black (dark, OLED-native).
        static let backgroundPrimary = Color.dynamic(
            light: Color.white,
            dark:  Color.black
        )
        /// Apple systemGroupedBackground.
        static let backgroundSecondary = Color.dynamic(
            light: Color(red: 242/255, green: 242/255, blue: 247/255),
            dark:  Color(red: 28/255,  green: 28/255,  blue: 30/255)
        )
        /// Card surface on grouped background.
        static let backgroundTertiary = Color.dynamic(
            light: Color.white,
            dark:  Color(red: 44/255, green: 44/255, blue: 46/255)
        )

        // MARK: - Labels

        static let labelPrimary = Color.dynamic(
            light: Color.black,
            dark:  Color.white
        )
        static let labelSecondary = Color.dynamic(
            light: Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.60),
            dark:  Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.60)
        )
        static let labelTertiary = Color.dynamic(
            light: Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.30),
            dark:  Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.30)
        )
        static let labelQuaternary = Color.dynamic(
            light: Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.18),
            dark:  Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.18)
        )

        // MARK: - Separators

        static let separator = Color.dynamic(
            light: Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.29),
            dark:  Color(red: 84/255, green: 84/255, blue: 88/255).opacity(0.60)
        )
        static let separatorOpaque = Color.dynamic(
            light: Color(red: 198/255, green: 198/255, blue: 200/255),
            dark:  Color(red: 56/255,  green: 56/255,  blue: 58/255)
        )

        // MARK: - Semantic (contextual only, never as branding)

        /// Errors / destructive actions only.
        static let destructive = Color.dynamic(
            light: Color(red: 255/255, green: 59/255, blue: 48/255),
            dark:  Color(red: 255/255, green: 69/255, blue: 58/255)
        )
        /// Completion states only.
        static let success = Color.dynamic(
            light: Color(red: 52/255, green: 199/255, blue: 89/255),
            dark:  Color(red: 48/255, green: 209/255, blue: 88/255)
        )

        // MARK: - Back-compat aliases

        /// @available alias — prefer `backgroundPrimary`.
        static let windowBackground  = backgroundPrimary
        /// @available alias — prefer `backgroundSecondary`.
        static let elevatedSurface   = backgroundSecondary
        /// @available alias — prefer `backgroundSecondary`.
        static let sidebar           = backgroundSecondary
        /// @available alias — prefer `separator`.
        static let hairline          = separator
        /// @available alias — prefer `labelPrimary`.
        static let primaryText       = labelPrimary
        /// @available alias — prefer `labelSecondary`.
        static let secondaryText     = labelSecondary
        /// @available alias — prefer `labelTertiary`.
        static let tertiaryText      = labelTertiary
        /// @available alias — use `accent.opacity(0.18)` directly.
        static let selection         = Color.dynamic(
            light: Color(red: 0/255,  green: 122/255, blue: 255/255).opacity(0.18),
            dark:  Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.18)
        )
        /// @available alias — system orange. Kept only for one-off warning contexts.
        static let warning           = Color.dynamic(
            light: Color(red: 255/255, green: 149/255, blue: 0/255),
            dark:  Color(red: 255/255, green: 159/255, blue: 10/255)
        )
        /// @available alias — prefer `destructive`.
        static let danger            = destructive
    }
}
