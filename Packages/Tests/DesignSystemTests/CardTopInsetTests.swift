import CoreGraphics
import Testing
@testable import DesignSystem

/// Where the current exercise's held card starts, from plain numbers (`LiftedCard.topInset`).
@Suite("Held card's top")
struct CardTopInsetTests {
    @Test("The node sits halfway between a plain row's inset and the one balanced on the name")
    func halfway() {
        // Plain: the card starts 50 - 20 = 30 down. Balanced: 120 tall, the last baseline 20
        // above the bottom, so the card starts 20 above the cap top at 40, at 20. Halfway: 25.
        let inset = LiftedCard.topInset(
            nodeY: 50, plainNodeY: 20, capTop: 40, lastBaseline: 100, height: 120,
        )
        #expect(inset == 25)
    }

    @Test("The card never starts above the row's own top")
    func neverAboveTheRow() {
        let inset = LiftedCard.topInset(
            nodeY: 15, plainNodeY: 20, capTop: 5, lastBaseline: 80, height: 120,
        )
        #expect(inset == 0)
    }

    @Test("Without the name's marks, the node sits a plain row's inset down the card")
    func withoutMarks() {
        let inset = LiftedCard.topInset(
            nodeY: 50, plainNodeY: 20, capTop: nil, lastBaseline: nil, height: 120,
        )
        #expect(inset == 30)
    }
}
