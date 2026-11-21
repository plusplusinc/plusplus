import Foundation
import Testing
@testable import DesignSystem

/// What the line under the current exercise's set bars reads in each state of a workout, and
/// which of its parts change between two states: only the number, "done", and the side, never
/// "Set" or "of 3".
@Suite("Progress line's words")
struct ProgressWordsTests {
    private enum Part: Hashable {
        case word
        case number
        case total
        case end
    }

    private static func focus(
        _ number: Int,
        of total: Int = 3,
        word: String = "Set",
        isDone: Bool = false,
        side: String? = nil,
        after: String? = nil,
    ) -> RowFocus {
        RowFocus(
            place: SetPlace(
                word: word,
                number: number,
                total: total,
                isDone: isDone,
                locale: Locale(identifier: "en_US"),
            ),
            side: side,
            figures: [.init(number: "10", unit: "reps")],
            spokenFigures: "10 reps",
            after: after,
        )
    }

    /// The line as it reads: "Set 1 of 3 done", "Set 1 of 3 · Left".
    private static func reads(_ focus: RowFocus) -> String {
        let words = ProgressWords(focus)
        let line = "\(words.word) \(words.number) of \(words.total)"
        switch words.end {
        case .done: return "\(line) done"
        case let .side(side): return "\(line) · \(side)"
        case nil: return line
        }
    }

    private static func changes(_ old: RowFocus, _ new: RowFocus) -> Set<Part> {
        let old = ProgressWords(old)
        let new = ProgressWords(new)
        return Set([
            old.word != new.word ? Part.word : nil,
            old.number != new.number ? .number : nil,
            old.total != new.total ? .total : nil,
            old.end != new.end ? .end : nil,
        ].compactMap(\.self))
    }

    @Test("A set of reps reads its place; resting after it, \"done\" follows")
    func reps() {
        #expect(Self.reads(Self.focus(1)) == "Set 1 of 3")
        #expect(Self.reads(Self.focus(1, isDone: true)) == "Set 1 of 3 done")
        // VoiceOver reads the same words.
        #expect(Self.focus(1, isDone: true).place.text == "Set 1 of 3 done")
    }

    @Test("Logging a set changes only its end, to \"done\"")
    func logging() {
        #expect(Self.changes(Self.focus(1), Self.focus(1, isDone: true)) == [.end])
    }

    @Test("A rest's end rolls only the number, as \"done\" goes")
    func restEnds() {
        #expect(Self.changes(Self.focus(1, isDone: true), Self.focus(2)) == [.number, .end])
    }

    @Test("A timed set reads as a set of reps, whatever its caption's end says")
    func timed() {
        let counting = Self.focus(2, after: "then rest 1:00")
        #expect(Self.reads(counting) == "Set 2 of 3")
        #expect(Self.changes(counting, Self.focus(2, isDone: true)) == [.end])
    }

    @Test("A sided set reads its side, and Left to Right changes only the side")
    func sided() {
        let left = Self.focus(1, side: "Left")
        let right = Self.focus(1, side: "Right")
        #expect(Self.reads(left) == "Set 1 of 3 · Left")
        #expect(Self.reads(right) == "Set 1 of 3 · Right")
        #expect(Self.changes(left, right) == [.end])
    }

    @Test(
        "Resting after a sided set, \"done\" takes the side's place, never shown with it",
    )
    func sidedResting() {
        let resting = Self.focus(1, isDone: true, side: "Left")
        #expect(Self.reads(resting) == "Set 1 of 3 done")
        #expect(!resting.showsSide)
        #expect(Self.changes(Self.focus(1, side: "Right"), resting) == [.end])
        #expect(Self.changes(resting, Self.focus(2, side: "Left")) == [.number, .end])
    }

    @Test("A superset's member reads its round, and a round's end rolls only the number")
    func supersetRound() {
        let first = Self.focus(1, word: "Round")
        #expect(Self.reads(first) == "Round 1 of 3")
        #expect(Self.changes(first, Self.focus(2, word: "Round")) == [.number])
    }

    @Test("The last set reads its place with nothing after it")
    func lastSet() {
        #expect(Self.reads(Self.focus(3)) == "Set 3 of 3")
        #expect(Self.changes(Self.focus(2), Self.focus(3)) == [.number])
    }
}
