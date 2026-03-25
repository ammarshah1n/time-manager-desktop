import SwiftUI

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
