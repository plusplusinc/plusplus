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

    // MARK: - Ring grab

    @Test func grabbedEdgeByPressedRow() {
        #expect(RailRing.grabbedEdge(groupSizes: [1], group: 0, pressedIndex: 0) == .bottom) // solo default
        #expect(RailRing.grabbedEdge(groupSizes: [3], group: 0, pressedIndex: 0) == .top)
        #expect(RailRing.grabbedEdge(groupSizes: [3], group: 0, pressedIndex: 2) == .bottom)
        #expect(RailRing.grabbedEdge(groupSizes: [4], group: 0, pressedIndex: 1) == .top)    // nearer top
        #expect(RailRing.grabbedEdge(groupSizes: [3], group: 0, pressedIndex: 1) == .bottom) // tie goes down
    }

    // MARK: - Ring span

    @Test func bottomEdgeAbsorbsFollowingSolosOnly() {
        // [2, 1, 1, 2]: superset flat 0-1, solos flat 2 and 3, superset flat 4-5.
        let sizes = [2, 1, 1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let lastSoloY = layout.row(for: .exercise(group: 2, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: lastSoloY, metrics: metrics)
        #expect(span.absorbAfter == 2)
        #expect(span.lastFlat == 3)

        let clamped = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: layout.totalHeight + 100, metrics: metrics)
        #expect(clamped.absorbAfter == 2)
    }

    @Test func soloBottomEdgeCreatesSupersetOverNextSolo() {
        let sizes = [1, 1]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let secondY = layout.row(for: .exercise(group: 1, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: secondY, metrics: metrics)
        #expect(span.absorbAfter == 1)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 1)
    }

    @Test func soloTopEdgeAbsorbsUpward() {
        // Device feedback (#87): dragging UP from a solo must work too —
        // the view picks .top from the drag direction; the span math
        // must extend a solo's ring upward over preceding solos.
        let sizes = [1, 1]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let firstY = layout.row(for: .exercise(group: 0, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 1, edge: .top, fingerY: firstY, metrics: metrics)
        #expect(span.absorbBefore == 1)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 1)
    }

    @Test func bottomEdgeContractsToOneRowMinimum() {
        let span = RailRing.span(groupSizes: [3], group: 0, edge: .bottom, fingerY: -100, metrics: metrics)
        #expect(span.ejectLast == 2)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 0)
    }

    @Test func topEdgeAbsorbsPrecedingSolosAndContracts() {
        let sizes = [1, 1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let firstSoloY = layout.row(for: .exercise(group: 0, index: 0))!.midY
        let expand = RailRing.span(groupSizes: sizes, group: 2, edge: .top, fingerY: firstSoloY, metrics: metrics)
        #expect(expand.absorbBefore == 2)
        #expect(expand.firstFlat == 0)

        let contract = RailRing.span(groupSizes: sizes, group: 2, edge: .top, fingerY: layout.totalHeight + 100, metrics: metrics)
        #expect(contract.ejectFirst == 1)
        #expect(contract.firstFlat == 3)
        #expect(contract.lastFlat == 3)
    }

    @Test func unmovedFingerIsANoOp() {
        let sizes = [1, 2, 1]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let lastMemberY = layout.row(for: .exercise(group: 1, index: 1))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 1, edge: .bottom, fingerY: lastMemberY, metrics: metrics)
        #expect(span.isNoOp)
    }

    // MARK: - Solo joins an adjacent superset (reverse-direction drag)

    @Test func soloBottomEdgeJoinsSupersetBelow() {
        // [1, 2]: a solo (flat 0) above a superset (flat 1-2). Dragging the
        // solo down into the ring joins it — the reverse of the ring
        // reaching up to absorb the solo.
        let sizes = [1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let ringFirstY = layout.row(for: .exercise(group: 1, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: ringFirstY, metrics: metrics)
        #expect(span.mergeSoloInto == 1)
        #expect(span.firstFlat == 0)      // highlight spans solo + whole ring
        #expect(span.lastFlat == 2)
        #expect(span.absorbAfter == 0)
        #expect(!span.isNoOp)
    }

    @Test func soloTopEdgeJoinsSupersetAbove() {
        // [2, 1]: a superset (flat 0-1) above a solo (flat 2). Dragging the
        // solo up into the ring joins it.
        let sizes = [2, 1]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let ringLastY = layout.row(for: .exercise(group: 0, index: 1))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 1, edge: .top, fingerY: ringLastY, metrics: metrics)
        #expect(span.mergeSoloInto == -1)
        #expect(span.firstFlat == 0)      // highlight spans whole ring + solo
        #expect(span.lastFlat == 2)
        #expect(span.absorbBefore == 0)
        #expect(!span.isNoOp)
    }

    @Test func soloNotYetReachingSupersetIsANoOp() {
        // The join engages only once the finger reaches the ring; before
        // that only the solo is tentatively highlighted.
        let sizes = [1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let soloY = layout.row(for: .exercise(group: 0, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: soloY, metrics: metrics)
        #expect(span.mergeSoloInto == 0)
        #expect(span.isNoOp)
    }

    @Test func soloBetweenSupersetsJoinsTheOneItIsDraggedInto() {
        // [2, 1, 2]: the middle solo (flat 2) joins the ring below when
        // dragged down, the ring above when dragged up.
        let sizes = [2, 1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let downY = layout.row(for: .exercise(group: 2, index: 0))!.midY
        let down = RailRing.span(groupSizes: sizes, group: 1, edge: .bottom, fingerY: downY, metrics: metrics)
        #expect(down.mergeSoloInto == 1)
        #expect(down.firstFlat == 2)
        #expect(down.lastFlat == 4)

        let upY = layout.row(for: .exercise(group: 0, index: 1))!.midY
        let up = RailRing.span(groupSizes: sizes, group: 1, edge: .top, fingerY: upY, metrics: metrics)
        #expect(up.mergeSoloInto == -1)
        #expect(up.firstFlat == 0)
        #expect(up.lastFlat == 2)
    }

    @Test func soloRunStillAbsorbsWhenNeighbourIsNotARing() {
        // [1, 1, 2]: the first solo's immediate neighbour is another solo,
        // not the ring — so the old absorb-the-solo-run behaviour stands
        // (a solo run is never a merge-into-ring).
        let sizes = [1, 1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let secondSoloY = layout.row(for: .exercise(group: 1, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: secondSoloY, metrics: metrics)
        #expect(span.mergeSoloInto == 0)
        #expect(span.absorbAfter == 1)
    }

    // MARK: - Ring-to-ring merge (drag one superset into another)

    @Test func supersetBottomEdgeAbsorbsRingBelow() {
        // [2, 2]: two rings (flat 0-1 and 2-3). Dragging the first ring's
        // bottom edge into the second combines them — the whole neighbour
        // ring is absorbed the moment the finger reaches its first member.
        let sizes = [2, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let ringBelowFirstY = layout.row(for: .exercise(group: 1, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: ringBelowFirstY, metrics: metrics)
        #expect(span.absorbRing == 1)
        #expect(span.firstFlat == 0)      // highlight spans both whole rings
        #expect(span.lastFlat == 3)
        #expect(span.absorbAfter == 0)
        #expect(!span.isNoOp)
    }

    @Test func supersetTopEdgeAbsorbsRingAbove() {
        // [2, 2]: dragging the second ring's top edge up into the first.
        let sizes = [2, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let ringAboveLastY = layout.row(for: .exercise(group: 0, index: 1))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 1, edge: .top, fingerY: ringAboveLastY, metrics: metrics)
        #expect(span.absorbRing == -1)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 3)
        #expect(span.ejectFirst == 0)
        #expect(!span.isNoOp)
    }

    @Test func supersetNotYetReachingRingBelowStillEjects() {
        // Short of reaching the neighbour ring, the bottom edge dragged
        // INWARD still ejects members (the merge never masks eject).
        let sizes = [3, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let ownFirstY = layout.row(for: .exercise(group: 0, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: ownFirstY, metrics: metrics)
        #expect(span.absorbRing == 0)
        #expect(span.ejectLast == 2)      // contracted to a single row
        #expect(span.lastFlat == 0)
    }

    @Test func supersetAbsorbsSoloNotRingWhenSoloIsAdjacent() {
        // [2, 1, 2]: the first ring's immediate neighbour is a SOLO, so the
        // solo is absorbed the old way; the ring beyond it is not reachable.
        let sizes = [2, 1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let soloY = layout.row(for: .exercise(group: 1, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: soloY, metrics: metrics)
        #expect(span.absorbRing == 0)
        #expect(span.absorbAfter == 1)
        #expect(span.lastFlat == 2)
    }
}
