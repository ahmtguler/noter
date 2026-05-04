import AppKit

/// `NSTextView` with markdown-aware editing affordances:
///
/// - Markdown keyboard shortcuts (⌘B / ⌘I / ⌘U / ⌘K / ⇧⌘X / ⇧⌘7 / ⇧⌘8 /
///   ⇧⌘9 / ⇧⌘T / ⌥⌘1-3) routed through `EditorCommands` instead of NSTextView's
///   own (rich-text-only) bold/italic actions.
/// - Smart Enter that continues the current list / quote, and exits it when the
///   item is empty (the standard Bear / Obsidian / Typora behaviour).
/// - Tab / Shift-Tab inside a list line indent / outdent that line by two spaces.
final class MarkdownTextView: NSTextView {
    weak var commands: EditorCommands?

    // MARK: - Keyboard shortcuts

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
        if modifiers == [.command, .option], let digit = Int(key), (1 ... 3).contains(digit) {
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

    // MARK: - Smart return: continue / exit list

    override func insertNewline(_ sender: Any?) {
        if handleListReturn() { return }
        super.insertNewline(sender)
    }

    private func handleListReturn() -> Bool {
        let nsString = string as NSString
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let lineRange = nsString.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = nsString.substring(with: lineRange)
        let lineWithoutNewline = line.hasSuffix("\n") ? String(line.dropLast()) : line

        guard let info = ListLine.parse(lineWithoutNewline) else { return false }

        // Empty content on a list line → break out of the list.
        if info.content.isEmpty {
            let trailingNewline = line.hasSuffix("\n") ? "\n" : ""
            let replacement = trailingNewline
            guard shouldChangeText(in: lineRange, replacementString: replacement) else { return true }
            textStorage?.replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: 0))
            return true
        }

        // Otherwise insert "\n" + continuation prefix so the next line is a list item too.
        let continuation = "\n" + info.continuation
        guard shouldChangeText(in: selection, replacementString: continuation) else { return true }
        textStorage?.replaceCharacters(in: selection, with: continuation)
        didChangeText()
        setSelectedRange(NSRange(
            location: selection.location + (continuation as NSString).length,
            length: 0
        ))
        return true
    }

    // MARK: - Tab / Backtab indent

    override func insertTab(_ sender: Any?) {
        if handleTab(outdent: false) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if handleTab(outdent: true) { return }
        super.insertBacktab(sender)
    }

    private func handleTab(outdent: Bool) -> Bool {
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: selectedRange())
        let line = nsString.substring(with: lineRange)
        let bare = line.hasSuffix("\n") ? String(line.dropLast()) : line
        guard ListLine.parse(bare) != nil else { return false }

        let indent = "  "
        if outdent {
            let prefix = (bare as NSString).substring(to: min(2, (bare as NSString).length))
            guard prefix == indent else { return false }
            let removeRange = NSRange(location: lineRange.location, length: 2)
            guard shouldChangeText(in: removeRange, replacementString: "") else { return true }
            textStorage?.replaceCharacters(in: removeRange, with: "")
            didChangeText()
            let oldSel = selectedRange()
            setSelectedRange(NSRange(
                location: max(lineRange.location, oldSel.location - 2),
                length: oldSel.length
            ))
            return true
        }

        let insertRange = NSRange(location: lineRange.location, length: 0)
        guard shouldChangeText(in: insertRange, replacementString: indent) else { return true }
        textStorage?.replaceCharacters(in: insertRange, with: indent)
        didChangeText()
        let oldSel = selectedRange()
        setSelectedRange(NSRange(location: oldSel.location + 2, length: oldSel.length))
        return true
    }
}

// MARK: - List line parsing

/// Identifies what kind of list / block-prefix line we're on, and what the
/// "continuation" prefix should look like on the next line.
private struct ListLine {
    let content: String
    let continuation: String

    static func parse(_ line: String) -> ListLine? {
        // Order matters: todo before bullet (todo is a bullet variant), numbered
        // before quote, quote last.
        if let parsed = parseTodo(line) { return parsed }
        if let parsed = parseBullet(line) { return parsed }
        if let parsed = parseNumbered(line) { return parsed }
        if let parsed = parseQuote(line) { return parsed }
        return nil
    }

    private static func parseTodo(_ line: String) -> ListLine? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(\s*)([-*+])\s+\[([xX ])\]\s(.*)$"#
        ) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        let indent = nsLine.substring(with: match.range(at: 1))
        let bullet = nsLine.substring(with: match.range(at: 2))
        let content = nsLine.substring(with: match.range(at: 4))
        return ListLine(content: content, continuation: "\(indent)\(bullet) [ ] ")
    }

    private static func parseBullet(_ line: String) -> ListLine? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)([-*+])\s(.*)$"#) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        let indent = nsLine.substring(with: match.range(at: 1))
        let bullet = nsLine.substring(with: match.range(at: 2))
        let content = nsLine.substring(with: match.range(at: 3))
        return ListLine(content: content, continuation: "\(indent)\(bullet) ")
    }

    private static func parseNumbered(_ line: String) -> ListLine? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)(\d+)\.\s(.*)$"#) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        let indent = nsLine.substring(with: match.range(at: 1))
        let numberString = nsLine.substring(with: match.range(at: 2))
        let content = nsLine.substring(with: match.range(at: 3))
        let nextNumber = (Int(numberString) ?? 1) + 1
        return ListLine(content: content, continuation: "\(indent)\(nextNumber). ")
    }

    private static func parseQuote(_ line: String) -> ListLine? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)>\s(.*)$"#) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        let indent = nsLine.substring(with: match.range(at: 1))
        let content = nsLine.substring(with: match.range(at: 2))
        return ListLine(content: content, continuation: "\(indent)> ")
    }
}
