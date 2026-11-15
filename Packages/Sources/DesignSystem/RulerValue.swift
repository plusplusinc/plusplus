import SwiftUI

/// A row's value as text: numbers in SF Mono, words in the system font. With `number`, the
/// digits roll by the way it went, up or down; without, the system's default roll. With Reduce
/// Motion, text that changes with its number, as a row opens ("25" to "25.0"), crossfades; a
/// new number `ValueRow` crossfades as a new view.
struct ValueText: View {
    let text: String
    let number: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(AttributedString.monoNumbers(text, font: .ppRowTitleNumber))
            .font(.ppRowTitle)
            .contentTransition(Self.transition(rolling: number, reduceMotion: reduceMotion))
            .foregroundStyle(.pp(.textPrimary))
    }

    static func transition(rolling number: Double?, reduceMotion: Bool) -> ContentTransition {
        if reduceMotion {
            return .opacity
        }
        return number.map { .numericText(value: $0) } ?? .numericText()
    }
}

/// The value of a row with a ruler, as it turns: a time in its pieces, a weight's number apart
/// from its unit.
struct RulerValue: View {
    let value: String
    let number: Double?

    var body: some View {
        if let pieces = TimePiece.pieces(of: value) {
            timeValue(pieces)
        } else {
            weightValue
        }
    }

    /// A time's pieces apart, each a number and its unit, kept by its unit: as the row opens,
    /// "55s" stays where it is while "0m" fades in beside it, and "1m" slides over for "0s".
    /// Every piece rolls the way the whole value went, its number apart from its unit, so a
    /// digit going ("15s" to "0s") slides under the unit's edge: in one text it drew over the
    /// "s" for a few frames. A piece arriving fades in only once the piece beside it has slid
    /// most of the way off its place, and one leaving goes at once, as the other starts over
    /// it: faded with the slide, even in 0.08 s, the two overlapped. Words, "None" or a time's
    /// "per side", have no neighbor to wait on, so they fade with the row and never leave a
    /// blank.
    private func timeValue(_ pieces: [TimePiece]) -> some View {
        PieceFlow {
            ForEach(pieces) { piece in
                if piece.isWord {
                    ValueText(text: piece.text, number: nil)
                        .transition(.opacity)
                } else {
                    numberAndUnit(piece.text)
                        .transition(Self.timePieceTransition)
                }
            }
        }
    }

    /// A time's piece arriving waits until the piece beside it has slid most of the way.
    private static var pieceArrival: Animation {
        .snappy(duration: 0.2).delay(0.14)
    }

    private static var timePieceTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(pieceArrival),
            removal: .opacity.animation(nil),
        )
    }

    /// A weight's number apart from its unit, so the ".0" the open row adds widens the number's
    /// own frame as the row opens and slides under its edge as it closes. In one text, the going
    /// ".0" faded over the unit while the number slid into it.
    private var weightValue: some View {
        numberAndUnit(value)
    }

    /// A number in its own frame, clipped on its trailing side, then the rest of `text` beside it.
    private func numberAndUnit(_ text: String) -> some View {
        let digits = text.prefix { $0.isNumber || $0 == "." || $0 == "," }
        return HStack(spacing: 0) {
            ValueText(text: String(digits), number: number)
                // Only the trailing side clips: the digits roll above and below the line, and
                // as the row opens they slide in from past the frame's leading edge.
                .mask(Rectangle().padding([.vertical, .leading], -Spacing.xl))
            ValueText(text: String(text.dropFirst(digits.count)), number: nil)
        }
    }
}

/// A time's pieces in a line, a piece that doesn't fit going whole onto the next, leading: at
/// the accessibility sizes "1m 0s" stays on one line with "per side" under it. Before, a
/// per-side time was split as a weight, its first digits apart, and "m 0s per side" wrapped
/// beside the "1".
struct PieceFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        lines(proposal, subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let placed = lines(proposal, subviews).placed
        for (subview, (origin, offer)) in zip(subviews, placed) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: offer,
            )
        }
    }

    /// Each piece's origin and what it was offered, and the size of all of them. The pieces
    /// share one font, so a line's tops align their baselines.
    private func lines(
        _ proposal: ProposedViewSize,
        _ subviews: Subviews,
    ) -> (placed: [(CGPoint, ProposedViewSize)], size: CGSize) {
        let width = proposal.width ?? .infinity
        var placed: [(CGPoint, ProposedViewSize)] = []
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + ideal.width > width {
                origin = CGPoint(x: 0, y: origin.y + lineHeight)
                lineHeight = 0
            }
            // The room left on the line, which a piece wider than a whole line wraps inside.
            let offer = ProposedViewSize(width: proposal.width.map { $0 - origin.x }, height: nil)
            let size = subview.sizeThatFits(offer)
            placed.append((origin, offer))
            origin.x += size.width
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, origin.x)
        }
        return (placed, CGSize(width: widest, height: origin.y + lineHeight))
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: Spacing.md) {
        RulerValue(value: "27.5\u{00A0}lb/side", number: 27.5)
        RulerValue(value: "0m\u{00A0}45s", number: 45)
        RulerValue(value: "1m\u{00A0}0s per side", number: 60)
        RulerValue(value: "None", number: 0)
    }
    .padding()
    .background(Color.pp(.background))
}
