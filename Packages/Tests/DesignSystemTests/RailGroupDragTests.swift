import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// Groups on a rail as a drag sees them: their slots, the row under the finger, and their links.
@Suite("Rail group drag")
struct RailGroupDragTests {
    /// Rows a to e, 64 pt each.
    private let rows: [(id: String, height: CGFloat)] = ["a", "b", "c", "d", "e"].map { ($0, 64) }
    private var ids: [String] {
        rows.map(\.id)
    }

    private let spread = RailDrag.edgeSlotSpread

    @Test("Rows joined to the next are grouped, numbered by where the group starts")
    func groups() {
        #expect(RailDrag.groups(ids, joined: ["b", "c"]) == ["b": 1, "c": 1, "d": 1])
        #expect(RailDrag.groups(ids, joined: ["a", "d"]) == ["a": 0, "b": 0, "d": 3, "e": 3])
        #expect(RailDrag.groups(ids, joined: ["e"]).isEmpty)
    }

    @Test("A group's edge has a slot inside it and one outside; inside it, one")
    func edgeSlots() {
        // b-c grouped, a lifted: boundaries above b, above c, above d, and the end.
        let groups = RailDrag.groups(ids, joined: ["b"])
        let candidates = RailDrag.candidates(rows: rows, lifted: "a", groups: groups)
        #expect(candidates == [
            .init(slot: .before("b"), gapTop: 0),
            .init(slot: .before("b", joining: .below), gapTop: 0),
            .init(slot: .before("c", joining: .above), gapTop: 64),
            .init(slot: .before("d", joining: .above), gapTop: 128),
            .init(slot: .before("d"), gapTop: 128),
            .init(slot: .before("e"), gapTop: 192),
            .init(slot: .end, gapTop: 256),
        ])
    }

    @Test("Between two groups, a slot inside each and one between")
    func betweenGroups() {
        let groups = RailDrag.groups(ids, joined: ["a", "c"])
        let candidates = RailDrag.candidates(rows: rows, lifted: "e", groups: groups)
            .filter { $0.slot.place == .before("c") }
        #expect(candidates.map(\.slot.joining) == [.above, nil, .below])
    }

    @Test("Plain rows keep one slot per boundary")
    func plainUnchanged() {
        let candidates = RailDrag.candidates(rows: rows, lifted: "a", groups: [:])
        #expect(candidates.count == 5)
        #expect(candidates.allSatisfy { $0.slot.joining == nil })
    }

    @Test("Crossing a group's edge switches inside and outside at the edge itself")
    func crossingEdge() {
        let groups = RailDrag.groups(ids, joined: ["b"])
        let candidates = RailDrag.candidates(rows: rows, lifted: "a", groups: groups)
        func slot(_ top: CGFloat) -> RailSlot<String> {
            RailDrag.candidate(for: top, in: candidates, current: nil)
        }
        #expect(slot(-1) == .before("b"))
        #expect(slot(1) == .before("b", joining: .below))
        #expect(slot(127) == .before("d", joining: .above))
        #expect(slot(129) == .before("d"))
    }

    @Test("Leaving a slot at a group's edge for the other takes the spread past the edge, either way")
    func edgeHysteresis() {
        let groups = RailDrag.groups(ids, joined: ["b"])
        let candidates = RailDrag.candidates(rows: rows, lifted: "a", groups: groups)
        func slot(_ top: CGFloat, from current: RailSlot<String>) -> RailSlot<String> {
            RailDrag.candidate(for: top, in: candidates, current: current)
        }
        let (inside, outside) = (RailSlot.before("d", joining: .above), RailSlot.before("d"))
        // A member held at its group's bottom edge, nudged out, stays in.
        #expect(slot(128 + 3, from: inside) == inside)
        #expect(slot(128 + spread - 1, from: inside) == inside)
        #expect(slot(128 + spread + 1, from: inside) == outside)
        // A plain row comes in as far past the edge, the other way.
        #expect(slot(128 - 3, from: outside) == outside)
        #expect(slot(128 - spread + 1, from: outside) == outside)
        #expect(slot(128 - spread - 1, from: outside) == inside)
        // The top edge, mirrored.
        let (top, above) = (RailSlot.before("b", joining: .below), RailSlot.before("b"))
        #expect(slot(-spread + 1, from: top) == top)
        #expect(slot(-spread - 1, from: top) == above)
        #expect(slot(spread - 1, from: above) == above)
        #expect(slot(spread + 1, from: above) == top)
    }

    @Test("Between two groups, the plain slot is reached from either side")
    func betweenGroupsHysteresis() {
        // a-b and c-d, e lifted: the boundary above c is at 128.
        let groups = RailDrag.groups(ids, joined: ["a", "c"])
        let candidates = RailDrag.candidates(rows: rows, lifted: "e", groups: groups)
        func slot(_ top: CGFloat, from current: RailSlot<String>) -> RailSlot<String> {
            RailDrag.candidate(for: top, in: candidates, current: current)
        }
        let upper = RailSlot.before("c", joining: .above)
        let plain = RailSlot.before("c")
        let lower = RailSlot.before("c", joining: .below)
        #expect(slot(128 + 3, from: upper) == upper)
        #expect(slot(128 + spread, from: upper) == plain)
        #expect(slot(128 + spread / 2, from: plain) == plain)
        #expect(slot(128 + spread + 2 * RailDrag.deadBand, from: plain) == lower)
        #expect(slot(128 - 3, from: lower) == lower)
        #expect(slot(128 - spread, from: lower) == plain)
    }

    @Test("A member lifted from a pair starts in the slot inside, beside its partner")
    func origin() {
        let groups = RailDrag.groups(ids, joined: ["a"])
        let candidates = RailDrag.candidates(rows: rows, lifted: "b", groups: groups)
        #expect(RailDrag.origin(of: "b", in: ids, candidates: candidates, groups: groups)
            == .before("c", joining: .above))
        let first = RailDrag.candidates(rows: rows, lifted: "a", groups: groups)
        #expect(RailDrag.origin(of: "a", in: ids, candidates: first, groups: groups)
            == .before("b", joining: .below))
        let plain = RailDrag.candidates(rows: rows, lifted: "d", groups: groups)
        #expect(RailDrag.origin(of: "d", in: ids, candidates: plain, groups: groups)
            == .before("e"))
    }

    @Test("Held over a slot inside a group, the gap's row is drawn in it")
    func joinedWhileHeld() {
        // b-c, d lifted into the slot inside c's bottom edge.
        #expect(RailDrag.joined(ids, joined: ["b"], moving: "d", to: .before("e", joining: .above))
            == ["b", "c"])
        #expect(RailDrag.joined(ids, joined: ["b"], moving: "d", to: .before("e")) == ["b"])
        // b lifted out of b-c: c is on its own.
        #expect(RailDrag.joined(ids, joined: ["b"], moving: "b", to: .end).isEmpty)
    }

    @Test("The row under the finger, clamped, with a dead band at its edges")
    func reach() {
        let band = RailDrag.deadBand
        #expect(RailDrag.reach(fingerY: -10, rows: rows, current: nil) == "a")
        #expect(RailDrag.reach(fingerY: 70, rows: rows, current: nil) == "b")
        #expect(RailDrag.reach(fingerY: 400, rows: rows, current: nil) == "e")
        #expect(RailDrag.reach(fingerY: 64 + band - 1, rows: rows, current: "a") == "a")
        #expect(RailDrag.reach(fingerY: 64 + band + 1, rows: rows, current: "a") == "b")
        #expect(RailDrag.reach(fingerY: 64 - band + 1, rows: rows, current: "b") == "b")
    }

    @Test("Links read solo, first, middle, last")
    func links() {
        let links = RailLink.links(ids, joined: ["a", "b", "d"])
        #expect(links == ["a": .first, "b": .middle, "c": .last, "d": .first, "e": .last])
        #expect(RailLink.links(["a"], joined: ["a"]) == ["a": .solo])
    }
}
