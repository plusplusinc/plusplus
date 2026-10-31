import SwiftUI

/// A current exercise's number and what it counts: side by side on their first baselines where
/// both fit the width, the number at the height offered, and otherwise, as at the accessibility
/// sizes, the unit under the number, wrapped to the width. Also the progress line's set and side.
/// A layout, not `ViewThatFits`: with
/// `ViewThatFits` here, the title's text view taking focus in a workout sent the view graph
/// round a cycle, and the app hung.
struct FigureLayout: Layout {
    var spacing: CGFloat

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
        for (subview, (frame, offer)) in zip(subviews, frames.placed) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: offer,
            )
        }
    }

    /// Where the number and the unit go, each with what it was offered, and the size of both.
    private func frames(_ proposal: ProposedViewSize, _ subviews: Subviews) -> Frames {
        guard subviews.count == 2 else {
            assertionFailure("A figure lays out its number and its unit, nothing else")
            return Frames(placed: [], size: .zero)
        }
        let (number, unit) = (subviews[0], subviews[1])
        // At the height offered, as far as it shrinks to fit it.
        let numberWidth = number.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height))
            .width
        let unitWidth = unit.sizeThatFits(.unspecified).width
        guard numberWidth + spacing + unitWidth <= proposal.width ?? .infinity else {
            return stacked(number, unit, proposal)
        }
        let numberOffer = ProposedViewSize(width: numberWidth, height: proposal.height)
        let numberSize = number.dimensions(in: numberOffer)
        let unitSize = unit.dimensions(in: .unspecified)
        let baseline = max(numberSize[.firstTextBaseline], unitSize[.firstTextBaseline])
        let numberTop = baseline - numberSize[.firstTextBaseline]
        let unitTop = baseline - unitSize[.firstTextBaseline]
        let unitX = numberSize.width + spacing
        return Frames(
            placed: [
                (
                    CGRect(origin: CGPoint(x: 0, y: numberTop), size: CGSize(
                        width: numberSize.width,
                        height: numberSize.height,
                    )),
                    numberOffer,
                ),
                (
                    CGRect(origin: CGPoint(x: unitX, y: unitTop), size: CGSize(
                        width: unitSize.width,
                        height: unitSize.height,
                    )),
                    .unspecified,
                ),
            ],
            size: CGSize(
                width: unitX + unitSize.width,
                height: max(numberTop + numberSize.height, unitTop + unitSize.height),
            ),
        )
    }

    /// The unit under the number, wrapped to the width, the number in the height left.
    private func stacked(
        _ number: LayoutSubview,
        _ unit: LayoutSubview,
        _ proposal: ProposedViewSize,
    ) -> Frames {
        let unitOffer = ProposedViewSize(width: proposal.width, height: nil)
        let unitSize = unit.dimensions(in: unitOffer)
        let numberOffer = ProposedViewSize(
            width: proposal.width,
            height: proposal.height.map { max($0 - unitSize.height, 0) },
        )
        let numberSize = number.dimensions(in: numberOffer)
        return Frames(
            placed: [
                (
                    CGRect(origin: .zero, size: CGSize(
                        width: numberSize.width,
                        height: numberSize.height,
                    )),
                    numberOffer,
                ),
                (
                    CGRect(
                        origin: CGPoint(x: 0, y: numberSize.height),
                        size: CGSize(width: unitSize.width, height: unitSize.height),
                    ),
                    unitOffer,
                ),
            ],
            size: CGSize(
                width: max(numberSize.width, unitSize.width),
                height: numberSize.height + unitSize.height,
            ),
        )
    }

    private struct Frames {
        /// The number's frame and offer, then the unit's.
        var placed: [(CGRect, ProposedViewSize)]
        var size: CGSize
    }
}
