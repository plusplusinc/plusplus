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

    // Measured again once the workout screen's scroll view had its height, in the frame its rows
    // first laid out: the same place as the first measure, but for its last bits. Taken, it ran
    // the rail's body again, building each row a third time in that frame, a fault per row.
    private let first: CGFloat = 18.166666666666515
    private let again: CGFloat = 18.16666666666663

    @Test("A node measured again in the same place keeps the first measure, so nothing redraws")
    func sameNodeKept() {
        let known = CGPoint(x: 26, y: first)
        #expect(RailDrag.railNode([CGPoint(x: 26, y: again)], isHeld: false, known: known) == known)
        #expect(RailDrag.railNode([CGPoint(x: 26, y: first + 0.5)], isHeld: false, known: known)
            == CGPoint(x: 26, y: first + 0.5))
    }

    @Test("Nodes measured again in the same places are the same; one moved or missing is not")
    func sameInsets() {
        let known = [1: first, 2: 18.0]
        #expect(RailDrag.isSame([1: again, 2: 18.0], as: known))
        #expect(!RailDrag.isSame([1: first + 0.5, 2: 18.0], as: known))
        #expect(!RailDrag.isSame([1: first], as: known))
        #expect(!RailDrag.isSame([1: first, 3: 18.0], as: known))
        #expect(!RailDrag.isSame(known, as: [:]))
    }
}
