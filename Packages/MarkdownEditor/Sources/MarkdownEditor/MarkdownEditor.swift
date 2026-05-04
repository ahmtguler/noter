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

    public init(
        text: Binding<String>,
        configuration: EditorConfiguration = .default,
        onCommandsReady: ((MarkdownCommands) -> Void)? = nil
    ) {
        _text = text
        self.configuration = configuration
        self.onCommandsReady = onCommandsReady
    }

    public var body: some View {
        EditorWebView(
            text: $text,
            configuration: configuration,
            onCommandsReady: onCommandsReady
        )
    }
}
