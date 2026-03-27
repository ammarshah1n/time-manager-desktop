import AppKit

@MainActor
final class TimedAppDelegate: NSObject, NSApplicationDelegate {
    private var globalHotkeyController: GlobalFocusHotkeyController?

    func configure(globalHotkeyController: GlobalFocusHotkeyController) {
        self.globalHotkeyController = globalHotkeyController
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        globalHotkeyController?.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotkeyController?.unregister()
    }
}
