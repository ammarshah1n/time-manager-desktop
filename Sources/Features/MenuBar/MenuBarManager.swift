// MenuBarManager.swift — Timed macOS
// Supplementary menu bar presence. Shows current task, next event, remaining count.
// Popover has quick actions: Start Focus, Defer, Mark Complete.

import SwiftUI
import AppKit

@MainActor
final class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var eventMonitor: Any?

    // Published state for the popover view
    @Published var currentTaskName: String?
    @Published var currentTaskElapsed: TimeInterval = 0
    @Published var nextEventName: String?
    @Published var nextEventIn: TimeInterval?
    @Published var remainingTaskCount: Int = 0
    @Published var tasks: [TimedTask] = []

    // Callbacks wired from the app
    var onStartFocus: ((TimedTask) -> Void)?
    var onMarkComplete: ((UUID) -> Void)?
    var onQuickCapture: ((String) -> Void)?

    func setup() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        button.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "Timed")
        button.image?.size = NSSize(width: 16, height: 16)
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        configurePopover()
        updateStatusText()
    }

    func teardown() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        removeEventMonitor()
    }

    // MARK: - Status Updates

    func updateStatus(
        currentTask: String?,
        elapsed: TimeInterval,
        nextEvent: String?,
        nextEventIn: TimeInterval?,
        remainingCount: Int,
        allTasks: [TimedTask]
    ) {
        currentTaskName = currentTask
        currentTaskElapsed = elapsed
        nextEventName = nextEvent
        self.nextEventIn = nextEventIn
        remainingTaskCount = remainingCount
        tasks = allTasks
        updateStatusText()
        updatePopoverContent()
    }

    // MARK: - Private

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            closePopover()
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
        installEventMonitor()
    }

    private func closePopover() {
        popover.performClose(nil)
        removeEventMonitor()
    }

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                if self?.popover.isShown == true {
                    self?.closePopover()
                }
            }
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 360)
        updatePopoverContent()
    }

    private func updatePopoverContent() {
        let view = MenuBarPopoverView(manager: self)
        popover.contentViewController = NSHostingController(rootView: view)
    }

    private func updateStatusText() {
        guard let button = statusItem?.button else { return }

        if let taskName = currentTaskName {
            let elapsed = formatElapsed(currentTaskElapsed)
            let title = "\(elapsed) \(truncate(taskName, max: 20))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            button.attributedTitle = NSAttributedString(string: title, attributes: attrs)
            button.image = nil
        } else if let nextEvent = nextEventName, let timeIn = nextEventIn {
            let countdown = formatCountdown(timeIn)
            let title = "\(countdown) \(truncate(nextEvent, max: 18))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            button.attributedTitle = NSAttributedString(string: title, attributes: attrs)
            button.image = nil
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "Timed")
            button.image?.size = NSSize(width: 16, height: 16)
            button.image?.isTemplate = true
        }
    }

    func formatElapsed(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    func formatCountdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }

    private func truncate(_ s: String, max: Int) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "\u{2026}" : s
    }
}

// MARK: - Menu Bar Popover View

private struct MenuBarPopoverView: View {
    @ObservedObject var manager: MenuBarManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.indigo)
                Text("Timed")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(manager.remainingTaskCount) tasks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {

                    // NOW section
                    statusSection(
                        label: "NOW",
                        icon: "play.circle.fill",
                        color: .green
                    ) {
                        if let task = manager.currentTaskName {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(2)
                                    Text(manager.formatElapsed(manager.currentTaskElapsed))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    // Mark current task complete
                                    if let t = manager.tasks.first(where: { $0.title == task }) {
                                        manager.onMarkComplete?(t.id)
                                    }
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 16))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.green)
                            }
                        } else {
                            Text("No active focus session")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // NEXT section
                    statusSection(
                        label: "NEXT",
                        icon: "arrow.right.circle.fill",
                        color: .blue
                    ) {
                        if let next = manager.nextEventName {
                            HStack {
                                Text(next)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Spacer()
                                if let timeIn = manager.nextEventIn {
                                    Text("in \(manager.formatCountdown(timeIn))")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.blue)
                                }
                            }
                        } else {
                            Text("Nothing scheduled next")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // LATER section — top 3 undone tasks
                    let undone = manager.tasks.filter { !$0.isDone }.prefix(3)
                    if !undone.isEmpty {
                        statusSection(
                            label: "LATER",
                            icon: "tray.full.fill",
                            color: .orange
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(undone)) { task in
                                    HStack(spacing: 8) {
                                        Image(systemName: task.bucket.icon)
                                            .font(.system(size: 10))
                                            .foregroundStyle(task.bucket.color)
                                            .frame(width: 14)
                                        Text(task.title)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(task.timeLabel)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // Quick Actions
                    HStack(spacing: 12) {
                        quickAction("Focus", icon: "play.fill", color: .indigo) {
                            if let first = manager.tasks.first(where: { !$0.isDone }) {
                                manager.onStartFocus?(first)
                            }
                        }

                        quickAction("Capture", icon: "mic.fill", color: .purple) {
                            QuickCapturePanel.shared.show(onSubmit: manager.onQuickCapture)
                        }

                        quickAction("Open App", icon: "macwindow", color: .secondary) {
                            NSApp.activate(ignoringOtherApps: true)
                            for w in NSApp.windows where w.canBecomeKey {
                                w.makeKeyAndOrderFront(nil)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .frame(width: 320)
        .frame(minHeight: 200)
    }

    @ViewBuilder
    private func statusSection<Content: View>(
        label: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
            content()
        }
    }

    @ViewBuilder
    private func quickAction(
        _ label: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
