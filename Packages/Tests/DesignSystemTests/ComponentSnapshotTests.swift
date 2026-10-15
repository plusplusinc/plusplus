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

    /// A row's name, its detail line in parts (equipment, plan, weight), and whether it is done
    /// one side at a time.
    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
        var showsSides = false
    }

    /// Start shows once there is a row.
    private func content(
        name: String = "",
        suggestion: String? = nil,
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
            Rail(rows) { row in
                RowLabel(title: row.title, detail: row.detail, showsSides: row.showsSides)
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
            of: content(rows: [Row(title: "Goblet squat", detail: ["Kettlebell", "3 × 10 reps"])]),
            width: Self.screenWidth,
        )
    }

    /// A generated name rests in white, as a chosen one does; only New routine is gray.
    @Test("An unnamed routine with exercises shows its generated name")
    func generatedName() {
        let rows: [Row] = [
            Row(title: "Goblet squat", detail: ["Kettlebell", "3 × 10 reps"]),
            Row(title: "Pull-up", detail: ["Pull-up bar", "3 × 6 reps"]),
        ]
        assertThemedSnapshots(
            of: content(suggestion: "Back and legs", rows: rows),
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
            Row(title: "Pull-up", detail: ["Pull-up bar", "3 × 6 reps"]),
            Row(title: "Dumbbell bench press", detail: ["Dumbbells, bench", "3 × 10 reps"]),
            Row(title: "Push-up", detail: ["3 × 10 reps"]),
            Row(title: "Kneeling hip flexor stretch", detail: ["60 s per side"], showsSides: true),
            Row(title: "Farmer\u{2019}s carry", detail: ["Dumbbells", "3 × 30 s"]),
        ]
        assertThemedSnapshots(of: content(rows: rows), width: Self.screenWidth)
    }

    /// Every kind of plan: a bar's total, one weight per side wrapping between parts, a pair's
    /// each, bodyweight, a weight not yet set, timed per side, and a single set.
    @Test("Rows with plans, per-side rows marked")
    func railPlans() {
        let rows: [Row] = [
            Row(title: "Barbell bench press", detail: ["Barbell, bench", "5 × 5 reps", "135 lb"]),
            Row(
                title: "Dumbbell row",
                detail: ["Dumbbells, bench", "3 × 10 reps per side", "50 lb"],
                showsSides: true,
            ),
            Row(title: "Biceps curl", detail: ["Dumbbells", "3 × 12 reps", "25 lb each"]),
            Row(title: "Pull-up", detail: ["Pull-up bar", "3 × 6 reps"]),
            Row(title: "Goblet squat", detail: ["Kettlebell", "3 × 10 reps"]),
            Row(title: "Side plank", detail: ["3 × 30 s per side"], showsSides: true),
            Row(title: "Pigeon stretch", detail: ["60 s per side"], showsSides: true),
        ]
        assertThemedSnapshots(of: content(name: "Full body", rows: rows), width: Self.screenWidth)
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
