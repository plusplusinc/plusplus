// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// Black belt as it is drawn: a workout mid-set on the black screen, and a sheet's rows on the
/// sheet's lifted gray. What its colors keep (their ratios, a sheet's step) is
/// `BlackBeltTests`'; these hold how they land on screen. Colors only: the layouts at the
/// largest text size are the rail's, the current exercise's, and the value row's own snapshots',
/// so these skip it.
@Suite("Black belt snapshots")
struct BlackBeltSnapshotTests {
    private static let width: CGFloat = 390

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
        var focus: RowFocus?
        var bars: SetProgress?
    }

    /// A finished exercise, the current one on its second set of three, and one to come: every
    /// rail color, the set bars, and the current exercise's figures.
    @Test("A workout mid-set on the black screen")
    func midSet() {
        let finished = Row(title: "Push-up", detail: ["3 × 10 reps"])
        let current = Row(
            title: "Dumbbell bench press",
            detail: ["3 × 10 reps", "25 lb/side"],
            focus: RowFocus(
                place: SetPlace(word: "Set", number: 2, total: 3),
                equipment: ["Dumbbells", "Bench"],
                figures: [.init(number: "10", unit: "reps"), .init(number: "25", unit: "lb/side")],
                spokenFigures: "10 reps, 25 pounds a side",
            ),
            bars: SetProgress(done: 1, total: 3, spoken: "1 of 3 sets done"),
        )
        let rows = [finished, current, Row(title: "Incline push-up", detail: ["3 × 10 reps"])]
        let view = Rail(rows, links: [], current: current.id, done: [finished.id]) { row in
            RowLabel(title: row.title, detail: row.detail, focus: row.focus, bars: row.bars)
                .padding(.top, row.focus == nil ? 0 : Spacing.lg)
                .railRow()
        } end: {
            FloatingButtonRoom()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
        .environment(\.isVoid, true)
        assertThemedSnapshots(of: view, width: Self.width, atLargestSize: false)
    }

    /// The exercise sheet's rows, one open, on the sheet's gray: the rows a step above it, the
    /// keys and the quieter text on them.
    @Test("A sheet's rows on the sheet's lifted gray")
    func sheetRows() {
        let view = VStack(spacing: Spacing.sm) {
            ValueRow(
                label: "Sets",
                value: "3",
                spokenValue: "3",
                isOpen: false,
                canDecrease: true,
                canIncrease: true,
                onToggle: { },
                onStep: { _ in },
            )
            ValueRow(
                label: "Reps",
                note: "Per set",
                value: "10",
                spokenValue: "10",
                isOpen: true,
                canDecrease: true,
                canIncrease: true,
                onToggle: { },
                onStep: { _ in },
            )
        }
        .padding(Spacing.md)
        .background(Color.pp(.background))
        .environment(\.isOnSheet, true)
        .environment(\.isVoid, true)
        assertThemedSnapshots(of: view, width: Self.width, atLargestSize: false)
    }
}

#endif
