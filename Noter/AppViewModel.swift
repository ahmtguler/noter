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
