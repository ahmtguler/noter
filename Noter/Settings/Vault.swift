import Foundation

/// Resolves the on-disk folder for notes. Until onboarding lands, falls back to
/// the sandboxed app's Application Support directory so the app is usable for
/// development without configuring a vault.
enum Vault {
    static func notesFolder(defaults: UserDefaults = .standard) throws -> URL {
        let subfolder = defaults.string(forKey: SettingsKey.subfolder) ?? SettingsKey.defaultSubfolder
        // TODO: resolve vault security-scoped bookmark in the onboarding commit.
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = support
            .appendingPathComponent("Noter", isDirectory: true)
            .appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
