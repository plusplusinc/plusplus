import SwiftUI

/// How tall a row's label stands as the current exercise of a workout, with the row after it: the
/// label takes what that row leaves, so the row fills the screen but for it. Given while the row
/// can be the current exercise or stop being it, so it grows and shrinks to the right height.
public struct RowStanding: Equatable {
    /// How tall the label and the row after it stand together.
    public var height: CGFloat
    /// The row after it, measured as it stands on the rail, if any.
    public var next: Next?

    public init(height: CGFloat, next: Next? = nil) {
        self.height = height
        self.next = next
    }

    /// The row after the current exercise: its name and its detail, in parts.
    public struct Next: Equatable {
        public var title: String
        public var detail: [String]

        public init(title: String, detail: [String]) {
            self.title = title
            self.detail = detail
        }
    }
}

/// The label's column, from its top, standing as tall as the row it is: as a row, its own height;
/// as the current exercise, what `standing` leaves once the row after it, its second subview,
/// measured here, has its room. `growth` runs from 0, a row, to 1, the current exercise, and the
/// height with it, so it grows and shrinks on the animation's curve; it is taller by however far
/// the column runs past both that height and the one it is going to. Worked out in the pass that
/// sizes the row: read back from the screen and the next row after layout, the height came a pass
/// later, and on a relaunch into a workout the row grew twice in a frame. The column takes its
/// new height at once, its new parts fading in later: counted whole, it held the label at that
/// height until the animated one passed it, so the rows below started late. A frame's
/// `minHeight` animated from 0 laid the row out at no height for the first frame.
struct StandingHeight: Layout {
    var growth: CGFloat
    /// Not animated: whether it is the current exercise, where `growth` is going to 1.
    let isCurrent: Bool
    /// The column's height as a row, which the height runs from and back to.
    let restingHeight: CGFloat
    /// How tall the label and the row after it stand together, if it is given.
    let standing: CGFloat?

    var animatableData: CGFloat {
        get { growth }
        set { growth = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let column = subviews.first else { return .zero }
        if isAtRest {
            return column.sizeThatFits(proposal)
        }
        let heights = heights(proposal, subviews)
        let size = column.sizeThatFits(offer(proposal, end: heights.end))
        // The column takes its new height at once, so it counts only past the end height, and
        // past the standing height: shrinking, parts fading out still take their room, which
        // held the rows below until they had gone, then let them jump.
        let counted = max(size.height - max(heights.end, heights.now), 0)
        return CGSize(width: size.width, height: heights.now + counted)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let end = isAtRest ? 0 : heights(proposal, subviews).end
        let placed = isAtRest ? proposal : ProposedViewSize(width: bounds.width, height: nil)
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: offer(placed, end: end),
        )
        // Measured, never shown.
        subviews.dropFirst().first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: proposal.width, height: nil),
        )
    }

    /// Resting, with no shrink still running: laid out as a plain stack, with what it was offered.
    private var isAtRest: Bool {
        !isCurrent && growth == 0
    }

    /// The height it stands at now, on the way from a row's to the current exercise's, and the
    /// one it is going to.
    private func heights(
        _ proposal: ProposedViewSize,
        _ subviews: Subviews,
    ) -> (now: CGFloat, end: CGFloat) {
        let grown = grownHeight(proposal, subviews)
        let now = restingHeight + (grown - restingHeight) * growth
        return (now, isCurrent ? grown : restingHeight)
    }

    /// As the current exercise: what `standing` leaves once the row after it has its room. With
    /// none given, as a preview has, its column's own height.
    private func grownHeight(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        guard let standing else {
            return subviews.first?.sizeThatFits(ProposedViewSize(
                width: proposal.width,
                height: nil,
            ))
            .height ?? 0
        }
        let next = subviews.count > 1
            ? subviews[1].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).height
            : 0
        return max(standing - next, 0)
    }

    /// What the column is offered: at rest, what the label was, as a row on `main` was; while it
    /// shrinks, as tall as it likes; and on the current exercise the height it stands at, `end`,
    /// which its numbers shrink to fit at the largest text sizes, so the row after it stays in
    /// view. Placed from its top, at its own height: placed in the standing height, it would
    /// center in it.
    private func offer(_ proposal: ProposedViewSize, end: CGFloat) -> ProposedViewSize {
        if isAtRest {
            return proposal
        }
        return ProposedViewSize(width: proposal.width, height: isCurrent ? end : nil)
    }
}
