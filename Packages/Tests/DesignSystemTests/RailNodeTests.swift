import Foundation
import Testing
@testable import DesignSystem

/// Where the wells place a row's node: read at rest, kept while held.
@Suite("Rail node")
struct RailNodeTests {
    private let insets = [CGPoint(x: 20, y: 18), CGPoint(x: 12, y: 18), CGPoint(x: 20, y: 22)]

    @Test("At rest, the node is the furthest across and highest of the rows' nodes")
    func readAtRest() {
        #expect(RailDrag.railNode(insets, isHeld: false, known: CGPoint(x: 1, y: 1))
            == CGPoint(x: 20, y: 18))
        #expect(RailDrag.railNode([], isHeld: false, known: CGPoint(x: 1, y: 1))
            == CGPoint(x: 1, y: 1))
    }

    @Test("While held, the node stays where it was read, as moving rows report theirs out")
    func keptWhileHeld() {
        let moving = [CGPoint(x: 20, y: -19.8), CGPoint(x: 20, y: 18.2)]
        #expect(RailDrag.railNode(moving, isHeld: true, known: CGPoint(x: 20, y: 18))
            == CGPoint(x: 20, y: 18))
        #expect(RailDrag.railNode(moving, isHeld: true, known: nil) == CGPoint(x: 20, y: -19.8))
    }

    /// The current exercise's node sits on its large name, far down its row. Shaped from that
    /// node, its card was far rounder than a plain row's and its leading edge was off the screen.
    @Test("A held card far down its row has a plain row's corners and sides, inside its frame")
    func cardShapedAsPlainRow() {
        let plainNodeY: CGFloat = 21
        let nearTop = CardFill.shape(
            node: CGPoint(x: railNodeCenter, y: 21),
            plainNodeY: plainNodeY,
        )
        let farDown = CardFill.shape(
            node: CGPoint(x: railNodeCenter, y: 70),
            plainNodeY: plainNodeY,
        )
        #expect(farDown == nearTop)
        #expect(farDown.leading >= 0)
    }
}
