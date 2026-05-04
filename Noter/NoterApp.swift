import SwiftUI

@main
struct NoterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            if let app = appDelegate.app {
                PreferencesView(app: app)
            } else {
                Text("Loading…").padding(40)
            }
        }
    }
}
