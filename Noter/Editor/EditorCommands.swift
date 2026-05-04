import AppKit
import Foundation

/// Bridge between toolbar / keyboard shortcuts and the underlying NSTextView.
///
/// Every command works whether or not the user has a selection. Empty selection
/// inserts the markers around the caret and parks the caret between them; a
/// non-empty selection wraps with the marker pair, or unwraps if the same
/// command was applied a second time. Single-character markers (`*`, `_`) are
/// careful never to false-match the inner side of doubled markers (`**`, `__`)
/// so styles stack — e.g. ⌘B then ⌘I yields `***text***`, not undone bold.
///
/// All edits go through `replace(_:_:_:)` which records undo, restores the
/// caret/selection sensibly, and re-publishes `activeStyles` so the toolbar
/// reflects the new state.
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

    // MARK: - Inline wrap (bold / italic / code / strikethrough / underline)

    func wrap(prefix: String, suffix: String? = nil) {
        guard let textView else { return }
        let suffix = suffix ?? prefix
        let nsString = textView.string as NSString
        let selection = textView.selectedRange()
        let prefixLen = (prefix as NSString).length
        let suffixLen = (suffix as NSString).length

        // Empty selection: try to unwrap if caret sits inside an existing pair,
        // otherwise insert empty markers and park the caret between them.
        if selection.length == 0 {
            if let pair = enclosingPair(prefix: prefix, suffix: suffix, around: selection.location, in: nsString) {
                unwrap(pair: pair, in: nsString)
                return
            }
            let combined = prefix + suffix
            let caret = NSRange(location: selection.location + prefixLen, length: 0)
            replace(in: selection, with: combined, restoreSelection: caret)
            return
        }

        // Selection covers the markers themselves — unwrap by stripping them.
        let selectedText = nsString.substring(with: selection)
        let nsSelected = selectedText as NSString
        let selectionWrapsMarkers = nsSelected.length >= prefixLen + suffixLen
            && selectedText.hasPrefix(prefix)
            && selectedText.hasSuffix(suffix)
        if selectionWrapsMarkers {
            let inner = String(selectedText.dropFirst(prefixLen).dropLast(suffixLen))
            let restored = NSRange(location: selection.location, length: (inner as NSString).length)
            replace(in: selection, with: inner, restoreSelection: restored)
            return
        }

        // Selection sits inside markers — unwrap.
        let outsideStart = selection.location - prefixLen
        let outsideEnd = selection.location + selection.length + suffixLen
        let boundaries = WrapBoundaries(
            prefix: prefix,
            suffix: suffix,
            outsideStart: outsideStart,
            outsideEnd: outsideEnd,
            selection: selection
        )
        if isInsideExistingWrap(boundaries, in: nsString) {
            let total = NSRange(location: outsideStart, length: prefixLen + selection.length + suffixLen)
            let inner = nsString.substring(with: selection)
            let restored = NSRange(location: outsideStart, length: (inner as NSString).length)
            replace(in: total, with: inner, restoreSelection: restored)
            return
        }

        // Default: wrap.
        let replacement = "\(prefix)\(selectedText)\(suffix)"
        let restored = NSRange(
            location: selection.location + prefixLen,
            length: (selectedText as NSString).length
        )
        replace(in: selection, with: replacement, restoreSelection: restored)
    }

    // MARK: - Block-level line prefix (lists / quote / todo)

    func toggleLinePrefix(_ prefix: String) {
        guard let textView else { return }
        let nsString = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = lineRangeCoveringSelection(selection: selection, in: nsString)
        let block = nsString.substring(with: lineRange)
        let trailingNewline = block.hasSuffix("\n")
        let bare = trailingNewline ? String(block.dropLast()) : block
        let lines = bare.components(separatedBy: "\n")

        let nonEmpty = lines.filter { !$0.isEmpty }
        let allHavePrefix = !nonEmpty.isEmpty && nonEmpty.allSatisfy { line in
            stripAnyBlockMarker(line).hasPrefix(prefix) || line.hasPrefix(prefix)
        }

        let rewritten: [String] = lines.map { line in
            if line.isEmpty { return line }
            if allHavePrefix {
                return removeLeading(prefix, from: line)
            }
            // Add the desired prefix, dropping any other block marker first
            // so toggling between bullet/numbered/quote/todo works cleanly.
            let cleaned = stripAnyBlockMarker(line)
            if cleaned.hasPrefix(prefix) { return cleaned }
            return prefix + cleaned
        }

        let newBlock = rewritten.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let newLength = (newBlock as NSString).length
        let restored = NSRange(location: lineRange.location, length: newLength)
        replace(in: lineRange, with: newBlock, restoreSelection: restored)
    }

    func setHeading(level: Int) {
        guard let textView else { return }
        precondition((1 ... 6).contains(level))
        let nsString = textView.string as NSString
        let lineRange = lineRangeCoveringSelection(selection: textView.selectedRange(), in: nsString)
        let block = nsString.substring(with: lineRange)
        let trailingNewline = block.hasSuffix("\n")
        let bare = trailingNewline ? String(block.dropLast()) : block
        let lines = bare.components(separatedBy: "\n")

        let target = String(repeating: "#", count: level) + " "
        let allAtLevel = !lines.isEmpty && lines.allSatisfy { line in
            line.isEmpty || line.hasPrefix(target)
        }

        let rewritten: [String] = lines.map { line in
            if line.isEmpty { return line }
            let stripped = stripAnyBlockMarker(line)
            return allAtLevel ? stripped : target + stripped
        }

        let newBlock = rewritten.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let newLength = (newBlock as NSString).length
        let restored = NSRange(location: lineRange.location, length: newLength)
        replace(in: lineRange, with: newBlock, restoreSelection: restored)
    }

    func insertTodo() {
        toggleLinePrefix("- [ ] ")
    }

    func insertLink() {
        guard let textView else { return }
        let nsString = textView.string as NSString
        let selection = textView.selectedRange()
        let selectedText = nsString.substring(with: selection)
        if selectedText.isEmpty {
            // [|]() — caret inside the brackets, ready to type link text.
            let snippet = "[]()"
            let caret = NSRange(location: selection.location + 1, length: 0)
            replace(in: selection, with: snippet, restoreSelection: caret)
            return
        }
        let replacement = "[\(selectedText)]()"
        let cursor = NSRange(
            location: selection.location + (replacement as NSString).length - 1,
            length: 0
        )
        replace(in: selection, with: replacement, restoreSelection: cursor)
    }

    // MARK: - Active style detection

    /// Recompute which styles apply at the caret. Toolbar observes this to
    /// highlight the matching buttons. Called from the text view delegate
    /// whenever text or selection changes.
    func recomputeActiveStyles() {
        guard let textView else {
            activeStyles = []
            return
        }
        let nsString = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = nsString.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = nsString.substring(with: lineRange)
        let lineRelativeStart = selection.location - lineRange.location
        let lineRelativeEnd = lineRelativeStart + selection.length

        var styles: Set<Style> = []

        if let level = headingLevel(in: line) {
            styles.insert(.heading(level))
        }
        if matchesPrefix(line, "- [ ] ") || matchesPrefix(line, "- [x] ") || matchesPrefix(line, "- [X] ") {
            styles.insert(.todoList)
        } else if line.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) != nil {
            styles.insert(.bulletList)
        }
        if line.range(of: #"^\s*\d+\.\s+"#, options: .regularExpression) != nil {
            styles.insert(.numberedList)
        }
        if matchesPrefix(line, "> ") {
            styles.insert(.quote)
        }

        // Triple-asterisk implies both bold and italic.
        if isInsideContent(
            pattern: #"\*\*\*([^*\n]+?)\*\*\*"#,
            line: line,
            start: lineRelativeStart,
            end: lineRelativeEnd
        ) {
            styles.insert(.bold)
            styles.insert(.italic)
        }
        let inBold = isInsideContent(
            pattern: #"\*\*([^*\n]+?)\*\*"#,
            line: line,
            start: lineRelativeStart,
            end: lineRelativeEnd
        )
        if inBold {
            styles.insert(.bold)
        }
        if isInsideContent(
            pattern: #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#,
            line: line,
            start: lineRelativeStart,
            end: lineRelativeEnd
        ) {
            styles.insert(.italic)
        }
        if isInsideContent(pattern: #"~~([^~\n]+?)~~"#, line: line, start: lineRelativeStart, end: lineRelativeEnd) {
            styles.insert(.strikethrough)
        }
        if isInsideContent(pattern: #"<u>([^<\n]+?)</u>"#, line: line, start: lineRelativeStart, end: lineRelativeEnd) {
            styles.insert(.underline)
        }
        if isInsideContent(pattern: #"`([^`\n]+?)`"#, line: line, start: lineRelativeStart, end: lineRelativeEnd) {
            styles.insert(.code)
        }

        activeStyles = styles
    }

    // MARK: - Replace helper

    private func replace(in range: NSRange, with replacement: String, restoreSelection: NSRange) {
        guard let textView else { return }
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(restoreSelection)
        refocus()
        recomputeActiveStyles()
    }

    private func unwrap(pair: EnclosingPair, in nsString: NSString) {
        let total = NSRange(
            location: pair.openMarker.location,
            length: pair.openMarker.length + pair.contentLength + pair.closeMarker.length
        )
        let inner = nsString.substring(with: NSRange(
            location: pair.openMarker.location + pair.openMarker.length,
            length: pair.contentLength
        ))
        let caret = NSRange(location: pair.openMarker.location + (inner as NSString).length, length: 0)
        replace(in: total, with: inner, restoreSelection: caret)
    }

    private func refocus() {
        guard let textView, let window = textView.window else { return }
        if window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    // MARK: - Block helpers

    private func lineRangeCoveringSelection(selection: NSRange, in nsString: NSString) -> NSRange {
        if selection.length == 0 {
            return nsString.lineRange(for: NSRange(location: selection.location, length: 0))
        }
        return nsString.lineRange(for: selection)
    }

    private func removeLeading(_ prefix: String, from line: String) -> String {
        if line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        let cleaned = stripAnyBlockMarker(line)
        if cleaned.hasPrefix(prefix) {
            return String(cleaned.dropFirst(prefix.count))
        }
        return line
    }

    /// Strips any leading block-level marker (heading hashes, bullet, numbered,
    /// quote, todo). Used so toggling between block styles replaces rather than
    /// stacks markers.
    private func stripAnyBlockMarker(_ line: String) -> String {
        let patterns = [
            #"^#{1,6}\s+"#,
            #"^\s*[-*+]\s+\[[xX ]\]\s+"#,
            #"^\s*[-*+]\s+"#,
            #"^\s*\d+\.\s+"#,
            #"^>\s+"#
        ]
        for pattern in patterns {
            let updated = line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            if updated != line {
                return updated
            }
        }
        return line
    }

    // MARK: - Inline-wrap helpers

    private struct EnclosingPair {
        let openMarker: NSRange
        let closeMarker: NSRange
        var contentLength: Int {
            closeMarker.location - (openMarker.location + openMarker.length)
        }
    }

    /// Returns the markers around `position` if it sits strictly inside a wrap
    /// of `prefix...suffix` on the same line. Single-char markers reject the
    /// inner side of doubled markers so italicising "abc" inside "**abc**"
    /// doesn't unwrap the bold.
    private func enclosingPair(
        prefix: String,
        suffix: String,
        around position: Int,
        in nsString: NSString
    ) -> EnclosingPair? {
        let lineRange = nsString.lineRange(for: NSRange(location: position, length: 0))
        let line = nsString.substring(with: lineRange)
        let positionInLine = position - lineRange.location
        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        let escapedSuffix = NSRegularExpression.escapedPattern(for: suffix)
        let pattern = "\(escapedPrefix)([^\n]+?)\(escapedSuffix)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let prefixLen = (prefix as NSString).length
        let suffixLen = (suffix as NSString).length
        let nsLine = line as NSString
        var found: EnclosingPair?
        regex.enumerateMatches(in: line, range: NSRange(location: 0, length: nsLine.length)) { match, _, stop in
            guard let match else { return }
            let lower = match.range.location
            let upper = match.range.location + match.range.length
            guard lower < positionInLine, positionInLine < upper else { return }

            // Single-char markers must not touch a doubled marker on either side
            // (otherwise `*` matches the inner edge of `**`).
            if prefixLen == 1, prefix == suffix {
                let beforeIdx = lower - 1
                let afterIdx = upper
                let before = beforeIdx >= 0
                    ? nsLine.substring(with: NSRange(location: beforeIdx, length: 1))
                    : ""
                let after = afterIdx < nsLine.length
                    ? nsLine.substring(with: NSRange(location: afterIdx, length: 1))
                    : ""
                if before == prefix || after == prefix { return }
            }

            let openMarker = NSRange(location: lower + lineRange.location, length: prefixLen)
            let closeMarker = NSRange(
                location: upper - suffixLen + lineRange.location,
                length: suffixLen
            )
            found = EnclosingPair(openMarker: openMarker, closeMarker: closeMarker)
            stop.pointee = true
        }
        return found
    }

    private struct WrapBoundaries {
        let prefix: String
        let suffix: String
        let outsideStart: Int
        let outsideEnd: Int
        let selection: NSRange
    }

    private func isInsideExistingWrap(_ bounds: WrapBoundaries, in nsString: NSString) -> Bool {
        let prefixLen = (bounds.prefix as NSString).length
        let suffixLen = (bounds.suffix as NSString).length
        guard bounds.outsideStart >= 0, bounds.outsideEnd <= nsString.length else { return false }
        let leading = nsString.substring(with: NSRange(location: bounds.outsideStart, length: prefixLen))
        let trailing = nsString.substring(with: NSRange(
            location: bounds.selection.location + bounds.selection.length,
            length: suffixLen
        ))
        guard leading == bounds.prefix, trailing == bounds.suffix else { return false }
        return !abutsDoubledMarker(
            prefix: bounds.prefix,
            suffix: bounds.suffix,
            outsideStart: bounds.outsideStart,
            outsideEnd: bounds.outsideEnd,
            in: nsString
        )
    }

    private func abutsDoubledMarker(
        prefix: String,
        suffix: String,
        outsideStart: Int,
        outsideEnd: Int,
        in nsString: NSString
    ) -> Bool {
        guard prefix.count == 1, prefix == suffix else { return false }
        let before = outsideStart > 0
            ? nsString.substring(with: NSRange(location: outsideStart - 1, length: 1))
            : ""
        let after = outsideEnd < nsString.length
            ? nsString.substring(with: NSRange(location: outsideEnd, length: 1))
            : ""
        return before == prefix || after == prefix
    }

    private func headingLevel(in line: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"^(#{1,6})\s+"#) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        return match.range(at: 1).length
    }

    private func matchesPrefix(_ line: String, _ prefix: String) -> Bool {
        line.hasPrefix(prefix)
    }

    /// Like `isInsideInline` but uses the captured group (the content) so the
    /// caret only counts as inside the styled span when it sits within the
    /// content, not on a marker character.
    private func isInsideContent(pattern: String, line: String, start: Int, end: Int) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let nsLine = line as NSString
        var inside = false
        regex.enumerateMatches(in: line, range: NSRange(location: 0, length: nsLine.length)) { match, _, stop in
            guard let match, match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            let contentStart = content.location
            let contentEnd = content.location + content.length
            if contentStart <= start, end <= contentEnd {
                inside = true
                stop.pointee = true
            }
        }
        return inside
    }
}
