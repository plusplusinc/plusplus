import SwiftUI

/// A row's name, `ppRowTitle` on a row and `ppCurrentTitle` on the current exercise, growing
/// between the two as `growth` animates from 0 to 1. Both sizes are laid out at the row's width
/// once, and the one showing is scaled from its top leading corner, so the name grows as one
/// drawn piece: a font size animated frame by frame reflowed its text on every frame, stepped
/// where the system font changes its optical size, and could break its lines differently partway.
/// Where the two sizes break into the same number of lines, the large name is drawn throughout,
/// scaled down; where they don't, as a long name can, the two crossfade as they scale. The name's
/// height and first baseline run between the two sizes', so the rail's node, on that baseline,
/// moves with it.
struct GrowingName: View, Animatable {
    let title: String
    var growth: CGFloat

    nonisolated var animatableData: CGFloat {
        get { growth }
        set { growth = newValue }
    }

    @State private var heights = Heights()
    @Environment(\.fontResolutionContext) private var fontContext
    @ObserveHotReload private var hotReload

    var body: some View {
        let ratio = ratio
        // The large name's scale: a row's size at 0, its own at 1.
        let scale = 1 / ratio + (1 - 1 / ratio) * growth
        let crossfades = !heights.breakAlike(ratio: ratio)
        let largeOpacity: CGFloat = switch growth {
        case ...0: 0
        case 1...: 1
        default: crossfades ? growth : 1
        }
        GrowingNameLayout(growth: growth) {
            name(.ppRowTitle)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { heights.small = $0 }
                .scaleEffect(scale * ratio, anchor: .topLeading)
                .opacity(1 - largeOpacity)
            name(.ppCurrentTitle)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { heights.large = $0 }
                // Unscaled at rest, where it doesn't show: scaled down to a row's size, its text
                // at the large size in a frame that much smaller read as clipped in the
                // accessibility audit.
                .scaleEffect(growth == 0 ? 1 : scale, anchor: .topLeading)
                .opacity(largeOpacity)
        }
        .hotReloadable()
    }

    private func name(_ font: Font) -> some View {
        Text(title)
            .font(font)
            .foregroundStyle(.pp(.textPrimary))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The large size against the small.
    private var ratio: CGFloat {
        let small = Font.ppRowTitle.resolve(in: fontContext).pointSize
        let large = Font.ppCurrentTitle.resolve(in: fontContext).pointSize
        return small > 0 ? max(large / small, 1) : 1
    }

    /// Both sizes' heights at the row's width.
    private struct Heights: Equatable {
        var small: CGFloat = 0
        var large: CGFloat = 0

        /// Whether the two sizes break into as many lines: the large as tall as the small
        /// scaled up, give or take less than a line.
        func breakAlike(ratio: CGFloat) -> Bool {
            guard small > 0 else { return true }
            let lines = large / (small * ratio)
            return lines > 0.75 && lines < 1.33
        }
    }
}

/// The two sizes of a name over each other at the top leading corner, as tall as the size growing
/// in is, `growth` of the way from the small's height to the large's, with its first baseline as
/// far between theirs.
private struct GrowingNameLayout: Layout {
    var growth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let (small, large) = sizes(proposal, subviews)
        return CGSize(
            width: max(small.width, large.width),
            height: small.height + (large.height - small.height) * growth,
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: offer)
        }
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGFloat? {
        guard guide == .firstTextBaseline, subviews.count == 2 else { return nil }
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        let small = subviews[0].dimensions(in: offer)[.firstTextBaseline]
        let large = subviews[1].dimensions(in: offer)[.firstTextBaseline]
        return bounds.minY + small + (large - small) * growth
    }

    private func sizes(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGSize, CGSize) {
        guard subviews.count == 2 else { return (.zero, .zero) }
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        return (subviews[0].sizeThatFits(offer), subviews[1].sizeThatFits(offer))
    }
}
