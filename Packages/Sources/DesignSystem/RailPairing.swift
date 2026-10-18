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

    /// The group a row takes on pairing with a plain one, while it is held.
    static let newGroup = -1

    /// The slot pairing the lifted row with the plain row its card lies over, `lean` or more past
    /// the gap at `slot`, or nil when it lies over neither neighbor, or over one in a group.
    /// Only a plain slot pairs: at a group's edge, the slot inside the group is the way in.
    static func pairing<ID: Hashable>(
        cardTop: CGFloat,
        gapTop: CGFloat,
        slot: RailSlot<ID>,
        rest: [ID],
        groups: [ID: Int],
        lean: CGFloat = pairLean,
    ) -> RailSlot<ID>? {
        guard slot.joining == nil else { return nil }
        let index = switch slot.place {
        case let .before(id): rest.firstIndex(of: id) ?? rest.endIndex
        case .end: rest.endIndex
        }
        let offset = cardTop - gapTop
        if offset <= -lean, index > 0, groups[rest[index - 1]] == nil {
            return RailSlot(slot.place, joining: .above)
        }
        if offset >= lean, index < rest.count, groups[rest[index]] == nil {
            return RailSlot(slot.place, joining: .below)
        }
        return nil
    }
}
