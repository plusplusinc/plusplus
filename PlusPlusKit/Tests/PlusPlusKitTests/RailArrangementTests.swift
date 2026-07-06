import Testing
@testable import PlusPlusKit

/// Issue #78: the pure geometry/semantics behind the rail's direct
/// manipulation. Structure snapshots are `groupSizes` — [1, 2, 1] means
/// solo, 2-superset, solo.
@Suite struct RailArrangementTests {
    let metrics = RailMetrics.v2 // solo 54, member 48, caption 30

    // MARK: - Layout

    @Test func layoutBuildsCaptionsForSupersetsOnly() {
        let layout = RailLayout.build(groupSizes: [1, 2, 1], metrics: metrics)
        let kinds = layout.rows.map(\.kind)
        #expect(kinds == [
            .exercise(group: 0, index: 0),
            .caption(group: 1),
            .exercise(group: 1, index: 0),
            .exercise(group: 1, index: 1),
            .exercise(group: 2, index: 0),
        ])
        #expect(layout.totalHeight == 54 + 30 + 48 + 48 + 54)
    }

    @Test func layoutPositionsAccumulate() {
        let layout = RailLayout.build(groupSizes: [1, 2], metrics: metrics)
        #expect(layout.row(for: .exercise(group: 0, index: 0))?.y == 0)
        #expect(layout.row(for: .caption(group: 1))?.y == 54)
        #expect(layout.row(for: .exercise(group: 1, index: 0))?.y == 84)
        #expect(layout.row(for: .exercise(group: 1, index: 1))?.y == 132)
    }

    @Test func hitTestIgnoresCaptionsAndClamps() {
        let layout = RailLayout.build(groupSizes: [1, 2], metrics: metrics)
        // Inside the caption band (y 54..84) the nearest exercise wins.
        #expect(layout.exercise(at: 56)!.group == 0)
        #expect(layout.exercise(at: 82)!.group == 1)
        // Beyond the ends clamps to first/last.
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

    @Test func memberDragGetsGapsPlusOwnRingPositions() {
        let targets = RailDrag.targets(groupSizes: [1, 3], dragging: (group: 1, index: 1), metrics: metrics)
        let kinds = Set(targets.map(\.target))
        #expect(kinds.contains(.within(group: 1, index: 0)))
        #expect(kinds.contains(.within(group: 1, index: 2)))
        #expect(kinds.contains(.gap(0)))
        #expect(kinds.contains(.gap(2)))
        // No way to target the interior of a group you're not in.
        #expect(!kinds.contains(.within(group: 0, index: 0)))
    }

    @Test func foreignRingInteriorIsNeverATarget() {
        // Dragging the solo (group 0) in [1, 3]: the only targets are the
        // three gaps — nothing inside the superset.
        let targets = RailDrag.targets(groupSizes: [1, 3], dragging: (group: 0, index: 0), metrics: metrics)
        for (target, _) in targets {
            if case .within = target { Issue.record("solo drag offered a ring interior: \(target)") }
        }
    }

    @Test func nearestTargetPicksByDistance() {
        // [1, 1]: gaps at y 0, 54, 108.
        let near0 = RailDrag.nearestTarget(groupSizes: [1, 1], dragging: (group: 0, index: 0), fingerY: 10, metrics: metrics)
        let near1 = RailDrag.nearestTarget(groupSizes: [1, 1], dragging: (group: 0, index: 0), fingerY: 60, metrics: metrics)
        let near2 = RailDrag.nearestTarget(groupSizes: [1, 1], dragging: (group: 0, index: 0), fingerY: 300, metrics: metrics)
        #expect(near0 == .gap(0))
        #expect(near1 == .gap(1))
        #expect(near2 == .gap(2))
    }

    @Test func memberNearestTargetInsideOwnRingIsAPosition() {
        // [3]: member rows at y 30, 78, 126 (caption first).
        let target = RailDrag.nearestTarget(groupSizes: [3], dragging: (group: 0, index: 0), fingerY: 126 + 24, metrics: metrics)
        #expect(target == .within(group: 0, index: 2))
    }

    // MARK: - Drag preview

    @Test func previewOpensHoleAtGapAndKeepsCaptions() {
        // Dragging the solo (group 0) of [1, 2] to the end gap.
        let positions = RailDrag.previewPositions(
            groupSizes: [1, 2],
            dragging: (group: 0, index: 0),
            target: .gap(2),
            metrics: metrics
        )
        // The superset (caption + 2 members) packs to the top; the hole
        // (54) sits after it.
        #expect(positions[.caption(group: 1)] == 0)
        #expect(positions[.exercise(group: 1, index: 0)] == 30)
        #expect(positions[.exercise(group: 1, index: 1)] == 78)
        #expect(positions[.exercise(group: 0, index: 0)] == nil) // dragged row is the floating preview
    }

    @Test func previewHoleAtOriginalSlotMovesNothing() {
        let positions = RailDrag.previewPositions(
            groupSizes: [1, 1],
            dragging: (group: 0, index: 0),
            target: .gap(0),
            metrics: metrics
        )
        // Row 1 stays exactly where it was: the hole re-occupies the
        // dragged row's own slot.
        #expect(positions[.exercise(group: 1, index: 0)] == 54)
    }

    @Test func previewWithinGroupShufflesMembers() {
        // Dragging member 0 of [3] to position 2: members 1 and 2 pack up.
        let positions = RailDrag.previewPositions(
            groupSizes: [3],
            dragging: (group: 0, index: 0),
            target: .within(group: 0, index: 2),
            metrics: metrics
        )
        #expect(positions[.caption(group: 0)] == 0)
        #expect(positions[.exercise(group: 0, index: 1)] == 30)
        #expect(positions[.exercise(group: 0, index: 2)] == 78)
        // Hole (48) after both = where the dragged member lands.
    }

    // MARK: - Ring grab

    @Test func grabbedEdgeByPressedRow() {
        #expect(RailRing.grabbedEdge(groupSizes: [1], group: 0, pressedIndex: 0) == .bottom) // solo
        #expect(RailRing.grabbedEdge(groupSizes: [3], group: 0, pressedIndex: 0) == .top)
        #expect(RailRing.grabbedEdge(groupSizes: [3], group: 0, pressedIndex: 2) == .bottom)
        #expect(RailRing.grabbedEdge(groupSizes: [4], group: 0, pressedIndex: 1) == .top)    // nearer top
        #expect(RailRing.grabbedEdge(groupSizes: [3], group: 0, pressedIndex: 1) == .bottom) // tie goes down
    }

    // MARK: - Ring span

    @Test func bottomEdgeAbsorbsFollowingSolosOnly() {
        // [2, 1, 1, 2]: superset rows flat 0-1, solos flat 2 and 3, then a superset.
        let sizes = [2, 1, 1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let lastSoloY = layout.row(for: .exercise(group: 2, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: lastSoloY, metrics: metrics)
        #expect(span.absorbAfter == 2)
        #expect(span.lastFlat == 3)

        // Dragging all the way to the far superset clamps at the solos.
        let farY = layout.totalHeight + 100
        let clamped = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: farY, metrics: metrics)
        #expect(clamped.absorbAfter == 2)
    }

    @Test func soloBottomEdgeCreatesSupersetOverNextSolo() {
        // [1, 1]: press the first solo's dot, drag to the second row.
        let sizes = [1, 1]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let secondY = layout.row(for: .exercise(group: 1, index: 0))!.midY
        let span = RailRing.span(groupSizes: sizes, group: 0, edge: .bottom, fingerY: secondY, metrics: metrics)
        #expect(span.absorbAfter == 1)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 1)
    }

    @Test func bottomEdgeContractsToOneRowMinimum() {
        // [3]: drag the bottom edge up past everything.
        let span = RailRing.span(groupSizes: [3], group: 0, edge: .bottom, fingerY: -100, metrics: metrics)
        #expect(span.ejectLast == 2)
        #expect(span.firstFlat == 0)
        #expect(span.lastFlat == 0)
    }

    @Test func topEdgeAbsorbsPrecedingSolosAndContracts() {
        // [1, 1, 2]: superset is flat 2-3; two solos above.
        let sizes = [1, 1, 2]
        let layout = RailLayout.build(groupSizes: sizes, metrics: metrics)
        let firstSoloY = layout.row(for: .exercise(group: 0, index: 0))!.midY
        let expand = RailRing.span(groupSizes: sizes, group: 2, edge: .top, fingerY: firstSoloY, metrics: metrics)
        #expect(expand.absorbBefore == 2)
        #expect(expand.firstFlat == 0)

        let bottomY = layout.totalHeight + 100
        let contract = RailRing.span(groupSizes: sizes, group: 2, edge: .top, fingerY: bottomY, metrics: metrics)
        #expect(contract.ejectFirst == 1) // clamped at one remaining row
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
}
