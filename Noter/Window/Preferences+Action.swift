import AppKit

enum PreferencesAction {
    /// Opens the Settings scene declared in `NoterApp`. Routes through
    /// `showSettingsWindow:` (macOS 13+) and falls back to the older
    /// `showPreferencesWindow:` selector for safety.
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
