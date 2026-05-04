import AppKit

/// Popup window for the editor — translucent, floating, joins all spaces.
/// Backed by an `NSWindow` (not `NSPanel`) for reliability across macOS releases.
final class PopupPanel: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        hidesOnDeactivate = false
        // .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive —
        // setting both throws NSInternalInconsistencyException at runtime.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Hide all traffic-light buttons — the SwiftUI title bar provides its
        // own close affordance and clicking outside also hides the popup.
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
