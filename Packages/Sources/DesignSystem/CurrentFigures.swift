import SwiftUI

/// The current exercise's numbers, large, each with what it counts: "10reps", "25lb/side",
/// "1m 35s". Digits are bold SF Mono at `CurrentFigure.size`; the letters with them, a time's
/// "m" and "s" and what a number counts, bold SF Pro at `CurrentFigure.unitSize`, in the same
/// color, on the digits' baseline, a `CurrentFigure.unitGap` after a digit. Below the
/// accessibility sizes a figure is one line, number and letters shrinking together to fit the
/// width; at them, what it counts goes under the number where the two don't fit side by side
/// (`FigureLayout`), the number shrinking to fit the width.
struct CurrentFigures: View {
    let figures: [RowFocus.Figure]

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = CurrentFigure.size
    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var unitSize = CurrentFigure
        .unitSize
    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var unitGap = CurrentFigure.unitGap
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(figures, id: \.self) { figure in
                if dynamicTypeSize.isAccessibilitySize {
                    FigureLayout(spacing: unitSpacing(after: figure.number)) {
                        number(figure.number).modifier(BaselineMark())
                        unit(figure).modifier(BaselineMark())
                    }
                } else {
                    // "10" "reps" as "10reps", the gap after the digit its kerning; a time's
                    // words after a space, "45s per side".
                    let spacer = figure.unit.isEmpty || figure.number.last?.isNumber == true
                        ? "" : " "
                    number(figure.number + spacer + figure.unit).modifier(BaselineMark())
                }
            }
        }
    }

    /// A small gap after a digit, "10 reps", and a word space after a time's last letter,
    /// "45s per side".
    private func unitSpacing(after number: String) -> CGFloat {
        number.last?.isNumber == false ? unitSize * CurrentFigure.wordSpace : unitGap
    }

    private func number(_ text: String) -> some View {
        Text(figureText(text))
            .foregroundStyle(.pp(.textPrimary))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
    }

    private func unit(_ figure: RowFocus.Figure) -> some View {
        Text(figure.unit)
            .font(unitFont)
            .foregroundStyle(.pp(.textPrimary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var unitFont: Font {
        .system(size: unitSize, weight: .bold)
    }

    /// The digits at the figure's size in SF Mono, and the letters at the unit's, each run of
    /// letters a small gap after the digit before it.
    private func figureText(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = unitFont
        for match in text.matches(of: /\d+(?:[.,:]\d+)*/) {
            guard let range = Range(match.range, in: attributed) else { continue }
            attributed[range].font = .system(size: size, weight: .bold, design: .monospaced)
            if match.range.upperBound < text.endIndex, text[match.range.upperBound].isLetter {
                let last = attributed.index(beforeCharacter: range.upperBound)
                attributed[last ..< range.upperBound].kern = unitGap
            }
        }
        return attributed
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.md) {
        CurrentFigures(figures: [
            .init(number: "10", unit: "reps"),
            .init(number: "27.5", unit: "lb/side"),
        ])
        CurrentFigures(figures: [.init(number: "1m\u{00A0}35s", unit: "per side")])
    }
    .padding()
    .background(Color.pp(.background))
}

/// Marks a text's last baseline for the held card (`CardMarks`).
private struct BaselineMark: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: Alignment(horizontal: .leading, vertical: .lastTextBaseline)) {
            Color.clear
                .frame(width: 0, height: 0)
                .anchorPreference(key: CardMarks.self, value: .center) {
                    CardMarks.Value(baselines: [$0])
                }
        }
    }
}
