import AppKit
import SwiftUI

#if !SCREENSHOT_RENDERER
@MainActor
@main
struct TimeManagerDesktopApp: App {
    @NSApplicationDelegateAdaptor(TimedAppDelegate.self) private var appDelegate

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
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, focusTimer: focusTimer)
        }
        .defaultSize(width: 1480, height: 940)
        .windowStyle(.hiddenTitleBar)
        .commands {
            TimedKeyboardCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
#endif
