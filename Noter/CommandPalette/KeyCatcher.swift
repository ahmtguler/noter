import AppKit
import SwiftUI

/// Invisible NSView that becomes first responder and forwards arrow keys,
/// Enter, and Esc to closures. Used by the command palette in place of a
/// search field — we still need somewhere for the keystrokes to land.
struct KeyCatcher: NSViewRepresentable {
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onMoveUp = onMoveUp
        view.onMoveDown = onMoveDown
        view.onCommit = onCommit
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        guard let view = nsView as? CatcherView else { return }
        view.onMoveUp = onMoveUp
        view.onMoveDown = onMoveDown
        view.onCommit = onCommit
        view.onCancel = onCancel
        DispatchQueue.main.async {
            if view.window?.firstResponder !== view {
                view.window?.makeFirstResponder(view)
            }
        }
    }

    private final class CatcherView: NSView {
        var onMoveUp: (() -> Void)?
        var onMoveDown: (() -> Void)?
        var onCommit: (() -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: // up
                onMoveUp?()
            case 125: // down
                onMoveDown?()
            case 36, 76: // return / enter
                onCommit?()
            case 53: // escape
                onCancel?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}
