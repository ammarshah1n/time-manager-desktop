import AppKit
import SwiftUI

struct TimedVisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State
    let emphasized: Bool
    let appearanceName: NSAppearance.Name?

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        emphasized: Bool = false,
        appearanceName: NSAppearance.Name? = nil
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.emphasized = emphasized
        self.appearanceName = appearanceName
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.blendingMode = blendingMode
        view.material = material
        view.state = state
        view.isEmphasized = emphasized
        if let appearanceName {
            view.appearance = NSAppearance(named: appearanceName)
        } else {
            view.appearance = nil
        }
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowConfiguratorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowConfiguratorView)?.configureWindow()
    }
}

private final class WindowConfiguratorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        DispatchQueue.main.async { [weak self] in
            self?.configureWindow()
        }
    }

    func configureWindow() {
        guard let window else { return }

        window.styleMask.insert(.titled)
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified

        clearBackgrounds(in: window.contentView)
        clearSuperviewChain(startingAt: self)
        clearBackgrounds(in: window.contentViewController?.view)
        clearBackgrounds(in: window.contentView?.superview)
    }

    private func clearSuperviewChain(startingAt view: NSView?) {
        var currentView = view
        while let view = currentView {
            clearViewBackground(view)
            currentView = view.superview
        }
    }

    private func clearBackgrounds(in view: NSView?) {
        guard let view else { return }
        clearViewBackground(view)
        for child in view.subviews {
            clearBackgrounds(in: child)
        }
    }

    private func clearViewBackground(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
