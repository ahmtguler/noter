import AppKit
import MarkdownEditor
import SwiftUI

/// Bottom formatting toolbar. Each control invokes a method on
/// `MarkdownCommands` (provided by the editor package), which dispatches the
/// corresponding command into CodeMirror. Active styles light up at full
/// label color while inactive buttons sit at a dim secondary tint.
struct ToolbarView: View {
    @ObservedObject var commands: MarkdownCommands

    var body: some View {
        HStack(spacing: 2) {
            headingButton(level: 1, label: "H1", style: .heading1)
            headingButton(level: 2, label: "H2", style: .heading2)
            headingButton(level: 3, label: "H3", style: .heading3)
            divider
            iconButton("bold", help: "Bold (⌘B)", isActive: isActive(.bold)) {
                commands.bold()
            }
            iconButton("italic", help: "Italic (⌘I)", isActive: isActive(.italic)) {
                commands.italic()
            }
            iconButton("underline", help: "Underline (⌘U)", isActive: isActive(.underline)) {
                commands.underline()
            }
            iconButton(
                "strikethrough",
                help: "Strikethrough (⇧⌘X)",
                isActive: isActive(.strikethrough)
            ) {
                commands.strikethrough()
            }
            iconButton(
                "chevron.left.forwardslash.chevron.right",
                help: "Inline code",
                isActive: isActive(.code)
            ) {
                commands.code()
            }
            divider
            iconButton(
                "list.bullet",
                help: "Bullet list (⇧⌘8)",
                isActive: isActive(.bulletList)
            ) {
                commands.bulletList()
            }
            iconButton(
                "list.number",
                help: "Numbered list (⇧⌘7)",
                isActive: isActive(.numberedList)
            ) {
                commands.numberedList()
            }
            iconButton(
                "checklist",
                help: "To-do (⇧⌘T)",
                isActive: isActive(.todoList)
            ) {
                commands.todo()
            }
            iconButton(
                "quote.opening",
                help: "Quote (⇧⌘9)",
                isActive: isActive(.quote)
            ) {
                commands.quote()
            }
            divider
            iconButton("link", help: "Link (⌘K)", isActive: false) {
                commands.link()
            }
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

    private func isActive(_ style: MarkdownStyle) -> Bool {
        commands.activeStyles.contains(style)
    }

    private func headingButton(level: Int, label: String, style: MarkdownStyle) -> some View {
        ToolbarTextButton(
            title: label,
            tooltip: "Heading \(level) (⌥⌘\(level))",
            isActive: isActive(style)
        ) {
            commands.heading(level)
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
/// clicking a toolbar button shifts the window's first responder away from
/// the editor and drops the selection.
final class FocusPreservingButton: NSButton {
    override var refusesFirstResponder: Bool {
        get { true }
        set {}
    }

    override var acceptsFirstResponder: Bool {
        false
    }
}

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
