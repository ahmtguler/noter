import Combine
import Foundation

/// Owns the in-memory list of notes and persists them as `.md` files in `folder`.
/// All mutations are synchronous; debouncing is the caller's responsibility.
@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    /// Set of pinned-note file paths. Mirrored to UserDefaults under
    /// `SettingsKey.pinnedNotes` so the choice survives across launches.
    @Published private(set) var pinnedPaths: Set<String> = []

    let folder: URL
    private let fileManager: FileManager
    private let defaults: UserDefaults

    init(
        folder: URL,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) throws {
        self.folder = folder
        self.fileManager = fileManager
        self.defaults = defaults
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        purgeExpiredTrash()
        let paths = (defaults.array(forKey: SettingsKey.pinnedNotes) as? [String]) ?? []
        pinnedPaths = Set(paths)
        try reload()
    }

    /// Sibling folder that holds soft-deleted notes for `trashTTL` before
    /// being permanently removed. Sibling — not nested — so the user can
    /// see/manage it in Obsidian if they want, and so Obsidian doesn't
    /// re-index trashed notes as live ones.
    var trashFolder: URL {
        folder.deletingLastPathComponent().appendingPathComponent("Recently Deleted")
    }

    /// How long a soft-deleted note lives in `trashFolder` before being
    /// permanently removed. 14 days.
    private let trashTTL: TimeInterval = 14 * 24 * 60 * 60

    func reload() throws {
        purgeExpiredTrash()
        let contents = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        notes = contents
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url in
                guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return Note(url: url, body: body, modifiedAt: modifiedAt, openedAt: nil)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    @discardableResult
    func createNote(initialBody: String = "") throws -> Note {
        let url = uniqueURL(for: Slugify.filename(from: initialBody))
        try initialBody.write(to: url, atomically: true, encoding: .utf8)
        let note = Note(url: url, body: initialBody, modifiedAt: Date(), openedAt: Date())
        notes.insert(note, at: 0)
        return note
    }

    /// Saves `body` for the note currently at `url`. If the slug derived from the new body
    /// differs from the current filename, the file is renamed (with collision suffixes).
    /// Returns the final URL of the note after any rename.
    @discardableResult
    func save(_ body: String, at url: URL) throws -> URL {
        let desiredSlug = Slugify.filename(from: body)
        let currentSlug = url.deletingPathExtension().lastPathComponent
        let finalURL: URL = if desiredSlug == currentSlug {
            url
        } else {
            uniqueURL(for: desiredSlug, excluding: url)
        }

        try body.write(to: finalURL, atomically: true, encoding: .utf8)
        if finalURL != url, fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        if let index = notes.firstIndex(where: { $0.url == url }) {
            notes[index].url = finalURL
            notes[index].body = body
            notes[index].modifiedAt = Date()
        }
        if finalURL != url, pinnedPaths.remove(url.path) != nil {
            pinnedPaths.insert(finalURL.path)
            persistPins()
        }
        return finalURL
    }

    func markOpened(_ url: URL) {
        guard let index = notes.firstIndex(where: { $0.url == url }) else { return }
        notes[index].openedAt = Date()
    }

    /// Soft-delete: moves the note to `Recently Deleted/`. The file's mtime
    /// is set to "now" by the move (or by an explicit touch if the move
    /// didn't update it on this filesystem) — that timestamp is what the
    /// 14-day purge reads. Note: file already gone from disk → idempotent.
    func delete(_ url: URL) throws {
        try fileManager.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let dest = uniqueTrashURL(for: url.lastPathComponent)
            try fileManager.moveItem(at: url, to: dest)
            // Stamp the trash file's mtime so the TTL counts from "deleted at".
            try? fileManager.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: dest.path
            )
        }
        notes.removeAll { $0.url == url }
        if pinnedPaths.remove(url.path) != nil {
            persistPins()
        }
    }

    /// Removes any file in `trashFolder` whose mtime is older than `trashTTL`.
    /// Called on init and from `reload()` so it runs at every panel show.
    func purgeExpiredTrash() {
        guard fileManager.fileExists(atPath: trashFolder.path) else { return }
        let cutoff = Date().addingTimeInterval(-trashTTL)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: trashFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for item in contents {
            let mtime = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let mtime else { continue }
            if mtime < cutoff {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    private func uniqueTrashURL(for filename: String) -> URL {
        let base = trashFolder.appendingPathComponent(filename)
        if !fileManager.fileExists(atPath: base.path) { return base }
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var counter = 2
        while true {
            let candidate = trashFolder.appendingPathComponent(
                ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            )
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    /// Creates a copy of the note's body as a new `.md` file. The new note
    /// gets a unique filename (suffix " 2", " 3", … if needed).
    @discardableResult
    func duplicate(_ url: URL) throws -> Note {
        guard let source = notes.first(where: { $0.url == url }) else {
            throw NSError(domain: "NoteStore", code: 1)
        }
        return try createNote(initialBody: source.body)
    }

    func isPinned(_ url: URL) -> Bool {
        pinnedPaths.contains(url.path)
    }

    func togglePin(_ url: URL) {
        if pinnedPaths.contains(url.path) {
            pinnedPaths.remove(url.path)
        } else {
            pinnedPaths.insert(url.path)
        }
        persistPins()
    }

    private func persistPins() {
        defaults.set(Array(pinnedPaths), forKey: SettingsKey.pinnedNotes)
    }

    private func uniqueURL(for slug: String, excluding existing: URL? = nil) -> URL {
        let base = folder.appendingPathComponent(slug).appendingPathExtension("md")
        if !fileManager.fileExists(atPath: base.path) || base == existing {
            return base
        }
        var counter = 2
        while true {
            let candidate = folder
                .appendingPathComponent("\(slug) \(counter)")
                .appendingPathExtension("md")
            if !fileManager.fileExists(atPath: candidate.path) || candidate == existing {
                return candidate
            }
            counter += 1
        }
    }
}
