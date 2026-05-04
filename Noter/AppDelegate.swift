import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelController = PanelController()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_: Notification) {
        menuBarController = MenuBarController { [weak self] in
            self?.panelController.toggle()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleNoter) { [weak self] in
            self?.panelController.toggle()
        }
    }
}
