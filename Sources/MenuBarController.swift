import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let timerModel: FocusTimerModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var statusTimer: Timer?

    init(timerModel: FocusTimerModel) {
        self.timerModel = timerModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        beginObservingTimer()
        startStatusTimer()
        updateStatusItem()
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        button.setAccessibilityLabel("Timed menu bar timer")
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 128)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarTimerPopoverView(
                timer: timerModel,
                onTogglePause: { [weak self] in
                    self?.timerModel.togglePause()
                },
                onStop: {
                    self.timerModel.stop()
                }
            )
        )
    }

    private func beginObservingTimer() {
        withObservationTracking {
            _ = timerModel.isVisible
            _ = timerModel.isRunning
            _ = timerModel.sessionTitle
            _ = timerModel.secondsRemaining
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusItem()
                self?.beginObservingTimer()
            }
        }
    }

    private func startStatusTimer() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
            }
        }
        statusTimer?.tolerance = 0.15
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let title = timerModel.menuBarLabel
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]

        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        button.toolTip = timerModel.isVisible
            ? "\(timerModel.sessionTitle) • \(timerModel.countdownText) remaining"
            : "Timed"
    }
}

private struct MenuBarTimerPopoverView: View {
    let timer: FocusTimerModel
    let onTogglePause: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if timer.isVisible {
                // Paused sessions stay visible here so resume is still one click away.
                FocusTimerWidget(
                    timer: timer,
                    onTogglePause: onTogglePause,
                    onStop: onStop
                )
            } else {
                TimedCard(title: "No active timer", icon: "hourglass") {
                    Text("Start a focus block in Timed to pin the countdown here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(Color.clear)
    }
}
