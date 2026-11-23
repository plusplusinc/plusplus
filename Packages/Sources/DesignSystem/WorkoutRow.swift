import SwiftUI

/// A workout's row on the Workouts list: its name, wrapping, with its length trailing; under it
/// its shape. The muscles are a bar of segments (`SegmentedBar`) in `barShare` of the row's
/// width, as long as `fill` of that, with each group's word under the start of its segment, or
/// just after the word before when the segment is short; the kind trails level with the bar
/// and the equipment level with the words, as many pieces as fit and "+N" for the rest. With no
/// shape, the name alone. At the accessibility sizes, one column: the name, the bar across the
/// width, the words wrapping, then the length, kind, and every piece of equipment.
///
/// VoiceOver reads it as one element, by the name; the caller gives the rest as its value.
public struct WorkoutRow: View {
    private let name: String
    private let shape: Shape?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// What the row shows of a workout's shape, as plain words and shares.
    public struct Shape {
        public let length: String
        public let kind: String
        public let equipment: [String]
        /// The muscles named, most first, each with its share of the workout.
        public let segments: [(word: String, share: Double)]
        /// The share of each muscle past those named, most first: each draws its own segment,
        /// in the "+N" shade, and one word, "+N", reads under the first of them.
        public let more: [Double]
        /// How much of the bar's column the bar fills, 0 to 1.
        public let fill: Double

        public init(
            length: String,
            kind: String,
            equipment: [String],
            segments: [(word: String, share: Double)],
            more: [Double] = [],
            fill: Double,
        ) {
            self.length = length
            self.kind = kind
            self.equipment = equipment
            self.segments = segments
            self.more = more
            self.fill = fill
        }

        var shares: [Double] {
            segments.map(\.share) + more
        }

        /// A word per named segment, then "+N" under the first of the rest's; `SegmentWords`
        /// places the words in order, so the rest's later segments go unworded.
        var words: [String] {
            segments.map(\.word) + (more.isEmpty ? [] : ["+\(more.count)"])
        }

        /// The equipment as it may read, longest first: every piece, then each fewer with "+N"
        /// for the rest, down to "+N" alone, so the line never truncates a piece's name; "No
        /// equipment" for none.
        var equipmentCandidates: [String] {
            guard !equipment.isEmpty else { return ["No equipment"] }
            let all = [equipment.joined(separator: ", ")]
            let shorter = (1 ..< equipment.count).reversed().map { shown in
                equipment.prefix(shown).joined(separator: ", ") + " +\(equipment.count - shown)"
            }
            return all + shorter + ["+\(equipment.count)"]
        }
    }

    /// The share of the row's width the bar's column takes.
    nonisolated static let barShare: CGFloat = 0.58

    public init(_ name: String, shape: Shape? = nil) {
        self.name = name
        self.shape = shape
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if dynamicTypeSize.isAccessibilitySize {
                nameText
                shape.map(stacked)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    nameText
                    shape.map { lengthText($0.length) }
                }
                shape.map(lines)
            }
        }
        .padding(.vertical, Spacing.md)
        .contentShape(.rect)
    }

    private var nameText: some View {
        Text(name)
            .font(.ppWorkoutName)
            .foregroundStyle(.pp(.textPrimary))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lengthText(_ length: String) -> some View {
        Text(AttributedString.monoNumbers(length, font: .ppWorkoutLengthNumber))
            .font(.ppWorkoutLength)
            .foregroundStyle(.pp(.textPrimary))
            .fixedSize()
    }

    private func detail(_ text: String) -> some View {
        Text(AttributedString.monoNumbers(text, font: .ppRowDetailNumber))
            .font(.ppRowDetail)
            .foregroundStyle(.pp(.textSecondary))
            .lineLimit(1)
    }

    private func words(_ shape: Shape) -> some View {
        ForEach(Array(shape.words.enumerated()), id: \.offset) { index, word in
            Text(AttributedString.monoNumbers(word, font: .ppRowDetailNumber))
                .font(.ppRowDetail)
                .foregroundStyle(.pp(index == 0 ? .textPrimary : .textSecondary))
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func lines(_ shape: Shape) -> some View {
        ShapeLines {
            SegmentedBar(shares: shape.shares, fill: shape.fill)
            detail(shape.kind)
            SegmentWords(shares: shape.shares, fill: shape.fill) {
                words(shape)
            }
            ViewThatFits(in: .horizontal) {
                ForEach(shape.equipmentCandidates, id: \.self, content: detail)
            }
        }
    }

    private func stacked(_ shape: Shape) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SegmentedBar(shares: shape.shares, fill: shape.fill)
            FlowLayout(spacing: Spacing.sm) {
                words(shape)
            }
            Text(AttributedString.monoNumbers(shape.length, font: .ppWorkoutLengthNumber))
                .font(.ppWorkoutLength)
                .foregroundStyle(.pp(.textPrimary))
            Text(shape.kind)
            Text(shape.equipment.isEmpty ? "No equipment" : shape.equipment.joined(separator: ", "))
        }
        .font(.ppRowDetail)
        .foregroundStyle(.pp(.textSecondary))
    }
}

/// The row's two shape lines: the bar in the column and the kind trailing level with it; the
/// muscle words in the column and the equipment trailing level with them, in the width the
/// words leave.
private struct ShapeLines: Layout {
    /// Between the column's content and what trails it.
    private let gap = Spacing.md
    /// Between the bar and the words under it.
    private let lineGap = Spacing.xs

    private struct Measured {
        let column: CGFloat
        let bar: CGSize
        let kind: CGSize
        let words: CGSize
        let equipment: CGSize
    }

    private func measure(_ width: CGFloat, _ subviews: Subviews) -> Measured {
        let column = (width * WorkoutRow.barShare).rounded()
        let bar = subviews[0].sizeThatFits(ProposedViewSize(width: column, height: nil))
        let kind = subviews[1].sizeThatFits(ProposedViewSize(
            width: width - column - gap,
            height: nil,
        ))
        let words = subviews[2].sizeThatFits(ProposedViewSize(width: column, height: nil))
        let room = max(0, width - words.width - gap)
        let equipment = subviews[3].sizeThatFits(ProposedViewSize(width: room, height: nil))
        return Measured(column: column, bar: bar, kind: kind, words: words, equipment: equipment)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let size = measure(width, subviews)
        let first = max(size.bar.height, size.kind.height)
        let second = max(size.words.height, size.equipment.height)
        return CGSize(width: width, height: first + lineGap + second)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let size = measure(bounds.width, subviews)
        let first = max(size.bar.height, size.kind.height)
        let second = max(size.words.height, size.equipment.height)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + first / 2),
            anchor: .leading,
            proposal: ProposedViewSize(width: size.column, height: size.bar.height),
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.minY + first / 2),
            anchor: .trailing,
            proposal: ProposedViewSize(size.kind),
        )
        let wordsTop = bounds.minY + first + lineGap + second / 2
        subviews[2].place(
            at: CGPoint(x: bounds.minX, y: wordsTop),
            anchor: .leading,
            proposal: ProposedViewSize(width: size.column, height: nil),
        )
        subviews[3].place(
            at: CGPoint(x: bounds.maxX, y: wordsTop),
            anchor: .trailing,
            proposal: ProposedViewSize(
                width: max(0, bounds.width - size.words.width - gap),
                height: nil,
            ),
        )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 0) {
            WorkoutRow("Legs and balance", shape: .init(
                length: "35 min",
                kind: "Strength",
                equipment: ["Dumbbells", "Balance board"],
                segments: [("Legs", 0.7), ("Core", 0.3)],
                fill: 35.0 / 75,
            ))
            WorkoutRow("Full body", shape: .init(
                length: "75 min",
                kind: "Strength",
                equipment: ["Barbell", "Dumbbells", "Bench", "Pull-up bar"],
                segments: [("Chest", 0.25), ("Back", 0.25), ("Legs", 0.2)],
                more: [0.2, 0.1],
                fill: 1,
            ))
            WorkoutRow("Morning stretch", shape: .init(
                length: "10 min",
                kind: "Stretching",
                equipment: [],
                segments: [("Legs", 0.6), ("Back", 0.4)],
                fill: 10.0 / 75,
            ))
            WorkoutRow("New workout")
        }
        .padding(.horizontal, Spacing.md)
    }
    .background(Color.pp(.background))
}
