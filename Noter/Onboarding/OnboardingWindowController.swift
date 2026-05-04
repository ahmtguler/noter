import AppKit
import SwiftUI

/// One-shot window shown the first time the app launches. Hands off to the
/// caller's completion when the user finishes setup.
@MainActor
final class OnboardingWindowController: NSObject {
    private var window: NSWindow?
    private let onComplete: () -> Void
    private let app: AppViewModel

    init(app: AppViewModel, onComplete: @escaping () -> Void) {
        self.app = app
        self.onComplete = onComplete
    }

    func show() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Noter"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FirstLaunchView(app: app) { [weak self] in
            self?.complete()
        })
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: SettingsKey.didOnboard)
        window?.close()
        window = nil
        onComplete()
    }
}
