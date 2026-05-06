import AppKit
import SwiftUI

/// Standalone window for the Preferences UI. SwiftUI's `Settings` scene
/// doesn't reliably surface in `LSUIElement` apps because the standard
/// "Preferences…" menu item lives on the main menu, which background
/// apps don't have. Hosting Preferences in our own NSWindow gives us a
/// dependable open path from both ⌘, and the menu-bar item.
@MainActor
final class PreferencesWindowController: NSObject {
    private let app: AppViewModel
    private var window: NSWindow?

    init(app: AppViewModel) {
        self.app = app
        super.init()
    }

    func show() {
        let window = ensureWindow()
        // Ensure the app is active so the prefs window can become key.
        // Without this, a popup-only LSUIElement app may fail to bring
        // the window forward.
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }
        let hostingController = NSHostingController(rootView: PreferencesView(app: app))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Noter Preferences"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.setContentSize(NSSize(width: 520, height: 520))
        window.delegate = self
        self.window = window
        return window
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    /// When prefs closes we hand key focus back to the visible popup so its
    /// own `windowDidResignKey` fires the next time the user clicks away,
    /// restoring normal hide-on-blur behaviour. Without this, the popup
    /// would have been frozen as "non-key but visible" since Preferences took
    /// key from it on open.
    func windowWillClose(_: Notification) {
        guard let popup = NSApp.windows.first(where: { window in
            window !== self.window && window.isVisible && window.canBecomeKey
        }) else { return }
        popup.makeKey()
    }
}
