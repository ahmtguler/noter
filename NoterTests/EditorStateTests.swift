import Foundation
@testable import Noter
import Testing

/// Covers the save/rename/delete path, which had no tests despite owning every
/// write to the user's vault.
///
/// The autosave debounce is 500ms on the main queue, so a `body` assignment in
/// a synchronous test leaves a *pending, unpersisted* edit — exactly the window
/// the delete-ordering bug lived in. Tests rely on that rather than waiting.
@MainActor
struct EditorStateTests {
    // MARK: - Saving

    @Test
    func openLoadsBodyAndTracksTheNote() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            let note = try store.createNote(initialBody: "# Hello")

            editor.open(note)

            #expect(editor.body == "# Hello")
            #expect(editor.currentNote?.url == note.url)
        }
    }

    @Test
    func flushPersistsAPendingEdit() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            let note = try store.createNote(initialBody: "# Hello")
            editor.open(note)

            editor.body = "# Hello\n\nnew paragraph"
            editor.flush()

            let onDisk = try String(contentsOf: note.url, encoding: .utf8)
            #expect(onDisk.contains("new paragraph"))
        }
    }

    @Test
    func flushRenamesWhenTheFirstLineChanges() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            let note = try store.createNote(initialBody: "# Old title")
            editor.open(note)

            editor.body = "# New title"
            editor.flush()

            #expect(editor.currentNote?.url.lastPathComponent == "New title.md")
            #expect(!FileManager.default.fileExists(atPath: note.url.path))
        }
    }

    @Test
    func blankDraftWritesNothingUntilItHasContent() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)

            editor.startBlankDraft()
            editor.flush()

            #expect(editor.currentNote == nil)
            #expect(store.notes.isEmpty)
        }
    }

    @Test
    func draftBecomesARealNoteOnFirstNonEmptyFlush() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            editor.startBlankDraft()

            editor.body = "# Promoted"
            editor.flush()

            #expect(store.notes.count == 1)
            #expect(editor.currentNote?.url.lastPathComponent == "Promoted.md")
        }
    }

    // MARK: - Deleting

    /// Regression: deleting the open note within the autosave window used to
    /// resurrect it. `delete` ran first, then `open`/`startBlankDraft` flushed
    /// the still-pending body back to the deleted note's original path —
    /// recreating the file in the live vault, untracked by the store.
    @Test
    func deletingTheOpenNoteWithAPendingEditDoesNotResurrectIt() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            let note = try store.createNote(initialBody: "# Keep")
            editor.open(note)

            // Pending edit: same slug, so no rename — only a body change.
            editor.body = "# Keep\n\nedited just before deleting"
            try editor.delete(note)

            #expect(!FileManager.default.fileExists(atPath: note.url.path))
            #expect(store.notes.isEmpty)
        }
    }

    /// The flush that now precedes the delete can rename the file, which
    /// invalidates the URL the caller passed in. The delete has to follow it.
    @Test
    func deletingAfterATitleEditRemovesTheRenamedFile() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            let note = try store.createNote(initialBody: "# Old")
            editor.open(note)

            editor.body = "# Renamed before delete"
            try editor.delete(note)

            let renamed = folder.appendingPathComponent("Renamed before delete.md")
            #expect(!FileManager.default.fileExists(atPath: note.url.path))
            #expect(!FileManager.default.fileExists(atPath: renamed.path))
            #expect(store.notes.isEmpty)
        }
    }

    /// The delete is a soft delete, so the pending edit should survive in trash
    /// rather than being silently dropped.
    @Test
    func theTrashedCopyKeepsThePendingEdit() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            let note = try store.createNote(initialBody: "# Keep")
            editor.open(note)

            editor.body = "# Keep\n\nedited just before deleting"
            try editor.delete(note)

            let trashed = store.trashedNotes()
            #expect(trashed.count == 1)
            #expect(trashed.first?.body.contains("edited just before deleting") == true)
        }
    }

    @Test
    func deletingTheOpenNoteMovesToTheNextOne() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            let first = try store.createNote(initialBody: "# First")
            _ = try store.createNote(initialBody: "# Second")
            editor.open(first)

            try editor.delete(first)

            #expect(editor.currentNote != nil)
            #expect(editor.currentNote?.url != first.url)
            #expect(editor.body.contains("Second"))
        }
    }

    @Test
    func deletingTheLastNoteFallsBackToABlankDraft() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            let only = try store.createNote(initialBody: "# Only")
            editor.open(only)

            try editor.delete(only)

            #expect(editor.currentNote == nil)
            #expect(editor.body.isEmpty)
            #expect(store.notes.isEmpty)
        }
    }

    /// Deleting a note from the ⌘P list while a *different* note is open must
    /// not disturb the open one.
    @Test
    func deletingAnUnopenedNoteLeavesTheOpenNoteAlone() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            let open = try store.createNote(initialBody: "# Open")
            let other = try store.createNote(initialBody: "# Other")
            editor.open(open)

            try editor.delete(other)

            #expect(editor.currentNote?.url == open.url)
            #expect(editor.body == "# Open")
            #expect(FileManager.default.fileExists(atPath: open.url.path))
        }
    }

    /// A pending edit to the open note must still reach disk when some other
    /// note is the one being deleted.
    @Test
    func deletingAnUnopenedNotePersistsThePendingEdit() throws {
        try withTempFolder { folder in
            let store = try NoteStore(folder: folder)
            let editor = EditorState(store: store)
            let open = try store.createNote(initialBody: "# Open")
            let other = try store.createNote(initialBody: "# Other")
            editor.open(open)

            editor.body = "# Open\n\nstill being typed"
            try editor.delete(other)

            let onDisk = try String(contentsOf: open.url, encoding: .utf8)
            #expect(onDisk.contains("still being typed"))
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
