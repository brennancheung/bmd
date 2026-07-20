import Darwin
import Foundation

@main
enum FuzzyMatcherTests {
    static func main() {
        testSubsequenceAndRanges()
        testBoundaryAndConsecutiveRanking()
        testCaseAndDiacriticFolding()
        testLetterNumberBoundary()
        testNoMatch()
        print("FuzzyMatcherTests passed")
    }

    private static func testSubsequenceAndRanges() {
        let match = FuzzyMatcher.score(query: "gc", candidate: "Google Chrome")
        expect(match?.ranges == [
            FuzzyMatchRange(start: 0, length: 1),
            FuzzyMatchRange(start: 7, length: 1),
        ], "fuzzy matching should return highlightable character ranges")
    }

    private static func testBoundaryAndConsecutiveRanking() {
        let boundary = FuzzyMatcher.score(query: "gc", candidate: "Google Chrome")
        let interior = FuzzyMatcher.score(query: "gc", candidate: "magic character")
        expect(
            score(boundary) > score(interior),
            "word-boundary matches should outrank interior subsequences"
        )

        let consecutive = FuzzyMatcher.score(query: "chr", candidate: "Chrome")
        let gapped = FuzzyMatcher.score(query: "chr", candidate: "cxxhxxr")
        expect(
            score(consecutive) > score(gapped),
            "consecutive matches should outrank equivalent gapped matches"
        )
    }

    private static func testCaseAndDiacriticFolding() {
        expect(
            FuzzyMatcher.score(query: "KREA", candidate: "krea 2 jalapeño") != nil,
            "matching should be case-insensitive"
        )
        expect(
            FuzzyMatcher.score(query: "jalapeno", candidate: "Jalapeño") != nil,
            "matching should be diacritic-insensitive"
        )
    }

    private static func testLetterNumberBoundary() {
        let boundary = FuzzyMatcher.score(query: "2p", candidate: "krea2Pro")
        let interior = FuzzyMatcher.score(query: "2p", candidate: "krea2example")
        expect(
            score(boundary) > score(interior),
            "letter-number and CamelCase transitions should contribute boundary weight"
        )
    }

    private static func testNoMatch() {
        expect(
            FuzzyMatcher.score(query: "xyz", candidate: "Google Chrome") == nil,
            "candidates missing a query character should not match"
        )
    }

    private static func score(_ match: FuzzyMatch?) -> Int {
        match?.score ?? Int.min
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
