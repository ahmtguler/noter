import SwiftUI

@main
struct NoterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The actual Preferences UI is hosted by `PreferencesWindowController`
        // (see AppDelegate). SwiftUI's Settings scene doesn't reliably surface
        // in `LSUIElement` apps because it relies on the standard
        // "Preferences…" menu item. We keep the scene with `EmptyView` so the
        // App protocol is satisfied; nothing user-visible attaches to it.
        Settings { EmptyView() }
    }
}
