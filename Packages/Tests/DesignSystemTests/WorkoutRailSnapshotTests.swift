// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// A workout's rail scrolled past the current exercise: a finished row's node purple, rows
/// partly done with their bars at one place at the trailing end however many sets they have and
/// however their name and plan wrap, and a row not started with none; and the current row's
/// node held small and gray while a set logged on it is not yet shown; and a superset's loop
/// stretched by its current exercise.
@Suite("Workout rail")
struct WorkoutRailSnapshotTests {
    private static let width: CGFloat = 390

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
        var focus: RowFocus?
        var bars: SetProgress?
    }

    private func rail(
        _ rows: [Row],
        links: Set<UUID> = [],
        done: Set<UUID> = [],
        current: UUID? = nil,
        isSetHeld: Bool = false,
        @ViewBuilder end: () -> some View,
    ) -> some View {
        Rail(rows, links: links, current: current, done: done, isSetHeld: isSetHeld) { row in
            RowLabel(title: row.title, detail: row.detail, focus: row.focus, bars: row.bars)
                // As the routine screen gives the current exercise, shown with its focus
                // (`currentTopSpace`).
                .padding(.top, row.focus == nil ? 0 : Spacing.lg)
                .railRow()
        } end: {
            end()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    private static func bars(_ done: Int, of total: Int) -> SetProgress {
        SetProgress(done: done, total: total, spoken: "\(done) of \(total) sets done")
    }

    @Test("Bars at 3, 6, and 8 sets line up, a long name wrapping before them")
    func setBars() {
        let finished = Row(title: "Goblet squat", detail: ["3 × 10 reps", "35 lb"])
        let rows = [
            finished,
            Row(title: "Pull-up", detail: ["3 × 6 reps"], bars: Self.bars(1, of: 3)),
            Row(
                title: "Single-arm dumbbell Romanian deadlift to row",
                detail: ["6 × 8 reps per side", "40 lb"],
                bars: Self.bars(4, of: 6),
            ),
            Row(title: "Plank", detail: ["8 × 30 s"], bars: Self.bars(2, of: 8)),
            Row(title: "Push-up", detail: ["3 × 10 reps"]),
        ]
        let view = rail(rows, done: [finished.id]) {
            Button("Add exercise", systemImage: "plus") { }
                .buttonStyle(.key)
        }
        assertThemedSnapshots(of: view, width: Self.width)
    }

    @Test("A set logged on the current row, not yet shown: its node small and gray, the rest not")
    func heldSet() {
        let rows = [
            Row(title: "Goblet squat", detail: ["3 × 10 reps", "35 lb"]),
            Row(title: "Pull-up", detail: ["3 × 6 reps"]),
        ]
        let view = rail(rows, current: rows[0].id, isSetHeld: true) {
            Button("Add exercise", systemImage: "plus") { }
                .buttonStyle(.key)
        }
        assertThemedSnapshots(of: view, width: Self.width)
    }

    /// A short exercise current in a superset grows to its numbers' height, and the loop down to
    /// its partner's node stretches with it: heads spread evenly along it, a resting row's height
    /// or more apart, none crowding the curves; between the resting members, one at the middle.
    @Test("A superset with a short exercise current: heads spread evenly up its stretched loop")
    func stretchedLoop() {
        let current = Row(
            title: "Plank",
            detail: ["3 × 30 s"],
            focus: RowFocus(
                progress: "Round 1 of 3",
                equipment: [],
                figures: [.init(number: "30", unit: "s")],
                spokenFigures: "30 seconds",
            ),
            bars: Self.bars(0, of: 3),
        )
        let rows = [
            current,
            Row(title: "Push-up", detail: ["3 × 10 reps"]),
            Row(title: "Dead hang", detail: ["3 × 30 s"]),
            Row(title: "Goblet squat", detail: ["3 × 10 reps", "35 lb"]),
        ]
        let view = rail(rows, links: [rows[0].id, rows[1].id], current: current.id) {
            Button("Add exercise", systemImage: "plus") { }
                .buttonStyle(.key)
        }
        assertThemedSnapshots(of: view, width: Self.width)
    }
}

#endif
