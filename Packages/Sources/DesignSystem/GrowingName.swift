import SwiftUI

/// A row's name, `ppRowTitle` on a row and `ppCurrentTitle` on the current exercise, growing
/// between the two as `growth` animates from 0 to 1. Both sizes are laid out at the row's width
/// once, and the one showing is scaled from its top leading corner, so the name grows as one
/// drawn piece: a font size animated frame by frame reflowed its text on every frame, stepped
/// where the system font changes its optical size, and could break its lines differently partway.
/// Where the two sizes break into the same number of lines, the large name is drawn throughout,
/// scaled down, and across from the small name's measured width at 0: the system font sets words
/// narrower per point at the large size, so the font sizes' ratio alone left it about 3% narrower
/// than the name it hands off to, which then stepped wider. Where they don't, as a long name can,
/// the two crossfade as they scale by the font sizes' ratio. The name's
/// height and first baseline run between the two sizes', so the rail's node, on that baseline,
/// moves with it.
struct GrowingName: View, Animatable {
    let title: String
    var growth: CGFloat

    nonisolated var animatableData: CGFloat {
        get { growth }
        set { growth = newValue }
    }

    @State private var sizes = Sizes()
    @Environment(\.fontResolutionContext) private var fontContext

    var body: some View {
        let drawing = Drawing(growth: growth, ratio: ratio, sizes: sizes)
        GrowingNameLayout(growth: growth) {
            name(.ppRowTitle)
                .onGeometryChange(for: CGSize.self, of: \.size) { sizes.small = $0 }
                .scaleEffect(drawing.smallScale, anchor: .topLeading)
                .opacity(1 - drawing.largeOpacity)
            name(.ppCurrentTitle)
                .onGeometryChange(for: CGSize.self, of: \.size) { sizes.large = $0 }
                .scaleEffect(drawing.largeScale, anchor: .topLeading)
                .opacity(drawing.largeOpacity)
        }
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

    /// Both sizes laid out at the row's width.
    struct Sizes: Equatable {
        var small: CGSize = .zero
        var large: CGSize = .zero

        /// Whether the two sizes break into the same lines: the large as tall as the small
        /// scaled up, give or take less than a line, and as wide, give or take a tenth. The
        /// system font's width per point differs between the sizes by only a few percent, so
        /// as many lines broken at other words show as widest lines far further apart.
        func breakAlike(ratio: CGFloat) -> Bool {
            guard small.height > 0 else { return true }
            let lines = large.height / (small.height * ratio)
            guard lines > 0.75, lines < 1.33 else { return false }
            guard small.width > 0, large.width > 0 else { return true }
            let widths = small.width * ratio / large.width
            return widths > 0.9 && widths < 1.1
        }

        /// The large name's scale across at rest: the small's width over its own, or the font
        /// sizes' ratio before both are measured.
        func restingWidthScale(ratio: CGFloat) -> CGFloat {
            guard small.width > 0, large.width > 0 else { return 1 / ratio }
            return small.width / large.width
        }
    }

    /// How each size is drawn at `growth`, given the font sizes' ratio and the two measured sizes.
    struct Drawing {
        /// The small name's scale, both ways.
        var smallScale: CGFloat
        /// The large name's scale, across and up and down.
        var largeScale: CGSize
        /// The large name's opacity; the small's is what's left of 1.
        var largeOpacity: CGFloat

        init(growth: CGFloat, ratio: CGFloat, sizes: Sizes) {
            let crossfades = !sizes.breakAlike(ratio: ratio)
            // Each way, from its scale at rest (at 0) to the large name's own size (at 1). Up and
            // down, a row's size by the font sizes' ratio, which keeps the letters' height.
            // Across, where the large name is drawn throughout, the small name's measured width,
            // so the hand-off at rest lands on the same width.
            let scale = 1 / ratio + (1 - 1 / ratio) * growth
            let resting = crossfades ? 1 / ratio : sizes.restingWidthScale(ratio: ratio)
            let widthScale = resting + (1 - resting) * growth
            smallScale = scale * ratio
            // Unscaled at rest, where it doesn't show: scaled down to a row's size, its text at
            // the large size in a frame that much smaller read as clipped in the accessibility
            // audit.
            largeScale = growth == 0
                ? CGSize(width: 1, height: 1)
                : CGSize(width: widthScale, height: scale)
            largeOpacity = switch growth {
            case ...0: 0
            case 1...: 1
            default: crossfades ? growth : 1
            }
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
