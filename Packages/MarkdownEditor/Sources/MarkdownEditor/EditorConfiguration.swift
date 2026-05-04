import Foundation

/// User-facing knobs that survive the lifetime of the view. Pushed across the
/// bridge as JSON whenever the value changes.
public struct EditorConfiguration: Equatable, Codable {
    public enum Theme: String, Codable {
        case system
        case light
        case dark
    }

    public var theme: Theme
    public var fontSize: Double
    public var spellCheck: Bool
    public var smartListContinuation: Bool
    public var revealMarkersOnCursor: Bool
    public var lineWrap: Bool
    public var contentPadding: Double

    public init(
        theme: Theme = .system,
        fontSize: Double = 14,
        spellCheck: Bool = true,
        smartListContinuation: Bool = true,
        revealMarkersOnCursor: Bool = true,
        lineWrap: Bool = true,
        contentPadding: Double = 24
    ) {
        self.theme = theme
        self.fontSize = fontSize
        self.spellCheck = spellCheck
        self.smartListContinuation = smartListContinuation
        self.revealMarkersOnCursor = revealMarkersOnCursor
        self.lineWrap = lineWrap
        self.contentPadding = contentPadding
    }

    public static let `default` = EditorConfiguration()
}
