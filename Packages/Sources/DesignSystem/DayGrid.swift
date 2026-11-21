import SwiftUI

/// A calendar of whole weeks: a row of weekday initials in secondary text, then a row of seven
/// rounded squares a week. A day marked done is filled purple (`done`), the others a quiet gray
/// fill (`selectionFill`); today is outlined, in primary text over purple and in the rail's gray
/// over the gray; a day after today keeps its room and draws nothing. The squares share the
/// row's width. VoiceOver reads the initials not at all and each drawn day as one element,
/// `spoken`, row by row.
public struct DayGrid: View {
    /// One day's square.
    public struct Square: Identifiable, Sendable {
        public let id: Date
        public let isDone: Bool
        public let isToday: Bool
        public let isShown: Bool
        public let spoken: String

        public init(id: Date, isDone: Bool, isToday: Bool, isShown: Bool, spoken: String) {
            self.id = id
            self.isDone = isDone
            self.isToday = isToday
            self.isShown = isShown
            self.spoken = spoken
        }
    }

    private let initials: [String]
    private let weeks: [[Square]]

    private static let outline: CGFloat = 1.5

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
