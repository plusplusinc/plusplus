import SwiftUI

// Supersets' wells: at rest each row draws its stretch; while a row or node is held the rail
// draws them all, under its strokes. And room above the rail, so a held superset first in the
// list comes no nearer what is above it than at rest.

extension Rail {
    /// The well of the rows from `rows.lowerBound` to `rows.upperBound` in the rail's space, with
    /// `card`'s ends, or nil until the rows have reported their nodes.
    func wellOutline(rows: ClosedRange<CGFloat>, card: WellCard = WellCard()) -> WellOutline? {
        railNode.map { WellOutline(rows: rows, node: $0, pen: pen, card: card) }
    }

    /// While a row or node is held, every superset's well, drawn here, under the rail's strokes,
    /// which the rows' own wells, drawn with the rows, would cover: the held row's superset as
    /// `held` shows it, and every other as the rows' own would draw it, placed from the rows'
    /// nodes, so it moves as they do. Each is named by its first row other than the held one, so
    /// as the held row comes into a superset or leaves it, that superset's one well changes shape
    /// on the slot's transaction, rather than one well fading over another. A superset a node's
    /// field wraps any of lies under the field; the rest of it shows around a field of one of its
    /// rows. A superset with a row swiped open draws none, as at rest.
    @ViewBuilder
    func drawnWells(_ nodes: [AnyHashable: Anchor<CGPoint>], held: HeldWell?) -> some View {
        if drag != nil || regrouping != nil {
            GeometryReader { proxy in
                ForEach(wellItems(nodes, in: proxy, held: held)) { item in
                    WellFill(outline: item.outline, width: proxy.size.width)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.identity)
        }
    }

    /// The wells `drawnWells` draws: every superset's, from the rows' nodes, but the held row's,
    /// which `held` draws, last, over the others, as the card is over the rows.
    private func wellItems(
        _ nodes: [AnyHashable: Anchor<CGPoint>],
        in proxy: GeometryProxy,
        held: HeldWell?,
    ) -> [RailWellItem] {
        let ids = shownRows.map(\.id)
        let groups = RailDrag.groups(ids, joined: shownJoined)
        let heldGroup = held == nil ? nil : drag.flatMap { groups[$0.lifted] }
        let skipped = loopsHidden(ids)
        var items: [RailWellItem] = []
        var seen: Set<Int> = []
        for id in ids {
            guard let group = groups[id], group != heldGroup, seen.insert(group).inserted
            else { continue }
            let rows = ids.filter { groups[$0] == group }
            guard rows.allSatisfy({ !skipped.contains($0) }),
                  let first = rows.first, let last = rows.last,
                  let key = rows.first(where: { $0 != drag?.lifted }),
                  let top = rowTop(first, nodes, in: proxy),
                  let lastTop = rowTop(last, nodes, in: proxy),
                  let outline = wellOutline(
                      rows: top ... max(top, lastTop + (heights.byID[last] ?? 0)),
                  )
            else { continue }
            items.append(RailWellItem(id: AnyHashable(key), outline: outline))
        }
        if let held {
            items.append(RailWellItem(id: held.key, outline: held.outline))
        }
        return items
    }

    /// A row's top in the rail's space, from where its node is drawn.
    private func rowTop(
        _ id: RowID,
        _ nodes: [AnyHashable: Anchor<CGPoint>],
        in proxy: GeometryProxy,
    ) -> CGFloat? {
        guard let anchor = nodes[AnyHashable(id)], let node = railNode else { return nil }
        return proxy[anchor].y - node.y
    }

    /// How far above the rail's top what the rows show while a row is held would reach, past
    /// where a superset first in the list has its well's top at rest: the held row's superset's
    /// well where the card leads it, or the first row, moved up out of a pair's way. Read from the
    /// drag's state, the card placed where its slot puts it, not where the finger has it, so it
    /// changes only as a pair forms or comes apart, not as the finger wobbles.
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

    /// Scrolls the list by `change` in the room above the rail, as the room opens or closes, so
    /// the rows stay put on the screen and what is above the rail moves up, clear of them. Where
    /// the list can't scroll that far, the rows move with the room, and the card goes the other
    /// way, staying under the finger.
    func makeRoom(_ change: CGFloat) {
        guard let held = drag, !held.isReleased, change != 0 else { return }
        let scrolled = edges?.makeRoom(change, animation: reduceMotion ? nil : RailDrag.gap) ?? 0
        cardTop -= change - scrolled
    }

    /// The rows of the superset `row` is in at rest, or the row alone.
    func restGroup(of row: RowID) -> Set<RowID> {
        let groups = groups
        guard let group = groups[row] else { return [row] }
        return Set(data.map(\.id).filter { groups[$0] == group })
    }
}

/// A superset's well while a row or node is held, named by its first row other than the held one.
struct RailWellItem: Identifiable {
    let id: AnyHashable
    let outline: WellOutline
}
