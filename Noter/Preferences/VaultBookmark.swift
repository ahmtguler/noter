import Foundation

/// Stores the vault folder URL as a security-scoped bookmark so the sandboxed
/// app can keep accessing it across launches without re-prompting the user.
///
/// Access is refcounted by the kernel and must be balanced. `resolve` used to
/// call `startAccessingSecurityScopedResource` on every invocation with no
/// matching stop anywhere in the app, and it was called far more often than
/// once per launch — every `reloadVault`, and every time the Preferences or
/// onboarding window appeared, purely to render a path string. The count only
/// ever grew, and switching vaults never released the old one.
///
/// So there are now two entry points: `resolve` acquires the scope and is the
/// one the app holds for its lifetime, while `displayPath` reads the location
/// without acquiring anything.
@MainActor
enum VaultBookmark {
    /// The URL whose security scope is currently held, so it can be released
    /// before acquiring a different one.
    private static var accessedURL: URL?

    static func save(_ url: URL, to defaults: UserDefaults = .standard) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: SettingsKey.vaultBookmark)
    }

    /// Resolves the saved bookmark and acquires its security scope, releasing
    /// any previously held scope first. Call this only when the app actually
    /// needs to read or write the vault.
    static func resolve(from defaults: UserDefaults = .standard) -> URL? {
        guard let url = resolvedURL(from: defaults) else { return nil }
        if let accessedURL {
            // Same vault as before: the scope is already held, and acquiring it
            // twice would need two releases.
            if accessedURL == url {
                return url
            }
            accessedURL.stopAccessingSecurityScopedResource()
            self.accessedURL = nil
        }
        guard url.startAccessingSecurityScopedResource() else {
            NSLog("[Noter] startAccessingSecurityScopedResource returned false")
            return nil
        }
        accessedURL = url
        return url
    }

    /// The vault's path for display, without acquiring the security scope.
    /// Safe to call from `onAppear` as often as the window is shown.
    static func displayPath(from defaults: UserDefaults = .standard) -> String? {
        resolvedURL(from: defaults)?.path
    }

    /// Releases the held scope, if any. The app holds it for its lifetime, so
    /// this exists for vault switches and for clearing the bookmark.
    static func releaseAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    static func clear(from defaults: UserDefaults = .standard) {
        releaseAccess()
        defaults.removeObject(forKey: SettingsKey.vaultBookmark)
    }

    /// Resolves the bookmark data to a URL, refreshing the stored bookmark if
    /// the OS reports it stale. Acquires nothing.
    private static func resolvedURL(from defaults: UserDefaults) -> URL? {
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
        if isStale {
            try? save(url, to: defaults)
        }
        return url
    }
}
