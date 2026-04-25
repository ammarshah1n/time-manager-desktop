// TimedMacAppMain.swift — TimedMacApp executable target
// Thin @main shim. All app behaviour lives in TimedKit.TimedAppShell.

import SwiftUI
import TimedKit

@main
struct TimedMacAppMain: App {
    @AppStorage("prefs.appearance.theme") private var theme: String = "system"

    init() {
        KeychainStore.migrateLegacyKeysIfNeeded()
    }

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup("Timed") {
            TimedAppShell()
                .preferredColorScheme(colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
    }
}
