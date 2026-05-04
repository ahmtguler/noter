import AppKit
import SwiftUI

/// Owns the popup panel, persists its frame, and coordinates show/hide/toggle.
@MainActor
final class PanelController: NSObject {
    typealias ContentFactory = () -> AnyView

    private var panel: PopupPanel?
    private let defaults: UserDefaults
    private let contentFactory: ContentFactory

    init(
        defaults: UserDefaults = .standard,
        contentFactory: @escaping ContentFactory = { AnyView(EmptyView()) }
    ) {
        self.defaults = defaults
        self.contentFactory = contentFactory
        super.init()
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        restoreFrame(into: panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private func ensurePanel() -> PopupPanel {
        if let panel {
            return panel
        }
        let panel = PopupPanel()
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: contentFactory())
        self.panel = panel
        return panel
    }

    private func restoreFrame(into panel: PopupPanel) {
        if let saved = defaults.string(forKey: SettingsKey.popupFrame) {
            let frame = NSRectFromString(saved)
            if frame != .zero {
                panel.setFrame(frame, display: false)
                return
            }
        }
        panel.center()
    }

    fileprivate func persistFrame() {
        guard let frame = panel?.frame else { return }
        defaults.set(NSStringFromRect(frame), forKey: SettingsKey.popupFrame)
    }
}

extension PanelController: NSWindowDelegate {
    func windowDidMove(_: Notification) {
        persistFrame()
    }

    func windowDidResize(_: Notification) {
        persistFrame()
    }

    func windowWillClose(_: Notification) {
        persistFrame()
    }
}
