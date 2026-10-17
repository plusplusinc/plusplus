import SwiftUI

// What the rows show, where a held row's gap opens, which loops hide, and the held row's card.

extension Rail {
    /// The rows in the order they show: with a row held, the order it would make if dropped now.
    var shownRows: [Data.Element] {
        guard let drag else { return Array(data) }
        let byID = Dictionary(data.map { ($0.id, $0) }) { first, _ in first }
        return RailDrag.order(data.map(\.id), moving: drag.lifted, to: drag.shownSlot)
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

    /// Keeps how far down each row its node is, read at rest: as rows move, where their nodes are
    /// drawn runs ahead of their layout.
    func noteNodeInsets(_ insets: [AnyHashable: CGFloat]) {
        guard drag == nil, regrouping == nil else { return }
        nodeInsets = Dictionary(uniqueKeysWithValues: data.compactMap { item in
            insets[AnyHashable(item.id)].map { (item.id, $0) }
        })
    }

    func noteSwipe(_ id: RowID, _ isSwiped: Bool) {
        if isSwiped {
            swiped.insert(id)
        } else {
            swiped.remove(id)
        }
    }

    /// The rail's strokes drawn once, while a row or its node is held, from the rows' nodes as
    /// they show. With the gap at an end of the rail, the line ends at the card's node instead,
    /// placed from the card's top at `cardY`, so it shows neither past the card nor short of it,
    /// even as the rows move; over a bar it ends at the gap's, the card being under the bar.
    func drawing(
        _ nodes: [AnyHashable: Anchor<CGPoint>],
        in proxy: GeometryProxy,
        cardY: CGFloat?,
    ) -> RailDrawing? {
        let ids = shownRows.map(\.id)
        let points = ids.compactMap { nodes[AnyHashable($0)].map { proxy[$0] } }
        guard points.count == ids.count, let first = points.first, let last = points.last
        else { return nil }
        let joined = shownJoined
        let flags = ids.dropLast().map(joined.contains)
        var (top, bottom) = (first.y, last.y)
        var followsCard = false
        if let drag, !drag.isOverBar, let cardY, let inset = nodeInset(of: drag, at: points, ids),
           ids.first == drag.lifted || ids.last == drag.lifted
        {
            // The rows' nodes are read where they are drawn as they move; the card's is where the
            // finger holds it, as far down it as the row's node was at rest.
            top = ids.first == drag.lifted ? cardY + inset : top
            bottom = ids.last == drag.lifted ? cardY + inset : bottom
            followsCard = true
        }
        return RailDrawing(
            // A row swiped open has slid its node off the column, to the left.
            nodeX: points.map(\.x).max() ?? first.x,
            nodes: points.map(\.y),
            joined: flags,
            spine: top ... max(top, bottom),
            followsCard: followsCard,
            shape: AnyHashable(ids.map(AnyHashable.init) + flags.map(AnyHashable.init)),
        )
    }

    /// How far down its row the held row's node is: as read at rest, or, for a moment of a drag
    /// drawn with no rest before it, from where its gap's node is.
    private func nodeInset(
        of drag: RailDragState<RowID>,
        at points: [CGPoint],
        _ ids: [RowID],
    ) -> CGFloat? {
        if let inset = nodeInsets[drag.lifted] {
            return inset
        }
        guard let index = ids.firstIndex(of: drag.lifted),
              let top = gapTop(lifting: drag.lifted, at: drag.slot)
        else { return nil }
        return points[index].y - top
    }

    /// The held row drawn again as a card, its top at `y`, drawing the rail's `strokes` behind
    /// it. It rises as it appears and lowers as it settles; while held, it follows the finger
    /// with no animation, whatever animation moves the rows.
    @ViewBuilder
    func card(_ drag: RailDragState<RowID>, at y: CGFloat, strokes: RailDrawing?) -> some View {
        if let item = data.first(where: { $0.id == drag.lifted }) {
            row(item)
                // As tall as in the rows, where the scroll view proposes no height, not as tall
                // as the rail it is over.
                .fixedSize(horizontal: false, vertical: true)
                .modifier(CardLook(
                    isReleased: drag.isReleased,
                    hasRisen: momentOffset != nil,
                    strokes: strokes,
                    top: y,
                ))
                .offset(y: y)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Reports a rail row's node by the row's id (`RowNodes`), and how far down the row it is
    /// (`RowNodeInsets`), so the rail finds each row's node however the rows are ordered as they
    /// move.
    func reportingNode(of id: some Hashable) -> some View {
        backgroundPreferenceValue(RailNodes.self) { anchors in
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: RowNodes.self,
                        value: anchors.first.map { [AnyHashable(id): $0] } ?? [:],
                    )
                    .preference(
                        key: RowNodeInsets.self,
                        value: anchors.first.map { [AnyHashable(id): proxy[$0].y] } ?? [:],
                    )
            }
        }
    }
}
