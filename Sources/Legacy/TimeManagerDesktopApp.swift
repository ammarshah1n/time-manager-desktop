import SwiftUI

@main
struct TimeManagerDesktopApp: App {
    var body: some Scene {
        WindowGroup("Timed") {
            TimedRootView()
        }
        .defaultSize(width: 1240, height: 820)
    }
}
