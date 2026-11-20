import SwiftUI

/// The current exercise's caption line: its first subview at the leading edge and its second at
/// the trailing edge, "Set 1 of 3" and "then rest 1:00", on one line where both fit with
/// `spacing` between them; else the second under the first, at the leading edge.
struct CaptionLine: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        frames(proposal.width, subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let frames = frames(bounds.width, subviews)
        for (subview, (origin, offer)) in zip(subviews, frames.placed) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: offer,
            )
        }
    }

    private func frames(
        _ width: CGFloat?,
        _ subviews: Subviews,
    ) -> (placed: [(CGPoint, ProposedViewSize)], size: CGSize) {
        guard subviews.count == 2 else {
            assertionFailure("A caption line lays out a leading part and a trailing one")
            return ([], .zero)
        }
        let (lead, trail) = (subviews[0], subviews[1])
        let trailSize = trail.sizeThatFits(.unspecified)
        let leadIdeal = lead.sizeThatFits(.unspecified)
        let width = width ?? (leadIdeal.width + spacing + trailSize.width)
        if leadIdeal.width + spacing + trailSize.width <= width {
            let leadOffer = ProposedViewSize(width: width - spacing - trailSize.width, height: nil)
            let leadSize = lead.sizeThatFits(leadOffer)
            return (
                [(.zero, leadOffer), (CGPoint(x: width - trailSize.width, y: 0), .unspecified)],
                CGSize(width: width, height: max(leadSize.height, trailSize.height)),
            )
        }
        let offer = ProposedViewSize(width: width, height: nil)
        let leadSize = lead.sizeThatFits(offer)
        let trailHeight = trail.sizeThatFits(offer).height
        return (
            [(.zero, offer), (CGPoint(x: 0, y: leadSize.height), offer)],
            CGSize(width: width, height: leadSize.height + trailHeight),
        )
    }
}
