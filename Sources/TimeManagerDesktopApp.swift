import SwiftUI

#if !SCREENSHOT_RENDERER
@main
struct TimeManagerDesktopApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1480, height: 940)

        Settings {
            SettingsView()
        }
    }
}
#endif
