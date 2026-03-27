import AppKit
import SwiftUI

#if !SCREENSHOT_RENDERER
@MainActor
@main
struct TimeManagerDesktopApp: App {
    @NSApplicationDelegateAdaptor(TimedAppDelegate.self) private var appDelegate
    @AppStorage(TimedPreferences.appearanceModeKey) private var appearanceModeRawValue = TimedPreferences.defaultAppearanceMode
    @AppStorage(TimedPreferences.accentColorKey) private var accentColorRawValue = TimedPreferences.defaultAccentColor
    @AppStorage(TimedPreferences.fontSizeCategoryKey) private var fontSizeCategoryRawValue = TimedPreferences.defaultFontSizeCategory

    private let store: PlannerStore
    private let focusTimer: FocusTimerModel
    private let menuBarController: MenuBarController
    private let globalHotkeyController: GlobalFocusHotkeyController

    init() {
        TimedPreferences.migrateLegacyValuesIfNeeded()
        let store = PlannerStore()
        let focusTimer = FocusTimerModel()
        let globalHotkeyController = GlobalFocusHotkeyController(store: store, focusTimer: focusTimer)
        self.store = store
        self.focusTimer = focusTimer
        menuBarController = MenuBarController(timerModel: focusTimer)
        self.globalHotkeyController = globalHotkeyController
        appDelegate.configure(globalHotkeyController: globalHotkeyController)
        applyAppearance(TimedPreferences.appearanceMode)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, focusTimer: focusTimer)
                .timedAppTheme(
                    appearanceMode: appearanceMode,
                    accentColor: accentColor,
                    fontSizeCategory: fontSizeCategory
                )
                .onAppear {
                    applyAppearance(appearanceMode)
                }
                .onChange(of: appearanceModeRawValue) { _, _ in
                    applyAppearance(appearanceMode)
                }
        }
        .defaultSize(width: 1480, height: 940)
        .windowStyle(.hiddenTitleBar)
        .commands {
            TimedKeyboardCommands()
        }

        Settings {
            SettingsView()
                .timedAppTheme(
                    appearanceMode: appearanceMode,
                    accentColor: accentColor,
                    fontSizeCategory: fontSizeCategory
                )
        }
    }

    private var appearanceMode: TimedAppearanceMode {
        TimedAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    private var accentColor: TimedAccentColor {
        TimedAccentColor.resolve(accentColorRawValue)
    }

    private var fontSizeCategory: TimedFontSizeCategory {
        TimedFontSizeCategory(rawValue: fontSizeCategoryRawValue) ?? .medium
    }

    private func applyAppearance(_ mode: TimedAppearanceMode) {
        NSApp.appearance = mode.nsAppearanceName.flatMap(NSAppearance.init(named:))
    }
}
#endif
