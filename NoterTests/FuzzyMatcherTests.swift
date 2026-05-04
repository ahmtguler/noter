@testable import Noter
import Testing

struct FuzzyMatcherTests {
    @Test
    func emptyQueryAlwaysMatchesWithZeroScore() {
        #expect(FuzzyMatcher.score(query: "", in: "Anything") == 0)
    }

    @Test
    func subsequenceMatchSucceeds() {
        #expect(FuzzyMatcher.score(query: "blockchainrpc", in: "Blockchain RPC") != nil)
    }

    @Test
    func nonSubsequenceFails() {
        #expect(FuzzyMatcher.score(query: "xyz", in: "Hello world") == nil)
    }

    @Test
    func wordStartScoresHigherThanMidWord() {
        let wordStart = FuzzyMatcher.score(query: "rd", in: "Read me")
        let midWord = FuzzyMatcher.score(query: "rd", in: "ardvark")
        #expect(wordStart != nil && midWord != nil)
        #expect((wordStart ?? 0) > (midWord ?? 0))
    }

    @Test
    func consecutiveMatchesScoreHigherThanScattered() {
        // Both targets have one word-start match ('a' at index 0); the consecutive
        // case scores higher purely from the consecutive bonus chain.
        let consecutive = FuzzyMatcher.score(query: "abc", in: "abcdef")
        let scattered = FuzzyMatcher.score(query: "abc", in: "axbycz")
        #expect(consecutive != nil && scattered != nil)
        #expect((consecutive ?? 0) > (scattered ?? 0))
    }

    @Test
    func caseInsensitive() {
        #expect(FuzzyMatcher.score(query: "HELLO", in: "hello") != nil)
        #expect(FuzzyMatcher.score(query: "hello", in: "HELLO") != nil)
    }
}
