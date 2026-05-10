import AppKit
import SwiftUI

/// Holds the system cursor at `cursor` while the modifier is alive. Combats
/// WKWebView underneath the overlay calling `NSCursor.IBeam.set()` on its
/// own — even when the mouse isn't moving — via CodeMirror's `cursor: text`
/// + caret blink. Mouse-move-driven solutions (`onContinuousHover`) only
/// re-win while the cursor is moving; once it rests, the WebKit setter is
/// the most recent call and the I-beam shows. A 30Hz heartbeat is cheap
/// and keeps our `.set()` the most recent caller.
///
/// Use as a view modifier:
///   `.cursorEnforced(.arrow)`
struct CursorEnforcer: ViewModifier {
    let cursor: NSCursor
    @State private var heartbeat: Timer?

    func body(content: Content) -> some View {
        content
            .onAppear { start() }
            .onDisappear { stop() }
            // Restart on cursor changes so callers can swap mid-life.
            .onChange(of: cursor) { _, _ in start() }
    }

    private func start() {
        stop()
        let cursor = cursor
        cursor.set()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { _ in
            cursor.set()
        }
    }

    private func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
    }
}

extension View {
    func cursorEnforced(_ cursor: NSCursor) -> some View {
        modifier(CursorEnforcer(cursor: cursor))
    }
}
