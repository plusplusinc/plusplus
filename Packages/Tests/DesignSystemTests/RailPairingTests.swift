import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// Which plain neighbor a held row's card lies over, to pair with on a rest, and how a pair draws
/// while held.
@Suite("Rail pairing")
struct RailPairingTests {
    private let ids = ["a", "b", "c", "d"]
    private let lean = RailDrag.pairLean

    /// The pairing for a card `offset` past the gap above `place`'s row, with `a` lifted.
    private func pairing(
        _ offset: CGFloat,
        at place: RailSlot<String>.Place,
        joined: Set<String> = [],
        slot joining: RailNeighbor? = nil,
    ) -> RailSlot<String>? {
        RailDrag.pairing(
            cardTop: 100 + offset,
            gapTop: 100,
            slot: RailSlot(place, joining: joining),
            rest: ids.filter { $0 != "a" },
            groups: RailDrag.groups(ids, joined: joined),
        )
    }

    @Test("A card over a plain neighbor, the lean or more past its gap, pairs with it")
    func leansOver() {
        #expect(pairing(lean, at: .before("c")) == .before("c", joining: .below))
        #expect(pairing(-lean, at: .before("c")) == .before("c", joining: .above))
        #expect(pairing(lean - 1, at: .before("c")) == nil)
        #expect(pairing(-lean + 1, at: .before("c")) == nil)
    }

    @Test("There is nothing to pair with past the ends")
    func ends() {
        #expect(pairing(-lean, at: .before("b")) == nil)
        #expect(pairing(lean, at: .before("b")) == .before("b", joining: .below))
        #expect(pairing(lean, at: .end) == nil)
        #expect(pairing(-lean, at: .end) == RailSlot(.end, joining: .above))
    }

    @Test("A neighbor in a group doesn't pair; its edge's slot inside is the way in")
    func groupedNeighbor() {
        // c-d grouped.
        #expect(pairing(lean, at: .before("c"), joined: ["c"]) == nil)
        #expect(pairing(-lean, at: .before("c"), joined: ["c"]) == .before("c", joining: .above))
        #expect(pairing(lean, at: .before("d"), joined: ["c"], slot: .above) == nil)
    }

    @Test("Held over a pair's slot, the two draw joined, the rest as they were")
    func pairedWhileHeld() {
        #expect(RailDrag.joined(ids, joined: [], moving: "a", to: .before("d", joining: .below))
            == ["a"])
        #expect(RailDrag.joined(ids, joined: [], moving: "a", to: .before("d", joining: .above))
            == ["c"])
        #expect(RailDrag.joined(ids, joined: ["c"], moving: "a", to: .before("c", joining: .above))
            == ["b", "c"])
    }
}
