import Foundation

/// User-facing knobs that survive the lifetime of the view. Pushed across the
/// bridge as JSON whenever the value changes.
public struct EditorConfiguration: Equatable, Codable {
    public enum Theme: String, Codable {
        case system
        case light
        case dark
    }

    // `smartListContinuation`, `revealMarkersOnCursor` and `contentPadding`
    // used to live here. They were public, documented, serialized across the
    // bridge on every config push — and read by nothing on the JS side. List
    // continuation works regardless, because `markdown({ addKeymap: true })`
    // wires CodeMirror's own Enter handling unconditionally, so the flag never
    // controlled it in either direction. Removed rather than implemented: the
    // package's public surface is meant to stay small, and a knob that silently
    // does nothing is worse than no knob.
    public var theme: Theme
    public var fontSize: Double
    public var spellCheck: Bool
    public var lineWrap: Bool

    public init(
        theme: Theme = .system,
        fontSize: Double = 14,
        spellCheck: Bool = true,
        lineWrap: Bool = true
    ) {
        self.theme = theme
        self.fontSize = fontSize
        self.spellCheck = spellCheck
        self.lineWrap = lineWrap
    }

    public static let `default` = EditorConfiguration()
}
