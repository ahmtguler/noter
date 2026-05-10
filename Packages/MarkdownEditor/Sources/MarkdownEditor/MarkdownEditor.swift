import SwiftUI

/// SwiftUI view embedding a WKWebView-hosted CodeMirror 6 markdown editor.
///
/// Bind a `String` to `text`; the binding is the source of truth. Provide an
/// optional `onCommandsReady` callback to receive the `MarkdownCommands` object
/// once the editor finishes loading — wire that into a toolbar to drive
/// formatting (`commands.bold()` etc.).
public struct MarkdownEditor: View {
    @Binding public var text: String
    public var configuration: EditorConfiguration
    public var onCommandsReady: ((MarkdownCommands) -> Void)?
    /// Called when the user clicks a link inside the editor. The host is
    /// responsible for actually opening the URL — the WKWebView never
    /// navigates itself.
    public var onOpenURL: ((String) -> Void)?

    /// Drives the in-editor link popover. Owned by the package so the popover
    /// stays inside this view's bounds and never escapes into a separate
    /// AppKit window.
    @StateObject private var linkState = LinkPopoverState()

    public init(
        text: Binding<String>,
        configuration: EditorConfiguration = .default,
        onCommandsReady: ((MarkdownCommands) -> Void)? = nil,
        onOpenURL: ((String) -> Void)? = nil
    ) {
        _text = text
        self.configuration = configuration
        self.onCommandsReady = onCommandsReady
        self.onOpenURL = onOpenURL
    }

    public var body: some View {
        EditorWebView(
            text: $text,
            configuration: configuration,
            onCommandsReady: onCommandsReady,
            onOpenURL: onOpenURL,
            linkState: linkState
        )
        .overlay(LinkPopoverOverlay(state: linkState))
    }
}
