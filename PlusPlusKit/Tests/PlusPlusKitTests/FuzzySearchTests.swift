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
        // A query with no letters or digits matches nothing.
        #expect(!FuzzySearch.matches(query: "++", candidate: "Push-Up"))
        #expect(FuzzySearch.score(query: "  ", candidate: "Push-Up") == nil)
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
}
