import SwiftUI

/// Where a superset's loop puts its heads, for every drawing of it.
nonisolated extension LoopPen {
    /// The heads on the loop between a node at `top` and the next one down, at `bottom`: each
    /// one's middle, and its size against its full size. Every drawing of the loop places its
    /// heads here, so they draw the same strokes.
    ///
    /// The heads are spread evenly over the stretch, as many as keep about `spacing` apart from
    /// each other and from the nodes, one at least: one at the middle, then two at thirds, and so
    /// on. As the stretch grows to room for another, the new one grows from nothing at its place
    /// over the last quarter `spacing` before it, while the others slide to theirs, and as it
    /// shrinks the same runs back, so a head never jumps. A head shrinks away as the two nodes
    /// meet. A head too small to see is left out.
    ///
    /// `level` says how many heads there are, and how far the newest has grown in
    /// (`headLevel(span:)`): a drawing whose stretch changes faster than a head can grow eases it
    /// toward the stretch's own instead, over the change.
    func headMiddles(
        from top: CGFloat,
        to bottom: CGFloat,
        level: CGFloat? = nil,
    ) -> [(middle: CGFloat, size: CGFloat)] {
        allHeadMiddles(from: top, to: bottom, level: level ?? headLevel(span: bottom - top))
            .filter { $0.size > 0.01 }
    }

    /// How many heads a stretch `span` long holds, one at least, less what the newest has yet to
    /// grow in: 2.5 is two whole heads and a third at half its size. It runs on evenly through
    /// every span, so a drawing can ease it from one span's to another's.
    func headLevel(span: CGFloat) -> CGFloat {
        let arrival = spacing / 4
        let fit = Int(((span + arrival) / spacing).rounded(.down)) - 1
        guard fit > 1 else { return 1 }
        let grown = min(max((span - CGFloat(fit + 1) * spacing + arrival) / arrival, 0), 1)
        return CGFloat(fit - 1) + grown
    }

    private func allHeadMiddles(
        from top: CGFloat,
        to bottom: CGFloat,
        level: CGFloat,
    ) -> [(middle: CGFloat, size: CGFloat)] {
        let span = bottom - top
        let meet = min(max((span - 2 * length) / (2 * length), 0), 1)
        guard meet > 0 else { return [] }
        let fit = Int(level.rounded(.up))
        let spread = { (count: Int, index: Int) in
            top + span * CGFloat(index + 1) / CGFloat(count + 1)
        }
        guard fit > 1 else { return [(spread(1, 0), meet)] }
        // How far the newest head has grown in, and where it is among the others: the middle one,
        // or the lower of the two middle ones.
        let grown = level - CGFloat(fit - 1)
        let arriving = fit / 2
        return (0 ..< fit).map { index in
            let to = spread(fit, index)
            guard index != arriving else { return (to, grown * meet) }
            let from = spread(fit - 1, index < arriving ? index : index - 1)
            return (from + (to - from) * grown, meet)
        }
    }
}

/// A row's stretch of loop (`LoopPen.stretch`), its heads at `level`, which animates.
nonisolated struct LoopStretch: Shape {
    struct Run {
        let node: CGPoint
        let height: CGFloat
        let nodeBelow: CGFloat
        let starts: Bool
        let ends: Bool
    }

    let run: Run?
    let pen: LoopPen
    var level: CGFloat

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    func path(in _: CGRect) -> Path {
        guard let run else { return Path() }
        return pen.stretch(
            node: run.node,
            height: run.height,
            nodeBelow: run.nodeBelow,
            starts: run.starts,
            ends: run.ends,
            level: level,
        )
    }
}
