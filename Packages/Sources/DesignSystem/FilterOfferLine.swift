#if os(iOS)
import SwiftUI

/// The line under the filter buttons while typed words name a filter's choice: "Filter by" in
/// the letter headings' style, right before a "+ Back" button per offer, the pair at the
/// trailing edge. Each button is the small capsule "+ Bench" wears (`SmallCapsuleButton`), its
/// + green, as the app's other + marks that add something are. Where the words and the buttons
/// won't fit on one line, as at the accessibility sizes or with three long names, the buttons
/// show alone (`WordsOrButtons`); where they won't fit side by side either, they go one under
/// another (`OfferButtons`). VoiceOver reads each button as "Add back to Muscle", which says
/// what it adds to with the words gone too.
///
/// Side by side, two buttons' touches each reach halfway into the gap between them, so a tap
/// lands on the nearer one.
public struct FilterOfferLine: View {
    let text: String
    let offers: [Offer]
    @Environment(\.touchRoom) private var room
    @State private var wordsShown = true

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

    public init(_ text: String = "Filter by", offers: [Offer]) {
        self.text = text
        self.offers = offers
    }

    public var body: some View {
        WordsOrButtons {
            Text(text)
                .fontWeight(.semibold)
                .foregroundStyle(Color.pp(.textSecondary))
                .lineLimit(1)
                .fixedSize()
                // Shrinks to nothing, and draws nothing, where `WordsOrButtons` drops it.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                // A dropped label keeps its text, so VoiceOver would still find it off screen;
                // in the filter bar, a bar item, only `accessibilityShown` hides it.
                .onGeometryChange(for: Bool.self) { $0.size.width > 0 } action: { wordsShown = $0 }
                .accessibilityShown(wordsShown)
            OfferButtons(room: room) {
                ForEach(offers) { offer in
                    SmallCapsuleButton(
                        systemImage: "plus",
                        title: offer.title,
                        symbolColor: .accent,
                        alignment: .trailing,
                        action: offer.action,
                    )
                    .accessibilityLabel("Add \(offer.title.lowercased()) to \(offer.filterName)")
                    .touchRoom(
                        leading: offer.id == offers.first?.id ? nil : Spacing.sm / 2,
                        trailing: offer.id == offers.last?.id ? nil : Spacing.sm / 2,
                    )
                    // A taken offer goes at once, as its choice lights in the filter's button:
                    // fading in place, the words sliding over to the offers left ran across it.
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
            }
        }
        .font(.ppRowDetail)
        // With Reduce Motion nothing slides: a new set of offers is a new line, which
        // crossfades, as the filter buttons' row does. Without the identity, the words and the
        // buttons left slid over to the trailing edge as a taken offer went.
        .crossfadesWithReduceMotion(on: offers.map(\.id))
    }
}

/// An offer line's words right before its buttons, together at the trailing edge, centered on
/// each other; or, where the two won't fit side by side at their one-line widths, the buttons
/// alone at the trailing edge, and the words not drawn: stacked over the buttons at the
/// largest text sizes they took a third of the list's room over the keyboard, and the "+" and
/// the line's place under the filters carry their meaning (decided 2026-11-22).
struct WordsOrButtons: Layout {
    var spacing = Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? .infinity
        if let line = oneLine(subviews[0], subviews[1], in: width) {
            return CGSize(width: width.isFinite ? width : line.width, height: line.height)
        }
        let buttons = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width.isFinite ? width : buttons.width, height: buttons.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        guard subviews.count == 2 else { return }
        let (words, buttons) = (subviews[0], subviews[1])
        if oneLine(words, buttons, in: bounds.width) != nil {
            let buttonsWidth = buttons.sizeThatFits(.unspecified).width
            buttons.place(
                at: CGPoint(x: bounds.maxX, y: bounds.midY),
                anchor: .trailing,
                proposal: .unspecified,
            )
            words.place(
                at: CGPoint(x: bounds.maxX - buttonsWidth - spacing, y: bounds.midY),
                anchor: .trailing,
                proposal: .unspecified,
            )
            return
        }
        words.place(at: bounds.origin, proposal: .zero)
        buttons.place(
            at: CGPoint(x: bounds.maxX, y: bounds.minY),
            anchor: .topTrailing,
            proposal: ProposedViewSize(width: bounds.width, height: nil),
        )
    }

    /// The two at their one-line sizes, when they fit side by side in the width.
    private func oneLine(
        _ words: LayoutSubview,
        _ buttons: LayoutSubview,
        in width: CGFloat,
    ) -> CGSize? {
        let leading = words.sizeThatFits(.unspecified)
        let trailing = buttons.sizeThatFits(.unspecified)
        guard leading.width + spacing + trailing.width <= width else { return nil }
        return CGSize(
            width: leading.width + spacing + trailing.width,
            height: max(leading.height, trailing.height),
        )
    }
}

/// An offer line's buttons: side by side, a gap apart, where they fit in the width; otherwise
/// one under another, trailing, each gap as wide as the two buttons' touches reach across it
/// (`TouchOutset`, capped by `room`), so they meet without overlapping or leaving a dead strip.
/// A small `Layout`, not `ViewThatFits`, which hung the workout screen.
struct OfferButtons: Layout {
    /// The cap on the buttons' reach from further out.
    var room = TouchRoom()

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? .infinity
        if fitsRow(sizes, in: width) {
            return CGSize(width: rowWidth(sizes), height: sizes.map(\.height).max() ?? 0)
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
        if fitsRow(sizes, in: bounds.width) {
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
            view.place(at: CGPoint(x: bounds.maxX, y: y), anchor: .topTrailing, proposal: column)
            y += heights[index] + gaps[index]
        }
    }

    private func rowWidth(_ sizes: [CGSize]) -> CGFloat {
        sizes.map(\.width).reduce(0, +) + Spacing.sm * CGFloat(max(sizes.count - 1, 0))
    }

    /// Whether the buttons fit side by side, give or take the half point a width rounds by:
    /// sizing and placing ask the same question, so they never pick different arrangements.
    private func fitsRow(_ sizes: [CGSize], in width: CGFloat) -> Bool {
        rowWidth(sizes) <= width + 0.5
    }

    /// The gap under each button but the last: a gap, or as wide as the upper button's touch
    /// reaches down and the lower one's up, where that is wider.
    private func gaps(_ heights: [CGFloat]) -> [CGFloat] {
        zip(heights, heights.dropFirst()).map { upper, lower in
            let outset = TouchOutset(
                minHeight: SmallCapsuleButton.touchHeight,
                sides: 0,
                room: room,
            )
            let below = outset.insets(around: CGSize(width: 0, height: upper)).bottom
            let above = outset.insets(around: CGSize(width: 0, height: lower)).top
            return max(Spacing.sm, below + above)
        }
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: Spacing.md) {
        FilterOfferLine(offers: [.init(title: "Back", filterName: "Muscle") { }])
        FilterOfferLine(offers: [
            .init(title: "Back", filterName: "Muscle") { },
            .init(title: "Dumbbells", filterName: "Equipment") { },
        ])
        FilterOfferLine(offers: [
            .init(title: "Medicine ball", filterName: "Equipment") { },
            .init(title: "Balance board", filterName: "Equipment") { },
            .init(title: "Stretch", filterName: "Kind") { },
        ])
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .trailing)
    .background(Color.pp(.background))
}
#endif
