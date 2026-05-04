import Combine
import Foundation

/// Drives the editor view: holds the body being edited, the URL it belongs to,
/// and debounces saves so disk writes are coalesced ~500ms after the last edit.
///
/// Saving is keyed on the URL captured at the time the body changed — if the
/// user switches notes mid-save, the in-flight write still goes to the right file.
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
        currentNote = note
        body = note.body
        lastPersistedSnapshot = Snapshot(url: note.url, body: note.body)
        store.markOpened(note.url)
    }

    /// Persist any pending edits synchronously. Call when switching notes,
    /// hiding the panel, or terminating the app.
    func flush() {
        guard let note = currentNote else { return }
        guard lastPersistedSnapshot?.body != body else { return }
        persist(body: body, at: note.url)
    }

    private func observeChanges() {
        $body
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] body in
                guard let self, let note = currentNote else { return }
                persist(body: body, at: note.url)
            }
            .store(in: &cancellables)
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

    private struct Snapshot: Equatable {
        let url: URL
        let body: String
    }
}
