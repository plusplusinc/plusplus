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

    @Test("A rest goes on within the slop over the same slot, and starts again otherwise")
    func dwellRestarts() {
        let below = RailSlot<String>.before("c", joining: .below)
        let above = RailSlot<String>.before("c", joining: .above)
        let resting = RailDwell(target: below, anchor: 100)
        let slop = RailDrag.pairSlop
        #expect(RailDrag.dwell(nil, over: below, cardTop: 100) == resting)
        #expect(RailDrag.dwell(resting, over: below, cardTop: 100 + slop) == resting)
        #expect(RailDrag.dwell(resting, over: below, cardTop: 100 - slop) == resting)
        #expect(RailDrag.dwell(resting, over: below, cardTop: 101 + slop)
            == RailDwell(target: below, anchor: 101 + slop))
        #expect(RailDrag.dwell(resting, over: above, cardTop: 100)
            == RailDwell(target: above, anchor: 100))
        #expect(RailDrag.dwell(resting, over: nil, cardTop: 100) == nil)
    }

    @Test("A paired card, eased back short of the release, is no longer over its partner")
    func releases() {
        let release = RailDrag.pairRelease
        func held(_ offset: CGFloat) -> RailSlot<String>? {
            RailDrag.pairing(
                cardTop: 100 + offset,
                gapTop: 100,
                slot: RailSlot(.before("c")),
                rest: ["b", "c", "d"],
                groups: [:],
                lean: release,
            )
        }
        #expect(held(release) == .before("c", joining: .below))
        #expect(held(release - 1) == nil)
    }

    @Test("Just outside the superset the row was lifted from, a rest doesn't pair")
    func leavingOwnSuperset() {
        /// a lifted from a-b, b-c-d plain below: the slot below b is b's edge's outer slot.
        func pairing(_ offset: CGFloat, at place: RailSlot<String>.Place) -> RailSlot<String>? {
            RailDrag.pairing(
                cardTop: 100 + offset,
                gapTop: 100,
                slot: RailSlot(place),
                rest: ["b", "c", "d"],
                groups: ["b": 0],
                leaving: ["b"],
            )
        }
        #expect(pairing(lean, at: .before("c")) == nil)
        #expect(pairing(-lean, at: .before("c")) == nil)
        // One slot further on, it pairs.
        #expect(pairing(lean, at: .before("d")) == .before("d", joining: .below))
        #expect(pairing(-lean, at: .before("d")) == .before("d", joining: .above))
        // Above the superset, its top edge's outer slot.
        #expect(RailDrag.isOutside(0, of: ["b"], in: ["b", "c", "d"]))
        #expect(!RailDrag.isOutside(2, of: ["b"], in: ["b", "c", "d"]))
        #expect(!RailDrag.isOutside(1, of: ["b", "c"], in: ["b", "c", "d"]))
    }
}
