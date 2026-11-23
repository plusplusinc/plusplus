import SwiftUI

/// Lays its one view out at the view's own size, then places it larger, centered on that
/// spot: at least `minHeight` tall and `sides` wider on each side. What is around it is laid
/// out as if it were its own size; it takes touches, and VoiceOver outlines it, over the
/// larger frame. The view fills whatever it is placed in (a flexible frame) and is otherwise
/// asked for no more than its one-line width, so it wraps only where the line is narrower.
///
/// The view carries its own `sides` of padding inside that frame, so what it draws keeps to
/// the width it was laid out at: given the outset's room to draw in, a capsule wider than the
/// line ran past the screen's margins at the largest text sizes rather than wrapping.
struct TouchOutset: Layout {
    let minHeight: CGFloat
    let sides: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let ideal = view.sizeThatFits(.unspecified).width - 2 * sides
        let width = min(proposal.width ?? ideal, ideal)
        let size = view.sizeThatFits(ProposedViewSize(width: width + 2 * sides, height: nil))
        return CGSize(width: size.width - 2 * sides, height: size.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        guard let view = subviews.first else { return }
        view.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(
                width: bounds.width + 2 * sides,
                height: max(bounds.height, minHeight),
            ),
        )
    }
}
