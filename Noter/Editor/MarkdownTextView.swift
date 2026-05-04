import AppKit

/// NSTextView that intercepts the standard markdown keyboard shortcuts and
/// dispatches them to `EditorCommands` instead of NSTextView's rich-text bold/italic
/// (which would silently no-op in a plain-text view).
final class MarkdownTextView: NSTextView {
    weak var commands: EditorCommands?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let commands, handle(event: event, with: commands) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func handle(event: NSEvent, with commands: EditorCommands) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }

        if modifiers == .command {
            return handleCommand(key: key, commands: commands)
        }
        if modifiers == [.command, .shift] {
            return handleCommandShift(key: key, commands: commands)
        }
        if modifiers == [.command, .option], let digit = Int(key), (1 ... 6).contains(digit) {
            commands.setHeading(level: digit)
            return true
        }
        return false
    }

    private func handleCommand(key: String, commands: EditorCommands) -> Bool {
        switch key {
        case "b": commands.wrap(prefix: "**")
            return true
        case "i": commands.wrap(prefix: "*")
            return true
        case "u": commands.wrap(prefix: "<u>", suffix: "</u>")
            return true
        case "k": commands.insertLink()
            return true
        default: return false
        }
    }

    private func handleCommandShift(key: String, commands: EditorCommands) -> Bool {
        switch key {
        case "x": commands.wrap(prefix: "~~")
            return true
        case "7": commands.toggleLinePrefix("1. ")
            return true
        case "8": commands.toggleLinePrefix("- ")
            return true
        case "9": commands.toggleLinePrefix("> ")
            return true
        case "t": commands.insertTodo()
            return true
        default: return false
        }
    }
}
