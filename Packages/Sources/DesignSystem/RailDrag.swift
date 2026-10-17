import SwiftUI

/// Where a row dragged on a rail lands. A slot names a row by id, not an index, so it still means
/// the same place if the rows change under it.
public nonisolated struct RailSlot<ID: Hashable>: Hashable {
    public enum Place: Hashable {
        /// Just above this row.
        case before(ID)
        /// After the last row.
        case end
    }

    public var place: Place
    /// The neighbor whose group the row joins there, or nil to land on its own. Between two rows
    /// of one group a row always joins it.
    public var joining: RailNeighbor?

    public init(_ place: Place, joining: RailNeighbor? = nil) {
        self.place = place
        self.joining = joining
    }

    /// Just above `id`.
    public static func before(_ id: ID, joining: RailNeighbor? = nil) -> Self {
        Self(.before(id), joining: joining)
    }

    /// After the last row.
    public static var end: Self {
        Self(.end)
    }
}

extension RailSlot: Sendable where ID: Sendable { }
extension RailSlot.Place: Sendable where ID: Sendable { }

/// The row next to a slot: the one above it, or below.
public nonisolated enum RailNeighbor: Hashable, Sendable {
    case above
    case below
}

/// A row held and dragged along its rail: the timings and sizes of the lift, the gap, and the
/// drop, and the pure arithmetic of where the gap goes, so it is tested without a touch.
///
/// The drag never works in indices. It hit-tests the card against candidates, one per slot the
/// lifted row could take, each at the y in the rail where its gap would open.
nonisolated enum RailDrag {
    /// A step of the drag, as the gesture reports it.
    enum Phase {
        case began
        case changed
        case ended
        case cancelled
    }

    /// Where the held finger is: its y in the rail's space, and in the scroll view's.
    struct Finger {
        var inRail: CGFloat
        var inScrollView: CGFloat
        /// In the rail column, on the node, rather than on the row's content.
        var inColumn = false
    }

    /// The rail's coordinate space, in which the gesture reports where the finger is.
    static let space = "rail"
    /// The space of the scroll view the rail scrolls in, whose frame is the area the list shows
    /// in, between the bars.
    static let scrollSpace = "railScrollView"

    /// How long a press holds still before the row lifts: quicker than a context menu, so the
    /// thumb doesn't tire, and long enough that a slow scroll has moved off first.
    static let hold: TimeInterval = 0.4
    /// How far a press may move before the hold fires. Further, and it is a scroll.
    static let allowableMovement: CGFloat = 10

    /// The card's lift, and its settling back.
    static let lift = Animation.snappy(duration: 0.18)
    /// The blur of the card's shadow: soft and centered, with no offset, so it reads as lifted
    /// without moving the card off the rail.
    static let liftedShadow: CGFloat = 8

    /// The rows moving aside as the gap goes to a new slot: quicker than `.railChange`.
    static let gap = Animation.snappy(duration: 0.2)
    /// The card settling into the gap as it is dropped.
    static let drop = Animation.snappy(duration: 0.22)
    /// The card going back to its row when the drag is cancelled.
    static let cancel = Animation.snappy(duration: 0.25)

    /// The tick as the gap moves to a new slot: a step up from `.selection`, which was too faint
    /// to feel mid-set, and unlike the lift's light impact. Not `.alignment`: on iPhone it plays
    /// nothing, as it is canvas feedback, for Apple Pencil Pro on iPad.
    static let slotChange = SensoryFeedback.impact(flexibility: .rigid, intensity: 0.6)

    /// How far past a switch point the card must go to leave the slot it is in, so the gap
    /// doesn't flap, and tick, at the boundary.
    static let deadBand: CGFloat = 4

    /// How deep the band at each end of the visible area is where a held row scrolls the list.
    static let edgeZone: CGFloat = 64
    /// How fast the list scrolls with the finger at the very edge, in points a second.
    static let edgeTopSpeed: CGFloat = 900

    /// How far past a group's edge the card must go to switch between the slot inside the group
    /// and the one outside it, either way, so a member lifted to look at it, or a wobble near the
    /// edge, doesn't leave the group, and a row joins one only on a deliberate move.
    static let edgeSlotSpread: CGFloat = 24

    /// A place the lifted row could land, and the top of its gap in the rail's space. At a
    /// group's edge, the slots inside and outside the group share a gap.
    struct Candidate<ID: Hashable>: Equatable {
        var slot: RailSlot<ID>
        var gapTop: CGFloat
    }

    /// The candidates at each boundary between the rows other than the lifted one, top to
    /// bottom: a gap opens above each row in turn, and after the last. Between plain rows, or two
    /// rows of one group, there is one; at a group's edge, one inside the group and one outside,
    /// and between two groups, one inside each and one between. `groups` names each grouped row's
    /// group, as `groups(_:joined:)` gives it.
    static func candidates<ID: Hashable>(
        rows: [(id: ID, height: CGFloat)],
        lifted: ID,
        groups: [ID: Int] = [:],
    ) -> [Candidate<ID>] {
        var top: CGFloat = 0
        var candidates: [Candidate<ID>] = []
        var above: ID?
        func boundary(_ place: RailSlot<ID>.Place, below: ID?) {
            let upper = above.flatMap { groups[$0] }
            let lower = below.flatMap { groups[$0] }
            if let upper, upper == lower {
                candidates.append(Candidate(slot: RailSlot(place, joining: .above), gapTop: top))
                return
            }
            if upper != nil {
                candidates.append(Candidate(slot: RailSlot(place, joining: .above), gapTop: top))
            }
            candidates.append(Candidate(slot: RailSlot(place), gapTop: top))
            if lower != nil {
                candidates.append(Candidate(slot: RailSlot(place, joining: .below), gapTop: top))
            }
        }
        for row in rows where row.id != lifted {
            boundary(.before(row.id), below: row.id)
            top += row.height
            above = row.id
        }
        boundary(.end, below: nil)
        return candidates
    }

    /// The slot the lifted row was lifted from, where dropping it changes nothing: its own place,
    /// in its own group, or none.
    static func origin<ID: Hashable>(
        of lifted: ID,
        in ids: [ID],
        candidates: [Candidate<ID>],
        groups: [ID: Int],
    ) -> RailSlot<ID>? {
        guard let index = ids.firstIndex(of: lifted) else { return nil }
        let place: RailSlot<ID>.Place = index + 1 < ids.count ? .before(ids[index + 1]) : .end
        let rest = ids.filter { $0 != lifted }
        return candidates.first { candidate in
            candidate.slot.place == place
                && group(joinedAt: candidate.slot, in: rest, groups: groups) == groups[lifted]
        }?.slot
    }

    /// The group a row dropped at `slot` among `rest` joins, or nil for none.
    static func group<ID: Hashable>(
        joinedAt slot: RailSlot<ID>,
        in rest: [ID],
        groups: [ID: Int],
    ) -> Int? {
        let index = switch slot.place {
        case let .before(id): rest.firstIndex(of: id) ?? rest.endIndex
        case .end: rest.endIndex
        }
        let above = index > 0 ? groups[rest[index - 1]] : nil
        let below = index < rest.count ? groups[rest[index]] : nil
        switch slot.joining {
        case .above: return above
        case .below: return below
        case nil: return above != nil && above == below ? above : nil
        }
    }

    /// Each grouped row's group, numbered by where it starts in `ids`: a row joined to the next,
    /// as `joined` has it, is in a group with it.
    static func groups<ID: Hashable>(_ ids: [ID], joined: Set<ID>) -> [ID: Int] {
        var groups: [ID: Int] = [:]
        var start: Int?
        for (index, id) in ids.enumerated() {
            let fromAbove = index > 0 && joined.contains(ids[index - 1])
            let toBelow = index + 1 < ids.count && joined.contains(id)
            if !fromAbove {
                start = toBelow ? index : nil
            }
            if let start {
                groups[id] = start
            }
        }
        return groups
    }

    /// The rows joined to the next in `ids`, by `groups`: each row whose next row is in its group.
    static func joined<ID: Hashable>(_ ids: [ID], groups: [ID: Int]) -> Set<ID> {
        Set(zip(ids, ids.dropFirst()).compactMap { row, next in
            groups[row] != nil && groups[row] == groups[next] ? row : nil
        })
    }

    /// The rows joined to the next while `lifted` is held over `slot`: as at rest, the lifted row
    /// out of its own group and in the one the slot joins.
    static func joined<ID: Hashable>(
        _ ids: [ID],
        joined: Set<ID>,
        moving lifted: ID,
        to slot: RailSlot<ID>,
    ) -> Set<ID> {
        var groups = groups(ids, joined: joined)
        groups[lifted] = group(joinedAt: slot, in: ids.filter { $0 != lifted }, groups: groups)
        return Self.joined(order(ids, moving: lifted, to: slot), groups: groups)
    }

    /// The row the finger is over, from `rows`' heights stacked from 0: the first above them and
    /// the last below them. Leaving `current` takes `deadBand` past its edge.
    static func reach<ID: Hashable>(
        fingerY: CGFloat,
        rows: [(id: ID, height: CGFloat)],
        current: ID?,
    ) -> ID? {
        // Each row's top, and the bottom of the last.
        let edges = rows.reduce(into: [CGFloat(0)]) { edges, row in
            edges.append((edges.last ?? 0) + row.height)
        }
        if let held = rows.firstIndex(where: { $0.id == current }),
           fingerY >= edges[held] - deadBand, fingerY < edges[held + 1] + deadBand
        {
            return rows[held].id
        }
        let under = rows.indices.first { fingerY < edges[$0 + 1] } ?? rows.indices.last
        return under.map { rows[$0].id }
    }

    /// The slot whose gap is nearest the card's top. The gap moves past a row once the card has
    /// traveled half that row's height, the same felt point for one line, two, or the largest
    /// text, and leaving `current` takes `deadBand` more. At a group's edge, where the slots
    /// inside and outside share a gap, the card switches between them at the gap's top, but
    /// leaving `current` there takes `edgeSlotSpread` more: a member lifted from its group's edge
    /// stays in it until the card goes that far out, and a row comes in from outside only as far
    /// past the edge.
    static func candidate<ID: Hashable>(
        for cardTop: CGFloat,
        in candidates: [Candidate<ID>],
        current: RailSlot<ID>?,
    ) -> RailSlot<ID> {
        guard !candidates.isEmpty else { return .end }
        let lines = candidates.indices.dropLast().map { switchLine(after: $0, in: candidates) }
        let nearest = lines.firstIndex { cardTop < $0.y } ?? candidates.count - 1
        guard let current, var index = candidates.firstIndex(where: { $0.slot == current })
        else { return candidates[nearest].slot }
        // Step toward the nearest across each line the card is far enough past.
        while index < nearest, cardTop >= lines[index].y + lines[index].margin {
            index += 1
        }
        while index > nearest, cardTop <= lines[index - 1].y - lines[index - 1].margin {
            index -= 1
        }
        return candidates[index].slot
    }

    /// Where the card's top switches from `candidates[index]` to the next, and how far past it
    /// the card must go to leave the one it is in. Between boundaries, halfway between their
    /// gaps. At one boundary, at its gap: between two groups, where a plain slot sits between the
    /// slots inside each, `deadBand` either side of it, so the plain slot can be reached.
    private static func switchLine<ID: Hashable>(
        after index: Int,
        in candidates: [Candidate<ID>],
    ) -> (y: CGFloat, margin: CGFloat) {
        let (upper, lower) = (candidates[index], candidates[index + 1])
        guard upper.slot.place == lower.slot.place else {
            return ((upper.gapTop + lower.gapTop) / 2, deadBand)
        }
        let isBetweenGroups = candidates.count(where: { $0.slot.place == upper.slot.place }) > 2
        let offset = isBetweenGroups ? (lower.slot.joining == .below ? deadBand : -deadBand) : 0
        return (upper.gapTop + offset, edgeSlotSpread)
    }

    /// `ids` as they show while `lifted` is held over `slot`: the lifted row in the gap.
    static func order<ID: Hashable>(_ ids: [ID], moving lifted: ID, to slot: RailSlot<ID>) -> [ID] {
        guard ids.contains(lifted) else { return ids }
        var order = ids.filter { $0 != lifted }
        switch slot.place {
        case let .before(target):
            order.insert(lifted, at: order.firstIndex(of: target) ?? order.endIndex)
        case .end:
            order.append(lifted)
        }
        return order
    }

    /// How far the held finger must go toward an edge, since the lift, before that edge's band
    /// scrolls the list: as far as turns a press into a scroll, or, lifted nearer the edge than
    /// that, to the edge, so the band arms without the finger going over a bar.
    static let edgeArming: CGFloat = 10

    /// Where the held finger has been since the row lifted. An edge's band scrolls the list only
    /// once the finger has gone `edgeArming` toward that edge, so a row lifted in a band and held
    /// still stays put, and lands where it was.
    struct Travel {
        let start: CGFloat
        private(set) var span: ClosedRange<CGFloat>

        init(from y: CGFloat) {
            start = y
            span = y ... y
        }

        mutating func pass(_ y: CGFloat) {
            span = min(span.lowerBound, y) ... max(span.upperBound, y)
        }

        /// Whether the finger has gone far enough toward the edge at `top`, at least a point.
        func hasGoneUp(toward top: CGFloat) -> Bool {
            start - span.lowerBound >= min(edgeArming, max(start - top, 1))
        }

        /// Whether the finger has gone far enough toward the edge at `bottom`, at least a point.
        func hasGoneDown(toward bottom: CGFloat) -> Bool {
            span.upperBound - start >= min(edgeArming, max(bottom - start, 1))
        }
    }

    /// How fast to scroll, in points a second, with the finger at `fingerY` in a visible area
    /// spanning `visible`: nothing outside the bands at its ends, or in a band the finger hasn't
    /// gone toward since the lift, then rising as the square of how deep the finger is in one,
    /// slow near its inner line for precision and fast at the edge to cross a long list. Up is
    /// negative. A finger past the edge counts as at it.
    static func edgeSpeed(
        fingerY: CGFloat,
        visible: ClosedRange<CGFloat>,
        travel: Travel,
    ) -> CGFloat {
        let zone = min(edgeZone, (visible.upperBound - visible.lowerBound) / 2)
        guard zone > 0 else { return 0 }
        let intoTop = (visible.lowerBound + zone - fingerY) / zone
        let intoBottom = (fingerY - (visible.upperBound - zone)) / zone
        if intoTop > 0 {
            guard travel.hasGoneUp(toward: visible.lowerBound) else { return 0 }
            return -edgeTopSpeed * pow(min(intoTop, 1), 2)
        }
        if intoBottom > 0 {
            guard travel.hasGoneDown(toward: visible.upperBound) else { return 0 }
            return edgeTopSpeed * pow(min(intoBottom, 1), 2)
        }
        return 0
    }
}
