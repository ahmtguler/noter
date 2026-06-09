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

    public func codeBlock() {
        exec(.codeBlock)
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
        // AppKit first: claim window first-responder. The JS exec then sets the
        // DOM caret/focus inside CodeMirror. Either alone is insufficient when
        // another view (an overlay field, the re-shown window) held focus.
        bridge?.makeWebViewFirstResponder()
        exec(.focus)
    }

    /// Suppress (or restore) the editor's text cursor. Call with `true` while a
    /// host overlay covers the editor: the web content then reports the default
    /// arrow instead of an I-beam, so the WKWebView no longer fights the
    /// overlay's cursor. Sent outside `exec` so it never steals first responder
    /// from the overlay. Pair every `true` with a `false` on dismissal.
    public func setCursorSuppressed(_ suppressed: Bool) {
        bridge?.send(.setCursorSuppressed(suppressed))
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
