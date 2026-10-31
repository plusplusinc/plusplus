import SwiftUI

/// The rail's rows and its end view one under the other, from the top, at their own heights and
/// the rail's width, leading edges aligned: a `VStack(alignment: .leading, spacing: 0)`, but
/// measuring every row afresh on every pass. Growing a row into the current exercise, a
/// `VStack` kept placing the rows below it at the row's height from a few frames before for
/// about 80 ms, mid-growth, then let them jump 83 pt in one frame, with the row itself growing
/// all the while.
struct RailStack: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = sizes(subviews, width: proposal.width)
        return CGSize(
            width: sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).reduce(0, +),
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let offer = ProposedViewSize(width: bounds.width, height: nil)
        var top = bounds.minY
        for (subview, size) in zip(subviews, sizes(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX, y: top), proposal: offer)
            top += size.height
        }
    }

    private func sizes(_ subviews: Subviews, width: CGFloat?) -> [CGSize] {
        let offer = ProposedViewSize(width: width, height: nil)
        return subviews.map { $0.sizeThatFits(offer) }
    }
}
