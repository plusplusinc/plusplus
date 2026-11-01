import SwiftUI

/// The label's column, from its top, standing as tall as the row it is: as a row, its own height;
/// as the current exercise, its grown column's own height, its name, set, equipment, and
/// numbers. `growth` runs from 0, a row, to 1, the current exercise, and the height with it, so
/// it grows and shrinks on the animation's curve; it is taller by however far the column runs
/// past both that height and the one it is going to. The column takes its
/// new height at once, its new parts fading in later: counted whole, it held the label at that
/// height until the animated one passed it, so the rows below started late. A frame's
/// `minHeight` animated from 0 laid the row out at no height for the first frame.
struct StandingHeight: Layout {
    var growth: CGFloat
    /// Not animated: whether it is the current exercise, where `growth` is going to 1.
    let isCurrent: Bool
    /// The column's height as a row, which the height runs from and back to.
    let restingHeight: CGFloat
    /// The column's height as the current exercise when last laid out as one, which a shrink runs
    /// from.
    let grownHeight: CGFloat

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
        // Shrinking, the parts going still take their room until they have gone, so the label
        // stands at its height alone, cutting them off (`BottomClip`): counted, they held the
        // rows below, then let them jump.
        guard isCurrent else { return CGSize(width: size.width, height: heights.now) }
        // The column takes its new height at once, so it counts only past the end height: where
        // it runs past it, as at the largest text sizes.
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
        let grown = isCurrent ? columnHeight(proposal, subviews) : grownHeight
        let now = restingHeight + (grown - restingHeight) * growth
        return (now, isCurrent ? grown : restingHeight)
    }

    /// As the current exercise: its column's own height, the parts it is growing included.
    private func columnHeight(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            .height ?? 0
    }

    /// What the column is offered: at rest, what the label was, as a row on `main` was; while it
    /// shrinks, as tall as it likes; and on the current exercise its own height, `end`. Placed
    /// from its top, at its own height: placed in the standing height, it would
    /// center in it.
    private func offer(_ proposal: ProposedViewSize, end: CGFloat) -> ProposedViewSize {
        if isAtRest {
            return proposal
        }
        return ProposedViewSize(width: proposal.width, height: isCurrent ? end : nil)
    }
}
