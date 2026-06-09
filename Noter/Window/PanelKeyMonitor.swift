import AppKit
import Foundation

/// Local key event monitor that intercepts `⌘N` / `⌘P` / `⌘K` / `⌘,` and
/// `⇧⌘⌫` before the hosted WKWebView consumes them. Posts notifications that
/// the SwiftUI `RootView` listens for. Active only while the popup window is key.
@MainActor
final class PanelKeyMonitor {
    private weak var panel: NSWindow?
    private var monitor: Any?

    init(panel: NSWindow) {
        self.panel = panel
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    func uninstall() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let panel, panel.isKeyWindow else { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // ⇧⌘⌫ — delete the active note (the open note, or the switcher's
        // highlighted row). keyCode 51 is delete/backspace; matching the code
        // avoids the awkward DEL character `charactersIgnoringModifiers` yields.
        if modifiers == [.command, .shift], event.keyCode == 51 {
            NotificationCenter.default.post(name: .noterDeleteActiveNote, object: nil)
            return nil
        }
        guard modifiers == .command else { return event }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "n":
            NotificationCenter.default.post(name: .noterNewNote, object: nil)
            return nil
        case "p":
            NotificationCenter.default.post(name: .noterShowSwitcher, object: nil)
            return nil
        case "k":
            NotificationCenter.default.post(name: .noterShowCommandPalette, object: nil)
            return nil
        case ",":
            NotificationCenter.default.post(name: .noterShowPreferences, object: nil)
            return nil
        default:
            return event
        }
    }
}

extension Notification.Name {
    static let noterNewNote = Notification.Name("io.gaiaswap.noter.newNote")
    static let noterShowSwitcher = Notification.Name("io.gaiaswap.noter.showSwitcher")
    static let noterShowCommandPalette = Notification.Name("io.gaiaswap.noter.showCommandPalette")
    static let noterShowPreferences = Notification.Name("io.gaiaswap.noter.showPreferences")
    static let noterDeleteActiveNote = Notification.Name("io.gaiaswap.noter.deleteActiveNote")
}
