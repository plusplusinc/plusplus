import Testing
@testable import PlusPlusKit

/// Issue #78/#87: the pure geometry/semantics behind the rail's direct
/// manipulation. Structure snapshots are `groupSizes` — [1, 2, 1] means
/// solo, 2-superset, solo. Every row is a uniform 48 pt; supersets are
/// marked by the loop drawing, not by layout structure.
@Suite struct RailArrangementTests {
    let metrics = RailMetrics.v2 // uniform 48 pt rows, no captions

    // MARK: - Layout

    @Test func layoutIsOneUniformRowPerExercise() {
        let layout = RailLayout.build(groupSizes: [1, 2, 1], metrics: metrics)
        let kinds = layout.rows.map(\.kind)
        #expect(kinds == [
            .exercise(group: 0, index: 0),
            .exercise(group: 1, index: 0),
            .exercise(group: 1, index: 1),
            .exercise(group: 2, index: 0),
        ])
        #expect(layout.totalHeight == 4 * 48)
        #expect(layout.rows.allSatisfy { $0.height == 48 })
    }

    @Test func layoutPositionsAccumulate() {
        let layout = RailLayout.build(groupSizes: [1, 2], metrics: metrics)
        #expect(layout.row(for: .exercise(group: 0, index: 0))?.y == 0)
        #expect(layout.row(for: .exercise(group: 1, index: 0))?.y == 48)
        #expect(layout.row(for: .exercise(group: 1, index: 1))?.y == 96)
    }

    @Test func hitTestClampsBeyondEnds() {
        let layout = RailLayout.build(groupSizes: [1, 2], metrics: metrics)
        #expect(layout.exercise(at: 50)! == (group: 1, index: 0))
        #expect(layout.exercise(at: -100)! == (group: 0, index: 0))
        #expect(layout.exercise(at: 9_999)! == (group: 1, index: 1))
    }

    @Test func flatIndexCountsAcrossGroups() {
        #expect(RailLayout.flatIndex(groupSizes: [2, 3, 1], group: 0, index: 0) == 0)
        #expect(RailLayout.flatIndex(groupSizes: [2, 3, 1], group: 1, index: 2) == 4)
        #expect(RailLayout.flatIndex(groupSizes: [2, 3, 1], group: 2, index: 0) == 5)
    }

    // MARK: - Drag targets

    @Test func soloDragGetsOnlyGaps() {
        let targets = RailDrag.targets(groupSizes: [1, 2, 1], dragging: (group: 0, index: 0), metrics: metrics)
        let gaps = targets.map(\.target)
        #expect(gaps == [.gap(0), .gap(1), .gap(2), .gap(3)])
    }

    @Test func gapAnchorsSitAtGroupBoundaries() {
        let targets = RailDrag.targets(groupSizes: [1, 2, 1], dragging: (group: 0, index: 0), metrics: metrics)
        let ys = Dictionary(uniqueKeysWithValues: targets.map { ($0.target, $0.y) })
        #expect(ys[.gap(0)] == 0)
        #expect(ys[.gap(1)] == 48)
        #expect(ys[.gap(2)] == 144)
        #expect(ys[.gap(3)] == 192)
    }

    @Test func memberDragGetsGapsPlusOwnRingPositions() {
        let targets = RailDrag.targets(groupSizes: [1, 3], dragging: (group: 1, index: 1), metrics: metrics)
        let kinds = Set(targets.map(\.target))
        #expect(kinds.contains(.within(group: 1, index: 0)))
        #expect(kinds.contains(.within(group: 1, index: 2)))
        #expect(kinds.contains(.gap(0)))
        #expect(kinds.contains(.gap(2)))
        #expect(!kinds.contains(.within(group: 0, index: 0)))
    }

    @Test func foreignRingInteriorIsNeverATarget() {
        let targets = RailDrag.targets(groupSizes: [1, 3], dragging: (group: 0, index: 0), metrics: metrics)
        for (target, _) in targets {
            if case .within = target { Issue.record("solo drag offered a ring interior: \(target)") }
        }
    }

    @Test func nearestTargetPicksByDistance() {
        // [1, 1]: gaps at y 0, 48, 96.
        let near0 = RailDrag.nearestTarget(groupSizes: [1, 1], dragging: (group: 0, index: 0), fingerY: 10, metrics: metrics)
        let near1 = RailDrag.nearestTarget(groupSizes: [1, 1], dragging: (group: 0, index: 0), fingerY: 52, metrics: metrics)
        let near2 = RailDrag.nearestTarget(groupSizes: [1, 1], dragging: (group: 0, index: 0), fingerY: 300, metrics: metrics)
        #expect(near0 == .gap(0))
        #expect(near1 == .gap(1))
        #expect(near2 == .gap(2))
    }

    @Test func memberNearestTargetInsideOwnRingIsAPosition() {
        // [3]: member midpoints at 24, 72, 120.
        let target = RailDrag.nearestTarget(groupSizes: [3], dragging: (group: 0, index: 0), fingerY: 120, metrics: metrics)
        #expect(target == .within(group: 0, index: 2))
    }

    // MARK: - Drag preview

    @Test func previewOpensHoleAtGap() {
        // Dragging the solo (group 0) of [1, 2] to the end gap: the two
        // members pack to the top, the hole (48) sits after them.
        let positions = RailDrag.previewPositions(
            groupSizes: [1, 2],
            dragging: (group: 0, index: 0),
            target: .gap(2),
            metrics: metrics
        )
        #expect(positions[.exercise(group: 1, index: 0)] == 0)
        #expect(positions[.exercise(group: 1, index: 1)] == 48)
        #expect(positions[.exercise(group: 0, index: 0)] == nil) // dragged row floats
    }

    @Test func previewHoleAtOriginalSlotMovesNothing() {
        let positions = RailDrag.previewPositions(
            groupSizes: [1, 1],
            dragging: (group: 0, index: 0),
            target: .gap(0),
            metrics: metrics
        )
        #expect(positions[.exercise(group: 1, index: 0)] == 48)
    }

    @Test func previewWithinGroupShufflesMembers() {
        let positions = RailDrag.previewPositions(
            groupSizes: [3],
            dragging: (group: 0, index: 0),
            target: .within(group: 0, index: 2),
            metrics: metrics
        )
        #expect(positions[.exercise(group: 0, index: 1)] == 0)
        #expect(positions[.exercise(group: 0, index: 2)] == 48)
    }

    // MARK: - Ring span: contract (drag an edge inward to eject)

    @Test func bottomEdgeContractsEjectingTail() {
        let sizes = [3]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let middleY = layout.row(for: .exercise(group: 0, index: 1))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: middleY, metrics: metrics)
        #expect(span.ejectLast == 1)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 1)
    }

    @Test func bottomEdgeContractsToOneRowMinimum() {
        let span = RailRing.span(groupSizes: [3], group: 0, edge: .bottom, fingerY: -100, metrics: metrics)
        #expect(span.ejectLast == 2)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 0)
    }

    @Test func topEdgeContractsEjectingHead() {
        let sizes = [3]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let middleY = layout.row(for: .exercise(group: 0, index: 1))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .top, fingerY: middleY, metrics: metrics)
        #expect(span.ejectFirst == 1)
        #expect(span.firstFlat == 1)
        #expect(span.lastFlat == 2)
    }

    @Test func unmovedFingerIsANoOp() {
        let sizes = [1, 2, 1]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let lastMemberY = layout.row(for: .exercise(group: 1, index: 1))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 1, edge: .bottom, fingerY: lastMemberY, metrics: metrics)
        #expect(span.isNoOp)
    }

    // MARK: - Ring span: unite (drag outward to gather a range)

    @Test func soloUnitesDownOverSolos() {
        let sizes = [1, 1, 1]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let lastY = layout.row(for: .exercise(group: 2, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: lastY, metrics: metrics)
        #expect(span.absorbAfter == 2)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 2)
    }

    @Test func soloUnitesUpOverSolos() {
        let sizes = [1, 1]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let firstY = layout.row(for: .exercise(group: 0, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 1, edge: .top, fingerY: firstY, metrics: metrics)
        #expect(span.absorbBefore == 1)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 1)
    }

    @Test func soloUnitesDownAcrossAWholeRing() {
        // [1, 2]: a solo above a ring. Dragging the solo down into the ring
        // gathers the WHOLE ring (not just its first member) into one span.
        let sizes = [1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let ringFirstY = layout.row(for: .exercise(group: 1, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: ringFirstY, metrics: metrics)
        #expect(span.absorbAfter == 1)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 2)      // whole ring, even landing on its first member
        #expect(!span.isNoOp)
    }

    @Test func soloUnitesUpAcrossAWholeRing() {
        // [2, 1]: a ring above a solo. Dragging the solo up into the ring.
        let sizes = [2, 1]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let ringLastY = layout.row(for: .exercise(group: 0, index: 1))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 1, edge: .top, fingerY: ringLastY, metrics: metrics)
        #expect(span.absorbBefore == 1)
        #expect(span.firstFlat == 0)     // whole ring, even landing on its last member
        #expect(span.lastFlat == 2)
        #expect(!span.isNoOp)
    }

    @Test func ringUnitesWithRingAcrossContent() {
        // [2, 2]: two rings unite into one.
        let sizes = [2, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let secondRingFirstY = layout.row(for: .exercise(group: 1, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: secondRingFirstY, metrics: metrics)
        #expect(span.absorbAfter == 1)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 3)
    }

    @Test func draggingToTheBottomGathersEverythingIncludingATrailingRing() {
        // [2, 1, 1, 2]: pressing the top ring and dragging to the very bottom
        // now unites ALL groups — the old model clamped to the solo run and
        // could not swallow the trailing superset. This is the whole point:
        // from any row, drag to an end and everything between joins up.
        let sizes = [2, 1, 1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: layout.totalHeight + 100, metrics: metrics)
        #expect(span.absorbAfter == 3)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 5)      // through the last member of the trailing ring
    }

    @Test func pressingAnyMemberUnitesFromItsWholeGroup() {
        // [3, 1]: pressing anywhere in the 3-ring and dragging down to the
        // solo unites the whole ring plus the solo — the pressed group is
        // never split, its full extent anchors the span.
        let sizes = [3, 1]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let soloY = layout.row(for: .exercise(group: 1, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: soloY, metrics: metrics)
        #expect(span.absorbAfter == 1)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 3)
    }
}
