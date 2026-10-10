// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// The routine screen's content, built from components the way the app composes it. The screen
/// itself lives in the app, which has no test target; its toolbar is checked on the simulator.
@Suite("Components")
struct ComponentSnapshotTests {
    private static let screenWidth: CGFloat = 390

    /// A row's name and its optional equipment line.
    private typealias Row = (title: String, detail: String?)

    /// Start shows once there is a row.
    private func content(
        name: String = "New routine",
        rows: [Row] = [],
        openRow: Int? = nil,
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            EditableTitle(
                text: .constant(name),
                defaultText: "New routine",
                accessibilityLabel: "Routine name",
                accessibilityHint: "Renames the routine.",
            )
            Rail {
                ForEach(rows.indices, id: \.self) { index in
                    RowLabel(title: rows[index].title, detail: rows[index].detail)
                        .padding(.vertical, Spacing.sm)
                        .swipeToDelete(id: index, openRow: .constant(openRow)) { }
                }
            } end: {
                Button("Add exercise", systemImage: "plus") { }
                    .buttonStyle(.key)
            }
            if !rows.isEmpty {
                Button("Start", systemImage: "play.fill") { }
                    .buttonStyle(.primaryKey)
                    .padding(.top, Spacing.lg)
            }
        }
        .padding(Spacing.md)
        .background(Color.pp(.background))
    }

    @Test("A new routine: title at rest and Add exercise")
    func newRoutine() {
        assertThemedSnapshots(of: content(), width: Self.screenWidth)
    }

    @Test("A long name wraps, and the cursor follows its last line")
    func longName() {
        assertThemedSnapshots(
            of: content(name: "Upper body strength and conditioning"),
            width: Self.screenWidth,
        )
    }

    @Test("One exercise on the rail, with Start")
    func oneExercise() {
        assertThemedSnapshots(
            of: content(rows: [("Goblet squat", "Kettlebell")]),
            width: Self.screenWidth,
        )
    }

    @Test("Several exercises, a bodyweight row among them")
    func severalExercises() {
        let rows: [Row] = [
            ("Pull-up", "Pull-up bar"),
            ("Dumbbell bench press", "Dumbbells, bench"),
            ("Push-up", nil),
            ("Kneeling hip flexor stretch", nil),
            ("Farmer\u{2019}s carry", "Dumbbells"),
        ]
        assertThemedSnapshots(of: content(rows: rows), width: Self.screenWidth)
    }

    @Test("A row swiped open shows Delete beside its name")
    func openRow() {
        let rows: [Row] = [
            ("Goblet squat", "Kettlebell"),
            ("Kneeling hip flexor stretch", nil),
        ]
        assertThemedSnapshots(of: content(rows: rows, openRow: 1), width: Self.screenWidth)
    }

    /// Rows as the exercise picker lists them, without a rail. The list itself is the system's.
    @Test("Picker rows: equipment line, two equipment, bodyweight, long name")
    func pickerRows() {
        let rows = VStack(alignment: .leading, spacing: Spacing.md) {
            RowLabel(title: "Goblet squat", detail: "Kettlebell")
            RowLabel(title: "Dumbbell bench press", detail: "Dumbbells, bench")
            RowLabel(title: "Push-up", detail: nil)
            RowLabel(title: "Cross-body shoulder stretch", detail: nil)
            RowLabel(title: "Bulgarian split squat", detail: "Dumbbells, bench")
        }
        .padding(Spacing.md)
        .background(Color.pp(.background))
        assertThemedSnapshots(of: rows, width: Self.screenWidth)
    }
}

#endif
