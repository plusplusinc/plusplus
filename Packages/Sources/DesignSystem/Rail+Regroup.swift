import SwiftUI

// A hold on a row's node: the rows stay put while the finger passes over them, the rows from the
// held one to the one under the finger sitting in one well, and a drop makes them one group, its
// loop flashing in `railJoin`.

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

    /// The rows' stretch on the rail: from the first one's top to the last one's bottom, in the
    /// rail's space.
    func stretch(_ rows: Set<RowID>) -> ClosedRange<CGFloat>? {
        var top: CGFloat = 0
        var stretch: ClosedRange<CGFloat>?
        for row in measuredRows {
            if rows.contains(row.id) {
                stretch = (stretch?.lowerBound ?? top) ... top + row.height
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

    /// The well behind the rows a held node spans, as a superset's rows sit in. It shows at once,
    /// the rows' own wells giving way to it, so a press on a superset's node changes nothing on
    /// the screen. Over a bar it fades, as a drop there makes nothing, and it fades as the node is
    /// let go, over the rows' own wells, before the new group's loop flashes.
    @ViewBuilder
    func spanField() -> some View {
        if let held = regrouping, let rows = stretch(held.field),
           let outline = wellOutline(rows: rows)
        {
            GeometryReader { proxy in
                WellFill(outline: outline, width: proxy.size.width)
            }
            .opacity(held.isOverBar ? 0 : 1)
            .transition(.asymmetric(
                insertion: .identity,
                removal: .opacity.animation(
                    reduceMotion ? nil : .easeOut(duration: RailEntry.fieldFade),
                ),
            ))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
