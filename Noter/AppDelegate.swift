import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var menuBarController: MenuBarController?
    private var noteStore: NoteStore?
    private var editorState: EditorState?

    func applicationDidFinishLaunching(_: Notification) {
        do {
            let folder = try Vault.notesFolder()
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            noteStore = store
            editorState = editor

            let controller = PanelController(contentFactory: {
                AnyView(RootView(store: store, editor: editor))
            })
            panelController = controller

            menuBarController = MenuBarController { [weak controller] in
                controller?.toggle()
            }
            KeyboardShortcuts.onKeyDown(for: .toggleNoter) { [weak controller] in
                controller?.toggle()
            }
        } catch {
            presentFatalError("Failed to initialize Noter: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_: Notification) {
        editorState?.flush()
    }

    private func presentFatalError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Noter could not start"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
