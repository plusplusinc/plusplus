import SwiftUI

/// Where a row dragged on a rail lands. A slot names a row by id, not an index, so it still means
/// the same place if the rows change under it.
public nonisolated enum RailSlot<ID: Hashable>: Hashable {
    /// Just above this row.
    case before(ID)
    /// After the last row.
    case end
}

extension RailSlot: Sendable where ID: Sendable { }

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

    /// Where the held finger is: its y in the rail's space, and on screen.
    struct Finger {
        var inRail: CGFloat
        var onScreen: CGFloat
    }

    /// The rail's coordinate space, in which the gesture reports where the finger is.
    static let space = "rail"

    /// How long a press holds still before the row lifts: quicker than a context menu, so the
    /// thumb doesn't tire, and long enough that a slow scroll has moved off first.
    static let hold: TimeInterval = 0.4
    /// How far a press may move before the hold fires. Further, and it is a scroll.
    static let allowableMovement: CGFloat = 10

    /// The card's lift, and its settling back.
    static let lift = Animation.snappy(duration: 0.18)
    static let liftedScale: CGFloat = 1.03
    static let liftedRotation = Angle.degrees(-0.6)

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

    /// A place the lifted row could land, and the top of its gap in the rail's space.
    struct Candidate<ID: Hashable>: Equatable {
        var slot: RailSlot<ID>
        var gapTop: CGFloat
    }

    /// One candidate per boundary between the rows other than the lifted one, top to bottom: a
    /// gap opens above each in turn, and after the last.
    static func candidates<ID: Hashable>(
        rows: [(id: ID, height: CGFloat)],
        lifted: ID,
    ) -> [Candidate<ID>] {
        var top: CGFloat = 0
        var candidates: [Candidate<ID>] = []
        for row in rows where row.id != lifted {
            candidates.append(Candidate(slot: .before(row.id), gapTop: top))
            top += row.height
        }
        candidates.append(Candidate(slot: .end, gapTop: top))
        return candidates
    }

    /// The slot whose gap is nearest the card's top. The gap moves past a row once the card has
    /// traveled half that row's height, the same felt point for one line, two, or the largest
    /// text, and leaving `current` takes `deadBand` more.
    static func candidate<ID: Hashable>(
        for cardTop: CGFloat,
        in candidates: [Candidate<ID>],
        current: RailSlot<ID>?,
    ) -> RailSlot<ID> {
        guard !candidates.isEmpty else { return .end }
        func midpoint(_ index: Int) -> CGFloat {
            (candidates[index].gapTop + candidates[index + 1].gapTop) / 2
        }
        let nearest = (0 ..< candidates.count - 1).first { cardTop < midpoint($0) }
            ?? candidates.count - 1
        guard let current, let held = candidates.firstIndex(where: { $0.slot == current }),
              held != nearest
        else { return candidates[nearest].slot }
        let stays = nearest > held
            ? cardTop < midpoint(held) + deadBand
            : cardTop > midpoint(held - 1) - deadBand
        return candidates[stays ? held : nearest].slot
    }

    /// `ids` as they show while `lifted` is held over `slot`: the lifted row in the gap.
    static func order<ID: Hashable>(_ ids: [ID], moving lifted: ID, to slot: RailSlot<ID>) -> [ID] {
        guard ids.contains(lifted) else { return ids }
        var order = ids.filter { $0 != lifted }
        switch slot {
        case let .before(target):
            order.insert(lifted, at: order.firstIndex(of: target) ?? order.endIndex)
        case .end:
            order.append(lifted)
        }
        return order
    }

    /// Where the held finger has been on screen since the row lifted. An edge's band scrolls the
    /// list only once the finger has gone toward that edge since the lift, as far as turns a press
    /// into a scroll, so a row lifted in a band and held still stays put, and lands where it was.
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

        var hasGoneUp: Bool {
            start - span.lowerBound >= allowableMovement
        }

        var hasGoneDown: Bool {
            span.upperBound - start >= allowableMovement
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
            return travel.hasGoneUp ? -edgeTopSpeed * pow(min(intoTop, 1), 2) : 0
        }
        if intoBottom > 0 {
            return travel.hasGoneDown ? edgeTopSpeed * pow(min(intoBottom, 1), 2) : 0
        }
        return 0
    }
}
