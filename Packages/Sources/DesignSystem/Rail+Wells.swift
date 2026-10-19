import SwiftUI

// The held row's superset's well, drawn by the rail under its strokes while the row is held. And
// room above the rail, so a held superset first in the list comes no nearer what is above it than
// its well's top would be in its rows' place.

extension Rail {
    /// The well of the rows from `rows.lowerBound` to `rows.upperBound` in the rail's space, with
    /// `card`'s ends, or nil until the rows have reported their nodes.
    func wellOutline(rows: ClosedRange<CGFloat>, card: WellCard = WellCard()) -> WellOutline? {
        railNode.map { WellOutline(rows: rows, node: $0, pen: pen, card: card) }
    }

    /// While a row is held, the well of the superset the held row is in, or would be in if
    /// dropped now, as `held` shows it, under the rail's strokes. No other superset shows a well:
    /// its loop shows its rows, and only where the thumb is over the rows does the well help. The
    /// well fades in as the card rises, and out as it settles, on the drop's transaction. It is
    /// named by its superset's first row other than the held one, so as the held row moves in
    /// that superset, or the superset grows or shrinks, one well changes shape on the slot's
    /// transaction.
    @ViewBuilder
    func drawnWells(held: HeldWell?) -> some View {
        if let drag {
            GeometryReader { proxy in
                if let held {
                    HeldWellFill(
                        outline: held.outline,
                        width: proxy.size.width,
                        isReleased: drag.isReleased,
                        hasRisen: isMoment,
                    )
                    .id(held.key)
                    // The held row leaving the superset, it fades on the slot's transaction.
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.identity)
        }
    }

    /// How far above the rail's top what the rows show while a row is held would reach, past
    /// where a superset first in the list would have its well's top in its rows' place: the held
    /// row's superset's well where the card leads it, or the first row, moved up out of a pair's
    /// way. Read from the drag's state, the card placed where its slot puts it, not where the
    /// finger has it, so it changes only as a pair forms or comes apart, not as the finger wobbles.
    func roomAbove(_ drag: RailDragState<RowID>) -> CGFloat {
        guard !drag.isReleased, !drag.isOverBar, let rest = wellOutline(rows: 0 ... 0)?.top
        else { return 0 }
        let ids = shownRows.map(\.id)
        // A paired card lies over its partner, below its gap or above it.
        let lead = !drag.isPaired ? 0 : drag.slot.joining == .below ? drag.shift : -drag.shift
        var top = heldWell(drag, cardY: gapTop(of: drag) + lead)?.outline.top ?? rest
        if let first = ids.first, first != drag.lifted {
            top = min(top, rest + (pairShifts(ids).rows[first] ?? 0))
        }
        return max(0, rest - top)
    }

    /// The rows of the superset `row` is in at rest, or the row alone.
    func restGroup(of row: RowID) -> Set<RowID> {
        let groups = groups
        guard let group = groups[row] else { return [row] }
        return Set(data.map(\.id).filter { groups[$0] == group })
    }
}
