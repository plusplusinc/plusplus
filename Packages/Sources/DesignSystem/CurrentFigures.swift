import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The current exercise's numbers, large, side by side: each in bold SF Mono at
/// `CurrentFigure.size`, with what it counts under it in a quiet caption, "reps", "lb/side",
/// "seconds". Two fixed, equal halves of the text column (`FigureHalves`), so the second figure
/// starts at the same place on every set and exercise; one figure takes the first half. Where a
/// figure can't fit its half even shrunk a little, as at the accessibility sizes, they stack.
struct CurrentFigures: View {
    let figures: [RowFocus.Figure]

    @ScaledMetric(relativeTo: CurrentFigure.textStyle) private var size = CurrentFigure.size

    var body: some View {
        FigureHalves(spacing: Spacing.md) {
            ForEach(figures, id: \.self) { figure in
                FigureStack(caption: figure.unit) {
                    Text(figure.number)
                        .font(.system(size: size, weight: .bold, design: .monospaced))
                        .foregroundStyle(.pp(.textPrimary))
                        .lineLimit(1)
                        .minimumScaleFactor(FigureHalves.leastScale)
                        .figureBox(size: size)
                        .modifier(BaselineMark())
                }
            }
        }
    }
}

/// A large number with what it counts under it, in a quiet caption: a figure, or a rest's
/// countdown over "rest".
struct FigureStack<Number: View>: View {
    let caption: String
    @ViewBuilder let number: Number

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            number
            Text(caption)
                .font(.ppFigureCaption)
                .foregroundStyle(.pp(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// A large figure's number as tall as its digits, from their tops to their baseline, and
    /// drawn left by its digits' side bearing, so it sits on the column's edge as the name does
    /// and the caption under it is as close as it looks: the font's line box left about 19 pt
    /// over the digits and 18 under them at 76 pt.
    func figureBox(size: CGFloat) -> some View {
        #if canImport(UIKit)
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        let over = font.ascender - font.capHeight
        let under = font.lineHeight - font.ascender
        #else
        let (over, under) = (CGFloat(0), CGFloat(0))
        #endif
        return padding(.top, -over)
            .padding(.bottom, -under)
            .padding(.leading, -size * CurrentFigure.bearing)
    }
}

/// Up to two figures, each in a fixed half of the width offered, `spacing` between the halves;
/// stacked, `spacing` apart, where any of them is wider than its half even at `leastScale`. A
/// layout, not `ViewThatFits`, which hung the app on this screen (`FigureLayout`).
struct FigureHalves: Layout {
    var spacing: CGFloat

    /// The least a figure's number shrinks to stay in its half, before the figures stack.
    static let leastScale: CGFloat = 0.75

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        frames(proposal.width, subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let frames = frames(bounds.width, subviews)
        for (subview, (origin, offer)) in zip(subviews, frames.placed) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: offer,
            )
        }
    }

    private func frames(
        _ width: CGFloat?,
        _ subviews: Subviews,
    ) -> (placed: [(CGPoint, ProposedViewSize)], size: CGSize) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let width = width ?? (ideal.reduce(0, +) + spacing)
        let half = max((width - spacing) / 2, 0)
        if subviews.count <= 2, ideal.allSatisfy({ $0 * Self.leastScale <= half }) {
            let offer = ProposedViewSize(width: half, height: nil)
            let height = subviews.map { $0.sizeThatFits(offer).height }.max() ?? 0
            let placed = subviews.indices.map {
                (CGPoint(x: CGFloat($0) * (half + spacing), y: 0), offer)
            }
            return (placed, CGSize(width: width, height: height))
        }
        let offer = ProposedViewSize(width: width, height: nil)
        var placed: [(CGPoint, ProposedViewSize)] = []
        var y: CGFloat = 0
        for subview in subviews {
            if !placed.isEmpty {
                y += spacing
            }
            placed.append((CGPoint(x: 0, y: y), offer))
            y += subview.sizeThatFits(offer).height
        }
        return (placed, CGSize(width: width, height: y))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        CurrentFigures(figures: [
            .init(number: "10", unit: "reps"),
            .init(number: "27.5", unit: "lb/side"),
        ])
        CurrentFigures(figures: [
            .init(number: "100", unit: "reps"),
            .init(number: "225", unit: "lb"),
        ])
        CurrentFigures(figures: [.init(number: "1:35", unit: "minutes per side")])
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
