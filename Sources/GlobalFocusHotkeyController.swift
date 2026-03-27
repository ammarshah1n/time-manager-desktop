import AppKit
import SwiftUI

@MainActor
final class GlobalFocusHotkeyController {
    private let store: PlannerStore
    private let focusTimer: FocusTimerModel
    private let hudController = FocusStartHUDController()

    private var globalKeyMonitor: Any?

    init(store: PlannerStore, focusTimer: FocusTimerModel) {
        self.store = store
        self.focusTimer = focusTimer
    }

    func register() {
        guard globalKeyMonitor == nil else { return }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalKeyEvent(event)
            }
        }
    }

    func unregister() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }

        hudController.close()
    }

    private func handleGlobalKeyEvent(_ event: NSEvent) {
        guard !event.isARepeat, event.keyCode == 17 else { return }

        let relevantModifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift, .function])
        let expectedModifiers: NSEvent.ModifierFlags = [.command, .option]
        guard relevantModifiers == expectedModifiers else { return }

        startTopRankedTask()
    }

    private func startTopRankedTask() {
        bringTimedToFront()

        // The story only specifies "top-ranked incomplete task". If there isn't one, surface that explicitly.
        guard let task = store.rankedTasks.first(where: { !$0.task.isCompleted })?.task else {
            hudController.show(message: "🍅 No ranked task ready to start")
            return
        }

        store.selectTask(task)

        // Restarting the timer is the most direct interpretation of "immediately starts a Pomodoro".
        focusTimer.start(for: task) { [store] completedTask in
            store.recordPomodoro(for: completedTask.id)
        }

        hudController.show(message: "🍅 Started: \(task.title)")
    }

    private func bringTimedToFront() {
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            if window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
    }
}

@MainActor
private final class FocusStartHUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(message: String) {
        dismissTask?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel
        updatePanel(panel, message: message)
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        dismissTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, let panel else { return }
            self.fadeOut(panel)
        }
    }

    func close() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 118),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private func updatePanel(_ panel: NSPanel, message: String) {
        let hostingController: NSHostingController<FocusStartHUDView>

        if let existing = panel.contentViewController as? NSHostingController<FocusStartHUDView> {
            hostingController = existing
            hostingController.rootView = FocusStartHUDView(message: message)
        } else {
            hostingController = NSHostingController(rootView: FocusStartHUDView(message: message))
            hostingController.view.appearance = NSAppearance(named: .darkAqua)
            panel.contentViewController = hostingController
        }
    }

    private func position(_ panel: NSPanel) {
        let targetScreen =
            NSApp.keyWindow?.screen ??
            NSApp.mainWindow?.screen ??
            NSScreen.main

        guard let visibleFrame = targetScreen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 36
        )
        panel.setFrameOrigin(origin)
    }

    private func fadeOut(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }
}

private struct FocusStartHUDView: View {
    let message: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.clear)
                .background(
                    TimedVisualEffectBackground(
                        material: .hudWindow,
                        blendingMode: .withinWindow,
                        state: .active,
                        emphasized: true
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            TimedCard(title: "Focus timer", icon: "command.circle.fill", accent: .red) {
                Text(message)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
        .frame(width: 420, height: 118)
        .background(Color.clear)
    }
}
