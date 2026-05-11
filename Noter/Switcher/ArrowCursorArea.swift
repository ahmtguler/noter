import AppKit
import SwiftUI

/// AppKit cursor claim for the popover area. Uses `NSTrackingArea` with
/// `.cursorUpdate` rather than `addCursorRect(_:cursor:)` because the
/// WKWebView underneath asserts its own cursor (CodeMirror's `cursor: text`)
/// on every mouseMoved it receives via its own tracking areas. Cursor rects
/// only fire on boundary crossings, so once WebKit re-asserted I-beam
/// mid-area, our rect was no longer in the picture. `.cursorUpdate` fires on
/// every mouseMoved within the area; AppKit picks the topmost cursor-update
/// owner per event, and as long as the popover's NSView is above the
/// WKWebView in z-order, ours wins for events inside our area while
/// WebKit's still wins for events outside the popover.
struct ArrowCursorArea: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        CursorTrackingView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class CursorTrackingView: NSView {
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .cursorUpdate],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func cursorUpdate(with _: NSEvent) {
            NSCursor.arrow.set()
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
