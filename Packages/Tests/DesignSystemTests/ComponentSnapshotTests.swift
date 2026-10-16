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

    /// A row's name and its plan in parts: the sets and reps or time, then the weight.
    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
    }

    /// The routine's equipment shows under the title; Start shows once there is a row.
    private func content(
        name: String = "",
        suggestion: String? = nil,
        equipment: [String] = [],
        rows: [Row] = [],
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            EditableTitle(
                text: .constant(name),
                placeholder: "New routine",
                suggestion: suggestion,
                accessibilityLabel: "Routine name",
                accessibilityHint: "Renames the routine.",
            )
            if !equipment.isEmpty {
                Capsules(equipment)
            }
            Rail(rows) { row in
                RowLabel(title: row.title, detail: row.detail)
                    .railRow()
            } end: {
                Button("Add exercise", systemImage: "plus") { }
                    .buttonStyle(.key)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            of: content(
                equipment: ["Kettlebell"],
                rows: [Row(title: "Goblet squat", detail: ["3 × 10 reps", "35 lb"])],
            ),
            width: Self.screenWidth,
        )
    }

    /// A generated name rests in white, as a chosen one does; only New routine is gray.
    @Test("An unnamed routine with exercises shows its generated name")
    func generatedName() {
        let rows: [Row] = [
            Row(title: "Goblet squat", detail: ["3 × 10 reps", "35 lb"]),
            Row(title: "Pull-up", detail: ["3 × 6 reps"]),
        ]
        assertThemedSnapshots(
            of: content(
                suggestion: "Back and legs",
                equipment: ["Kettlebell", "Pull-up bar"],
                rows: rows,
            ),
            width: Self.screenWidth,
        )
    }

    /// The xxxl image holds it: both wrap "Legs and" / "back", the `_` after the k.
    @Test("A generated name at rest draws exactly as the same name typed")
    func generatedAsTyped() {
        let titles = VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach([("", "Legs and back"), ("Legs and back", nil)], id: \.0) { name, suggestion in
                EditableTitle(
                    text: .constant(name),
                    placeholder: "New routine",
                    suggestion: suggestion,
                    accessibilityLabel: "Routine name",
                    accessibilityHint: "Renames the routine.",
                )
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
        assertThemedSnapshots(of: titles, width: Self.screenWidth)
    }

    @Test("Several exercises, a bodyweight row among them")
    func severalExercises() {
        let rows: [Row] = [
            Row(title: "Pull-up", detail: ["3 × 6 reps"]),
            Row(title: "Dumbbell bench press", detail: ["3 × 10 reps", "25 lb/side"]),
            Row(title: "Push-up", detail: ["3 × 10 reps"]),
            Row(title: "Kneeling hip flexor stretch", detail: ["60 s per side"]),
            Row(title: "Farmer\u{2019}s carry", detail: ["3 × 30 s", "25 lb/side"]),
        ]
        assertThemedSnapshots(
            of: content(equipment: ["Dumbbells", "Bench", "Pull-up bar"], rows: rows),
            width: Self.screenWidth,
        )
    }

    /// Every kind of plan: a bar's total, one weight with reps per side, a pair's weight per
    /// side, bodyweight, timed per side, and a single set; the equipment wrapping onto a second
    /// line of capsules.
    @Test("Rows with plans, under the routine's equipment")
    func railPlans() {
        let rows: [Row] = [
            Row(title: "Barbell bench press", detail: ["5 × 5 reps", "135 lb"]),
            Row(title: "Dumbbell row", detail: ["3 × 10 reps per side", "50 lb"]),
            Row(title: "Biceps curl", detail: ["3 × 12 reps", "25 lb/side"]),
            Row(title: "Pull-up", detail: ["3 × 6 reps"]),
            Row(title: "Goblet squat", detail: ["3 × 10 reps", "35 lb"]),
            Row(title: "Side plank", detail: ["3 × 30 s per side"]),
            Row(title: "Pigeon stretch", detail: ["60 s per side"]),
        ]
        let equipment = ["Dumbbells", "Kettlebell", "Barbell", "Bench", "Pull-up bar"]
        assertThemedSnapshots(
            of: content(name: "Full body", equipment: equipment, rows: rows),
            width: Self.screenWidth,
        )
    }

    /// The exercise sheet's content, as the app composes it under its bar: the exercise's
    /// equipment, then a row for each value. The sheet and its bar are the system's, seen on the
    /// simulator.
    private func sheetContent(open: Int?) -> some View {
        let values = [
            ("Sets", "3", "3 sets"),
            ("Reps", "10 per side", "10 reps per side"),
            ("Weight", "20 lb/side", "20 pounds per side"),
        ]
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Capsules(["Dumbbells", "Bench"])
                .padding(.bottom, Spacing.sm)
            ForEach(values.indices, id: \.self) { index in
                ValueRow(
                    label: values[index].0,
                    value: values[index].1,
                    spokenValue: values[index].2,
                    isOpen: open == index,
                    canDecrease: true,
                    canIncrease: true,
                    onToggle: { },
                    onStep: { _ in },
                )
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    @Test("A sheet's values with every stepper closed")
    func sheetClosed() {
        assertThemedSnapshots(of: sheetContent(open: nil), width: Self.screenWidth)
    }

    @Test("A sheet's values with one stepper open")
    func sheetOpen() {
        assertThemedSnapshots(of: sheetContent(open: 1), width: Self.screenWidth)
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
