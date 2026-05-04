import Combine
import Foundation

/// Owns the in-memory list of notes and persists them as `.md` files in `folder`.
/// All mutations are synchronous; debouncing is the caller's responsibility.
@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []

    let folder: URL
    private let fileManager: FileManager

    init(folder: URL, fileManager: FileManager = .default) throws {
        self.folder = folder
        self.fileManager = fileManager
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try reload()
    }

    func reload() throws {
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
        return finalURL
    }

    func markOpened(_ url: URL) {
        guard let index = notes.firstIndex(where: { $0.url == url }) else { return }
        notes[index].openedAt = Date()
    }

    func delete(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        notes.removeAll { $0.url == url }
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
