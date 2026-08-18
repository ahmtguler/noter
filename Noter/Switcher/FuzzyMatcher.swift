import Foundation

/// Subsequence-based fuzzy matcher with simple bonuses for word-start and
/// consecutive-character matches. Returns nil if `query` is not a subsequence
/// of `target` (case-insensitive). Higher score = better match.
enum FuzzyMatcher {
    static func score(query: String, in target: String) -> Int? {
        if query.isEmpty {
            return 0
        }
        let lowerQuery = Array(query.lowercased())
        let lowerTarget = Array(target.lowercased())

        var queryIndex = 0
        var previousMatchIndex: Int = -2 // ensures first match is not "consecutive"
        var score = 0
        var consecutiveBonus = 0

        for (targetIndex, character) in lowerTarget.enumerated() {
            if queryIndex >= lowerQuery.count {
                break
            }
            if character == lowerQuery[queryIndex] {
                if previousMatchIndex == targetIndex - 1 {
                    consecutiveBonus += 5
                    score += 10 + consecutiveBonus
                } else {
                    consecutiveBonus = 0
                    let isWordStart = targetIndex == 0 || lowerTarget[targetIndex - 1] == " "
                    score += isWordStart ? 25 : 5
                }
                previousMatchIndex = targetIndex
                queryIndex += 1
            }
        }
        return queryIndex == lowerQuery.count ? score : nil
    }
}
