import Foundation
import ServiceManagement

/// Registers Noter as a login item via `SMAppService`, the modern replacement
/// for the old `SMLoginItemSetEnabled` helper-bundle dance.
///
/// Two pieces of state exist on purpose. `SettingsKey.launchAtLogin` records
/// what the *user asked for*; `SMAppService` holds what macOS has actually
/// registered. They can fall out of step — most obviously because installing a
/// new build replaces the app bundle, which can invalidate an existing
/// registration — so `reconcile()` runs at launch and re-applies the intent.
/// Without that, "launch at login" would quietly stop working after an update
/// and nothing in the UI would look wrong.
@MainActor
enum LoginItem {
    /// What macOS has registered right now.
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS wants the user to approve the item in System Settings before it
    /// will run. Registration succeeded, but nothing launches until they do.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// The user's stored intent, which is what the Preferences toggle shows.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: SettingsKey.launchAtLogin)
    }

    /// Records the intent and applies it. Returns what macOS ended up doing, so
    /// a refused registration snaps the toggle back rather than lying.
    @discardableResult
    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) -> Bool {
        defaults.set(enabled, forKey: SettingsKey.launchAtLogin)
        apply(enabled)
        // `requiresApproval` still counts as on: the user's choice is recorded
        // and macOS is merely waiting on them, so unticking the box would be
        // misleading.
        return isRegistered || needsApproval
    }

    /// Re-applies the stored intent. Called at launch so a replaced app bundle
    /// or a registration macOS dropped doesn't silently disable the feature.
    static func reconcile(defaults: UserDefaults = .standard) {
        let wanted = isEnabled(defaults: defaults)
        guard wanted != isRegistered else { return }
        // Don't fight a pending approval: re-registering wouldn't help, and the
        // user still has to act in System Settings.
        guard !(wanted && needsApproval) else { return }
        apply(wanted)
    }

    private static func apply(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[Noter] could not \(enabled ? "register" : "unregister") login item: \(error)")
        }
    }
}
