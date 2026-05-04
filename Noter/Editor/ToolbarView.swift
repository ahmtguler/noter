import SwiftUI

/// Bottom toolbar with markdown formatting shortcuts. Matches the style of the
/// Raycast Notes screenshot — compact icon buttons, mostly insert-syntax actions.
struct ToolbarView: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            iconButton("h.square", help: "Heading") { wrapLinePrefix("# ") }
            iconButton("bold", help: "Bold") { wrapInline("**") }
            iconButton("italic", help: "Italic") { wrapInline("*") }
            iconButton("list.bullet", help: "Bullet list") { wrapLinePrefix("- ") }
            iconButton("list.number", help: "Numbered list") { wrapLinePrefix("1. ") }
            iconButton("quote.opening", help: "Quote") { wrapLinePrefix("> ") }
            iconButton("chevron.left.forwardslash.chevron.right", help: "Inline code") { wrapInline("`") }
            iconButton("link", help: "Link") { insert("[]()") }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func wrapInline(_ marker: String) {
        text += marker + marker
    }

    private func wrapLinePrefix(_ prefix: String) {
        if text.isEmpty || text.hasSuffix("\n") {
            text += prefix
        } else {
            text += "\n" + prefix
        }
    }

    private func insert(_ snippet: String) {
        text += snippet
    }
}
