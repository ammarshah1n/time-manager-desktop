#if canImport(AppKit)
// QuickCapturePanel.swift — Timed macOS
// Floating panel triggered by global hotkey (Cmd+Shift+Space).
// Minimal: text field + submit. Creates a CaptureItem via callback.

import SwiftUI
import AppKit

@MainActor
final class QuickCapturePanel {
    static let shared = QuickCapturePanel()

    private var panel: NSPanel?
    private var onSubmit: ((String) -> Void)?

    private init() {}

    func show(onSubmit: ((String) -> Void)?) {
        self.onSubmit = onSubmit

        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = makePanel()
        self.panel = panel
        updateContent()
        positionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    func submit(text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSubmit?(text)
        dismiss()
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Allow the text field to receive key events
        panel.isMovableByWindowBackground = true
        return panel
    }

    private func updateContent() {
        let view = QuickCaptureView(panel: self)
        let controller = NSHostingController(rootView: view)
        controller.view.appearance = NSAppearance(named: .darkAqua)
        panel?.contentViewController = controller
    }

    private func positionPanel(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 120
        )
        panel.setFrameOrigin(origin)
    }
}

// MARK: - Quick Capture SwiftUI View

private struct QuickCaptureView: View {
    let panel: QuickCapturePanel
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.primary)

            TextField("Quick capture \u{2014} type a task and press Return", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .focused($isFocused)
                .onSubmit {
                    panel.submit(text: text)
                }

            Button {
                panel.submit(text: text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .primary)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                panel.dismiss()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .frame(width: 480, height: 72)
        .onAppear { isFocused = true }
    }
}

#endif
