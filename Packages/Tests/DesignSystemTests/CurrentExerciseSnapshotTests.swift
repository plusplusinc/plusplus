// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// The current exercise of a workout on the rail, as the routine screen composes it: its node
/// large and green, its name grown, which set it is on with its bars, its equipment, its plan's
/// numbers large, the label as tall as they are, the next row under it. At AX5 the numbers' unit
/// goes under them, and nothing truncates.
@Suite("Current exercise")
struct CurrentExerciseSnapshotTests {
    private static let width: CGFloat = 390

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
        var focus: RowFocus?
        var bars: SetProgress?
    }

    private func rail(_ rows: [Row]) -> some View {
        Rail(rows, current: rows.first?.id) { row in
            RowLabel(
                title: row.title,
                detail: row.detail,
                focus: row.focus,
                bars: row.bars,
            )
            .railRow()
        } end: {
            Button("Add exercise", systemImage: "plus") { }
                .buttonStyle(.key)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    private let next = Row(title: "Push-up", detail: ["3 × 10 reps"])

    @Test("With equipment: reps and weight, each with what it counts")
    func withEquipment() {
        let current = Row(
            title: "Dumbbell bench press",
            detail: ["3 × 10 reps", "25 lb/side"],
            focus: RowFocus(
                progress: "Set 1 of 3",
                equipment: ["Dumbbells", "Bench"],
                figures: [
                    .init(number: "10", unit: "reps"),
                    .init(number: "25", unit: "lb per side"),
                ],
                spokenFigures: "10 reps, 25 pounds per side",
            ),
            bars: SetProgress(done: 1, total: 3, spoken: "1 of 3 sets done"),
        )
        assertThemedSnapshots(of: rail([current, next]), width: Self.width)
    }

    @Test("One side at a time: the side beside the set, the bars gray until both sides are in")
    func oneSide() {
        let current = Row(
            title: "Dumbbell row",
            detail: ["3 × 10 reps per side", "30 lb"],
            focus: RowFocus(
                progress: "Set 1 of 3",
                side: "Right",
                equipment: ["Dumbbells", "Bench"],
                figures: [
                    .init(number: "10", unit: "reps"),
                    .init(number: "30", unit: "lb"),
                ],
                spokenFigures: "10 reps, 30 pounds",
            ),
            bars: SetProgress(done: 0, total: 3, spoken: "0 of 3 sets done"),
        )
        assertThemedSnapshots(of: rail([current, next]), width: Self.width)
    }

    @Test("Bodyweight: no equipment, a time per side")
    func bodyweight() {
        let current = Row(
            title: "Kneeling hip flexor stretch",
            detail: ["60 s per side"],
            focus: RowFocus(
                progress: "Set 1 of 1",
                figures: [.init(number: "60", unit: "s per side")],
                spokenFigures: "60 seconds per side",
            ),
        )
        assertThemedSnapshots(of: rail([current, next]), width: Self.width)
    }
}

#endif
