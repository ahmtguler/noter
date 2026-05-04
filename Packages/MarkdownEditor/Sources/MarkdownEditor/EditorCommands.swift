import Combine
import Foundation

/// Public command surface for toolbars. All methods send a message across the
/// bridge to the underlying CodeMirror view. `activeStyles` reflects what's in
/// effect at the caret and is updated by `selectionChanged` messages from JS.
@MainActor
public final class MarkdownCommands: ObservableObject {
    @Published public internal(set) var activeStyles: Set<MarkdownStyle> = []

    var bridge: EditorBridge?

    public init() {}

    public func bold() {
        exec(.bold)
    }

    public func italic() {
        exec(.italic)
    }

    public func underline() {
        exec(.underline)
    }

    public func strikethrough() {
        exec(.strikethrough)
    }

    public func code() {
        exec(.code)
    }

    public func heading(_ level: Int) {
        exec(.heading, arg: String(level))
    }

    public func bulletList() {
        exec(.bulletList)
    }

    public func numberedList() {
        exec(.numberedList)
    }

    public func todo() {
        exec(.todo)
    }

    public func quote() {
        exec(.quote)
    }

    public func link() {
        exec(.link)
    }

    public func focus() {
        exec(.focus)
    }

    private func exec(_ command: BridgeCommand, arg: String? = nil) {
        bridge?.send(.execute(command: command, arg: arg))
    }
}

public enum MarkdownStyle: String, Hashable, Codable, Sendable {
    case heading1, heading2, heading3
    case bold
    case italic
    case underline
    case strikethrough
    case code
    case bulletList
    case numberedList
    case todoList
    case quote
}
