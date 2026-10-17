import SwiftUI

// A hold on a row's node: the rows stay put while the finger passes over them, the rows from the
// held one to the one under the finger sitting in one raised field, and a drop makes them one
// group, its loop flashing in `railJoin`.

extension Rail {
    /// The rows joined to the next as they show: a regroup's preview, the held row's slot, or
    /// `links`.
    var shownJoined: Set<RowID> {
        if let grouping = regrouping?.shown {
            return grouping.links
        }
        guard let drag else { return links }
        return RailDrag.joined(
            data.map(\.id),
            joined: links,
            moving: drag.lifted,
            to: drag.shownSlot,
        )
    }

    var groups: [RowID: Int] {
        RailDrag.groups(data.map(\.id), joined: links)
    }

    /// Each row's id and height, in order.
    var measuredRows: [(id: RowID, height: CGFloat)] {
        // Read so heights measured while a row is held redraw its gap and card.
        _ = remeasured
        return data.map { ($0.id, heights.byID[$0.id] ?? 0) }
    }

    /// The rows' stretch on the rail: the first row's index, and the stretch's top and bottom in
    /// the rail's space.
    func stretch(_ rows: Set<RowID>) -> RowStretch? {
        var top: CGFloat = 0
        var stretch: RowStretch?
        for (index, row) in measuredRows.enumerated() {
            if rows.contains(row.id) {
                let bounds = (stretch?.bounds.lowerBound ?? top) ... top + row.height
                stretch = RowStretch(first: stretch?.first ?? index, bounds: bounds)
            }
            top += row.height
        }
        return stretch
    }

    /// Holds a row's node: the rows stay put, and the drag draws a group.
    func holdNode(_ id: RowID, at finger: RailDrag.Finger) {
        regrouping = RailRegroupState(
            held: id,
            reach: id,
            fingerY: finger.inRail,
            pickedUp: regroup?.pickUp(id) ?? [id],
        )
        lifts += 1
        // The list scrolling under a still finger carries it over the rows.
        edges?.lift(at: finger.inScrollView) { distance in
            regrouping?.fingerY += distance
            reachFinger()
        }
    }

    /// Follows the finger holding a node: over a bar, where a drop makes nothing, the preview
    /// fades, and comes back as the finger returns over the rows.
    func moveNodeFinger(to finger: RailDrag.Finger) {
        regrouping?.fingerY = finger.inRail
        edges?.move(to: finger.inScrollView)
        let overBar = isOverBar(finger)
        if overBar != regrouping?.isOverBar {
            withAnimation(reduceMotion ? nil : RailDrag.gap) {
                regrouping?.isOverBar = overBar
            }
        }
        reachFinger()
    }

    /// Previews what a drop on the row under the finger would make, with a tick when it changes.
    func reachFinger() {
        guard let held = regrouping, let regroup,
              let reach = RailDrag.reach(
                  fingerY: held.fingerY,
                  rows: measuredRows,
                  current: held.reach,
              ),
              reach != held.reach
        else { return }
        let grouping = reach == held.held ? nil : regroup.preview(held.held, reach)
        withAnimation(reduceMotion ? nil : RailDrag.gap) {
            regrouping?.reach = reach
            regrouping?.grouping = grouping
        }
        // Over a bar the preview isn't shown, so its changes aren't felt either.
        if grouping != held.grouping, !held.isOverBar {
            ticks += 1
        }
    }

    /// Lets go of a held node: a drop commits what it previewed, with a light impact, and the
    /// group's loop flashes in `railJoin` as a new node does, but not with Reduce Motion. Going
    /// back, nothing changes, and the field fades.
    func letGoOfNode(_ held: RailRegroupState<RowID>, goingBack: Bool) {
        guard !goingBack, let grouping = held.grouping else {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { regrouping = nil }
            return
        }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            regroup?.commit(held.held, held.reach)
            regrouping = nil
        }
        if !reduceMotion {
            for id in grouping.superset {
                flashes[id, default: 0] += 1
            }
        }
        lifts += 1
    }

    /// The raised field behind the rows a held node spans, a held row's card stretched over them,
    /// shadow and all, the first row's node inset in it as the card's is. Over a bar it fades, as
    /// a drop there makes nothing.
    @ViewBuilder
    func spanField(_ nodes: [Anchor<CGPoint>]) -> some View {
        if let held = regrouping, let stretch = stretch(held.field),
           nodes.indices.contains(stretch.first)
        {
            GeometryReader { proxy in
                let node = proxy[nodes[stretch.first]]
                let (top, bottom) = (stretch.bounds.lowerBound, stretch.bounds.upperBound)
                CardFill(
                    node: CGPoint(x: node.x, y: node.y - top),
                    size: CGSize(width: proxy.size.width, height: bottom - top),
                )
                // The held card's shadow: in light mode its fill is the background's white.
                .shadow(color: .pp(.shadow), radius: RailDrag.liftedShadow)
                .offset(y: top)
                FieldLabel(
                    field: CGRect(x: 0, y: top, width: proxy.size.width, height: bottom - top),
                    node: node,
                    texts: textFrames,
                    isShown: held.field.count > 1,
                )
            }
            .opacity(held.isOverBar ? 0 : 1)
            // Gone before the new group's loop flashes.
            .transition(.opacity.animation(
                reduceMotion ? nil : .easeOut(duration: RailEntry.fieldFade),
            ))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Rows next to each other on a rail: the first one's index, and their top and bottom in the
/// rail's space.
struct RowStretch {
    var first: Int
    var bounds: ClosedRange<CGFloat>
}

/// "Superset" in the regroup field's top trailing corner, while letting go would leave the rows
/// in it a superset: two rows or more. Where a row's text reaches that corner, as it can at the
/// largest text sizes, it goes further down the trailing edge, to the first place the rows' text
/// leaves clear, and where there is none, it doesn't show. VoiceOver reads the rows' own values
/// instead.
private struct FieldLabel: View {
    /// The field's rows' stretch, the rail's width, in the rail's space.
    let field: CGRect
    /// The first row's node, in the rail's space.
    let node: CGPoint
    let texts: [CGRect]
    let isShown: Bool
    @State private var size = CGSize.zero
    @ScaledMetric(relativeTo: .body) private var nodeSize = railNodeSize

    var body: some View {
        let place = place
        Text("Superset")
            .font(.ppCaption)
            .foregroundStyle(.pp(.textSecondary))
            // It grows with the text up to the first accessibility size, past which it would
            // crowd the rows' own names out of their room.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .position(x: place?.midX ?? 0, y: place?.midY ?? 0)
            .opacity(isShown && place != nil ? 1 : 0)
            .animation(.snappy(duration: 0.15), value: isShown)
            .accessibilityHidden(true)
    }

    /// Where it goes: inset from the field's trailing edge as the node is from its leading one,
    /// level with the first row's node, or else the highest place down that edge clear of text.
    private var place: CGRect? {
        // Inset as `CardFill` sets the node in.
        let (inset, edge) = CardFill.insets(
            node: CGPoint(x: node.x, y: node.y - field.minY),
            nodeSize: nodeSize,
        )
        let trailing = field.maxX - edge - inset - size.width
        let spot = { (y: CGFloat) in
            CGRect(x: trailing, y: y, width: size.width, height: size.height)
        }
        let lowest = field.maxY - inset - size.height
        let downTheEdge = stride(from: field.minY + inset, through: lowest, by: Spacing.xxs)
        return ([node.y - size.height / 2] + downTheEdge).lazy.map(spot).first { spot in
            !texts.contains { $0.intersects(spot.insetBy(dx: -Spacing.xs, dy: -Spacing.xxs)) }
        }
    }
}

/// Where each row's text is, in the rail's space: its name and detail as laid out, not the
/// row's width.
struct RowTextFrames: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value += nextValue()
    }
}
