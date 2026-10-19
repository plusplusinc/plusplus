import SwiftUI

// A row held still over a plain neighbor pairs with it, as a new group: like an app held on
// another to make a folder. A drag that moves on, or pauses briefly, only moves the row, so
// reordering is as it was, and a group forms only when the thumb rests on purpose.

nonisolated extension RailDrag {
    /// How far the card must lie over a plain neighbor, past its gap, to pair with it: half the
    /// way to where the gap moves past a one-line row, so a card that is simply carried there and
    /// held over its gap never pairs.
    static let pairLean: CGFloat = 16
    /// How long the card must rest over a plain neighbor before the two pair: long enough that a
    /// pause before a drop doesn't pair, short enough not to feel like waiting.
    static let pairDwell: Duration = .milliseconds(500)
    /// How far the card may wander while it rests, and still pair.
    static let pairSlop: CGFloat = 6
    /// How far past its gap a paired card must stay for the pair to hold: less than the lean, so
    /// a pair holds while the thumb settles.
    static let pairRelease: CGFloat = 8
    /// The tap as a pair forms: firmer than a slot's tick, so it is felt as something made.
    static let pairFormed = SensoryFeedback.impact(weight: .medium)

    /// The group a row takes on pairing with a plain one, while it is held. Real groups are
    /// numbered from 0 by where they start, so this one never names a group at rest.
    static let newGroup = -1

    /// The slot pairing the lifted row with the plain row its card lies over, `lean` or more past
    /// the gap at `slot`, or nil when it lies over neither neighbor, or over one in a group.
    /// Only a plain slot pairs: at a group's edge, the slot inside the group is the way in. Nor
    /// does the slot just outside the group the row was lifted from, `leaving`, its partners
    /// there: a drop there leaves the group, so a member dragged out of its superset doesn't
    /// pair with the next row as it goes; a further slot, or the node, pairs it.
    static func pairing<ID: Hashable>(
        cardTop: CGFloat,
        gapTop: CGFloat,
        slot: RailSlot<ID>,
        rest: [ID],
        groups: [ID: Int],
        leaving: Set<ID> = [],
        lean: CGFloat = pairLean,
    ) -> RailSlot<ID>? {
        guard slot.joining == nil else { return nil }
        let index = switch slot.place {
        case let .before(id): rest.firstIndex(of: id) ?? rest.endIndex
        case .end: rest.endIndex
        }
        guard !isOutside(index, of: leaving, in: rest) else { return nil }
        let offset = cardTop - gapTop
        if offset <= -lean, index > 0, groups[rest[index - 1]] == nil {
            return RailSlot(slot.place, joining: .above)
        }
        if offset >= lean, index < rest.count, groups[rest[index]] == nil {
            return RailSlot(slot.place, joining: .below)
        }
        return nil
    }

    /// Whether the boundary above `rest[index]` is an edge of the rows `group`, just outside it:
    /// one of the rows either side is in it and the other isn't.
    static func isOutside<ID: Hashable>(_ index: Int, of group: Set<ID>, in rest: [ID]) -> Bool {
        let above = index > 0 && group.contains(rest[index - 1])
        let below = index < rest.count && group.contains(rest[index])
        return above != below
    }

    /// The rest toward pairing with `target` once the card is at `cardTop`: `current`, unchanged,
    /// while the card stays over the same slot within `pairSlop` of where it came to rest, so its
    /// countdown runs on; a new rest anchored at `cardTop` over any other; and none with no
    /// target.
    static func dwell<ID: Hashable>(
        _ current: RailDwell<ID>?,
        over target: RailSlot<ID>?,
        cardTop: CGFloat,
    ) -> RailDwell<ID>? {
        guard let target else { return nil }
        if let current, current.target == target, abs(cardTop - current.anchor) <= pairSlop {
            return current
        }
        return RailDwell(target: target, anchor: cardTop)
    }
}

/// The card resting over a plain neighbor: the slot that pairs the two, and where the card was
/// when it came to rest. A new value starts the countdown to pairing again.
nonisolated struct RailDwell<ID: Hashable>: Equatable {
    var target: RailSlot<ID>
    var anchor: CGFloat
}
