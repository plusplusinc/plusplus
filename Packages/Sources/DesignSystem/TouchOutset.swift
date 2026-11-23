import SwiftUI

/// Lays its one view out at the view's own size, then places it larger on that spot: at least
/// `minHeight` tall and `sides` wider on each side. What is around it is laid out as if it
/// were its own size; it takes touches, and VoiceOver outlines it, over the larger frame. The
/// view fills whatever it is placed in (a flexible frame) and is otherwise asked for no more
/// than its one-line width, so it wraps only where the line is narrower.
///
/// It grows as far above as below, except where `TouchRoom` caps a side: where two buttons sit
/// closer than their touches reach, each reaches only halfway into the gap between them, so a
/// tap lands on the button nearer the finger, not on whichever was drawn last. What it shows
/// then stays where it was laid out, not centered in the lopsided frame (`TouchInset`).
struct TouchOutset: Layout {
    let minHeight: CGFloat
    let sides: CGFloat
    var room = TouchRoom()

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let ideal = view.sizeThatFits(.unspecified)
        let width = min(proposal.width ?? ideal.width, ideal.width)
        return view.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        guard let view = subviews.first else { return }
        let reach = insets(around: bounds.size)
        view.place(
            at: CGPoint(x: bounds.minX - reach.leading, y: bounds.minY - reach.top),
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: bounds.width + reach.leading + reach.trailing,
                height: bounds.height + reach.top + reach.bottom,
            ),
        )
    }

    /// How far the touch reaches past a view of `size` on each side.
    func insets(around size: CGSize) -> EdgeInsets {
        let reach = max(minHeight - size.height, 0) / 2
        return EdgeInsets(
            top: min(reach, room.above),
            leading: min(sides, room.leading),
            bottom: min(reach, room.below),
            trailing: min(sides, room.trailing),
        )
    }
}

/// The inside of a `TouchOutset`: places its one view where the outset laid it out, its own
/// size, at the outset's insets from the touch frame's edges. Centered, it would sit off its
/// spot wherever `TouchRoom` makes the insets lopsided.
struct TouchInset: Layout {
    let outset: TouchOutset

    /// What it is offered, as a flexible frame takes, or its view's own size where unoffered.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let own = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            ?? .zero
        return CGSize(width: proposal.width ?? own.width, height: proposal.height ?? own.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        guard let view = subviews.first else { return }
        let sides = outset.insets(around: .zero)
        let width = bounds.width - sides.leading - sides.trailing
        let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let reach = outset.insets(around: size)
        view.place(
            at: CGPoint(x: bounds.minX + reach.leading, y: bounds.minY + reach.top),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: size.height),
        )
    }
}

/// How far a line's small buttons may reach past their capsules on each side (`TouchOutset`):
/// no limit, unless another button sits closer than its touch reaches
/// (`touchRoom(above:below:leading:trailing:)`).
struct TouchRoom: Equatable {
    var above = CGFloat.infinity
    var below = CGFloat.infinity
    var leading = CGFloat.infinity
    var trailing = CGFloat.infinity
}

extension EnvironmentValues {
    @Entry var touchRoom = TouchRoom()
}

extension View {
    /// Caps how far the small buttons inside reach past their capsules; a side left nil keeps
    /// the cap from further out.
    func touchRoom(
        above: CGFloat? = nil,
        below: CGFloat? = nil,
        leading: CGFloat? = nil,
        trailing: CGFloat? = nil,
    ) -> some View {
        transformEnvironment(\.touchRoom) { room in
            room.above = above ?? room.above
            room.below = below ?? room.below
            room.leading = leading ?? room.leading
            room.trailing = trailing ?? room.trailing
        }
    }
}
