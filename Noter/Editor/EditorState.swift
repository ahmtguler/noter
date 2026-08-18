import Combine
import Foundation

/// Drives the editor view: holds the body being edited, the URL it belongs to,
/// and debounces saves so disk writes are coalesced ~500ms after the last edit.
///
/// Saving is keyed on the URL captured at the time the body changed — if the
/// user switches notes mid-save, the in-flight write still goes to the right file.
///
/// Supports a "draft" mode (currentNote is nil) where the editor shows a blank
/// canvas without writing anything to disk. The first non-empty save promotes
/// the draft to a real note in the store.
@MainActor
final class EditorState: ObservableObject {
    @Published var body: String = ""
    @Published private(set) var currentNote: Note?

    private let store: NoteStore
    private var cancellables = Set<AnyCancellable>()
    private var lastPersistedSnapshot: Snapshot?

    init(store: NoteStore) {
        self.store = store
        observeChanges()
    }

    func open(_ note: Note) {
        flush()
        adopt(note)
    }

    /// Switch to a blank in-memory draft. Nothing is written to disk until the
    /// user types something and the autosave debounce fires.
    func startBlankDraft() {
        flush()
        adopt(nil)
    }

    /// Deletes `note`, then moves the editor on if it was the open one.
    ///
    /// Order is the whole point. Callers used to delete first and switch notes
    /// afterwards, but `open`/`startBlankDraft` flush on entry, so that flush
    /// persisted the in-flight body back to the deleted note's original path.
    /// The file reappeared in the live vault, untracked by the store — invisible
    /// for the rest of the session, then listed again on the next launch as if
    /// the delete never happened.
    ///
    /// Returns the note the editor moved to, or nil if it fell back to a draft.
    @discardableResult
    func delete(_ note: Note) throws -> Note? {
        let wasOpen = currentNote?.url == note.url
        flush()
        // Flushing can rename the open note, which invalidates the URL the
        // caller handed us, so re-resolve the target after persisting.
        let target = wasOpen ? (currentNote?.url ?? note.url) : note.url
        try store.delete(target)
        guard wasOpen else { return currentNote }
        adopt(store.notes.first)
        return currentNote
    }

    /// Re-points the editor at the store's copy of the open note after the
    /// store has been reloaded from disk.
    ///
    /// Callers flush before reloading, so the editor's own edits are already on
    /// disk by this point and anything that still differs came from outside
    /// Noter — Obsidian, or a sync client. That version wins, otherwise the
    /// next autosave would overwrite it with Noter's stale in-memory copy.
    func resyncWithStore() {
        guard let current = currentNote else { return }
        guard let fresh = store.notes.first(where: { $0.url == current.url }) else {
            // The open note was deleted or moved outside Noter.
            adopt(store.notes.first)
            return
        }
        guard fresh.body != body else {
            // Same content; just refresh the metadata.
            currentNote = fresh
            return
        }
        adopt(fresh)
    }

    /// Points the editor at `note`, or at a blank draft when nil, *without*
    /// flushing. `open` and `startBlankDraft` flush before calling this;
    /// `delete` must not, because the note being left no longer exists.
    private func adopt(_ note: Note?) {
        currentNote = note
        body = note?.body ?? ""
        lastPersistedSnapshot = note.map { Snapshot(url: $0.url, body: $0.body) }
        if let note {
            store.markOpened(note.url)
        }
    }

    /// Persist any pending edits synchronously. Call when switching notes,
    /// hiding the panel, or terminating the app.
    func flush() {
        persistIfNeeded(body: body)
    }

    private func observeChanges() {
        $body
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] body in
                self?.persistIfNeeded(body: body)
            }
            .store(in: &cancellables)
    }

    private func persistIfNeeded(body: String) {
        if let note = currentNote {
            persist(body: body, at: note.url)
        } else if !body.isEmpty {
            promoteDraftToNote(body: body)
        }
    }

    private func persist(body: String, at url: URL) {
        guard lastPersistedSnapshot != Snapshot(url: url, body: body) else { return }
        do {
            let newURL = try store.save(body, at: url)
            lastPersistedSnapshot = Snapshot(url: newURL, body: body)
            if newURL != url, let updated = store.notes.first(where: { $0.url == newURL }) {
                currentNote = updated
            }
        } catch {
            NSLog("[Noter] autosave failed: \(error)")
        }
    }

    private func promoteDraftToNote(body: String) {
        do {
            let note = try store.createNote(initialBody: body)
            currentNote = note
            lastPersistedSnapshot = Snapshot(url: note.url, body: body)
        } catch {
            NSLog("[Noter] could not promote draft: \(error)")
        }
    }

    private struct Snapshot: Equatable {
        let url: URL
        let body: String
    }
}
