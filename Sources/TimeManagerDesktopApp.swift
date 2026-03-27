import SwiftUI

#if !SCREENSHOT_RENDERER
@MainActor
@main
struct TimeManagerDesktopApp: App {
    private let store: PlannerStore
    private let focusTimer: FocusTimerModel
    private let menuBarController: MenuBarController

    init() {
        TimedPreferences.migrateLegacyValuesIfNeeded()
        let store = PlannerStore()
        let focusTimer = FocusTimerModel()
        self.store = store
        self.focusTimer = focusTimer
        menuBarController = MenuBarController(timerModel: focusTimer)
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
