import Foundation
@testable import Noter
import Testing

@MainActor
struct NoteStoreTests {
    @Test
    func createsNoteAndPersistsToDisk() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let note = try store.createNote(initialBody: "# Hello")
            #expect(FileManager.default.fileExists(atPath: note.url.path))
            #expect(note.url.lastPathComponent == "Hello.md")
            #expect(store.notes.count == 1)
        }
    }

    @Test
    func saveRenamesOnFirstLineChange() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let note = try store.createNote(initialBody: "# Old title")
            let newURL = try store.save("# New title\n\nbody", at: note.url)
            #expect(newURL.lastPathComponent == "New title.md")
            #expect(!FileManager.default.fileExists(atPath: note.url.path))
            #expect(FileManager.default.fileExists(atPath: newURL.path))
            #expect(store.notes.first?.url == newURL)
        }
    }

    @Test
    func saveWithoutSlugChangeKeepsFilename() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let note = try store.createNote(initialBody: "# Stable")
            let newURL = try store.save("# Stable\n\nmore body", at: note.url)
            #expect(newURL == note.url)
            #expect(store.notes.first?.body.contains("more body") == true)
        }
    }

    @Test
    func renameDedupesWithCounter() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let first = try store.createNote(initialBody: "# Same")
            let second = try store.createNote(initialBody: "# Other")
            let renamed = try store.save("# Same\n\nbody", at: second.url)
            #expect(renamed.lastPathComponent == "Same 2.md")
            #expect(FileManager.default.fileExists(atPath: first.url.path))
            #expect(FileManager.default.fileExists(atPath: renamed.path))
        }
    }

    @Test
    func reloadDiscoversExistingFiles() throws {
        try withTempFolder { folder in
            try "# A".write(to: folder.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
            try "# B".write(to: folder.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
            try "ignore".write(to: folder.appendingPathComponent("Other.txt"), atomically: true, encoding: .utf8)
            let store = try NoteStore(folder: folder)
            #expect(store.notes.count == 2)
        }
    }

    @Test
    func deleteRemovesFileAndNote() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let note = try store.createNote(initialBody: "X")
            try store.delete(note.url)
            #expect(!FileManager.default.fileExists(atPath: note.url.path))
            #expect(store.notes.isEmpty)
        }
    }

    @Test
    func emptyBodyUsesUntitledFilename() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let note = try store.createNote(initialBody: "")
            #expect(note.url.lastPathComponent == "Untitled.md")
        }
    }
}

@MainActor
private func withTempFolder(_ work: (URL) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("NoterTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    try work(url)
}
