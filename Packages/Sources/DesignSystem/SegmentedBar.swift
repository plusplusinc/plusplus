import SwiftUI

/// A workout's muscles as one bar of capsules, a segment per group in proportion to its share,
/// the bar's length `fill` of its width. Its segments' places come from `frames(shares:fill:in:)`,
/// which the words under it (`SegmentWords`) read too, so a word starts under its segment.
struct SegmentedBar: View {
    let shares: [Double]
    let fill: Double

    /// The bar's thickness.
    nonisolated static let height: CGFloat = 6
    /// The gap between two segments.
    nonisolated static let gap: CGFloat = 3
    /// The narrowest a segment draws, so every segment can be told apart.
    nonisolated static let minSegment: CGFloat = 12

    var body: some View {
        // Placed by a layout, so a change of `fill` moves the segments under the change's
        // animation.
        Segments(shares: shares, fill: fill) {
            ForEach(shares.indices, id: \.self) { index in
                Capsule().fill(Self.color(at: index))
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    private struct Segments: Layout {
        let shares: [Double]
        let fill: Double

        func sizeThatFits(
            proposal: ProposedViewSize,
            subviews _: Subviews,
            cache _: inout (),
        ) -> CGSize {
            CGSize(width: proposal.width ?? 0, height: proposal.height ?? SegmentedBar.height)
        }

        func placeSubviews(
            in bounds: CGRect,
            proposal _: ProposedViewSize,
            subviews: Subviews,
            cache _: inout (),
        ) {
            let frames = SegmentedBar.frames(shares: shares, fill: fill, in: bounds.width)
            for (subview, frame) in zip(subviews, frames) {
                subview.place(
                    at: CGPoint(x: bounds.minX + frame.lowerBound, y: bounds.minY),
                    proposal: ProposedViewSize(
                        width: frame.upperBound - frame.lowerBound,
                        height: bounds.height,
                    ),
                )
            }
        }
    }

    /// The segment's gray, stepping down from the first, the largest.
    static func color(at index: Int) -> Color {
        switch index {
        case 0: .pp(.textPrimary)
        case 1: .pp(.textSecondary)
        case 2: .pp(.textTertiary)
        default: .pp(.toDo)
        }
    }

    /// Each segment's span along a bar `width` wide: together `fill` of it, gaps between, each at
    /// least `minSegment` and the rest shared out by `shares`, which sum to 1. A bar never
    /// passes `width`, nor draws shorter than its segments' minimums and gaps.
    nonisolated static func frames(
        shares: [Double],
        fill: Double,
        in width: CGFloat,
    ) -> [ClosedRange<CGFloat>] {
        guard !shares.isEmpty, width > 0 else { return [] }
        let count = CGFloat(shares.count)
        let shortest = count * minSegment + (count - 1) * gap
        let length = min(width, max(shortest, CGFloat(fill) * width))
        let spare = max(0, length - shortest)
        let total = shares.reduce(0, +)
        var start: CGFloat = 0
        return shares.map { share in
            let part = total > 0 ? CGFloat(share / total) : 1 / count
            let end = start + minSegment + spare * part
            defer { start = end + gap }
            return start ... end
        }
    }
}

/// Where each word under a bar starts: at its segment's start, or just after the word before
/// it when that one runs past, so every word shows, in order, and none overlap.
nonisolated enum WordPlacement {
    static func origins(starts: [CGFloat], widths: [CGFloat], gap: CGFloat) -> [CGFloat] {
        var end = -CGFloat.infinity
        return zip(starts, widths).map { start, width in
            let origin = max(start, end + gap)
            end = origin + width
            return origin
        }
    }
}

/// The words under a `SegmentedBar`, each placed by `WordPlacement` under its segment. It
/// reports the last word's end as its width.
struct SegmentWords: Layout {
    let shares: [Double]
    let fill: Double
    var gap: CGFloat = Spacing.sm

    private func origins(subviews: Subviews, width: CGFloat) -> [CGFloat] {
        let starts = SegmentedBar.frames(shares: shares, fill: fill, in: width).map(\.lowerBound)
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        return WordPlacement.origins(starts: starts, widths: widths, gap: gap)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let origins = origins(subviews: subviews, width: width)
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let end = zip(origins, sizes).map { $0 + $1.width }.max() ?? 0
        return CGSize(width: end, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let origins = origins(subviews: subviews, width: proposal.width ?? bounds.width)
        for (subview, origin) in zip(subviews, origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin, y: bounds.minY),
                proposal: .unspecified,
            )
        }
    }
}
