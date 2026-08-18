import Foundation

/// Resolves the on-disk folder for notes. Prefers the user-chosen vault (via
/// security-scoped bookmark) and falls back to the sandboxed app's Application
/// Support directory if no vault is configured yet.
@MainActor
enum Vault {
    static func notesFolder(defaults: UserDefaults = .standard) throws -> URL {
        let raw = defaults.string(forKey: SettingsKey.subfolder) ?? ""
        let subfolder = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? SettingsKey.defaultSubfolder
            : raw
        if let vault = VaultBookmark.resolve(from: defaults) {
            let folder = vault.appendingPathComponent(subfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
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
