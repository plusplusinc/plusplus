import CoreText
import SwiftUI

/// A row's name, `ppRowTitle` on a row and `ppCurrentTitle` on the current exercise, growing
/// between the two as `growth` animates from 0 to 1, as one block that scales from its top leading
/// corner: a font size animated frame by frame reflowed its text on every frame, stepped where the
/// system font changes its optical size, and could break its lines differently partway.
///
/// Both sizes hold the same words on each line, the lines the large name breaks into at the row's
/// width (`LineBreaks`): a hidden copy of the large name is laid out at that width, the system
/// wraps it, and the name is drawn at both sizes with a line break where each of its lines
/// starts. Each line fits the row at the large size, so at the small size, a few percent wider
/// per point at most, it fits too, and neither size has a break of its own to make. Laid out
/// apart, the two broke at other words where a long name fit one line small and two large, and
/// the row's height had to change by a line partway (rounds 15 to 19).
///
/// The small name is drawn at rest and the large throughout the growth, scaled down, and across
/// from the small name's measured width at 0, so each is sharp at its own size: the system font
/// sets words narrower per point at the large size, so the font sizes' ratio alone left it about
/// 3% narrower than the name it takes over from, which then stepped wider. The name's height and
/// first baseline run between the two sizes'. The rail's node keeps the place it has on a row's
/// name, its center that far above the baseline grown by the letters' scale (`railNodeBaseline`):
/// on the baseline alone, it kept a row's height above it and sat low on the large name.
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
    @State private var breaks = LineBreaks()
    @Environment(\.fontResolutionContext) private var fontContext

    var body: some View {
        let drawing = Drawing(growth: growth, ratio: ratio, sizes: sizes)
        let lines = breaks.lines(of: title)
        GrowingNameLayout(growth: growth, letterScale: drawing.smallScale) {
            name(lines, .ppRowTitle)
                .onGeometryChange(for: CGSize.self, of: \.size) { sizes.small = $0 }
                .scaleEffect(drawing.smallScale, anchor: .topLeading)
                .opacity(1 - drawing.largeOpacity)
            name(lines, .ppCurrentTitle)
                .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                    Color.clear
                        .frame(width: 0, height: capHeight)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                        .anchorPreference(key: CardMarks.self, value: .top) {
                            CardMarks.Value(nameTop: $0)
                        }
                }
                .onGeometryChange(for: CGSize.self, of: \.size) { sizes.large = $0 }
                .scaleEffect(drawing.largeScale, anchor: .topLeading)
                .opacity(drawing.largeOpacity)
            RailNodeGlyph()
            linesProbe(1, .ppRowTitle)
            linesProbe(2, .ppRowTitle)
            linesProbe(1, .ppCurrentTitle)
            linesProbe(2, .ppCurrentTitle)
            name(title, .ppCurrentTitle)
                .hidden()
        }
        .background(alignment: .topLeading) { measure }
    }

    /// `count` lines in `font`, never drawn, from which the layout reads a line's height and the
    /// next line's advance (`GrowingNameLayout`).
    private func linesProbe(_ count: Int, _ font: Font) -> some View {
        Text(verbatim: Array(repeating: "X", count: count).joined(separator: "\n"))
            .font(font)
            .fixedSize()
            .hidden()
    }

    private func name(_ text: String, _ font: Font) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(.pp(color))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The large name as the system wraps it at the row's width, never drawn, where its lines are
    /// read from.
    private var measure: some View {
        let title = title
        return Text(title)
            .font(.ppCurrentTitle)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0)
            .accessibilityHidden(true)
            .onPreferenceChange(Text.LayoutKey.self) { layouts in
                guard let layout = layouts.first?.layout else { return }
                let measured = LineBreaks(title: title, layout: layout)
                if breaks != measured {
                    breaks = measured
                }
            }
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

    /// Where the large name's lines start, as the system laid it out at the row's width: offsets
    /// into the title's UTF-16 view, the first line's at 0 left out.
    struct LineBreaks: Equatable {
        var title = ""
        var starts: [Int] = []

        init() { }

        init(title: String, starts: [Int]) {
            self.title = title
            self.starts = starts
        }

        init(title: String, layout: Text.Layout) {
            let firsts = layout.compactMap { line in
                line.flatMap(\.characterIndices).min()
            }
            guard let origin = firsts.first else {
                self.init(title: title, starts: [])
                return
            }
            self.init(title: title, starts: firsts.dropFirst().map { origin.distance(to: $0) })
        }

        /// The title with a line break where each line starts and the spaces before it dropped,
        /// or the title as it is when these were measured for another.
        func lines(of title: String) -> String {
            guard title == self.title, !starts.isEmpty else { return title }
            let utf16 = title.utf16
            var lines: [String] = []
            var from = 0
            for start in starts + [utf16.count] {
                guard start > from, start <= utf16.count,
                      let lower = utf16.index(
                          utf16.startIndex,
                          offsetBy: from,
                          limitedBy: utf16.endIndex,
                      ),
                      let upper = utf16.index(
                          utf16.startIndex,
                          offsetBy: start,
                          limitedBy: utf16.endIndex,
                      ),
                      let line = String(utf16[lower ..< upper])
                else { return title }
                lines.append(line.trimmingCharacters(in: .whitespaces))
                from = start
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Both sizes, laid out at the row's width.
    struct Sizes: Equatable {
        var small: CGSize = .zero
        var large: CGSize = .zero

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
            // Each way, from its scale at rest (at 0) to the large name's own size (at 1). Up and
            // down, a row's size by the font sizes' ratio, which keeps the letters' height.
            // Across, the small name's measured width, so the large name taking over at rest
            // lands on the same width.
            let scale = 1 / ratio + (1 - 1 / ratio) * growth
            let resting = sizes.restingWidthScale(ratio: ratio)
            let widthScale = resting + (1 - resting) * growth
            smallScale = scale * ratio
            // Unscaled at rest, where it doesn't show: scaled down to a row's size, its text at
            // the large size in a frame that much smaller read as clipped in the accessibility
            // audit.
            largeScale = growth == 0
                ? CGSize(width: 1, height: 1)
                : CGSize(width: widthScale, height: scale)
            largeOpacity = growth > 0 ? 1 : 0
        }
    }
}

/// The two sizes of a name over each other at the top leading corner, as tall as the size growing
/// in is, `growth` of the way from the small's height to the large's, with its first baseline as
/// far between theirs. Its third subview is the node's glyph, which a node centers on at a row's
/// size: the node's center is as far above the baseline as the glyph's, times `letterScale`, so the
/// node column's baseline (`railNodeBaseline`) rises that offset times `letterScale - 1`. The last
/// four are one line and two at each size, never drawn, and the eighth the large name whole,
/// never drawn either.
///
/// The small name's height is that of as many lines at a row's size as the large name whole
/// breaks into at the width offered, from the probes' line height and advance, so the row is laid
/// out once, at the height it keeps: until the large name's lines are read, the small one is drawn
/// whole, and from its own height the row grew a line in the pass after, a list of them reporting
/// its height twice in one frame. Not from the drawn large name, whose breaks were read at the
/// last width: at launch, read at the window's narrow first width, they stood the row that many
/// lines tall at its full width for a pass.
private struct GrowingNameLayout: Layout {
    var growth: CGFloat
    /// How large the letters are drawn against a row's name.
    var letterScale: CGFloat

    /// As wide as the row, where it is given, so the name knows the width it has to grow in.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        var (small, large) = sizes(proposal, subviews)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        if subviews.count == 8 {
            let row = Lines(one: subviews[3], two: subviews[4])
            let current = Lines(one: subviews[5], two: subviews[6])
            // Offered no width, the whole name would stand on one line: the drawn one's breaks
            // are all there is to go by.
            let lines = width.map {
                subviews[7].sizeThatFits(ProposedViewSize(width: $0, height: nil)).height
            } ?? large.height
            small.height = row.height(of: current.count(in: lines))
        }
        return CGSize(
            width: width ?? max(small.width, large.width),
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
        for subview in subviews.prefix(2) {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: offer)
        }
        // Offered as `explicitAlignment` measures it, so it is measured once.
        for subview in subviews.dropFirst(2).prefix(5) {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
        }
        // At the width `sizeThatFits` measures it, so it is measured once.
        subviews.dropFirst(7).first?.place(at: bounds.origin, anchor: .topLeading, proposal: offer)
    }

    /// A name's lines at one size: a line's height and the next one's advance, from one line of
    /// the name and two of the probe.
    private struct Lines {
        let first: CGFloat
        let advance: CGFloat

        init(one: LayoutSubview, two: LayoutSubview) {
            first = one.sizeThatFits(.unspecified).height
            advance = two.sizeThatFits(.unspecified).height - first
        }

        func count(in height: CGFloat) -> Int {
            guard advance > 0 else { return 1 }
            return max(1, Int(((height - first) / advance).rounded()) + 1)
        }

        func height(of lines: Int) -> CGFloat {
            first + advance * CGFloat(lines - 1)
        }
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .railNodeBaseline, subviews.count == 8 else {
            return nil
        }
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        let small = subviews[0].dimensions(in: offer)[.firstTextBaseline]
        let large = subviews[1].dimensions(in: offer)[.firstTextBaseline]
        let baseline = bounds.minY + small + (large - small) * growth
        guard guide == .railNodeBaseline else { return baseline }
        let glyph = subviews[2].dimensions(in: .unspecified)
        return baseline - (glyph[.firstTextBaseline] - glyph.height / 2) * (letterScale - 1)
    }

    private func sizes(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGSize, CGSize) {
        guard subviews.count == 8 else { return (.zero, .zero) }
        let offer = ProposedViewSize(width: proposal.width, height: nil)
        return (subviews[0].sizeThatFits(offer), subviews[1].sizeThatFits(offer))
    }
}
