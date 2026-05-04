import Foundation

/// Centralised UserDefaults key strings so we don't sprinkle stringly-typed keys
/// throughout the codebase.
enum SettingsKey {
    static let vaultBookmark = "noter.vaultBookmark"
    static let subfolder = "noter.subfolder"
    static let popupFrame = "noter.popupFrame"
    static let pinned = "noter.pinned"
    static let currentNoteURL = "noter.currentNoteURL"
    static let didOnboard = "noter.didOnboard"
    static let idleNewNoteMinutes = "noter.idleNewNoteMinutes"

    static let defaultSubfolder = "Quick Notes"
    /// 0 disables the idle reset; otherwise: minutes the panel must have been
    /// hidden before the next show starts a fresh blank draft.
    static let defaultIdleNewNoteMinutes = 10
}
