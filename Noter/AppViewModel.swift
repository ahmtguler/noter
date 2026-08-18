import Combine
import Foundation

/// Owns the live `NoteStore` and `EditorState`, and can swap them when the user
/// changes the vault folder in Preferences. Views observe this object and
/// reactively re-render when the underlying store changes.
@MainActor
final class AppViewModel: ObservableObject {
    @Published var store: NoteStore
    @Published var editor: EditorState

    private var defaults: UserDefaults

    init(defaults: UserDefaults = .standard) throws {
        self.defaults = defaults
        let folder = try Vault.notesFolder(defaults: defaults)
        let store = try NoteStore(folder: folder)
        self.store = store
        editor = EditorState(store: store)
    }

    /// Picks up changes made to the vault outside Noter.
    ///
    /// `NoteStore.notes` was only ever populated in `init` and maintained
    /// purely in memory afterwards — there is no file-system watcher. For an
    /// app whose whole point is sharing an Obsidian vault, that meant a note
    /// edited in Obsidian while Noter ran stayed invisible for the rest of the
    /// session, and the next in-app save silently overwrote it with Noter's
    /// stale copy. Called when the popup is about to appear, which is the
    /// cheapest moment that reliably precedes the user reading or editing.
    func refreshFromDisk() {
        // Flush first so the editor's pending edits are on disk before the
        // reload reads it back; otherwise resync would treat them as an
        // external change and discard them.
        editor.flush()
        do {
            try store.reload()
        } catch {
            NSLog("[Noter] vault refresh failed: \(error)")
            return
        }
        editor.resyncWithStore()
    }

    /// Re-resolves the vault folder and rebuilds store + editor. Called after the
    /// user picks a new vault path or changes the subfolder in Preferences.
    func reloadVault() {
        editor.flush()
        do {
            let folder = try Vault.notesFolder(defaults: defaults)
            let newStore = try NoteStore(folder: folder)
            store = newStore
            editor = EditorState(store: newStore)
        } catch {
            NSLog("[Noter] failed to reload vault: \(error)")
        }
    }
}
