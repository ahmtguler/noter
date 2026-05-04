import AppKit

/// Lives in the system menu bar. Left-click toggles the popup; right-click shows a
/// small menu with "Show Noter" and "Quit Noter".
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
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
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            onToggle()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Noter", action: #selector(handleShow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Noter",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func handleShow() {
        onToggle()
    }
}
