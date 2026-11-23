#if os(iOS)
import SwiftUI

/// The line that offers a filter when typed words name one of its choices: "Filter by
/// muscle" leading, gray as the count line's words, and a "+ Back" button per offer trailing,
/// the small capsule Clear and "+ Bench" wear (`SmallCapsuleButton`). Where they won't fit
/// side by side, the buttons go under the words (`LineOrStack`), and where the buttons won't
/// fit side by side either, as with three long names or at the largest text sizes, they go
/// one under another (`OfferButtons`). VoiceOver reads each button as "Add back to Muscle".
///
/// Side by side, two buttons' touches each reach halfway into the gap between them, so a tap
/// lands on the nearer one.
public struct FilterOfferLine: View {
    let text: String
    let offers: [Offer]

    /// One offer's button: the choice's name, the filter it joins, and what a tap does.
    public struct Offer: Identifiable {
        public let id: String
        let title: String
        let filterName: String
        let action: () -> Void

        public init(title: String, filterName: String, action: @escaping () -> Void) {
            id = "\(filterName).\(title)"
            self.title = title
            self.filterName = filterName
            self.action = action
        }
    }

    public init(_ text: String, offers: [Offer]) {
        self.text = text
        self.offers = offers
    }

    public var body: some View {
        TextAndButton {
            Text(text)
                .foregroundStyle(Color.pp(.textSecondary))
        } button: {
            OfferButtons {
                ForEach(offers) { offer in
                    SmallCapsuleButton(
                        systemImage: "plus",
                        title: offer.title,
                        action: offer.action,
                    )
                    .accessibilityLabel("Add \(offer.title.lowercased()) to \(offer.filterName)")
                    .touchRoom(
                        leading: offer.id == offers.first?.id ? nil : Spacing.sm / 2,
                        trailing: offer.id == offers.last?.id ? nil : Spacing.sm / 2,
                    )
                }
            }
        }
    }
}

/// An offer line's buttons: side by side, a gap apart, where they fit in the width; otherwise
/// one under another, leading, each gap wide enough that two buttons' thumb-high touches
/// (`TouchOutset`) meet without overlapping. A small `Layout`, not `ViewThatFits`, which hung
/// the workout screen.
struct OfferButtons: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let row = rowWidth(sizes)
        let width = proposal.width ?? .infinity
        if row <= width {
            return CGSize(width: row, height: sizes.map(\.height).max() ?? 0)
        }
        let column = ProposedViewSize(width: width, height: nil)
        let heights = subviews.map { $0.sizeThatFits(column).height }
        return CGSize(
            width: min(width, sizes.map(\.width).max() ?? 0),
            height: heights.reduce(0, +) + gaps(heights).reduce(0, +),
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        if rowWidth(sizes) <= bounds.width + 0.5 {
            var x = bounds.minX
            for (view, size) in zip(subviews, sizes) {
                view.place(
                    at: CGPoint(x: x, y: bounds.midY),
                    anchor: .leading,
                    proposal: .unspecified,
                )
                x += size.width + Spacing.sm
            }
            return
        }
        let column = ProposedViewSize(width: bounds.width, height: nil)
        let heights = subviews.map { $0.sizeThatFits(column).height }
        let gaps = gaps(heights) + [0]
        var y = bounds.minY
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX, y: y), proposal: column)
            y += heights[index] + gaps[index]
        }
    }

    private func rowWidth(_ sizes: [CGSize]) -> CGFloat {
        sizes.map(\.width).reduce(0, +) + Spacing.sm * CGFloat(max(sizes.count - 1, 0))
    }

    /// The gap under each button but the last: a gap, or wider where the two buttons' touches,
    /// each reaching to a thumb's height around its capsule, would overlap across it.
    private func gaps(_ heights: [CGFloat]) -> [CGFloat] {
        zip(heights, heights.dropFirst()).map { upper, lower in
            max(Spacing.sm, SmallCapsuleButton.touchHeight - (upper + lower) / 2)
        }
    }
}

/// The lines under the filter buttons: the count and Clear while a filter is on
/// (`FilterCount`), and under it the offer line while typed words name a filter's choice
/// (`FilterOfferLine`), a gap apart. The two lines' touches reach a thumb's height around
/// their capsules, further than the gap, so where both show each reaches only halfway into it,
/// and a tap lands on the button nearer the finger. Either line comes and goes at once, with no
/// motion.
public struct FilterLines: View {
    let count: FilterCount?
    let offer: FilterOfferLine?

    public init(count: FilterCount?, offer: FilterOfferLine?) {
        self.count = count
        self.offer = offer
    }

    public var body: some View {
        let shared = count != nil && offer != nil ? Spacing.sm / 2 : nil
        VStack(alignment: .leading, spacing: Spacing.sm) {
            count.map { $0.touchRoom(below: shared) }
            offer.map { $0.touchRoom(above: shared) }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.md) {
        FilterOfferLine(
            "Filter by muscle",
            offers: [.init(title: "Back", filterName: "Muscle") { }],
        )
        FilterLines(
            count: FilterCount("23 exercises") { },
            offer: FilterOfferLine("Filter by", offers: [
                .init(title: "Back", filterName: "Muscle") { },
                .init(title: "Dumbbells", filterName: "Equipment") { },
            ]),
        )
        FilterOfferLine("Filter by", offers: [
            .init(title: "Medicine ball", filterName: "Equipment") { },
            .init(title: "Balance board", filterName: "Equipment") { },
            .init(title: "Stretch", filterName: "Kind") { },
        ])
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.pp(.background))
}
#endif
