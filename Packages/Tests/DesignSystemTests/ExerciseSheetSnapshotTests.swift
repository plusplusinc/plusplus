// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// An exercise sheet's content, its steppers, built the way the app composes it. The sheet, its
/// bar with the exercise's name, and the keyboard are the system's; the UI tests show them.
@Suite("Exercise sheet")
struct ExerciseSheetSnapshotTests {
    private static let sheetWidth: CGFloat = 390

    private struct Part {
        let title: String
        var note: String?
        let value: String?
        var unit: String?
        /// The keys' step: "1", "5", "15 s".
        var step = "1"
        var canDecrease = true
        var isEditing = false
    }

    private func content(equipment: String?, parts: [Part]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let equipment {
                Text(equipment)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textSecondary))
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(parts, id: \.title) { part in
                    StepperRow(
                        title: part.title,
                        note: part.note,
                        spokenValue: "",
                        decreaseLabel: "\u{2212}" + part.step,
                        increaseLabel: "+" + part.step,
                        canDecrease: part.canDecrease,
                        canIncrease: true,
                        onDecrease: { },
                        onIncrease: { },
                        value: {
                            NumberFieldContent(
                                text: part.value,
                                unit: part.unit,
                                isEditing: part.isEditing,
                                blinks: false,
                            )
                        },
                    )
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.pp(.background))
    }

    @Test("A bench press: sets, reps, and the bar's total")
    func bench() {
        assertThemedSnapshots(
            of: content(equipment: "Barbell, bench", parts: [
                Part(title: "Sets", value: "5"),
                Part(title: "Reps", value: "5"),
                Part(title: "Weight", note: "Bar, total", value: "135", unit: "lb", step: "5"),
            ]),
            width: Self.sheetWidth,
        )
    }

    @Test("A dumbbell row: reps per side, one dumbbell not set, − dimmed")
    func row() {
        assertThemedSnapshots(
            of: content(equipment: "Dumbbells, bench", parts: [
                Part(title: "Sets", value: "3"),
                Part(title: "Reps", note: "Per side", value: "10"),
                Part(
                    title: "Weight",
                    note: "One dumbbell",
                    value: nil,
                    step: "5",
                    canDecrease: false,
                ),
            ]),
            width: Self.sheetWidth,
        )
    }

    @Test("A pigeon stretch: one set, a time per side, no weight")
    func pigeon() {
        assertThemedSnapshots(
            of: content(equipment: nil, parts: [
                Part(title: "Sets", value: "1"),
                Part(title: "Time", note: "Per side", value: "60", unit: "s", step: "5\u{00A0}s"),
            ]),
            width: Self.sheetWidth,
        )
    }

    @Test("Typing a weight: the `_` after the number, the unit, the line under the slot")
    func typingWeight() {
        assertThemedSnapshots(
            of: content(equipment: nil, parts: [
                Part(
                    title: "Weight",
                    note: "Bar, total",
                    value: "142.5",
                    unit: "lb",
                    isEditing: true,
                ),
            ]),
            width: Self.sheetWidth,
        )
    }

    @Test("Typing a time: digits fill from the right")
    func typingTime() {
        assertThemedSnapshots(
            of: content(equipment: nil, parts: [
                Part(title: "Time", note: "Per side", value: "1:30", isEditing: true),
            ]),
            width: Self.sheetWidth,
        )
    }
}

#endif
