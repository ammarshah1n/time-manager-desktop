#if canImport(AppKit)
// GlobalHotkeyManager.swift — Timed macOS
// Registers Cmd+Shift+Space as a global hotkey for quick capture.
// Uses NSEvent.addGlobalMonitorForEvents for when app is not focused,
// and addLocalMonitorForEvents for when it is.

import AppKit

@MainActor
final class GlobalHotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onTrigger: (() -> Void)?

    func register(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        unregister()

        // Monitor when app is NOT focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }

        // Monitor when app IS focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
            // Don't swallow the event — return it so other handlers can process
            return event
        }
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Cmd+Shift+Space: keyCode 49 = Space
        guard !event.isARepeat, event.keyCode == 49 else { return }

        let relevantModifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift, .function])
        let expected: NSEvent.ModifierFlags = [.command, .shift]
        guard relevantModifiers == expected else { return }

        onTrigger?()
    }
}

#endif
