import SwiftUI

// A row held and dragged by its body: the lift, following the finger, and the drop.

extension Rail {
    /// A row's hold, from its lift or a node's hold to its drop.
    func dragged(_ id: RowID, _ phase: RailDrag.Phase, at finger: RailDrag.Finger) {
        switch phase {
        case .began:
            guard drag == nil, regrouping == nil else { return }
            if finger.inColumn, regroup != nil {
                return holdNode(id, at: finger)
            }
            guard onMove != nil else { return }
            let candidates = candidates(lifting: id)
            guard let origin = RailDrag.origin(
                of: id,
                in: data.map(\.id),
                candidates: candidates,
                groups: groups,
            ),
                let own = candidates.first(where: { $0.slot == origin })
            else { return }
            cardTop = own.gapTop
            drag = RailDragState(
                lifted: id,
                origin: own.slot,
                slot: own.slot,
                grab: finger.inRail - own.gapTop,
                rows: data.map(\.id),
            )
            lifts += 1
            // The list scrolling under a still finger carries the card through the rows.
            // The most room above the rail a pair can ask for: the card's own height.
            edges?.lift(at: finger.inScrollView, room: heights.byID[id] ?? 0) { distance, byEdge in
                railMoved(distance, carrying: id, byEdge: byEdge)
            }
        case .changed:
            if regrouping?.held == id {
                return moveNodeFinger(to: finger)
            }
            guard let held = drag, held.lifted == id else { return }
            cardTop = finger.inRail - held.grab
            edges?.move(to: finger.inScrollView)
            // Over a bar, where a drop sends the row back, the rows show it back where it was.
            let overBar = isOverBar(finger)
            if overBar != held.isOverBar {
                withAnimation(reduceMotion ? nil : RailDrag.gap) { drag?.isOverBar = overBar }
            }
            follow(id)
        case .ended, .cancelled:
            if let held = regrouping, held.held == id {
                edges?.letGo()
                let goesBack = phase == .cancelled || isOverBar(finger)
                return letGoOfNode(held, goingBack: goesBack)
            }
            guard let released = drag, released.lifted == id, !released.isReleased else { return }
            edges?.letGo()
            dwell = nil
            // Let go over a bar, or past the screen's edge, the row goes back.
            let goesBack = phase == .cancelled || isOverBar(finger)
            settle(released, goingBack: goesBack)
        }
    }

    /// The rail moved `distance` up the screen under the held finger: the card moves down it as
    /// far, staying under the finger. Only the finger moves the gap, or a pair: the list scrolling
    /// for it in an edge's band, `byEdge`, carries it through the rows; the room above the rail
    /// doesn't.
    private func railMoved(_ distance: CGFloat, carrying id: RowID, byEdge: Bool) {
        cardTop += distance
        if byEdge {
            follow(id)
        }
    }

    /// Whether the finger is over a bar, or past the screen's edge, where a drop changes nothing.
    func isOverBar(_ finger: RailDrag.Finger) -> Bool {
        edges?.isOutside(finger.inScrollView) == true
    }

    /// Lets the held row go, into its gap or, `goingBack`, back where it started: the card lowers
    /// into the gap as `onMove` reorders the data to match the rows shown, in one transaction, so
    /// no row moves. Back where it started, nothing moves, and the rows close up around it. Once
    /// it has settled, the row draws in its place again.
    private func settle(_ released: RailDragState<RowID>, goingBack: Bool) {
        let slot = goingBack ? released.origin : released.slot
        var settling = released
        settling.slot = slot
        settling.isReleased = true
        settling.isOverBar = false
        let animation = goingBack ? RailDrag.cancel : RailDrag.drop
        withAnimation(reduceMotion ? nil : animation) {
            if slot != released.origin {
                onMove?(released.lifted, slot)
            }
            cardTop = gapTop(lifting: released.lifted, at: slot) ?? cardTop
            drag = settling
        } completion: {
            if drag?.lifted == released.lifted {
                drag = nil
            }
        }
    }
}
