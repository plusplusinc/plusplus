import SwiftUI

// A hold on a row's node: the rows stay put while the finger passes over them, the rail drawing
// what a drop would make, and a drop joins or parts them.

extension Rail {
    /// The rows joined to the next as they show: a regroup's preview, the held row's slot, or
    /// `links`.
    var shownJoined: Set<RowID> {
        if let grouping = regrouping?.grouping {
            return grouping.links
        }
        guard let drag else { return links }
        return RailDrag.joined(data.map(\.id), joined: links, moving: drag.lifted, to: drag.slot)
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

    /// The top and bottom, in the rail's space, of the rows a join would make, which a field
    /// marks behind them.
    func joinSpan(_ joining: Set<RowID>) -> ClosedRange<CGFloat>? {
        guard !joining.isEmpty else { return nil }
        var top: CGFloat = 0
        var span: ClosedRange<CGFloat>?
        for row in measuredRows {
            if joining.contains(row.id) {
                span = (span?.lowerBound ?? top) ... top + row.height
            }
            top += row.height
        }
        return span
    }

    /// Holds a row's node: the rows stay put, and the drag joins or parts them.
    func holdNode(_ id: RowID, at finger: RailDrag.Finger) {
        regrouping = RailRegroupState(held: id, reach: id, fingerY: finger.inRail)
        lifts += 1
        // The list scrolling under a still finger carries it over the rows.
        edges?.lift(at: finger.inScrollView) { distance in
            regrouping?.fingerY += distance
            reachFinger()
        }
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
        if grouping != held.grouping {
            ticks += 1
        }
    }

    /// Lets go of a held node: a drop commits what it previewed, and a join's loop settles from
    /// `railJoin` to its own color, with a light impact. Going back, nothing changes.
    func letGoOfNode(_ held: RailRegroupState<RowID>, goingBack: Bool) {
        guard !goingBack, let grouping = held.grouping else {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { regrouping = nil }
            return
        }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            regroup?.commit(held.held, held.reach)
            regrouping = nil
            settling = grouping.joining
        }
        if !grouping.joining.isEmpty {
            lifts += 1
        }
    }

    /// Whether a row's loop draws in `railJoin`: a join's rows while it is previewed, and as it
    /// settles after the drop. Never with Reduce Motion.
    func isJoining(_ id: RowID, _ joining: Set<RowID>) -> Bool {
        !reduceMotion && (joining.contains(id) || settling.contains(id))
    }

    @ViewBuilder
    func joinField(_ joining: Set<RowID>) -> some View {
        if !reduceMotion, let span = joinSpan(joining) {
            JoinField(span: span)
                .transition(.opacity.animation(.snappy(duration: 0.2)))
        }
    }

    /// A join's loop holds in `railJoin` a moment after the drop, then settles to its own color.
    func cool(_ rows: Set<RowID>) {
        guard !rows.isEmpty else { return }
        withAnimation(.easeOut(duration: RailEntry.settle).delay(RailEntry.hold)) {
            settling = []
        }
    }
}
