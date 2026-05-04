import AppKit

/// Applies live-preview attributes to an `NSTextStorage`. Markdown markers
/// (`#`, `**`, `*`, `~~`, `` ` ``, `<u>`, `>` block-quote, `[]()` brackets/url)
/// are visually hidden — set to a near-zero font with clear color so the
/// editor reads as a rendered preview while the file on disk stays plain
/// markdown. The cursor still navigates through the hidden chars; one
/// arrow-press takes the caret across them as a single step.
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    private let bodyFont: NSFont = .systemFont(ofSize: 14)
    private let monoFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    private let secondary = NSColor.secondaryLabelColor
    private let tertiary = NSColor.tertiaryLabelColor
    private let linkColor = NSColor.linkColor
    private let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.45)

    private let hiddenFont: NSFont = .systemFont(ofSize: 0.5)
    private var hiddenAttributes: [NSAttributedString.Key: Any] {
        [
            .font: hiddenFont,
            .foregroundColor: NSColor.clear,
            .kern: -0.5
        ]
    }

    private lazy var italicFont: NSFont = NSFontManager.shared.font(
        withFamily: bodyFont.familyName ?? "System",
        traits: .italicFontMask,
        weight: 5,
        size: bodyFont.pointSize
    ) ?? bodyFont

    private lazy var boldItalicFont: NSFont = NSFontManager.shared.font(
        withFamily: bodyFont.familyName ?? "System",
        traits: [.italicFontMask, .boldFontMask],
        weight: 8,
        size: bodyFont.pointSize
    ) ?? NSFont.boldSystemFont(ofSize: bodyFont.pointSize)

    func textStorage(
        _ storage: NSTextStorage,
        didProcessEditing actions: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength _: Int
    ) {
        guard actions.contains(.editedCharacters) else { return }
        // Restyle the entire affected paragraph block(s) — a single line is
        // usually enough but multi-line edits need to expand to all touched lines.
        let nsString = storage.string as NSString
        let safeRange = NSRange(location: 0, length: nsString.length).intersection(editedRange) ?? .init()
        let lineRange = nsString.lineRange(for: safeRange)
        applyStyles(in: lineRange, on: storage)
    }

    func restyleAll(_ storage: NSTextStorage) {
        applyStyles(in: NSRange(location: 0, length: storage.length), on: storage)
    }

    // MARK: - Styling pipeline

    private func applyStyles(in range: NSRange, on storage: NSTextStorage) {
        guard storage.length > 0 else { return }
        let scopedRange = clamp(range, to: storage.length)
        guard scopedRange.length > 0 else { return }

        // Reset to baseline before re-applying to avoid stale attrs from a
        // previous edit (e.g., a deleted bold marker leaving leftover bold font).
        let defaults: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.clear,
            .kern: 0.0,
            .strikethroughStyle: 0,
            .underlineStyle: 0,
            .paragraphStyle: NSParagraphStyle.default
        ]
        storage.setAttributes(defaults, range: scopedRange)

        let plain = (storage.string as NSString).substring(with: scopedRange)
        let base = scopedRange.location

        // Block-level first so paragraph styles set up indent for inline passes.
        applyHeadings(plain: plain, base: base, on: storage)
        applyBlockquotes(plain: plain, base: base, on: storage)
        applyTodoList(plain: plain, base: base, on: storage)
        applyBulletList(plain: plain, base: base, on: storage)
        applyNumberedList(plain: plain, base: base, on: storage)

        // Inline order: bold-italic last so it overrides bold's inner font on `***x***`.
        applyStrikethrough(plain: plain, base: base, on: storage)
        applyInlineCode(plain: plain, base: base, on: storage)
        applyHTMLUnderline(plain: plain, base: base, on: storage)
        applyBold(plain: plain, base: base, on: storage)
        applyItalic(plain: plain, base: base, on: storage)
        applyBoldItalic(plain: plain, base: base, on: storage)
        applyLinks(plain: plain, base: base, on: storage)
    }

    // MARK: - Block elements

    private func applyHeadings(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(#{1,6})\s+(.*)$"#) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match else { return }
            let hashes = match.range(at: 1)
            let level = hashes.length
            let size: CGFloat = switch level {
            case 1: 24
            case 2: 20
            case 3: 17
            default: 15
            }
            let lineAbsolute = NSRange(location: match.range.location + base, length: match.range.length)
            storage.addAttributes(
                [.font: NSFont.boldSystemFont(ofSize: size)],
                range: lineAbsolute
            )
            // Hide the leading `#`s plus the single space after them.
            let markerAbsolute = NSRange(
                location: hashes.location + base,
                length: hashes.length + 1
            )
            storage.addAttributes(hiddenAttributes, range: markerAbsolute)
        }
    }

    private func applyBlockquotes(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(>\s)(.*)$"#) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let marker = match.range(at: 1)
            let inner = match.range(at: 2)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = 14
            paragraphStyle.firstLineHeadIndent = 14
            storage.addAttributes(
                [
                    .foregroundColor: secondary,
                    .obliqueness: 0.05,
                    .paragraphStyle: paragraphStyle
                ],
                range: NSRange(location: inner.location + base, length: inner.length)
            )
            hide(range: marker, base: base, in: storage)
        }
    }

    private func applyBulletList(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(\s*)([-*+])(\s+)"#) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 4 else { return }
            // Skip task-list lines — those are handled in `applyTodoList`.
            let lineRange = nsText.lineRange(for: match.range)
            let line = nsText.substring(with: lineRange)
            if line.range(of: #"^\s*[-*+]\s+\[[xX ]\]\s+"#, options: .regularExpression) != nil {
                return
            }
            let bullet = match.range(at: 2)
            let trailingSpace = match.range(at: 3)
            // Dim the marker — true `•` glyph substitution would require glyph
            // remapping which is overkill for v1; this reads as a list bullet.
            storage.addAttributes(
                [
                    .foregroundColor: secondary,
                    .font: NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold)
                ],
                range: NSRange(
                    location: bullet.location + base,
                    length: bullet.length + trailingSpace.length
                )
            )
        }
    }

    private func applyNumberedList(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(\s*)(\d+\.)(\s+)"#) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 4 else { return }
            let number = match.range(at: 2)
            let trailingSpace = match.range(at: 3)
            storage.addAttributes(
                [
                    .foregroundColor: secondary,
                    .font: NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .medium)
                ],
                range: NSRange(
                    location: number.location + base,
                    length: number.length + trailingSpace.length
                )
            )
        }
    }

    private func applyTodoList(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?m)^(\s*[-*+]\s+)(\[([xX ])\])(\s+)(.*)$"#
        ) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 6 else { return }
            let listMarker = match.range(at: 1)
            let checkboxFull = match.range(at: 2)
            let checkboxChar = match.range(at: 3)
            let content = match.range(at: 5)
            // Hide the dash/asterisk and trailing space — the [ ] / [x] reads
            // as the visible affordance.
            hide(range: listMarker, base: base, in: storage)
            // Style the brackets as a checkbox-ish element.
            storage.addAttributes(
                [.foregroundColor: tertiary],
                range: NSRange(location: checkboxFull.location + base, length: checkboxFull.length)
            )
            let isChecked = (nsText.substring(with: checkboxChar) == "x"
                || nsText.substring(with: checkboxChar) == "X")
            if isChecked {
                storage.addAttributes(
                    [
                        .foregroundColor: secondary,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: NSRange(location: content.location + base, length: content.length)
                )
            }
        }
    }

    // MARK: - Inline elements

    private func applyBold(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"\*\*([^*\n]+?)\*\*"#) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
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

    private func applyItalic(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#
        ) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
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

    private func applyBoldItalic(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"\*\*\*([^*\n]+?)\*\*\*"#) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let inner = match.range(at: 1)
            let openMarker = NSRange(location: match.range.location, length: 3)
            let closeMarker = NSRange(location: inner.location + inner.length, length: 3)
            storage.addAttributes(
                [.font: boldItalicFont],
                range: NSRange(location: inner.location + base, length: inner.length)
            )
            hide(range: openMarker, base: base, in: storage)
            hide(range: closeMarker, base: base, in: storage)
        }
    }

    private func applyStrikethrough(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"~~([^~\n]+?)~~"#) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
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

    private func applyInlineCode(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"`([^`\n]+?)`"#) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
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

    private func applyHTMLUnderline(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"<u>([^<\n]+?)</u>"#) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
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

    private func applyLinks(plain: String, base: Int, on storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]\n]+?)\]\(([^)\n]+?)\)"#) else { return }
        let nsText = plain as NSString
        regex.enumerateMatches(in: plain, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let label = match.range(at: 1)
            let labelOpen = NSRange(location: match.range.location, length: 1)
            let labelClose = NSRange(location: label.location + label.length, length: 1)
            let urlStart = labelClose.location + 1
            let urlEnd = match.range.location + match.range.length
            let urlBracketRange = NSRange(location: urlStart - 1, length: urlEnd - (urlStart - 1))
            storage.addAttributes(
                [.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue],
                range: NSRange(location: label.location + base, length: label.length)
            )
            hide(range: labelOpen, base: base, in: storage)
            hide(range: labelClose, base: base, in: storage)
            hide(range: urlBracketRange, base: base, in: storage)
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
