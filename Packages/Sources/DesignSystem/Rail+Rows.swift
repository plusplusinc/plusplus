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

    /// The top of the gap at `slot`, where the card rests when it is let go there. Every slot at
    /// one place shares its gap, a pair's included, which is no candidate.
    func gapTop(lifting lifted: RowID, at slot: RailSlot<RowID>) -> CGFloat? {
        candidates(lifting: lifted).first { $0.slot.place == slot.place }?.gapTop
    }

    /// The rows whose loops hide: those of a group with a row swiped open, which would otherwise
    /// leave its partners' stretches hanging.
    func loopsHidden(_ ids: [RowID]) -> Set<RowID> {
        guard !swiped.isEmpty else { return [] }
        let groups = RailDrag.groups(ids, joined: shownJoined)
        let open = Set(swiped.compactMap { groups[$0] })
        return Set(ids.filter { groups[$0].map(open.contains) ?? false })
    }

    /// Where the rail's strokes drawn under the rows don't show while a row is held: across the
    /// end view, which a card dragged below it would draw them through, and across a row swiped
    /// open, its text slid over the column. The card draws its own over its fill.
    var cutouts: [CGRect] {
        [heights.end] + swiped.compactMap { heights.frames[$0] }
    }

    /// Keeps how far down each row its node is, and where a row's node is, which places the
    /// wells and is the same on every row, the furthest across, a row swiped open having slid its
    /// node to the left. Both are read at rest: while rows move, a row reports its node where it
    /// is drawn against its frame where it will end up, up to a row's height out.
    func noteNodeInsets(_ insets: [AnyHashable: CGPoint]) {
        let isHeld = drag != nil || regrouping != nil
        if !isHeld || railNode == nil, let x = insets.values.map(\.x).max(),
           let y = insets.values.map(\.y).min(), railNode != CGPoint(x: x, y: y)
        {
            railNode = CGPoint(x: x, y: y)
        }
        guard !isHeld else { return }
        nodeInsets = Dictionary(uniqueKeysWithValues: data.compactMap { item in
            insets[AnyHashable(item.id)].map { (item.id, $0.y) }
        })
    }

    /// Drops what the rail keeps for rows no longer in it, so a deleted row swiped open cuts
    /// nothing out of the line.
    func forget(rowsNotIn ids: Set<RowID>) {
        swiped.formIntersection(ids)
        flashes = flashes.filter { ids.contains($0.key) }
        heights.frames = heights.frames.filter { ids.contains($0.key) }
    }

    func noteSwipe(_ id: RowID, _ isSwiped: Bool) {
        if isSwiped {
            swiped.insert(id)
        } else {
            swiped.remove(id)
        }
    }

    /// The rail's strokes drawn once under the rows while a row or its node is held, cut where
    /// they would show through (`cutouts`).
    @ViewBuilder
    func strokes(
        _ nodes: [AnyHashable: Anchor<CGPoint>],
        in proxy: GeometryProxy,
        cardY: CGFloat?,
    ) -> some View {
        if let drag, let cardY {
            heldDrawing(drag, nodes, in: proxy, cardY: cardY)
                .mask { RailCutouts(holes: cutouts).fill(style: FillStyle(eoFill: true)) }
        } else {
            drawing(nodes, in: proxy)
        }
    }

    /// The rows as they show, and their nodes, or nil until every row has reported its node.
    private func shownNodes(
        _ nodes: [AnyHashable: Anchor<CGPoint>],
        in proxy: GeometryProxy,
    ) -> ([RowID], [CGPoint])? {
        let ids = shownRows.map(\.id)
        let points = ids.compactMap { nodes[AnyHashable($0)].map { proxy[$0] } }
        return points.count == ids.count ? (ids, points) : nil
    }

    /// The rail's strokes drawn once, while a row's node is held, from the rows' nodes as they
    /// show.
    func drawing(_ nodes: [AnyHashable: Anchor<CGPoint>], in proxy: GeometryProxy) -> RailDrawing? {
        guard let (ids, points) = shownNodes(nodes, in: proxy), let first = points.first,
              let last = points.last
        else { return nil }
        let joined = shownJoined
        let flags = ids.dropLast().map(joined.contains)
        return RailDrawing(
            nodeX: first.x,
            nodes: points.map(\.y),
            joined: flags,
            spine: first.y ... max(first.y, last.y),
            shape: AnyHashable(ids.map(AnyHashable.init) + flags.map(AnyHashable.init)),
        )
    }

    /// The rail's strokes drawn once, while a row is held by its content: the held row's node is
    /// the card's, placed from the card's top at `cardY` as far down it as the row's node was at
    /// rest, so whatever ends at it ends on the card.
    func heldDrawing(
        _ drag: RailDragState<RowID>,
        _ nodes: [AnyHashable: Anchor<CGPoint>],
        in proxy: GeometryProxy,
        cardY: CGFloat,
    ) -> HeldRailDrawing? {
        guard let (ids, points) = shownNodes(nodes, in: proxy), let first = points.first,
              let inset = nodeInset(of: drag, at: points, ids)
        else { return nil }
        let order = drag.rows.isEmpty ? data.map(\.id) : drag.rows
        let keys = Dictionary(order.enumerated().map { ($1, $0) }) { first, _ in first }
        guard let held = keys[drag.lifted] else { return nil }
        var ys: [Int: CGFloat] = [:]
        for (id, point) in zip(ids, points) {
            keys[id].map { ys[$0] = point.y }
        }
        ys[held] = cardY + inset
        return HeldRailDrawing(
            // A row swiped open has slid its node off the column, to the left.
            nodeX: points.map(\.x).max() ?? first.x,
            nodes: ys,
            held: held,
            isHeldOnLine: !drag.isOverBar,
            groups: heldGroups(drag, ids, keys: keys),
        )
    }

    /// Every superset without the held row, and every row on its own, which the held row could
    /// join, and whether the held row is in it now: over a bar it is in none, its card being under
    /// the bar. A superset with a row swiped open draws no loop, as at rest.
    private func heldGroups(
        _ drag: RailDragState<RowID>,
        _ ids: [RowID],
        keys: [RowID: Int],
    ) -> [HeldGroup] {
        let atRest = groups
        let shown = RailDrag.groups(ids, joined: shownJoined)
        let hidden = loopsHidden(ids)
        let heldGroup = shown[drag.lifted]
        let partners: Set<Int> = drag.isOverBar || heldGroup == nil ? [] : Set(ids.compactMap {
            $0 != drag.lifted && shown[$0] == heldGroup ? keys[$0] : nil
        })
        var order: [HeldGroupKey<RowID>] = []
        var members: [HeldGroupKey<RowID>: [Int]] = [:]
        for id in ids where id != drag.lifted && !hidden.contains(id) {
            guard let node = keys[id] else { continue }
            let group = atRest[id].map(HeldGroupKey.superset) ?? .row(id)
            if members[group] == nil {
                order.append(group)
            }
            members[group, default: []].append(node)
        }
        // Named by its first row as lifted, which stays the same through the drop, as the rows
        // change order and the supersets at rest are numbered anew.
        return order.compactMap { members[$0] }.compactMap { rows in
            rows.min().map { first in
                HeldGroup(
                    id: first,
                    members: rows,
                    hasHeld: rows.contains(where: partners.contains),
                )
            }
        }
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
    func card(_ drag: RailDragState<RowID>, at y: CGFloat, strokes: HeldRailDrawing?) -> some View {
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

/// The key of a loop while a row is held: a superset at rest, by where it starts, or a row on its
/// own.
private enum HeldGroupKey<RowID: Hashable>: Hashable {
    case superset(Int)
    case row(RowID)
}

extension View {
    /// Calls `action` with the view's frame in the rail's space as it changes.
    func reportingFrame(_ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(
            for: CGRect.self,
            of: { $0.frame(in: .named(RailDrag.space)) },
            action: action,
        )
    }

    /// Reports a rail row's node by the row's id (`RowNodes`), and where it is in the row
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
                        value: anchors.first.map { [AnyHashable(id): proxy[$0]] } ?? [:],
                    )
            }
        }
    }
}
