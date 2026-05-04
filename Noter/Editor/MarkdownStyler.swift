import AppKit

/// Applies live-preview attributes to an `NSTextStorage`. Markdown markers
/// (`#`, `**`, `*`, `` ` ``, `~~`, `>`, `- [ ]`, `[](…)` parens) are visually
/// hidden — we set them to a near-zero font size with a clear color so the
/// editor reads as a rendered preview, while the underlying source markdown
/// stays in the file. The cursor still navigates through the hidden chars.
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    private let bodyFont: NSFont = .systemFont(ofSize: 14)
    private let monoFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    private let secondary = NSColor.secondaryLabelColor
    private let linkColor = NSColor.linkColor
    private let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.5)
    private let hiddenFont: NSFont = .systemFont(ofSize: 0.5)

    private var hiddenAttributes: [NSAttributedString.Key: Any] {
        [
            .font: hiddenFont,
            .foregroundColor: NSColor.clear,
            .kern: -0.5
        ]
    }

    func textStorage(
        _ storage: NSTextStorage,
        didProcessEditing actions: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength _: Int
    ) {
        guard actions.contains(.editedCharacters) else { return }
        // Restyle from the start of the affected paragraph block. Cheap on small docs.
        let nsString = storage.string as NSString
        let safeRange = NSRange(location: 0, length: nsString.length).intersection(editedRange) ?? .init()
        let lineRange = nsString.lineRange(for: safeRange)
        applyStyles(in: lineRange, on: storage)
    }

    func restyleAll(_ storage: NSTextStorage) {
        applyStyles(in: NSRange(location: 0, length: storage.length), on: storage)
    }

    // MARK: - Styling

    private func applyStyles(in range: NSRange, on storage: NSTextStorage) {
        guard storage.length > 0 else { return }
        let scopedRange = clamp(range, to: storage.length)
        guard scopedRange.length > 0 else { return }

        let defaults: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.clear,
            .kern: 0.0,
            .strikethroughStyle: 0,
            .underlineStyle: 0
        ]
        storage.setAttributes(defaults, range: scopedRange)

        let plainText = (storage.string as NSString).substring(with: scopedRange)
        let base = scopedRange.location

        applyHeadings(plainText: plainText, base: base, on: storage)
        applyBold(plainText: plainText, base: base, on: storage)
        applyItalic(plainText: plainText, base: base, on: storage)
        applyStrikethrough(plainText: plainText, base: base, on: storage)
        applyInlineCode(plainText: plainText, base: base, on: storage)
        applyHTMLUnderline(plainText: plainText, base: base, on: storage)
        applyBlockquotes(plainText: plainText, base: base, on: storage)
        applyTaskList(plainText: plainText, base: base, on: storage)
        applyBulletList(plainText: plainText, base: base, on: storage)
        applyLinks(plainText: plainText, base: base, on: storage)
    }

    private func applyHeadings(plainText: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(#{1,6})\s+(.*)$"#) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match else { return }
            let hashesGroup = match.range(at: 1)
            let level = hashesGroup.length
            let size: CGFloat = switch level {
            case 1: 24
            case 2: 20
            case 3: 17
            case 4: 16
            case 5: 15
            default: 14
            }
            let font = NSFont.boldSystemFont(ofSize: size)
            let lineAbsolute = NSRange(location: match.range.location + base, length: match.range.length)
            storage.addAttributes([.font: font], range: lineAbsolute)
            // Hide the leading `#` characters and the space after them.
            let markerLength = hashesGroup.length + 1 // hashes + single space
            let markerAbsolute = NSRange(location: hashesGroup.location + base, length: markerLength)
            storage.addAttributes(hiddenAttributes, range: markerAbsolute)
        }
    }

    private func applyBold(plainText: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let inner = match.range(at: 1)
            let openMarker = NSRange(location: match.range.location, length: 2)
            let closeMarker = NSRange(location: inner.location + inner.length, length: 2)
            storage.addAttributes(
                [.font: NSFont.boldSystemFont(ofSize: bodyFont.pointSize)],
                range: NSRange(location: inner.location + base, length: inner.length)
            )
            hide(range: openMarker, base: base, in: storage)
            hide(range: closeMarker, base: base, in: storage)
        }
    }

    private func applyItalic(plainText: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#) else { return }
        let italicFont = NSFontManager.shared.font(
            withFamily: bodyFont.familyName ?? "System",
            traits: .italicFontMask,
            weight: 5,
            size: bodyFont.pointSize
        ) ?? bodyFont
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let inner = match.range(at: 1)
            let openMarker = NSRange(location: match.range.location, length: 1)
            let closeMarker = NSRange(location: inner.location + inner.length, length: 1)
            storage.addAttributes(
                [.font: italicFont],
                range: NSRange(location: inner.location + base, length: inner.length)
            )
            hide(range: openMarker, base: base, in: storage)
            hide(range: closeMarker, base: base, in: storage)
        }
    }

    private func applyStrikethrough(plainText: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"~~([^~\n]+)~~"#) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let inner = match.range(at: 1)
            let openMarker = NSRange(location: match.range.location, length: 2)
            let closeMarker = NSRange(location: inner.location + inner.length, length: 2)
            storage.addAttributes(
                [.strikethroughStyle: NSUnderlineStyle.single.rawValue],
                range: NSRange(location: inner.location + base, length: inner.length)
            )
            hide(range: openMarker, base: base, in: storage)
            hide(range: closeMarker, base: base, in: storage)
        }
    }

    private func applyInlineCode(plainText: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"`([^`\n]+)`"#) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let inner = match.range(at: 1)
            let openMarker = NSRange(location: match.range.location, length: 1)
            let closeMarker = NSRange(location: inner.location + inner.length, length: 1)
            storage.addAttributes(
                [.font: monoFont, .backgroundColor: codeBackground],
                range: NSRange(location: inner.location + base, length: inner.length)
            )
            hide(range: openMarker, base: base, in: storage)
            hide(range: closeMarker, base: base, in: storage)
        }
    }

    private func applyHTMLUnderline(plainText: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"<u>([^<\n]+)</u>"#) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let inner = match.range(at: 1)
            let openMarker = NSRange(location: match.range.location, length: 3)
            let closeMarker = NSRange(location: inner.location + inner.length, length: 4)
            storage.addAttributes(
                [.underlineStyle: NSUnderlineStyle.single.rawValue],
                range: NSRange(location: inner.location + base, length: inner.length)
            )
            hide(range: openMarker, base: base, in: storage)
            hide(range: closeMarker, base: base, in: storage)
        }
    }

    private func applyBlockquotes(plainText: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(>\s+)(.*)$"#) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let marker = match.range(at: 1)
            let inner = match.range(at: 2)
            storage.addAttributes(
                [.foregroundColor: secondary],
                range: NSRange(location: inner.location + base, length: inner.length)
            )
            hide(range: marker, base: base, in: storage)
        }
    }

    private func applyBulletList(plainText: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(\s*)([-*+])(\s+)"#) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 4 else { return }
            let bullet = match.range(at: 2)
            let trailingSpace = match.range(at: 3)
            // Replace the dash/asterisk visually with a real bullet by hiding the
            // marker and inserting a foreground bullet via a glyph trick is overkill;
            // we just dim the marker so it reads as a bullet-style prefix.
            storage.addAttributes(
                [.foregroundColor: secondary],
                range: NSRange(location: bullet.location + base, length: bullet.length + trailingSpace.length)
            )
        }
    }

    private func applyTaskList(plainText: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(\s*[-*+]\s+)\[( |x|X)\](\s+)"#) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 4 else { return }
            let listMarker = match.range(at: 1)
            let checkbox = match.range(at: 2)
            let trailingSpace = match.range(at: 3)
            // Hide the leading "- " prefix; the [ ] / [x] reads as the box itself.
            hide(range: listMarker, base: base, in: storage)
            let checkboxChar = (plainText as NSString).substring(with: checkbox).first
            let isComplete = checkboxChar == "x" || checkboxChar == "X"
            if isComplete {
                let lineEnd = nsText.lineRange(for: NSRange(location: match.range.location, length: 0))
                storage.addAttributes(
                    [
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: secondary
                    ],
                    range: NSRange(location: lineEnd.location + base, length: lineEnd.length)
                )
            }
            _ = trailingSpace // kept for clarity / future spacing tweaks
        }
    }

    private func applyLinks(plainText: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\n]+)\)"#) else { return }
        let nsText = plainText as NSString
        regex.enumerateMatches(in: plainText, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let label = match.range(at: 1)
            let labelOpen = NSRange(location: match.range.location, length: 1)
            let labelClose = NSRange(location: label.location + label.length, length: 1)
            let urlStart = labelClose.location + 1
            let urlEnd = match.range.location + match.range.length
            let urlRange = NSRange(location: urlStart - 1, length: urlEnd - (urlStart - 1))
            storage.addAttributes(
                [.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue],
                range: NSRange(location: label.location + base, length: label.length)
            )
            hide(range: labelOpen, base: base, in: storage)
            hide(range: labelClose, base: base, in: storage)
            hide(range: urlRange, base: base, in: storage)
        }
    }

    // MARK: - Helpers

    private func hide(range: NSRange, base: Int, in storage: NSTextStorage) {
        let absolute = NSRange(location: range.location + base, length: range.length)
        storage.addAttributes(hiddenAttributes, range: absolute)
    }

    private func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        let end = max(location, min(range.location + range.length, length))
        return NSRange(location: location, length: end - location)
    }
}
