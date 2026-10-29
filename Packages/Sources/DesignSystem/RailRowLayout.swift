import SwiftUI

/// A row's content inset above and below as the design has it, at least as tall as two lines, so
/// a one-line row keeps the rhythm of a two-line one.
struct RailRowContentFrame: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 64
    @ObserveHotReload private var hotReload

    func body(content: Content) -> some View {
        content
            .padding(.vertical, RailRowMetrics.verticalInset)
            .frame(minHeight: minHeight, alignment: .top)
            .hotReloadable()
    }
}

/// A row's node column and its content side by side, on their first lines' baselines, the content
/// ending as far in from the row's trailing edge as the node's edge is from its leading one: the
/// lifted card is centered on the row. The inset is worked out here, in the pass that sizes the
/// row, from the column's width; read from the node after layout, it narrowed the content a pass
/// later, and the row, grown taller, was laid out twice in a frame.
struct RailRowLayout: Layout {
    /// The node's diameter, at the current text size.
    var nodeSize: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        frames(proposal, subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let frames = frames(proposal, subviews)
        // Offered what each was measured at, so neither is measured again.
        let placed = [(frames.column, ProposedViewSize.unspecified), (frames.content, frames.offer)]
        for (subview, (frame, offer)) in zip(subviews, placed) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: offer,
            )
        }
    }

    /// Where the column and the content go in the row, and the row's size: as an `HStack` with
    /// no spacing aligned on `.firstTextBaseline` places them, the content offered the width the
    /// column and the trailing inset leave.
    private func frames(
        _ proposal: ProposedViewSize,
        _ subviews: Subviews,
    ) -> Frames {
        guard subviews.count == 2 else {
            assertionFailure("A rail row lays out its node column and its content, nothing else")
            return Frames(column: .zero, content: .zero, offer: .zero, size: .zero)
        }
        let column = subviews[0].dimensions(in: .unspecified)
        let inset = max((column.width - nodeSize) / 2, 0)
        let offer = ProposedViewSize(
            width: proposal.width.map { max($0 - column.width - inset, 0) },
            height: proposal.height,
        )
        let content = subviews[1].dimensions(in: offer)
        let baseline = max(column[.firstTextBaseline], content[.firstTextBaseline])
        let columnTop = baseline - column[.firstTextBaseline]
        let contentTop = baseline - content[.firstTextBaseline]
        return Frames(
            column: CGRect(x: 0, y: columnTop, width: column.width, height: column.height),
            content: CGRect(
                x: column.width,
                y: contentTop,
                width: content.width,
                height: content.height,
            ),
            offer: offer,
            size: CGSize(
                width: column.width + content.width + inset,
                height: max(columnTop + column.height, contentTop + content.height),
            ),
        )
    }

    private struct Frames {
        var column: CGRect
        var content: CGRect
        /// What the content was offered.
        var offer: ProposedViewSize
        var size: CGSize
    }
}
