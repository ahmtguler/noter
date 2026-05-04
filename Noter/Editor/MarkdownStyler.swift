import AppKit

/// Applies hybrid live-preview attributes to an `NSTextStorage`:
/// raw markdown markers stay visible (Bear/Raycast style), but headings, bold,
/// italic, inline code, blockquotes and links are styled inline as the user types.
///
/// Intentionally regex-based rather than a full markdown parser — for v1 this
/// covers the common cases at near-zero cost and stays correct under partial input.
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    private let bodyFont: NSFont = .systemFont(ofSize: 14)
    private let monoFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    private let secondary = NSColor.secondaryLabelColor
    private let linkColor = NSColor.linkColor
    private let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.4)

    func textStorage(
        _ storage: NSTextStorage,
        didProcessEditing actions: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength _: Int
    ) {
        guard actions.contains(.editedCharacters) else { return }
        let nsString = storage.string as NSString
        // Re-style the line(s) the edit touched. Cheap enough to do on every keystroke.
        let safeRange = NSRange(location: 0, length: nsString.length)
            .intersection(editedRange) ?? NSRange(location: 0, length: 0)
        let lineRange = nsString.lineRange(for: safeRange)
        applyStyles(in: lineRange, on: storage)
    }

    /// Style the entire document. Called when loading a new note's text.
    func restyleAll(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        applyStyles(in: full, on: storage)
    }

    // MARK: - Styling

    private func applyStyles(in range: NSRange, on storage: NSTextStorage) {
        guard range.length > 0 || storage.length == 0 else { return }
        let scopedRange = clamp(range, to: storage.length)
        guard scopedRange.length > 0 else { return }

        // Reset to defaults so re-edits don't accumulate stale attributes.
        let defaults: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.clear
        ]
        storage.setAttributes(defaults, range: scopedRange)

        let plainText = (storage.string as NSString).substring(with: scopedRange)

        applyHeadings(plainText: plainText, base: scopedRange.location, on: storage)
        applyInline(
            pattern: #"\*\*([^*\n]+)\*\*"#,
            plainText: plainText,
            base: scopedRange.location,
            on: storage,
            attrs: [.font: NSFont.boldSystemFont(ofSize: bodyFont.pointSize)],
            dimGroup: 0
        )
        applyInline(
            pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
            plainText: plainText,
            base: scopedRange.location,
            on: storage,
            attrs: [.font: NSFontManager.shared.font(
                withFamily: bodyFont.familyName ?? "System",
                traits: .italicFontMask,
                weight: 5,
                size: bodyFont.pointSize
            ) ?? bodyFont],
            dimGroup: 0
        )
        applyInline(
            pattern: #"`([^`\n]+)`"#,
            plainText: plainText,
            base: scopedRange.location,
            on: storage,
            attrs: [
                .font: monoFont,
                .backgroundColor: codeBackground
            ],
            dimGroup: 0
        )
        applyBlockquotes(plainText: plainText, base: scopedRange.location, on: storage)
        applyLinks(plainText: plainText, base: scopedRange.location, on: storage)
    }

    private func applyHeadings(plainText: String, base: Int, on storage: NSTextStorage) {
        let pattern = #"(?m)^(#{1,6})\s+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match else { return }
            let hashes = match.range(at: 1)
            let line = match.range
            let level = hashes.length
            let size: CGFloat = switch level {
            case 1: 22
            case 2: 19
            case 3: 17
            case 4: 16
            default: 15
            }
            let font = NSFont.boldSystemFont(ofSize: size)
            let absoluteLine = NSRange(location: line.location + base, length: line.length)
            storage.addAttributes([.font: font], range: absoluteLine)
            // Dim the leading hashes to make them feel decorative without hiding them.
            let absoluteHashes = NSRange(location: hashes.location + base, length: hashes.length)
            storage.addAttributes([.foregroundColor: secondary], range: absoluteHashes)
        }
    }

    private func applyInline(
        pattern: String,
        plainText: String,
        base: Int,
        attrs: [NSAttributedString.Key: Any],
        on storage: NSTextStorage
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match else { return }
            let absolute = NSRange(location: match.range.location + base, length: match.range.length)
            storage.addAttributes(attrs, range: absolute)
        }
    }

    private func applyBlockquotes(plainText: String, base: Int, on storage: NSTextStorage) {
        let pattern = #"(?m)^>\s+.*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match else { return }
            let absolute = NSRange(location: match.range.location + base, length: match.range.length)
            storage.addAttributes([.foregroundColor: secondary], range: absolute)
        }
    }

    private func applyLinks(plainText: String, base: Int, on storage: NSTextStorage) {
        let pattern = #"\[([^\]\n]+)\]\(([^)\n]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match else { return }
            let absolute = NSRange(location: match.range.location + base, length: match.range.length)
            storage.addAttributes([.foregroundColor: linkColor], range: absolute)
        }
    }

    private func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        let end = max(location, min(range.location + range.length, length))
        return NSRange(location: location, length: end - location)
    }
}
