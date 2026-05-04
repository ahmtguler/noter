import AppKit

/// Lives in the system menu bar. Left-click toggles the popup; right-click (or
/// ⌃-click) opens a small menu with Show Noter, Preferences (⌘,), and Quit (⌘Q).
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let onShow: () -> Void
    private let onShowPreferences: () -> Void

    init(
        onToggle: @escaping () -> Void,
        onShow: @escaping () -> Void,
        onShowPreferences: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onShow = onShow
        self.onShowPreferences = onShowPreferences
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "note.text",
            accessibilityDescription: "Noter"
        )
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc
    private func handleClick(_: Any?) {
        let event = NSApp.currentEvent
        let modifiers = event?.modifierFlags ?? []
        if event?.type == .rightMouseUp || modifiers.contains(.control) {
            showContextMenu()
        } else {
            onToggle()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(
            title: "Show Noter",
            action: #selector(handleShow),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let prefsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(handlePreferences),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Noter",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func handleShow() {
        onShow()
    }

    @objc
    private func handlePreferences() {
        onShowPreferences()
    }
}
