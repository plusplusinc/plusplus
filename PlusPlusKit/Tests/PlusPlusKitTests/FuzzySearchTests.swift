import Foundation
import Testing
@testable import PlusPlusKit

@Suite("FuzzySearch")
struct FuzzySearchTests {
    // MARK: - Folding

    @Test("Case and diacritics never block a match")
    func folding() {
        #expect(FuzzySearch.matches(query: "BENCH", candidate: "bench press"))
        #expect(FuzzySearch.matches(query: "bénch", candidate: "Bench Press"))
        #expect(FuzzySearch.matches(query: "lateral", candidate: "LATERAL RAISE"))
    }

    @Test("Punctuation is a separator, not content")
    func punctuation() {
        #expect(FuzzySearch.matches(query: "push up", candidate: "Push-Up"))
        #expect(FuzzySearch.matches(query: "push-up", candidate: "Push Up"))
        #expect(!FuzzySearch.matches(query: "++", candidate: "Push-Up"))
        #expect(FuzzySearch.score(query: "  ", candidate: "Push-Up") == nil)
    }

    @Test("Symbol-only names and queries compare literally, never match-all")
    func symbolOnly() {
        // A user CAN name a routine "++" in this app; it must stay findable.
        #expect(FuzzySearch.matches(query: "++", candidate: "++"))
        #expect(FuzzySearch.matches(query: "++", candidate: "Push++"))
        // A symbol query NARROWS — only a blank query passes everything.
        #expect(FuzzySearch.ranked(["Push Day", "++"], query: "++", key: { $0 }) == ["++"])
        // A resolver must never pick an arbitrary winner for a token-free
        // name (a stat scoped to the wrong routine reads as fact).
        #expect(FuzzySearch.bestMatch(query: "💪", in: ["Push Day", "Leg Day"]) == nil)
        #expect(FuzzySearch.bestMatch(query: "  ", in: ["Push Day"]) == nil)
    }

    // MARK: - Tiers

    @Test("Prefixes match while typing")
    func prefixes() {
        #expect(FuzzySearch.matches(query: "ben", candidate: "Bench Press"))
        #expect(FuzzySearch.matches(query: "b", candidate: "Bench Press"))
        #expect(FuzzySearch.matches(query: "bench pr", candidate: "Bench Press"))
    }

    @Test("Query words are order-free but ALL must land")
    func tokenSemantics() {
        #expect(FuzzySearch.matches(query: "press bench", candidate: "Bench Press"))
        #expect(!FuzzySearch.matches(query: "bench fly", candidate: "Bench Press"))
        #expect(!FuzzySearch.matches(query: "bench press machine", candidate: "Bench Press"))
    }

    @Test("Everyday typos are forgiven")
    func typos() {
        // Transposition.
        #expect(FuzzySearch.matches(query: "benhc", candidate: "Bench Press"))
        // Missing letter.
        #expect(FuzzySearch.matches(query: "dumbell", candidate: "Dumbbells"))
        // Transposition inside a long word.
        #expect(FuzzySearch.matches(query: "shoudler", candidate: "Shoulder Press"))
        // Wrong letter.
        #expect(FuzzySearch.matches(query: "squet", candidate: "Squat"))
    }

    @Test("Short words get no typo budget")
    func shortWordsStrict() {
        #expect(!FuzzySearch.matches(query: "rox", candidate: "Row"))
        #expect(!FuzzySearch.matches(query: "cul", candidate: "Curl"))
        // One edit at four letters made "carl" match the whole Cable
        // family — short words must be typed straight.
        #expect(!FuzzySearch.matches(query: "carl", candidate: "Cable Row"))
    }

    @Test("Unrelated names stay unmatched")
    func noFalsePositives() {
        #expect(!FuzzySearch.matches(query: "curl", candidate: "Crawl Out"))
        #expect(!FuzzySearch.matches(query: "bench", candidate: "Barbell Row"))
        #expect(FuzzySearch.score(query: "deadlift", candidate: "Leg Press") == nil)
    }

    @Test("Missing spaces still find the spaced name")
    func gluedQueries() {
        #expect(FuzzySearch.matches(query: "benchpress", candidate: "Bench Press"))
        #expect(FuzzySearch.matches(query: "pushup", candidate: "Push-Up"))
        #expect(FuzzySearch.matches(query: "benchpres", candidate: "Bench Press"))
    }

    @Test("Over-typed queries reach the shorter word, but only just")
    func overTyped() {
        #expect(FuzzySearch.matches(query: "presses", candidate: "Leg Press"))
        #expect(FuzzySearch.matches(query: "rows", candidate: "Barbell Row"))
        // Three leftover letters is a different word, not an inflection:
        // "deadlft" must not land on "Dead" (Bug).
        #expect(!FuzzySearch.matches(query: "deadlft", candidate: "Dead Bug"))
    }

    @Test("Abbreviations reach multi-word names")
    func abbreviations() {
        #expect(FuzzySearch.matches(query: "rd", candidate: "Romanian Deadlift"))
        #expect(FuzzySearch.matches(query: "rdl", candidate: "Romanian Deadlift"))
        #expect(FuzzySearch.matches(query: "ohp", candidate: "Overhead Press"))
        #expect(FuzzySearch.matches(query: "bp", candidate: "Bench Press"))
        // Single-word names have no initials to hit.
        #expect(!FuzzySearch.matches(query: "rd", candidate: "Row"))
        // Letters must anchor at word starts, in order.
        #expect(!FuzzySearch.matches(query: "pb", candidate: "Bench Press"))
        // Five letters is a misspelled word, not an abbreviation: the
        // typo tier's honest match must outrank the subsequence sneak.
        let typo = FuzzySearch.score(query: "benhc", candidate: "Bench") ?? 0
        let sneak = FuzzySearch.score(query: "benhc", candidate: "Nordic Bench Curl") ?? 0
        #expect(typo > sneak)
    }

    @Test("Mid-word substrings need three characters")
    func substrings() {
        #expect(FuzzySearch.matches(query: "row", candidate: "Narrow Stance Squat"))
        #expect(!FuzzySearch.matches(query: "ro", candidate: "Narrow Stance Squat"))
    }

    // MARK: - Ranking

    @Test("Literal beats tolerant: exact > prefix > typo")
    func tierOrdering() {
        let exact = FuzzySearch.score(query: "bench", candidate: "Bench")
        let prefix = FuzzySearch.score(query: "benc", candidate: "Bench")
        let typo = FuzzySearch.score(query: "benhc", candidate: "Bench")
        let scores = [exact, prefix, typo].compactMap { $0 }
        #expect(scores.count == 3)
        #expect(scores == scores.sorted(by: >))
    }

    @Test("Full coverage outranks partial coverage")
    func coverage() {
        let whole = FuzzySearch.score(query: "press", candidate: "Press") ?? 0
        let partial = FuzzySearch.score(query: "press", candidate: "Leg Press") ?? 0
        #expect(whole > partial)
    }

    @Test("ranked filters, orders best-first, keeps ties stable")
    func rankedOrdering() {
        let names = ["Bicep Curls", "Crawl Out", "Curl", "Hammer Curls"]
        let result = FuzzySearch.ranked(names, query: "curl", key: { $0 })
        #expect(result.first == "Curl")
        #expect(!result.contains("Crawl Out"))
        // The two prefix-tier plural hits keep their alphabetical order.
        let curls = result.filter { $0.hasSuffix("Curls") }
        #expect(curls == ["Bicep Curls", "Hammer Curls"])
    }

    @Test("ranked with a blank query narrows nothing")
    func rankedBlankQuery() {
        let names = ["Squat", "Bench Press"]
        #expect(FuzzySearch.ranked(names, query: "", key: { $0 }) == names)
        #expect(FuzzySearch.ranked(names, query: "  ", key: { $0 }) == names)
    }

    @Test("bestMatch resolves a typed name to its canonical form")
    func bestMatchResolution() {
        let names = ["Incline Bench Press", "Bench Press", "Chest Fly"]
        #expect(FuzzySearch.bestMatch(query: "benchpres", in: names) == "Bench Press")
        #expect(FuzzySearch.bestMatch(query: "bench press", in: names) == "Bench Press")
        #expect(FuzzySearch.bestMatch(query: "kettlebell", in: names) == nil)
    }

    // MARK: - Highlight ranges

    private func painted(_ query: String, _ candidate: String) -> [String] {
        FuzzySearch.highlightRanges(query: query, in: candidate).map { String(candidate[$0]) }
    }

    @Test("Exact and prefix hits paint the matched run")
    func highlightPrefix() {
        #expect(painted("curl", "Bicep Curl") == ["Curl"])
        #expect(painted("cu", "Bicep Curl") == ["Cu"])
        // Separated words paint as separate runs (the space between is
        // not part of any match).
        #expect(painted("bench press", "Bench Press") == ["Bench", "Press"])
    }

    @Test("Every query word paints its own home, order-free")
    func highlightMultiToken() {
        #expect(painted("press bench", "Bench Press") == ["Bench", "Press"])
        #expect(painted("press", "Overhead Press Machine") == ["Press"])
    }

    @Test("Mid-word substrings paint at three letters, not below")
    func highlightSubstringFloor() {
        #expect(painted("ead", "Deadlift") == ["ead"])
        #expect(painted("ea", "Deadlift") == [])
    }

    @Test("Case and diacritics paint the original spelling")
    func highlightFolding() {
        #expect(painted("BENCH", "bench press") == ["bench"])
        #expect(painted("bénch", "Bench Press") == ["Bench"])
    }

    @Test("Over-typed inflections paint the word they outgrew")
    func highlightOverTyped() {
        #expect(painted("curls", "Bicep Curl") == ["Curl"])
        #expect(painted("presses", "Bench Press") == ["Press"])
    }

    @Test("Typo and abbreviation matches paint nothing")
    func highlightInexact() {
        #expect(painted("benhc", "Bench Press") == [])
        #expect(painted("rdl", "Romanian Deadlift") == [])
        // A short glued query still paints the word it over-types
        // ("pushup" honestly contains "Push"); a long one has no home.
        #expect(painted("pushup", "Push-Up") == ["Push"])
        #expect(painted("benchpress", "Bench Press") == [])
    }

    @Test("Symbol-only queries compare literally")
    func highlightSymbols() {
        #expect(painted("++", "Push++") == ["++"])
        #expect(painted("++", "Push Day") == [])
    }

    @Test("Overlapping paints fuse into one range")
    func highlightMerging() {
        // Both words paint; the adjacent runs stay separate ranges only
        // when text separates them.
        let ranges = FuzzySearch.highlightRanges(query: "leg press", in: "Leg Press Machine")
        #expect(ranges.count == 2)
        #expect(painted("leg leg", "Leg Press") == ["Leg"])
    }
}
