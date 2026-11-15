import SwiftUI

/// A row's value as text: numbers in SF Mono, words in the system font. With `number`, the
/// digits roll by the way it went, up or down; without, the system's default roll.
struct ValueText: View {
    let text: String
    let number: Double?

    var body: some View {
        Text(AttributedString.monoNumbers(text, font: .ppRowTitleNumber))
            .font(.ppRowTitle)
            .contentTransition(number.map { .numericText(value: $0) } ?? .numericText())
            .foregroundStyle(.pp(.textPrimary))
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
    /// Every piece rolls the way the whole value went. A piece arriving fades in only once the
    /// piece beside it has slid most of the way off its place, and one leaving goes at once, as
    /// the other starts over it: faded with the slide, even in 0.08 s, the two overlapped.
    /// "None" has no neighbor to wait on, so it fades with the row and never leaves a blank.
    private func timeValue(_ pieces: [TimePiece]) -> some View {
        HStack(spacing: 0) {
            ForEach(pieces) { piece in
                ValueText(text: piece.text, number: number)
                    .transition(piece.isWord ? .opacity : Self.timePieceTransition)
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
        let digits = value.prefix { $0.isNumber || $0 == "." || $0 == "," }
        return HStack(spacing: 0) {
            ValueText(text: String(digits), number: number)
                // Only the trailing side clips: the digits roll above and below the line, and
                // as the row opens they slide in from past the frame's leading edge.
                .mask(Rectangle().padding([.vertical, .leading], -Spacing.xl))
            ValueText(text: String(value.dropFirst(digits.count)), number: nil)
        }
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: Spacing.md) {
        RulerValue(value: "27.5\u{00A0}lb/side", number: 27.5)
        RulerValue(value: "0m\u{00A0}45s", number: 45)
        RulerValue(value: "None", number: 0)
    }
    .padding()
    .background(Color.pp(.background))
}
