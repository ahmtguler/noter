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
