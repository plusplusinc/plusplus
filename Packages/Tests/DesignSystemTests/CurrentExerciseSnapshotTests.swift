// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// The current exercise of a workout on the rail, as the routine screen composes it: its node
/// large and green, its name grown, which set it is on, its equipment, and its plan's numbers
/// large, in a label standing at the height the screen gives it, the next row under it. At AX5
/// the numbers shrink to that height, their unit under them, and nothing truncates.
@Suite("Current exercise")
struct CurrentExerciseSnapshotTests {
    private static let width: CGFloat = 390
    /// The current exercise's label height: what the screen leaves it, fixed here so AX5 shows
    /// the numbers fitting it.
    private static let labelHeight: CGFloat = 460

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
        var focus: RowFocus?
    }

    private func rail(_ rows: [Row]) -> some View {
        Rail(rows, current: rows.first?.id) { row in
            RowLabel(title: row.title, detail: row.detail, focus: row.focus)
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
                minHeight: Self.labelHeight,
            ),
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
                minHeight: Self.labelHeight,
            ),
        )
        assertThemedSnapshots(of: rail([current, next]), width: Self.width)
    }
}

#endif
