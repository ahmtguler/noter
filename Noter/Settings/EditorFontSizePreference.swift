import Foundation

/// User-facing choice for the editor's body font size. Headings scale with
/// the body size via em-based rules in the editor's CodeMirror theme, so this
/// single value controls overall reading size.
enum EditorFontSizePreference: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var pointSize: Double {
        switch self {
        case .small: 14
        case .medium: 16
        case .large: 18
        }
    }
}
