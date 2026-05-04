import AppKit
import Combine
import Foundation

/// Bridge between toolbar / keyboard shortcuts and the underlying NSTextView.
/// All actions operate on the current selection (or the cursor line for line-prefix
/// commands), exactly like every other markdown editor.
///
/// Also publishes `activeStyles` derived from the current selection so the
/// toolbar can highlight the buttons whose style is in effect at the caret.
@MainActor
final class EditorCommands: ObservableObject {
    enum Style: Hashable {
        case heading(Int)
        case bold
        case italic
        case underline
        case strikethrough
        case code
        case bulletList
        case numberedList
        case todoList
        case quote
    }

    weak var textView: NSTextView?
    @Published private(set) var activeStyles: Set<Style> = []

    // MARK: - Inline wrap (bold/italic/code/strikethrough/underline)

    func wrap(prefix: String, suffix: String? = nil) {
        guard let textView else { return }
        let suffix = suffix ?? prefix
        let nsString = textView.string as NSString
        let selectedRange = textView.selectedRange()

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
            guard leading == prefix, trailing == suffix else { return false }
            // Single-character markers (* or _) shouldn't match the inner side
            // of a doubled marker (** or __). Otherwise italicizing inside bold
            // would unwrap the bold instead of stacking the italic.
            if prefix.count == 1, prefix == suffix {
                let beforeChar = surroundingStart > 0
                    ? nsString.substring(with: NSRange(location: surroundingStart - 1, length: 1))
                    : ""
                let afterChar = surroundingEnd < nsString.length
                    ? nsString.substring(with: NSRange(location: surroundingEnd, length: 1))
                    : ""
                if beforeChar == prefix || afterChar == prefix { return false }
            }
            return true
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
            let withoutHeading = stripHeadingPrefix(line)
            if withoutHeading.hasPrefix(prefix) { return withoutHeading }
            return prefix + withoutHeading
        }.joined(separator: "\n")

        let newSelection = NSRange(location: lineRange.location, length: (newBlock as NSString).length)
        replace(in: lineRange, with: newBlock, restoreSelection: newSelection)
    }

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
            insertSnippet("[]()", cursorOffset: 1)
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

    // MARK: - Active style detection

    /// Recompute which styles apply to the current caret/selection. Toolbar
    /// observes this to highlight the matching buttons.
    func recomputeActiveStyles() {
        guard let textView else {
            activeStyles = []
            return
        }
        let nsString = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let lineRange = nsString.lineRange(for: selectedRange)
        let line = nsString.substring(with: lineRange)
        let lineRelativeStart = selectedRange.location - lineRange.location
        let lineRelativeEnd = lineRelativeStart + selectedRange.length

        var styles: Set<Style> = []

        if let level = headingLevel(in: line) {
            styles.insert(.heading(level))
        }
        let isTodo = matchesPrefix(in: line, prefix: "- [ ] ")
            || matchesPrefix(in: line, prefix: "- [x] ")
            || matchesPrefix(in: line, prefix: "- [X] ")
        if isTodo {
            styles.insert(.todoList)
        } else if line.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) != nil {
            styles.insert(.bulletList)
        }
        if line.range(of: #"^\s*\d+\.\s+"#, options: .regularExpression) != nil {
            styles.insert(.numberedList)
        }
        if matchesPrefix(in: line, prefix: "> ") {
            styles.insert(.quote)
        }
        if isInsideInline(pattern: #"\*\*([^*\n]+)\*\*"#, line: line, start: lineRelativeStart, end: lineRelativeEnd) {
            styles.insert(.bold)
        }
        if isInsideInline(
            pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
            line: line,
            start: lineRelativeStart,
            end: lineRelativeEnd
        ) {
            styles.insert(.italic)
        }
        if isInsideInline(pattern: #"~~([^~\n]+)~~"#, line: line, start: lineRelativeStart, end: lineRelativeEnd) {
            styles.insert(.strikethrough)
        }
        if isInsideInline(pattern: #"<u>([^<\n]+)</u>"#, line: line, start: lineRelativeStart, end: lineRelativeEnd) {
            styles.insert(.underline)
        }
        if isInsideInline(pattern: #"`([^`\n]+)`"#, line: line, start: lineRelativeStart, end: lineRelativeEnd) {
            styles.insert(.code)
        }

        activeStyles = styles
    }

    // MARK: - Helpers

    private func replace(in range: NSRange, with replacement: String, restoreSelection: NSRange) {
        guard let textView else { return }
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(restoreSelection)
        recomputeActiveStyles()
    }

    private func stripHeadingPrefix(_ line: String) -> String {
        line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
    }

    private func stripHeadingHashes(_ line: String) -> String {
        line.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
    }

    private func headingLevel(in line: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"^(#{1,6})\s+"#) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        return match.range(at: 1).length
    }

    private func matchesPrefix(in line: String, prefix: String) -> Bool {
        line.hasPrefix(prefix)
    }

    private func isInsideInline(pattern: String, line: String, start: Int, end: Int) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let nsLine = line as NSString
        var inside = false
        regex.enumerateMatches(in: line, range: NSRange(location: 0, length: nsLine.length)) { match, _, stop in
            guard let match else { return }
            let lower = match.range.location
            let upper = match.range.location + match.range.length
            if lower <= start, upper >= end {
                inside = true
                stop.pointee = true
            }
        }
        return inside
    }
}
