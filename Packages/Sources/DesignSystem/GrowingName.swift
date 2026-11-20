import CoreText
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
/// both scale by the font sizes' ratio and hand over in a short span (`Drawing.handOverSpan`)
/// ending where the small name, scaled up, would no longer fit the row: the two crossfade, the
/// name's first baseline and height running between the two sizes' as drawn over the same span
/// (`room`), the large name cut off at that height so its second line never lies over what is
/// under the name.
/// The rail's node keeps the place it has
/// on a row's name, its center that far above the baseline grown by the letters' scale
/// (`railNodeBaseline`): on the baseline alone, it kept a row's height above it and sat low on the
/// large name.
struct GrowingName: View, Animatable {
    let title: String
    var growth: CGFloat
    /// `textSecondary` on a finished exercise, so what is current reads brightest.
    var color: ColorToken = .textPrimary

    nonisolated var animatableData: CGFloat {
        get { growth }
        set { growth = newValue }
    }

    @State private var sizes = Sizes()
    @Environment(\.fontResolutionContext) private var fontContext

    var body: some View {
        let drawing = Drawing(growth: growth, ratio: ratio, sizes: sizes)
        GrowingNameLayout(growth: growth, drawing: drawing) {
            name(.ppRowTitle)
                .onGeometryChange(for: CGSize.self, of: \.size) { sizes.small = $0 }
                .scaleEffect(drawing.smallScale, anchor: .topLeading)
                .opacity(drawing.smallOpacity)
            name(.ppCurrentTitle)
                .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                    Color.clear
                        .frame(width: 0, height: capHeight)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                        .anchorPreference(key: CardMarks.self, value: .top) {
                            CardMarks.Value(nameTop: $0)
                        }
                }
                .onGeometryChange(for: CGSize.self, of: \.size) { sizes.large = $0 }
                .mask { TopPart(height: drawing.largeShown(sizes)) }
                .scaleEffect(drawing.largeScale, anchor: .topLeading)
                .opacity(drawing.largeOpacity)
            RailNodeGlyph()
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { sizes.width = $0 }
    }

    private func name(_ font: Font) -> some View {
        Text(title)
            .font(font)
            .foregroundStyle(.pp(color))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var capHeight: CGFloat {
        CTFontGetCapHeight(Font.ppCurrentTitle.resolve(in: fontContext).ctFont)
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
        /// The row's width, which both are laid out at.
        var width: CGFloat = 0

        /// Where the two hand over, where they crossfade: the growth up to which the small name,
        /// scaled up, still fits the row's width; at most 1.
        func handOver(ratio: CGFloat) -> CGFloat {
            guard small.width > 0, width > 0, ratio > 1 else { return 1 }
            return min(max((width / small.width - 1) / (ratio - 1), 0), 1)
        }

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
        /// The large name's opacity, and the small's.
        var largeOpacity: CGFloat
        var smallOpacity: CGFloat
        /// Where the crossfade is, from 0, the small name alone, to 1, the large alone: the
        /// name's height and first baseline run between the two as drawn.
        var handOff: CGFloat
        var crossfades: Bool

        /// The share of growth a crossfade spans: the small name goes in its first half, the
        /// large comes in its second, so the two are never drawn over each other.
        static let handOverSpan: CGFloat = 0.2

        init(growth: CGFloat, ratio: CGFloat, sizes: Sizes) {
            let crossfades = !sizes.breakAlike(ratio: ratio)
            self.crossfades = crossfades
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
            guard crossfades else {
                largeOpacity = growth > 0 ? 1 : 0
                smallOpacity = 1 - largeOpacity
                handOff = growth
                room = growth
                return
            }
            // Over a short span ending where the small name, scaled up, stops fitting the row:
            // across the whole growth, both were drawn at once, the two names' lines over each
            // other, and held there by the next exercise's step through a rest (`nextGrowth`).
            // The two crossfade over the span, the name's room running from the small's height to
            // the large's through the same frames, and the large name cut off at the room's
            // bottom, so its second line shows as the room reaches it, never over what is under
            // the name. Each fading in a half of the span, a frame drew neither; with the room
            // running ahead of the hand-over, a line stood empty under the small name.
            let span = Self.handOverSpan
            let end = max(sizes.handOver(ratio: ratio), span)
            let share = min(max((growth - (end - span)) / span, 0), 1)
            handOff = growth >= 1 ? 1 : growth <= 0 ? 0 : share
            smallOpacity = 1 - handOff
            largeOpacity = handOff
            room = handOff
        }

        /// Where crossfading names' room is, from the small name's at 0 to the large's at 1: over
        /// the hand-off. Where the two break alike, the growth.
        var room: CGFloat = 0

        /// The large name's height drawn, in its own unscaled points: where they crossfade, cut
        /// off at the name's room; else all of it.
        func largeShown(_ sizes: Sizes) -> CGFloat {
            guard crossfades, largeScale.height > 0 else { return .infinity }
            let small = sizes.small.height * smallScale
            let large = sizes.large.height * largeScale.height
            return (small + (large - small) * room) / largeScale.height
        }
    }
}

/// The two sizes of a name over each other at the top leading corner, as tall as the size growing
/// in is, `growth` of the way from the small's height to the large's, with its first baseline as
/// far between theirs. Its third subview is the node's glyph, which a node centers on at a row's
/// size: the node's center is as far above the baseline as the glyph's, times `letterScale`, so the
/// node column's baseline (`railNodeBaseline`) rises that offset times `letterScale - 1`.
private struct GrowingNameLayout: Layout {
    var growth: CGFloat
    var drawing: GrowingName.Drawing

    /// How large the letters are drawn against a row's name.
    private var letterScale: CGFloat {
        drawing.smallScale
    }

    /// As wide as the row, where it is given, so the name knows the width it has to grow in.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let (small, large) = sizes(proposal, subviews)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        return CGSize(
            width: width ?? max(small.width, large.width),
            height: between(small.height, large.height, by: drawing.room),
        )
    }

    /// A length of the small name and the large, at the growth: where the two break alike, run
    /// straight between; where they crossfade, between the two as drawn, `share` of the way: the
    /// hand-off for the first baseline, which is the name showing's; the room's share for the
    /// height, which runs on with the growth.
    private func between(_ small: CGFloat, _ large: CGFloat, by share: CGFloat) -> CGFloat {
        guard drawing.crossfades else { return small + (large - small) * growth }
        let drawnSmall = small * drawing.smallScale
        let drawnLarge = large * drawing.largeScale.height
        return drawnSmall + (drawnLarge - drawnSmall) * share
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        for subview in subviews.prefix(2) {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: offer)
        }
        // Offered as `explicitAlignment` measures it, so it is measured once.
        subviews.last?.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .railNodeBaseline, subviews.count == 3 else {
            return nil
        }
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        let small = subviews[0].dimensions(in: offer)[.firstTextBaseline]
        let large = subviews[1].dimensions(in: offer)[.firstTextBaseline]
        let baseline = bounds.minY + between(small, large, by: drawing.handOff)
        guard guide == .railNodeBaseline else { return baseline }
        let glyph = subviews[2].dimensions(in: .unspecified)
        return baseline - (glyph[.firstTextBaseline] - glyph.height / 2) * (letterScale - 1)
    }

    private func sizes(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGSize, CGSize) {
        guard subviews.count == 3 else { return (.zero, .zero) }
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        return (subviews[0].sizeThatFits(offer), subviews[1].sizeThatFits(offer))
    }
}

/// Everything down to `height` from the top, however far it reaches up or to either side.
private nonisolated struct TopPart: Shape {
    var height: CGFloat

    func path(in rect: CGRect) -> Path {
        let far = max(rect.width, rect.height) * 4
        let bottom = height.isFinite ? rect.minY + height : rect.maxY + far
        return Path(CGRect(
            x: rect.minX - far,
            y: rect.minY - far,
            width: rect.width + far * 2,
            height: bottom - rect.minY + far,
        ))
    }
}
