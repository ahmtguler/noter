import SwiftUI

/// Bottom formatting toolbar. Each control invokes `EditorCommands` so it
/// operates on the current selection, just like keyboard shortcuts.
struct ToolbarView: View {
    let commands: EditorCommands

    var body: some View {
        HStack(spacing: 2) {
            headingMenu
            Divider().frame(height: 16)
            iconButton("bold", help: "Bold (⌘B)") { commands.wrap(prefix: "**") }
            iconButton("italic", help: "Italic (⌘I)") { commands.wrap(prefix: "*") }
            iconButton("underline", help: "Underline (⌘U)") {
                commands.wrap(prefix: "<u>", suffix: "</u>")
            }
            iconButton("strikethrough", help: "Strikethrough (⇧⌘X)") {
                commands.wrap(prefix: "~~")
            }
            iconButton("chevron.left.forwardslash.chevron.right", help: "Inline code") {
                commands.wrap(prefix: "`")
            }
            Divider().frame(height: 16)
            iconButton("list.bullet", help: "Bullet list (⇧⌘8)") {
                commands.toggleLinePrefix("- ")
            }
            iconButton("list.number", help: "Numbered list (⇧⌘7)") {
                commands.toggleLinePrefix("1. ")
            }
            iconButton("checklist", help: "To-do (⇧⌘T)") {
                commands.insertTodo()
            }
            iconButton("quote.opening", help: "Quote (⇧⌘9)") {
                commands.toggleLinePrefix("> ")
            }
            Divider().frame(height: 16)
            iconButton("link", help: "Link (⌘K)") { commands.insertLink() }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private var headingMenu: some View {
        Menu {
            ForEach(1 ... 6, id: \.self) { level in
                Button("Heading \(level)") { commands.setHeading(level: level) }
                    .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: [.command, .option])
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "textformat.size")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Heading level")
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
}
