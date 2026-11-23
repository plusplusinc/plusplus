// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// The parts of the Workouts screen drawn here: a workout's row and its shape, the list with an
/// "Also needs" section, and the Length sheet's content. The fills are given as plain values;
/// what a fill is, against the longest row shown, is `WorkoutSummaryTests`'.
@Suite("Workouts")
struct WorkoutsSnapshotTests {
    private static let screenWidth: CGFloat = 390

    /// Rows as the screen lays them out: a margin each side and a line under each.
    private func list(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    private func row(_ name: String, _ shape: WorkoutRow.Shape?) -> some View {
        WorkoutRow(name, shape: shape)
            .padding(.horizontal, Spacing.md)
            .overlay(alignment: .bottom) { RowLine().padding(.horizontal, Spacing.md) }
    }

    @Test("Rows: a longer workout draws a longer bar, segments longest first, words under them")
    func rows() {
        assertThemedSnapshots(
            of: list {
                row("Legs and balance", .init(
                    length: "35 min",
                    kind: "Strength",
                    equipment: ["Dumbbells", "Balance board"],
                    segments: [("Legs", 0.7), ("Core", 0.3)],
                    fill: 35.0 / 75,
                ))
                row("Full body", .init(
                    length: "75 min",
                    kind: "Strength",
                    equipment: ["Barbell", "Dumbbells", "Bench", "Pull-up bar"],
                    segments: [("Chest", 0.25), ("Back", 0.25), ("Legs", 0.2)],
                    more: [0.2, 0.1],
                    fill: 1,
                ))
                row("Kettlebell circuit", .init(
                    length: "25 min",
                    kind: "Conditioning",
                    equipment: ["Kettlebell"],
                    segments: [("Legs", 0.5), ("Core", 0.3), ("Shoulders", 0.2)],
                    fill: 25.0 / 75,
                ))
                row("Morning stretch", .init(
                    length: "10 min",
                    kind: "Stretching",
                    equipment: [],
                    segments: [("Legs", 0.6), ("Back", 0.4)],
                    fill: 10.0 / 75,
                ))
            },
            width: Self.screenWidth,
        )
    }

    @Test("A short bar: every word shows after the one before, the equipment shortened to +N")
    func shortBar() {
        assertThemedSnapshots(
            of: list {
                row("Quick upper", .init(
                    length: "5 min",
                    kind: "Strength",
                    equipment: ["Dumbbells", "Resistance band", "Pull-up bar"],
                    segments: [("Shoulders", 0.4), ("Chest", 0.3), ("Back", 0.3)],
                    fill: 0,
                ))
            },
            width: Self.screenWidth,
        )
    }

    @Test("A long name wraps beside its length; a workout with no exercises shows its name alone")
    func longName() {
        assertThemedSnapshots(
            of: list {
                row("Upper body strength, conditioning, and mobility", .init(
                    length: "45 min",
                    kind: "Strength",
                    equipment: ["Dumbbells"],
                    segments: [("Chest", 0.5), ("Back", 0.5)],
                    fill: 0.6,
                ))
                row("New workout", nil)
            },
            width: Self.screenWidth,
        )
    }

    @Test("An Also needs section under the matches; its button wraps inside the margins at AX5")
    func alsoNeeds() {
        let short = WorkoutRow.Shape(
            length: "15 min",
            kind: "Strength",
            equipment: ["Dumbbells", "Balance board"],
            segments: [("Legs", 1)],
            fill: 0.5,
        )
        assertThemedSnapshots(
            of: list {
                row("Legs", .init(
                    length: "30 min",
                    kind: "Strength",
                    equipment: ["Dumbbells"],
                    segments: [("Legs", 0.6), ("Core", 0.4)],
                    fill: 1,
                ))
                NeedsHeader(needed: "a balance board", addTitle: "Balance board") { }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xs)
                row("Balance and calves", short)
            },
            width: Self.screenWidth,
        )
    }

    /// The Length sheet's presets, on the narrowest phone the app runs on, as the sheet insets
    /// them. The wheels under them are a `UIPickerView`, which draws only in a window; the
    /// screenshots show them.
    @Test("Length's presets: one row of three at 375 pt, 20–40 min lit; stacked at AX5")
    func lengthPresets() {
        assertThemedSnapshots(
            of: LengthPresets(
                presets: ["≤ 20 min", "20–40 min", "≥ 40 min"],
                spoken: ["20 minutes or less", "20 to 40 minutes", "40 minutes or more"],
                lit: 1,
                onPreset: { _ in },
            )
            .padding(-Spacing.xs)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pp(.surface)),
            width: 375,
        )
    }
}

#endif
