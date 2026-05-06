import AppKit
import SwiftUI

/// Owns the popup panel, persists its frame, and coordinates show/hide/toggle.
@MainActor
final class PanelController: NSObject {
    typealias ContentFactory = () -> AnyView

    private var panel: PopupPanel?
    private var keyMonitor: PanelKeyMonitor?
    private var defaultsObserver: NSObjectProtocol?
    private let defaults: UserDefaults
    private let contentFactory: ContentFactory
    private(set) var lastHiddenAt: Date?
    /// Suppresses hide-on-blur briefly after a programmatic show so transient
    /// activation glitches (LSUIElement apps don't reliably hold key focus
    /// across modal-window close transitions) don't dismiss the panel.
    private var suppressHideUntil: Date?
    private let suppressHideWindow: TimeInterval = 0.6
    var onWillShow: (() -> Void)?

    init(
        defaults: UserDefaults = .standard,
        contentFactory: @escaping ContentFactory = { AnyView(EmptyView()) }
    ) {
        self.defaults = defaults
        self.contentFactory = contentFactory
        super.init()
        // React to theme changes immediately so the visual effect view's
        // appearance follows the user's choice, even while the panel is open.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyAppearance()
            }
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        onWillShow?()
        let panel = ensurePanel()
        applyAppearance()
        restoreFrame(into: panel)
        suppressHideUntil = Date().addingTimeInterval(suppressHideWindow)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        keyMonitor?.install()
    }

    private func applyAppearance() {
        guard let panel else { return }
        let raw = defaults.string(forKey: SettingsKey.editorTheme) ?? SettingsKey.defaultEditorTheme
        let preference = EditorAppearancePreference(rawValue: raw) ?? .system
        panel.appearance = preference.nsAppearance
    }

    func hide() {
        lastHiddenAt = Date()
        keyMonitor?.uninstall()
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
        let host = NSHostingView(rootView: contentFactory())
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        keyMonitor = PanelKeyMonitor(panel: panel)
        return panel
    }

    private func restoreFrame(into panel: PopupPanel) {
        if let saved = defaults.string(forKey: SettingsKey.popupFrame) {
            let frame = NSRectFromString(saved)
            if frame != .zero, isOnVisibleScreen(frame) {
                panel.setFrame(frame, display: false)
                return
            }
        }
        panel.center()
    }

    /// Guard against frames saved on a screen that's no longer attached, or so
    /// far off-screen that the panel would appear invisible.
    private func isOnVisibleScreen(_ frame: NSRect) -> Bool {
        guard frame.width > 100, frame.height > 100 else { return false }
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
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

    func windowDidResignKey(_: Notification) {
        guard !defaults.bool(forKey: SettingsKey.pinned) else { return }
        if let suppressUntil = suppressHideUntil, Date() < suppressUntil {
            return
        }
        hide()
    }
}
