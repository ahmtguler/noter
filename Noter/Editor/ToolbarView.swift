import AppKit
import SwiftUI

/// Bottom formatting toolbar. Each control invokes `EditorCommands` so it
/// operates on the current selection. Active styles are indicated by a
/// brighter (full-label-color) tint instead of an accent-color highlight.
struct ToolbarView: View {
    @ObservedObject var commands: EditorCommands

    var body: some View {
        HStack(spacing: 2) {
            headingButton(level: 1, label: "H1")
            headingButton(level: 2, label: "H2")
            headingButton(level: 3, label: "H3")
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
        .padding(.vertical, 6)
        .frame(height: 36)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private var divider: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private func headingButton(level: Int, label: String) -> some View {
        ToolbarTextButton(
            title: label,
            tooltip: "Heading \(level) (⌥⌘\(level))",
            isActive: commands.activeStyles.contains(.heading(level))
        ) {
            commands.setHeading(level: level)
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

private let activeColor = NSColor.labelColor
private let inactiveColor = NSColor.secondaryLabelColor.withAlphaComponent(0.7)

/// `NSButton` subclass that refuses to become first responder. Without this,
/// clicking a toolbar button shifts the window's first responder to the button,
/// dropping the text-view selection. Keeping focus on the editor lets every
/// command operate on the active selection.
final class FocusPreservingButton: NSButton {
    override var refusesFirstResponder: Bool {
        get { true }
        set {}
    }

    override var acceptsFirstResponder: Bool {
        false
    }
}

/// Borderless icon button with an explicit `toolTip` set on the underlying
/// NSButton — SwiftUI's `.help()` wasn't reliably materialising on borderless
/// buttons in the macOS 26 builds we tested.
private struct ToolbarIconButton: NSViewRepresentable {
    let symbol: String
    let tooltip: String
    let isActive: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = FocusPreservingButton()
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.click)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 22)
        ])
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.toolTip = tooltip
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        button.image = symbolImage
        button.contentTintColor = isActive ? activeColor : inactiveColor
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

/// Same as `ToolbarIconButton` but renders a short text title (H1 / H2 / H3)
/// instead of an SF Symbol.
private struct ToolbarTextButton: NSViewRepresentable {
    let title: String
    let tooltip: String
    let isActive: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = FocusPreservingButton()
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.click)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 22)
        ])
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.toolTip = tooltip
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: isActive ? activeColor : inactiveColor
        ]
        button.attributedTitle = NSAttributedString(string: title, attributes: attrs)
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
