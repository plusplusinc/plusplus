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
    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: String?

        init(_ title: String, _ detail: String?) {
            self.title = title
            self.detail = detail
        }
    }

    /// Start shows once there is a row.
    private func content(
        name: String = "New routine",
        rows: [Row] = [],
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            EditableTitle(
                text: .constant(name),
                defaultText: "New routine",
                accessibilityLabel: "Routine name",
                accessibilityHint: "Renames the routine.",
            )
            Rail(rows) { row in
                RowLabel(title: row.title, detail: row.detail).railRow()
            } end: {
                Button("Add exercise", systemImage: "plus") { }
                    .buttonStyle(.key)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // With no screen corners around it to be concentric with, Start shows its minimum radius.
        .primaryKeyBar(isPresented: !rows.isEmpty) {
            Button("Start", systemImage: "play.fill") { }
        }
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
            of: content(rows: [Row("Goblet squat", "Kettlebell")]),
            width: Self.screenWidth,
        )
    }

    @Test("Several exercises, a bodyweight row among them")
    func severalExercises() {
        let rows: [Row] = [
            Row("Pull-up", "Pull-up bar"),
            Row("Dumbbell bench press", "Dumbbells, bench"),
            Row("Push-up", nil),
            Row("Kneeling hip flexor stretch", nil),
            Row("Farmer\u{2019}s carry", "Dumbbells"),
        ]
        assertThemedSnapshots(of: content(rows: rows), width: Self.screenWidth)
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
