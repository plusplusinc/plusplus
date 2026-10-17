import SwiftUI

// What the rows show, where a held row's gap opens, which loops hide, and the held row's card.

extension Rail {
    /// The rows in the order they show: with a row held, the order it would make if dropped now.
    var shownRows: [Data.Element] {
        guard let drag else { return Array(data) }
        let byID = Dictionary(data.map { ($0.id, $0) }) { first, _ in first }
        return RailDrag.order(data.map(\.id), moving: drag.lifted, to: drag.slot)
            .compactMap { byID[$0] }
    }

    func candidates(lifting lifted: RowID) -> [RailDrag.Candidate<RowID>] {
        RailDrag.candidates(rows: measuredRows, lifted: lifted, groups: groups)
    }

    /// The top of the gap at `slot`, where the card rests when it is let go there.
    func gapTop(lifting lifted: RowID, at slot: RailSlot<RowID>) -> CGFloat? {
        candidates(lifting: lifted).first { $0.slot == slot }?.gapTop
    }

    /// The rows whose loops hide: those of a group with a row swiped open, which would otherwise
    /// leave its partners' stretches hanging.
    func loopsHidden(_ ids: [RowID]) -> Set<RowID> {
        guard !swiped.isEmpty else { return [] }
        let groups = RailDrag.groups(ids, joined: shownJoined)
        let open = Set(swiped.compactMap { groups[$0] })
        return Set(ids.filter { groups[$0].map(open.contains) ?? false })
    }

    func noteSwipe(_ id: RowID, _ isSwiped: Bool) {
        if isSwiped {
            swiped.insert(id)
        } else {
            swiped.remove(id)
        }
    }

    /// The held row drawn again as a card, its top at `y`. It rises as it appears and lowers as
    /// it settles; while held, it follows the finger with no animation, whatever animation moves
    /// the rows. Over a slot in a group, it draws the group's loop as its gap's row would, over the
    /// stretch it hides.
    @ViewBuilder
    func card(
        _ drag: RailDragState<RowID>,
        at y: CGFloat,
        link: RailLink,
        isFirst: Bool,
        isLast: Bool,
    ) -> some View {
        if let item = data.first(where: { $0.id == drag.lifted }) {
            row(item)
                // As tall as in the rows, where the scroll view proposes no height, not as tall
                // as the rail it is over.
                .fixedSize(horizontal: false, vertical: true)
                .modifier(CardLook(
                    isReleased: drag.isReleased,
                    hasRisen: momentOffset != nil,
                    link: link,
                    isFirst: isFirst,
                    isLast: isLast,
                ))
                .offset(y: y)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
