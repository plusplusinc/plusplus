// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// An exercise sheet's rows, each a value on its rounded fill, built the way the app composes
/// them, with one open, its fill brighter. The sheet, its bar with the exercise's name, and the
/// wheel are the system's; the UI tests show them.
@Suite("Exercise sheet")
struct ExerciseSheetSnapshotTests {
    private static let sheetWidth: CGFloat = 390

    private struct Part {
        let title: String
        let value: String
        var suffix: String?
        var isOpen = false
    }

    private func content(_ parts: [Part]) -> some View {
        VStack(spacing: Spacing.xs) {
            ForEach(parts, id: \.title) { part in
                ValueRow(
                    title: part.title,
                    value: part.value,
                    suffix: part.suffix,
                    amount: nil,
                    spokenValue: "",
                    isOpen: part.isOpen,
                    identifier: part.title,
                    onToggle: { },
                    wheel: { EmptyView() },
                )
            }
        }
        .padding(Spacing.md)
        .background(Color.pp(.background))
    }

    @Test("A bench press: sets open, reps, and the bar's weight")
    func bench() {
        assertThemedSnapshots(
            of: content([
                Part(title: "Sets", value: "5", isOpen: true),
                Part(title: "Reps", value: "5"),
                Part(title: "Weight", value: "135", suffix: "lb"),
            ]),
            width: Self.sheetWidth,
        )
    }

    @Test("A dumbbell row: reps per side, one dumbbell's weight open")
    func row() {
        assertThemedSnapshots(
            of: content([
                Part(title: "Sets", value: "3"),
                Part(title: "Reps", value: "10", suffix: "per side"),
                Part(title: "Weight", value: "25", suffix: "lb", isOpen: true),
            ]),
            width: Self.sheetWidth,
        )
    }

    @Test("A pigeon stretch: one set, a time per side open, no weight")
    func pigeon() {
        assertThemedSnapshots(
            of: content([
                Part(title: "Sets", value: "1"),
                Part(title: "Time", value: "60", suffix: "s per side", isOpen: true),
            ]),
            width: Self.sheetWidth,
        )
    }
}

#endif
