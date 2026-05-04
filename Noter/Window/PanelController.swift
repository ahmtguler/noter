import AppKit
import SwiftUI

/// Owns the popup panel, persists its frame, and coordinates show/hide/toggle.
@MainActor
final class PanelController: NSObject {
    private var panel: PopupPanel?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        panel.contentView = NSHostingView(rootView: RootPlaceholderView())
        self.panel = panel
        return panel
    }

    private func restoreFrame(into panel: PopupPanel) {
        if let saved = defaults.string(forKey: SettingsKey.popupFrame) {
            let frame = NSCoder.cgRect(for: saved)
            if frame != .zero {
                panel.setFrame(frame, display: false)
                return
            }
        }
        panel.center()
    }

    fileprivate func persistFrame() {
        guard let frame = panel?.frame else { return }
        defaults.set(NSCoder.string(for: frame), forKey: SettingsKey.popupFrame)
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

/// Placeholder content shown while the editor and switcher are being built up
/// in subsequent commits. Replaced by `RootView` in the editor commit.
private struct RootPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Noter")
                .font(.title2.weight(.semibold))
            Text("Editor coming in the next commit.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
