import Testing
@testable import DesignSystem

/// How an open row splits a time into the pieces it rolls, each kept by its unit, so "55s"
/// keeps its place as "0m" arrives beside it; and what it leaves whole.
@Suite("Time pieces")
struct TimePieceTests {
    @Test("A time splits into its units, each but the last with the space after it")
    func splitsByUnit() throws {
        let pieces = try #require(TimePiece.pieces(of: "1m\u{00A0}35s"))
        #expect(pieces.map(\.id) == ["m", "s"])
        #expect(pieces.map(\.text) == ["1m\u{00A0}", "35s"])
        #expect(TimePiece.pieces(of: "55s")?.map(\.id) == ["s"])
    }

    @Test("The same unit keeps its identity as the time changes shape")
    func unitKeepsIdentity() throws {
        let closed = try #require(TimePiece.pieces(of: "55s"))
        let open = try #require(TimePiece.pieces(of: "0m\u{00A0}55s"))
        #expect(open.last?.id == closed.first?.id)
        #expect(open.last?.text == closed.first?.text)
    }

    @Test("A locale's longer unit splits the same way")
    func germanUnits() {
        #expect(TimePiece.pieces(of: "1min\u{00A0}35s")?.map(\.id) == ["min", "s"])
    }

    @Test("A per-side time splits into its units, then its words as one piece, a word")
    func perSide() throws {
        let pieces = try #require(TimePiece.pieces(of: "1m\u{00A0}0s per side"))
        #expect(pieces.map(\.id) == ["m", "s", "per side"])
        #expect(pieces.map(\.text) == ["1m\u{00A0}", "0s\u{00A0}", "per side"])
        #expect(pieces.map(\.isWord) == [false, false, true])
        #expect(TimePiece.pieces(of: "45s per side")?.map(\.id) == ["s", "per side"])
    }

    @Test("A word with no number is one piece, a word")
    func word() throws {
        let pieces = try #require(TimePiece.pieces(of: "None"))
        #expect(pieces.count == 1)
        #expect(pieces[0].isWord)
        #expect(TimePiece.pieces(of: "45s")?.first?.isWord == false)
    }

    @Test("A weight is not split into pieces: its number stands apart from its unit")
    func notTimes() {
        #expect(TimePiece.pieces(of: "25.0\u{00A0}lb") == nil)
        #expect(TimePiece.pieces(of: "27.5\u{00A0}lb/side") == nil)
        #expect(TimePiece.pieces(of: "") == nil)
    }
}
