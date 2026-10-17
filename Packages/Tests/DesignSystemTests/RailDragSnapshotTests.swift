// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// A row held on a rail, drawn at a moment of its drag from plain values: the card raised over
/// the rows, and the gap open on the rail where it would land. The hold, the finger, and the
/// haptics are the phone's; the drag's arithmetic is unit-tested in `RailDragTests`.
@Suite("Rail drag")
struct RailDragSnapshotTests {
    private static let screenWidth: CGFloat = 390

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
    }

    private static let rows = [
        Row(title: "Goblet squat", detail: ["3 × 10 reps", "35 lb"]),
        Row(title: "Push-up", detail: ["3 × 10 reps"]),
        Row(title: "Farmer\u{2019}s carry", detail: ["3 × 30 s", "25 lb/side"]),
        Row(title: "Plank", detail: ["60 s"]),
    ]

    /// `rows` with the row at `lifted` held over `slot`, its card `offset` below the gap.
    private func rail(
        _ rows: [Row] = Self.rows,
        links: Set<UUID> = [],
        lifting lifted: Int,
        origin: RailSlot<UUID>,
        over slot: RailSlot<UUID>,
        offset: CGFloat,
    ) -> some View {
        Rail(
            rows,
            links: links,
            drag: RailDragState(lifted: rows[lifted].id, origin: origin, slot: slot, grab: 20),
            cardOffset: offset,
        ) { row in
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

    @Test("A held row lifts into a card over its own gap")
    func liftedInPlace() {
        let rows = Self.rows
        let own = RailSlot.before(rows[2].id)
        assertThemedSnapshots(
            of: rail(lifting: 1, origin: own, over: own, offset: 8),
            width: Self.screenWidth,
        )
    }

    /// The rows below moved up into its place, the line unbroken through the gap, no node in it.
    @Test("The gap moved two rows down, the card over it")
    func gapMoved() {
        let rows = Self.rows
        assertThemedSnapshots(
            of: rail(
                lifting: 1,
                origin: .before(rows[2].id),
                over: .before(rows[3].id),
                offset: -20,
            ),
            width: Self.screenWidth,
        )
    }

    /// The gap's node is hidden; the line starts at the card's node, never above the card.
    @Test("The first row held a little below its gap shows no line above the card")
    func firstRowBelowGap() {
        let rows = Self.rows
        let own = RailSlot.before(rows[1].id)
        assertThemedSnapshots(
            of: rail(lifting: 0, origin: own, over: own, offset: 30),
            width: Self.screenWidth,
        )
    }

    /// The rail draws the pair as the drop would leave it, B then the held row, its loop running
    /// to the card's node, not the empty gap's; the card shows that loop's stretch over its fill.
    @Test("A pair's first row held inside its bottom edge, the card below its gap")
    func pairMemberInsideBottomEdge() {
        let rows = Self.rows
        assertThemedSnapshots(
            of: rail(
                links: [rows[1].id],
                lifting: 1,
                origin: .before(rows[2].id, joining: .below),
                over: .before(rows[3].id, joining: .above),
                offset: 24,
            ),
            width: Self.screenWidth,
        )
    }

    /// Past the inside slot, the pair lets go of the held row: the partner below draws plain, no
    /// loop on the rail or the card.
    @Test("A pair's first row held outside its bottom edge, plain")
    func pairMemberOutsideBottomEdge() {
        let rows = Self.rows
        assertThemedSnapshots(
            of: rail(
                links: [rows[1].id],
                lifting: 1,
                origin: .before(rows[2].id, joining: .below),
                over: .before(rows[3].id),
                offset: 40,
            ),
            width: Self.screenWidth,
        )
    }

    @Test("A routine of one row lifts it, with nowhere to move")
    func oneRowLifted() {
        let one = [Self.rows[0]]
        assertThemedSnapshots(
            of: rail(one, lifting: 0, origin: .end, over: .end, offset: 6),
            width: Self.screenWidth,
        )
    }
}

#endif
