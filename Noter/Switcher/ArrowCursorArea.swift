import AppKit
import SwiftUI

/// Backing NSView that declares an arrow cursor rect for its bounds. Used
/// inside switcher / command-palette row areas so the cursor doesn't
/// remain stuck as an I-beam after the user moves out of the SearchField
/// (NSTextField sets an I-beam cursor rect for itself, but no other view
/// claims a rect for the row region — so the previously-set cursor lingers).
struct ArrowCursorArea: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        CursorRectView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class CursorRectView: NSView {
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .arrow)
        }
    }
}

/// AppKit bridge for a reliable native tooltip on plain SwiftUI views.
/// SwiftUI's `.help()` is unreliable on borderless rows in macOS 26.
struct NativeTooltip: NSViewRepresentable {
    let text: String

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        nsView.toolTip = text
    }
}
