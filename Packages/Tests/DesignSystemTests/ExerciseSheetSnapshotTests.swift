// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// An exercise sheet's content, its rows of values in capsules, built the way the app composes
/// it. The sheet, its bar with the exercise's name, and the wheels are the system's; the UI tests
/// show them.
@Suite("Exercise sheet")
struct ExerciseSheetSnapshotTests {
    private static let sheetWidth: CGFloat = 390

    private struct Part {
        let title: String
        var note: String?
        let value: String
        var unit: String?
        var isOpen = false
    }

    private func content(_ parts: [Part]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(parts, id: \.title) { part in
                PickerRow(
                    title: part.title,
                    note: part.note,
                    value: part.value,
                    unit: part.unit,
                    amount: nil,
                    spokenValue: "",
                    isOpen: part.isOpen,
                    identifier: part.title,
                    onToggle: { },
                    wheel: { EmptyView() },
                )
            }
        }
        .padding(Spacing.lg)
        .background(Color.pp(.background))
    }

    @Test("A bench press: sets, reps, and the bar's total")
    func bench() {
        assertThemedSnapshots(
            of: content([
                Part(title: "Sets", value: "5"),
                Part(title: "Reps", value: "5"),
                Part(title: "Weight", note: "Bar, total", value: "135", unit: "lb"),
            ]),
            width: Self.sheetWidth,
        )
    }

    @Test("A dumbbell row: reps per side, one dumbbell, its weight's capsule open")
    func row() {
        assertThemedSnapshots(
            of: content([
                Part(title: "Sets", value: "3"),
                Part(title: "Reps", note: "Per side", value: "10"),
                Part(title: "Weight", note: "One dumbbell", value: "25", unit: "lb", isOpen: true),
            ]),
            width: Self.sheetWidth,
        )
    }

    @Test("A pigeon stretch: one set, a time per side, no weight")
    func pigeon() {
        assertThemedSnapshots(
            of: content([
                Part(title: "Sets", value: "1"),
                Part(title: "Time", note: "Per side", value: "60", unit: "s"),
            ]),
            width: Self.sheetWidth,
        )
    }
}

#endif
