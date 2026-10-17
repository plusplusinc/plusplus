// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// Supersets on a rail: the loop at rest, and a moment of a drag from a row's node, drawn from
/// plain values through `Rail`'s internal initializer. What a drag makes is the routine's rule,
/// unit-tested in `WorkoutStore`; where the finger reaches is `RailDrag`'s, in
/// `RailGroupDragTests`.
@Suite("Rail supersets")
struct RailSupersetSnapshotTests {
    private static let screenWidth: CGFloat = 390

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
    }

    private static let rows = [
        Row(title: "Goblet squat", detail: ["3 × 10 reps", "35 lb"]),
        Row(title: "Push-up", detail: ["3 × 10 reps"]),
        Row(title: "Pull-up", detail: ["3 × 6 reps"]),
        Row(title: "Plank", detail: ["60 s"]),
        Row(title: "Farmer\u{2019}s carry", detail: ["3 × 30 s", "25 lb/side"]),
        Row(title: "Dead hang", detail: ["3 × 30 s"]),
        Row(title: "Face pull", detail: ["3 × 15 reps"]),
    ]

    private func id(_ index: Int) -> UUID {
        Self.rows[index].id
    }

    private func rail(
        links: Set<UUID>,
        regrouping: RailRegroupState<UUID>? = nil,
    ) -> some View {
        Rail(Self.rows, links: links, drag: nil, regrouping: regrouping) { row in
            RowLabel(title: row.title, detail: row.detail)
                .railRow()
        } end: {
            Button("Add exercise", systemImage: "plus") { }
                .buttonStyle(.key)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    /// A plain row, a pair, a plain row, and a triple: each superset's loop runs from its last
    /// node up to its first, with a head in each gap between members.
    @Test("A pair and a triple at rest, between plain rows")
    func atRest() {
        assertThemedSnapshots(
            of: rail(links: [id(1), id(4), id(5)]),
            width: Self.screenWidth,
        )
    }

    /// The first row's node held over the third row's: the three sit in one raised field labeled
    /// Superset, their loop drawn as the drop would leave it, in the rail's gray, beside the pair
    /// below that the drag leaves alone.
    @Test("A node held over two rows down: the span's field, its label, and its loop")
    func nodeHeldOverSpan() {
        let span: Set = [id(0), id(1), id(2)]
        let held = RailRegroupState(
            held: id(0),
            reach: id(2),
            fingerY: 0,
            grouping: RailGrouping(links: [id(0), id(1), id(4)], span: span),
        )
        assertThemedSnapshots(
            of: rail(links: [id(1), id(4)], regrouping: held),
            width: Self.screenWidth,
        )
    }

    /// A press on a superset's end node, before the finger moves: the field wraps the whole
    /// superset, whose end the drag moves, and its loop stays as it is.
    @Test("An end node pressed: the field wraps its whole superset")
    func endNodePressed() {
        let pair: Set = [id(1), id(2)]
        let held = RailRegroupState(held: id(1), reach: id(1), fingerY: 0, pickedUp: pair)
        assertThemedSnapshots(
            of: rail(links: [id(1)], regrouping: held),
            width: Self.screenWidth,
        )
    }
}

#endif
