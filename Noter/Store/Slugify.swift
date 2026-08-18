import Foundation

enum Slugify {
    static let maxLength = 80

    private static let invalidFilenameChars = CharacterSet(charactersIn: "/:\\?<>|*\"")

    /// Returns the human-readable title from a markdown body — first non-empty line,
    /// with leading heading markers (`#`, `##`, …) stripped.
    static func title(from body: String) -> String {
        guard let firstLine = body
            .split(whereSeparator: \.isNewline)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else {
            return ""
        }
        return String(firstLine)
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Returns a copy of `body` with the title line marked as a duplicate so
    /// the new note is visually distinct from the source in the switcher /
    /// trash. The first non-empty line is suffixed with ` (copy)`; if it
    /// already ends in `(copy)` or `(copy N)`, the counter increments —
    /// matches how Finder names duplicates. Heading markers (`# `, `## `…)
    /// stay where they are; the suffix lands on the text portion.
    static func bodyMarkedAsDuplicate(_ body: String) -> String {
        var lines = body.components(separatedBy: "\n")
        let titleIndex = lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let idx = titleIndex else {
            return "(copy)"
        }
        lines[idx] = duplicateLine(lines[idx])
        return lines.joined(separator: "\n")
    }

    private static func duplicateLine(_ line: String) -> String {
        let pattern = #"^(\s*#{1,6}\s+)?(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return line + " (copy)"
        }
        let ns = line as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: line, range: fullRange) else {
            return line + " (copy)"
        }
        let headingPrefix = match.range(at: 1).location == NSNotFound
            ? "" : ns.substring(with: match.range(at: 1))
        let text = ns.substring(with: match.range(at: 2))
        return headingPrefix + suffixAsDuplicate(text)
    }

    private static func suffixAsDuplicate(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "(copy)"
        }
        let copyPattern = #"^(.+?)\s*\(copy(?:\s+(\d+))?\)\s*$"#
        if let regex = try? NSRegularExpression(pattern: copyPattern) {
            let range = NSRange(location: 0, length: (trimmed as NSString).length)
            if let match = regex.firstMatch(in: trimmed, range: range) {
                let ns = trimmed as NSString
                let base = ns.substring(with: match.range(at: 1))
                let bumped: Int = if match.range(at: 2).location != NSNotFound {
                    (Int(ns.substring(with: match.range(at: 2))) ?? 1) + 1
                } else {
                    2
                }
                return "\(base) (copy \(bumped))"
            }
        }
        return "\(trimmed) (copy)"
    }

    /// Returns a filesystem-safe slug derived from a markdown body. Falls back to "Untitled".
    static func filename(from body: String) -> String {
        // 1. Collapse runs of any whitespace (tab, NBSP, multiple spaces) to a single space.
        // 2. Drop invalid filename chars and remaining sub-space control chars.
        // 3. Trim, cap to maxLength.
        let collapsed = title(from: body)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let cleaned = collapsed.unicodeScalars
            .filter { !invalidFilenameChars.contains($0) && $0.value >= 0x20 }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespaces)

        let trimmed: String
        if cleaned.count > maxLength {
            let endIndex = cleaned.index(cleaned.startIndex, offsetBy: maxLength)
            trimmed = String(cleaned[..<endIndex]).trimmingCharacters(in: .whitespaces)
        } else {
            trimmed = cleaned
        }
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
