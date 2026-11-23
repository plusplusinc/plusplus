import SwiftUI

/// Two views across the width, the first leading and the second trailing, centered on each
/// other; or, when the two won't fit side by side at their one-line widths, the second under
/// the first, both leading. So at the largest text sizes a title and its button stack rather
/// than either breaking a word to make room, and stay side by side wherever they fit.
///
/// `atTrailingEdge` keeps the two together at the trailing edge instead, the first right
/// before the second, and stacked, both trailing: a phrase that ends in its button.
struct LineOrStack: Layout {
    var spacing = Spacing.sm
    var atTrailingEdge = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? .infinity
        let (first, second) = (subviews[0], subviews[1])
        if let line = oneLine(first, second, in: width) {
            return CGSize(width: width.isFinite ? width : line.width, height: line.height)
        }
        let column = ProposedViewSize(width: width, height: nil)
        let top = first.sizeThatFits(column)
        let under = second.sizeThatFits(column)
        return CGSize(
            width: width.isFinite ? width : max(top.width, under.width),
            height: top.height + spacing + under.height,
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        guard subviews.count == 2 else { return }
        let (first, second) = (subviews[0], subviews[1])
        if oneLine(first, second, in: bounds.width) != nil {
            let firstX = atTrailingEdge
                ? bounds.maxX - second.sizeThatFits(.unspecified).width - spacing
                : bounds.minX
            first.place(
                at: CGPoint(x: firstX, y: bounds.midY),
                anchor: atTrailingEdge ? .trailing : .leading,
                proposal: .unspecified,
            )
            second.place(
                at: CGPoint(x: bounds.maxX, y: bounds.midY),
                anchor: .trailing,
                proposal: .unspecified,
            )
            return
        }
        let column = ProposedViewSize(width: bounds.width, height: nil)
        let top = first.sizeThatFits(column)
        let x = atTrailingEdge ? bounds.maxX : bounds.minX
        let anchor: UnitPoint = atTrailingEdge ? .topTrailing : .topLeading
        first.place(at: CGPoint(x: x, y: bounds.minY), anchor: anchor, proposal: column)
        second.place(
            at: CGPoint(x: x, y: bounds.minY + top.height + spacing),
            anchor: anchor,
            proposal: column,
        )
    }

    /// The two at their one-line sizes, when they fit side by side in the width.
    private func oneLine(
        _ first: LayoutSubview,
        _ second: LayoutSubview,
        in width: CGFloat,
    ) -> CGSize? {
        let leading = first.sizeThatFits(.unspecified)
        let trailing = second.sizeThatFits(.unspecified)
        let lineWidth = leading.width + spacing + trailing.width
        guard lineWidth <= width else { return nil }
        return CGSize(width: lineWidth, height: max(leading.height, trailing.height))
    }
}
