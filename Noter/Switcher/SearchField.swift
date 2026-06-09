import AppKit
import SwiftUI

/// A borderless `NSTextField` that forwards arrow keys, Enter, and Esc to the
/// switcher overlay. SwiftUI's `TextField` swallows these keys for its own
/// caret movement, so we drop down to AppKit for this case.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = SwitcherSearchTextField()
        field.placeholderString = "Search notes…"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.delegate = context.coordinator
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.parent = self
        DispatchQueue.main.async {
            if field.window?.firstResponder !== field.currentEditor() {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Marker subclass so `PanelController.windowWillReturnFieldEditor` can
    /// hand this field — and only this field — the arrow-cursor field editor.
    /// Its own cursor rect is also forced to arrow so the brief unfocused
    /// state can't flash an I-beam either.
    final class SwitcherSearchTextField: NSTextField {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField

        init(parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _: NSControl,
            textView _: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

/// Field editor for the switcher's search field that never asserts the I-beam.
///
/// Why: while the switcher is open the search field is focused, so this editor
/// is the window's first responder — and AppKit routes *every* `mouseMoved` to
/// the first responder, where NSTextView re-sets the I-beam synchronously. The
/// suppressed WKWebView underneath asserts *arrow* asynchronously (its cursor
/// IPC arrives at variable latency), so the two alternate: I-beam, arrow,
/// I-beam… — the flicker. No z-ordered claim can fix that race; the only
/// stable equilibrium is every claimant agreeing on arrow. This editor is the
/// last dissenter, so all three cursor paths are pinned to arrow / no-op:
/// per-move re-assert (`mouseMoved`), tracking-area updates (`cursorUpdate`),
/// and entry-based cursor rects (`resetCursorRects`).
/// Typing, caret placement, and drag-selection are unaffected — those ride
/// `keyDown` / `mouseDown` / `mouseDragged`, which all call through to super.
final class ArrowCursorFieldEditor: NSTextView {
    override func mouseMoved(with _: NSEvent) {
        // Deliberately empty: super re-asserts the I-beam on every move.
    }

    override func cursorUpdate(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: .arrow)
    }
}
