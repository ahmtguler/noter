import Foundation

/// Centralised UserDefaults key strings so we don't sprinkle stringly-typed keys
/// throughout the codebase.
enum SettingsKey {
    static let vaultBookmark = "noter.vaultBookmark"
    static let subfolder = "noter.subfolder"
    static let popupFrame = "noter.popupFrame"
    static let pinned = "noter.pinned"
    static let didOnboard = "noter.didOnboard"
    static let idleNewNoteMinutes = "noter.idleNewNoteMinutes"
    static let showFormattingToolbar = "noter.showFormattingToolbar"
    static let editorTheme = "noter.editorTheme"
    static let editorFontSize = "noter.editorFontSize"
    /// The user's intent for launching at login. `LoginItem` reconciles this
    /// against what SMAppService has actually registered — see the note there
    /// on why both exist.
    static let launchAtLogin = "noter.launchAtLogin"
    /// Array of file paths (strings) for pinned notes. Pinned notes sort to
    /// the top of the switcher.
    static let pinnedNotes = "noter.pinnedNotes"

    static let defaultSubfolder = "Quick Notes"
    static let defaultShowFormattingToolbar = true
    /// Stored as the rawValue of `EditorAppearancePreference` ("system" / "light" / "dark").
    static let defaultEditorTheme = "system"
    /// Stored as the rawValue of `EditorFontSizePreference` ("small" / "medium" / "large").
    static let defaultEditorFontSize = "medium"
    /// 0 disables the idle reset; otherwise: minutes the panel must have been
    /// hidden before the next show starts a fresh blank draft.
    static let defaultIdleNewNoteMinutes = 10
}
