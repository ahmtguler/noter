import SwiftUI

/// Bottom formatting toolbar. Each control invokes `EditorCommands` so it
/// operates on the current selection. Buttons highlight when the matching
/// style applies to the caret position.
struct ToolbarView: View {
    @ObservedObject var commands: EditorCommands

    var body: some View {
        HStack(spacing: 2) {
            headingMenu
            divider
            iconButton(
                "bold",
                help: "Bold (⌘B)",
                isActive: commands.activeStyles.contains(.bold)
            ) { commands.wrap(prefix: "**") }
            iconButton(
                "italic",
                help: "Italic (⌘I)",
                isActive: commands.activeStyles.contains(.italic)
            ) { commands.wrap(prefix: "*") }
            iconButton(
                "underline",
                help: "Underline (⌘U)",
                isActive: commands.activeStyles.contains(.underline)
            ) { commands.wrap(prefix: "<u>", suffix: "</u>") }
            iconButton(
                "strikethrough",
                help: "Strikethrough (⇧⌘X)",
                isActive: commands.activeStyles.contains(.strikethrough)
            ) { commands.wrap(prefix: "~~") }
            iconButton(
                "chevron.left.forwardslash.chevron.right",
                help: "Inline code",
                isActive: commands.activeStyles.contains(.code)
            ) { commands.wrap(prefix: "`") }
            divider
            iconButton(
                "list.bullet",
                help: "Bullet list (⇧⌘8)",
                isActive: commands.activeStyles.contains(.bulletList)
            ) { commands.toggleLinePrefix("- ") }
            iconButton(
                "list.number",
                help: "Numbered list (⇧⌘7)",
                isActive: commands.activeStyles.contains(.numberedList)
            ) { commands.toggleLinePrefix("1. ") }
            iconButton(
                "checklist",
                help: "To-do (⇧⌘T)",
                isActive: commands.activeStyles.contains(.todoList)
            ) { commands.insertTodo() }
            iconButton(
                "quote.opening",
                help: "Quote (⇧⌘9)",
                isActive: commands.activeStyles.contains(.quote)
            ) { commands.toggleLinePrefix("> ") }
            divider
            iconButton(
                "link",
                help: "Link (⌘K)",
                isActive: false
            ) { commands.insertLink() }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private var divider: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private var headingMenu: some View {
        Menu {
            Button("Heading 1") { commands.setHeading(level: 1) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Heading 2") { commands.setHeading(level: 2) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Heading 3") { commands.setHeading(level: 3) }
                .keyboardShortcut("3", modifiers: [.command, .option])
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "textformat.size")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(headingActive ? AnyShapeStyle(Color.accentColor) :
                AnyShapeStyle(HierarchicalShapeStyle.secondary))
            .frame(width: 36, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Heading level")
    }

    private var headingActive: Bool {
        commands.activeStyles.contains { style in
            if case .heading = style { return true }
            return false
        }
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ToolbarIconButton(
            symbol: symbol,
            tooltip: help,
            isActive: isActive,
            action: action
        )
    }
}

/// Borderless icon button with an explicit `toolTip` set on the underlying
/// NSButton — SwiftUI's `.help()` doesn't always materialise on borderless
/// buttons in macOS 26 builds we've seen.
private struct ToolbarIconButton: NSViewRepresentable {
    let symbol: String
    let tooltip: String
    let isActive: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.click)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.toolTip = tooltip
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        button.image = symbolImage
        button.contentTintColor = isActive ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        button.setFrameSize(NSSize(width: 28, height: 22))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func click() {
            action()
        }
    }
}
