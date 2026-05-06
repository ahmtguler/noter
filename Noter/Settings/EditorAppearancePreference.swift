import AppKit
import Foundation
import MarkdownEditor
import SwiftUI

/// User-facing choice for the editor's appearance. Persisted as the rawValue
/// of this enum via `@AppStorage(SettingsKey.editorTheme)`.
enum EditorAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Maps to the package's `EditorConfiguration.Theme`.
    var editorTheme: EditorConfiguration.Theme {
        switch self {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
    }

    /// Maps to a SwiftUI `ColorScheme?` (`nil` for system).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Maps to an `NSAppearance` (`nil` for system).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
