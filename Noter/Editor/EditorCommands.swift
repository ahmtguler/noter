import AppKit
import Foundation

/// Bridge between toolbar / keyboard shortcuts and the underlying NSTextView.
/// All actions operate on the current selection (or the cursor line for line-prefix
/// commands), exactly like every other markdown editor.
@MainActor
final class EditorCommands: ObservableObject {
    weak var textView: NSTextView?

    // MARK: - Inline wrap (bold/italic/code/strikethrough/underline)

    /// Wrap the current selection with `prefix`/`suffix`. If the selection is
    /// already wrapped, unwrap it. If selection is empty, insert markers and
    /// place the caret between them.
    func wrap(prefix: String, suffix: String? = nil) {
        guard let textView else { return }
        let suffix = suffix ?? prefix
        let nsString = textView.string as NSString
        let selectedRange = textView.selectedRange()

        // Try to detect already-wrapped selection so the second tap toggles off.
        let prefixLen = (prefix as NSString).length
        let suffixLen = (suffix as NSString).length
        let surroundingStart = selectedRange.location - prefixLen
        let surroundingEnd = selectedRange.location + selectedRange.length + suffixLen
        let alreadyWrapped: Bool = {
            guard surroundingStart >= 0, surroundingEnd <= nsString.length else { return false }
            let leading = nsString.substring(with: NSRange(location: surroundingStart, length: prefixLen))
            let trailing = nsString.substring(with: NSRange(
                location: selectedRange.location + selectedRange.length,
                length: suffixLen
            ))
            return leading == prefix && trailing == suffix
        }()

        if alreadyWrapped {
            let totalRange = NSRange(
                location: surroundingStart,
                length: prefixLen + selectedRange.length + suffixLen
            )
            let inner = nsString.substring(with: selectedRange)
            replace(in: totalRange, with: inner, restoreSelection: NSRange(
                location: surroundingStart,
                length: (inner as NSString).length
            ))
            return
        }

        let selectedText = nsString.substring(with: selectedRange)
        let replacement = "\(prefix)\(selectedText)\(suffix)"
        let newSelection = NSRange(
            location: selectedRange.location + prefixLen,
            length: (selectedText as NSString).length
        )
        replace(in: selectedRange, with: replacement, restoreSelection: newSelection)
    }

    // MARK: - Line-prefix (heading / list / quote / todo)

    /// Toggle a line prefix on every line of the selection. If all lines already
    /// have the prefix, remove it; otherwise add it to lines that lack it.
    func toggleLinePrefix(_ prefix: String) {
        guard let textView else { return }
        let nsString = textView.string as NSString
        let lineRange = nsString.lineRange(for: textView.selectedRange())
        let block = nsString.substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")

        let allHavePrefix = lines.allSatisfy { line in
            line.isEmpty || line.hasPrefix(prefix) || stripHeadingHashes(line).hasPrefix(prefix)
        }

        let newBlock: String = lines.map { line in
            if line.isEmpty { return line }
            if allHavePrefix {
                if line.hasPrefix(prefix) {
                    return String(line.dropFirst(prefix.count))
                }
                return line
            }
            // Replace any existing heading prefix (#, ##, …) before adding ours.
            let withoutHeading = stripHeadingPrefix(line)
            if withoutHeading.hasPrefix(prefix) { return withoutHeading }
            return prefix + withoutHeading
        }.joined(separator: "\n")

        let newSelection = NSRange(location: lineRange.location, length: (newBlock as NSString).length)
        replace(in: lineRange, with: newBlock, restoreSelection: newSelection)
    }

    /// Specialised heading toggle: cycles "" → "# " → "## " → … "###### " → "" if the
    /// same level is requested twice. Replaces any existing heading level.
    func setHeading(level: Int) {
        guard let textView else { return }
        precondition((1 ... 6).contains(level))
        let nsString = textView.string as NSString
        let lineRange = nsString.lineRange(for: textView.selectedRange())
        let line = nsString.substring(with: lineRange)
        let trimmedNewline = line.hasSuffix("\n")
        let body = trimmedNewline ? String(line.dropLast()) : line
        let withoutCurrent = stripHeadingPrefix(body)
        let alreadyAtLevel: Bool = {
            let prefix = String(repeating: "#", count: level) + " "
            return body.hasPrefix(prefix)
        }()
        let newBody: String = if alreadyAtLevel {
            withoutCurrent
        } else {
            String(repeating: "#", count: level) + " " + withoutCurrent
        }
        let replacement = newBody + (trimmedNewline ? "\n" : "")
        let newSelection = NSRange(
            location: lineRange.location + (newBody as NSString).length,
            length: 0
        )
        replace(in: lineRange, with: replacement, restoreSelection: newSelection)
    }

    // MARK: - Snippet insertion (link, todo)

    /// Insert a snippet at the caret. `cursorOffset` places the caret relative
    /// to the start of the inserted text (e.g. `[]()` → cursor offset 1 puts it
    /// inside the square brackets).
    func insertSnippet(_ snippet: String, cursorOffset: Int) {
        guard let textView else { return }
        let selectedRange = textView.selectedRange()
        let newCaret = NSRange(location: selectedRange.location + cursorOffset, length: 0)
        replace(in: selectedRange, with: snippet, restoreSelection: newCaret)
    }

    func insertLink() {
        guard let textView else { return }
        let nsString = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let selectedText = nsString.substring(with: selectedRange)
        if selectedText.isEmpty {
            insertSnippet("[]()", cursorOffset: 1) // caret inside the brackets
        } else {
            let replacement = "[\(selectedText)]()"
            let cursor = NSRange(
                location: selectedRange.location + (replacement as NSString).length - 1,
                length: 0
            )
            replace(in: selectedRange, with: replacement, restoreSelection: cursor)
        }
    }

    func insertTodo() {
        toggleLinePrefix("- [ ] ")
    }

    // MARK: - Helpers

    private func replace(in range: NSRange, with replacement: String, restoreSelection: NSRange) {
        guard let textView else { return }
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(restoreSelection)
    }

    private func stripHeadingPrefix(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"^#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
    }

    private func stripHeadingHashes(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"^#{1,6}\s*"#,
            with: "",
            options: .regularExpression
        )
    }
}
