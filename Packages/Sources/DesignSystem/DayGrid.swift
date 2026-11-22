import SwiftUI

/// A calendar of whole weeks: a row of weekday initials in secondary text, then a row of seven
/// rounded squares a week. A day marked done is filled purple (`done`), the others a quiet gray
/// fill (`selectionFill`); today is outlined, in primary text over purple and in the rail's gray
/// over the gray; a day after today keeps its room and draws nothing. Each square shows its day
/// of the month, small and centered, in SF Mono: secondary text on the gray, the background's
/// dark on purple, so the fill stays what the eye finds first. It grows with the text size up
/// to the first accessibility size, and shrinks rather than reach the square's edge. The squares
/// share the row's width, and
/// their height follows it, whatever height the grid is offered. VoiceOver reads the initials
/// and numbers not at all and each drawn day as one element, `spoken`, row by row.
public struct DayGrid: View {
    /// One day's square.
    public struct Square: Identifiable, Sendable {
        public let id: Date
        /// The day of the month, "25".
        public let number: String
        public let isDone: Bool
        public let isToday: Bool
        public let isShown: Bool
        public let spoken: String

        public init(
            id: Date,
            number: String,
            isDone: Bool,
            isToday: Bool,
            isShown: Bool,
            spoken: String,
        ) {
            self.id = id
            self.number = number
            self.isDone = isDone
            self.isToday = isToday
            self.isShown = isShown
            self.spoken = spoken
        }
    }

    private let initials: [String]
    private let weeks: [[Square]]

    private static let outline: CGFloat = 1.5
    /// The least a number shrinks to, where a narrow screen's squares are smaller than its two
    /// digits.
    private static let numberShrink: CGFloat = 0.4

    public init(initials: [String], weeks: [[Square]]) {
        self.initials = initials
        self.weeks = weeks
    }

    public var body: some View {
        Grid(horizontalSpacing: Spacing.sm, verticalSpacing: Spacing.sm) {
            GridRow {
                ForEach(Array(initials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.ppCaption)
                        .foregroundStyle(.pp(.textSecondary))
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(week) { square in
                        squareView(square)
                    }
                }
            }
        }
        // The squares' size comes from the width alone: offered less height, as by a screen
        // filling its room below, they drew smaller.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func squareView(_ square: Square) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        return shape
            .fill(.pp(square.isDone ? .done : .selectionFill))
            .overlay {
                if square.isToday {
                    shape.strokeBorder(
                        .pp(square.isDone ? .textPrimary : .rail),
                        lineWidth: Self.outline,
                    )
                }
            }
            .overlay {
                Text(square.number)
                    .font(.ppCaptionNumber)
                    .foregroundStyle(.pp(square.isDone ? .background : .textSecondary))
                    .lineLimit(1)
                    .minimumScaleFactor(Self.numberShrink)
                    // Past the first accessibility size the square's width stays put, and a
                    // number grown further filled it, louder than the purple.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .padding(Spacing.xs)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .opacity(square.isShown ? 1 : 0)
            .accessibilityElement()
            .accessibilityLabel(square.spoken)
            .accessibilityHidden(!square.isShown)
    }
}

#Preview {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let weeks = (0 ..< 4).map { week in
        (0 ..< 7).map { day in
            let index = week * 7 + day
            return DayGrid.Square(
                id: start.addingTimeInterval(Double(index) * 86400),
                number: "\(index + 1)",
                isDone: index.isMultiple(of: 3),
                isToday: index == 26,
                isShown: index <= 26,
                spoken: "Day \(index)",
            )
        }
    }
    DayGrid(initials: ["S", "M", "T", "W", "T", "F", "S"], weeks: weeks)
        .padding()
        .background(Color.pp(.background))
}
