import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// Where a dragged row's gap goes, and how fast a held row scrolls the list, from plain numbers.
@Suite("Rail drag")
struct RailDragTests {
    /// Rows a, b, c of mixed heights: one line, two, one.
    private let rows: [(id: String, height: CGFloat)] = [("a", 64), ("b", 88), ("c", 64)]

    @Test("Candidates are one per boundary, the lifted row left out")
    func candidates() {
        let candidates = RailDrag.candidates(rows: rows, lifted: "b")
        #expect(candidates == [
            .init(slot: .before("a"), gapTop: 0),
            .init(slot: .before("c"), gapTop: 64),
            .init(slot: .end, gapTop: 128),
        ])
    }

    @Test("The gap moves past a row once the card is halfway over it")
    func halfway() {
        // Lifting a: gaps at 0 (its own), 88 above c, 152 at the end; switch points 44 and 120.
        let candidates = RailDrag.candidates(rows: rows, lifted: "a")
        func slot(_ top: CGFloat) -> RailSlot<String> {
            RailDrag.candidate(for: top, in: candidates, current: nil)
        }
        #expect(slot(43) == .before("b"))
        #expect(slot(45) == .before("c"))
        #expect(slot(119) == .before("c"))
        #expect(slot(121) == .end)
    }

    @Test("A dead band holds the current slot at the switch point")
    func deadBand() {
        let candidates = RailDrag.candidates(rows: rows, lifted: "a")
        let band = RailDrag.deadBand
        func slot(_ top: CGFloat, from current: RailSlot<String>) -> RailSlot<String> {
            RailDrag.candidate(for: top, in: candidates, current: current)
        }
        #expect(slot(44 + band - 1, from: .before("b")) == .before("b"))
        #expect(slot(44 + band + 1, from: .before("b")) == .before("c"))
        #expect(slot(44 - band + 1, from: .before("c")) == .before("c"))
        #expect(slot(44 - band - 1, from: .before("c")) == .before("b"))
    }

    @Test("Above the first row and below the last clamp to the ends")
    func clamps() {
        let candidates = RailDrag.candidates(rows: rows, lifted: "c")
        #expect(RailDrag.candidate(for: -500, in: candidates, current: .end) == .before("a"))
        #expect(RailDrag.candidate(for: 5000, in: candidates, current: nil) == .end)
    }

    @Test("One row has one slot, its own")
    func oneRow() {
        let candidates = RailDrag.candidates(rows: [("a", 64)], lifted: "a")
        #expect(candidates == [.init(slot: .end, gapTop: 0)])
        #expect(RailDrag.candidate(for: 300, in: candidates, current: .end) == .end)
    }

    @Test("While held, the lifted row shows in its gap")
    func order() {
        let ids = ["a", "b", "c", "d"]
        #expect(RailDrag.order(ids, moving: "a", to: .before("d")) == ["b", "c", "a", "d"])
        #expect(RailDrag.order(ids, moving: "d", to: .before("a")) == ["d", "a", "b", "c"])
        #expect(RailDrag.order(ids, moving: "b", to: .end) == ["a", "c", "d", "b"])
        #expect(RailDrag.order(ids, moving: "b", to: .before("c")) == ids)
    }

    @Test("Edge speed is zero outside the zone, rises toward the edge, and caps there")
    func edgeSpeed() {
        let visible: ClosedRange<CGFloat> = 100 ... 700
        let zone = RailDrag.edgeZone
        let top = RailDrag.edgeTopSpeed
        // A finger that has gone both ways since the lift, so both bands are armed.
        var travel = RailDrag.Travel(from: 400)
        travel.pass(100)
        travel.pass(700)
        func speed(_ y: CGFloat) -> CGFloat {
            RailDrag.edgeSpeed(fingerY: y, visible: visible, travel: travel)
        }
        #expect(speed(400) == 0)
        #expect(speed(700 - zone) == 0)
        #expect(speed(700 - zone / 2) == top / 4)
        #expect(speed(700) == top)
        #expect(speed(900) == top)
        #expect(speed(100 + zone / 2) == -top / 4)
        #expect(speed(0) == -top)
        #expect(speed(700 - zone / 4) > speed(700 - zone / 2))
    }

    @Test("An edge's band scrolls only once the finger has gone toward that edge since the lift")
    func edgeArming() {
        let visible: ClosedRange<CGFloat> = 100 ... 700
        let move = RailDrag.allowableMovement
        func speed(_ y: CGFloat, _ travel: RailDrag.Travel) -> CGFloat {
            RailDrag.edgeSpeed(fingerY: y, visible: visible, travel: travel)
        }
        // Lifted in the top band and held still: nothing.
        var still = RailDrag.Travel(from: 120)
        still.pass(120 - move / 2)
        #expect(speed(120 - move / 2, still) == 0)
        // Gone up far enough: it scrolls, and keeps on if the finger eases back down.
        var up = still
        up.pass(120 - move)
        #expect(speed(120 - move, up) < 0)
        up.pass(125)
        #expect(speed(125, up) < 0)
        // Gone down only: the top band stays still, the bottom one scrolls.
        var down = RailDrag.Travel(from: 120)
        down.pass(140)
        #expect(speed(120, down) == 0)
        var across = RailDrag.Travel(from: 300)
        across.pass(690)
        #expect(speed(690, across) > 0)
        // Lifted in the bottom band and held still: nothing.
        #expect(speed(690, RailDrag.Travel(from: 690)) == 0)
    }
}
