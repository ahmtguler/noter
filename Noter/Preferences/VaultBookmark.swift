import Foundation

/// Stores the vault folder URL as a security-scoped bookmark so the sandboxed
/// app can keep accessing it across launches without re-prompting the user.
enum VaultBookmark {
    static func save(_ url: URL, to defaults: UserDefaults = .standard) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: SettingsKey.vaultBookmark)
    }

    /// Resolves the saved bookmark, refreshing it if the OS marks it stale.
    /// Caller takes ownership of the security scope — long-running apps just
    /// hold it for the lifetime of the process.
    static func resolve(from defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: SettingsKey.vaultBookmark) else { return nil }
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            NSLog("[Noter] could not resolve vault bookmark: \(error)")
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else {
            NSLog("[Noter] startAccessingSecurityScopedResource returned false")
            return nil
        }
        if isStale {
            try? save(url, to: defaults)
        }
        return url
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: SettingsKey.vaultBookmark)
    }
}
