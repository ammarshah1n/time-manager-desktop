import AppKit
import SwiftUI

enum TimedAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum TimedAccentColor: String, CaseIterable, Identifiable {
    case crimsonRed = "#D32F2F"
    case blue = "#0A84FF"
    case green = "#30D158"
    case purple = "#BF5AF2"
    case `default` = "default"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crimsonRed: "Crimson Red"
        case .blue: "Blue"
        case .green: "Green"
        case .purple: "Purple"
        case .default: "Default"
        }
    }

    var color: Color {
        switch self {
        case .crimsonRed:
            Color(red: 211 / 255, green: 47 / 255, blue: 47 / 255)
        case .blue:
            Color(red: 10 / 255, green: 132 / 255, blue: 1)
        case .green:
            Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
        case .purple:
            Color(red: 191 / 255, green: 90 / 255, blue: 242 / 255)
        case .default:
            Color(nsColor: .controlAccentColor)
        }
    }

    static func resolve(_ rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .default
    }
}

enum TimedFontSizeCategory: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var bodyPointSize: CGFloat {
        switch self {
        case .small: 13
        case .medium: 15
        case .large: 17
        }
    }

    var sizeCategory: ContentSizeCategory {
        switch self {
        case .small: .medium
        case .medium: .large
        case .large: .extraLarge
        }
    }

    var sliderValue: Double {
        switch self {
        case .small: 0
        case .medium: 1
        case .large: 2
        }
    }

    static func nearest(to value: Double) -> Self {
        switch Int(value.rounded()) {
        case 0: .small
        case 2: .large
        default: .medium
        }
    }
}

private struct TimedBodyFontSizeKey: EnvironmentKey {
    static let defaultValue = TimedFontSizeCategory.medium.bodyPointSize
}

extension EnvironmentValues {
    var timedBodyFontSize: CGFloat {
        get { self[TimedBodyFontSizeKey.self] }
        set { self[TimedBodyFontSizeKey.self] = newValue }
    }
}

private struct TimedScaledFontModifier: ViewModifier {
    @Environment(\.timedBodyFontSize) private var timedBodyFontSize

    let baseSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        // The app still uses many fixed point sizes, so we shift them off the selected body baseline.
        let adjustedSize = max(10, baseSize + (timedBodyFontSize - TimedFontSizeCategory.medium.bodyPointSize))
        content.font(.system(size: adjustedSize, weight: weight, design: design))
    }
}

extension View {
    func timedScaledFont(
        _ baseSize: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(TimedScaledFontModifier(baseSize: baseSize, weight: weight, design: design))
    }

    func timedAppTheme(
        appearanceMode: TimedAppearanceMode,
        accentColor: TimedAccentColor,
        fontSizeCategory: TimedFontSizeCategory
    ) -> some View {
        self
            .tint(accentColor.color)
            .preferredColorScheme(appearanceMode.preferredColorScheme)
            .environment(\.sizeCategory, fontSizeCategory.sizeCategory)
            .environment(\.timedBodyFontSize, fontSizeCategory.bodyPointSize)
    }
}
