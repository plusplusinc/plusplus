import Foundation

/// Pure geometry and semantics for direct manipulation on the workout
/// detail rail (issue #78): long-press-drag rearrangement and ring-drag
/// superset membership. Everything here operates on a snapshot of the
/// group structure (`groupSizes` — exercises per group, in order) and
/// deterministic row heights, so the interaction rules are unit-testable
/// without SwiftUI or SwiftData. The view layer translates gestures into
/// these calls and commits results through the Workout mutations.
public struct RailMetrics: Equatable, Sendable {
    /// Every exercise row is the same height regardless of superset
    /// membership (device feedback on #87: rows must not shift when
    /// joining/leaving a ring).
    public var rowHeight: Double

    public init(rowHeight: Double = 48) {
        self.rowHeight = rowHeight
    }

    /// The v2 design's row height.
    public static let v2 = RailMetrics()
}

/// One visual row of the rail list.
public enum RailRowKind: Hashable, Sendable {
    case exercise(group: Int, index: Int)
}

public struct RailRow: Equatable, Sendable {
    public let kind: RailRowKind
    public let y: Double
    public let height: Double

    public var midY: Double { y + height / 2 }
    public var maxY: Double { y + height }
}

/// Deterministic row layout for a group structure: one uniform row per
/// exercise, packed in order. Supersets are marked by the loop drawing,
/// not by structure — no caption rows, no per-membership heights.
public struct RailLayout: Equatable, Sendable {
    public let rows: [RailRow]
    public let totalHeight: Double

    public static func build(groupSizes: [Int], metrics: RailMetrics = .v2) -> RailLayout {
        var rows: [RailRow] = []
        var y = 0.0
        for (group, size) in groupSizes.enumerated() {
            for index in 0..<size {
                rows.append(RailRow(kind: .exercise(group: group, index: index), y: y, height: metrics.rowHeight))
                y += metrics.rowHeight
            }
        }
        return RailLayout(rows: rows, totalHeight: y)
    }

    public func row(for kind: RailRowKind) -> RailRow? {
        rows.first { $0.kind == kind }
    }

    /// The exercise row nearest to `y` (positions beyond either end
    /// clamp to the closest row).
    public func exercise(at y: Double) -> (group: Int, index: Int)? {
        var best: (group: Int, index: Int)?
        var bestDistance = Double.infinity
        for row in rows {
            guard case .exercise(let group, let index) = row.kind else { continue }
            let distance = abs(row.midY - y)
            if distance < bestDistance {
                bestDistance = distance
                best = (group, index)
            }
        }
        return best
    }

    /// Flat exercise ordinal (position in the concatenated exercise
    /// list) for a (group, index) pair.
    public static func flatIndex(groupSizes: [Int], group: Int, index: Int) -> Int {
        groupSizes.prefix(group).reduce(0, +) + index
    }
}

// MARK: - Rearrange (long-press a row body, drag)

/// Where a dragged exercise may land. By construction there is no
/// boundary ambiguity: gaps between groups always mean "solo here", and
/// in-ring positions exist only for the dragged row's own group.
public enum RailDropTarget: Hashable, Sendable {
    /// Between groups; 0...groupCount in pre-move group indices.
    case gap(Int)
    /// Reorder within the dragged exercise's own superset.
    case within(group: Int, index: Int)
}

public enum RailDrag {
    /// All valid drop targets for dragging (group, index), each with the
    /// y position (in the original layout) the target represents.
    public static func targets(
        groupSizes: [Int],
        dragging: (group: Int, index: Int),
        metrics: RailMetrics = .v2
    ) -> [(target: RailDropTarget, y: Double)] {
        let layout = RailLayout.build(groupSizes: groupSizes, metrics: metrics)
        var result: [(RailDropTarget, Double)] = []

        // Gaps: boundary above each group, plus the very end.
        for group in 0..<groupSizes.count {
            if let row = layout.row(for: .exercise(group: group, index: 0)) {
                result.append((.gap(group), row.y))
            }
        }
        result.append((.gap(groupSizes.count), layout.totalHeight))

        // Positions inside the dragged row's own superset.
        if groupSizes[dragging.group] > 1 {
            for index in 0..<groupSizes[dragging.group] {
                if let row = layout.row(for: .exercise(group: dragging.group, index: index)) {
                    result.append((.within(group: dragging.group, index: index), row.midY))
                }
            }
        }
        return result
    }

    /// The target whose y position is closest to the finger.
    public static func nearestTarget(
        groupSizes: [Int],
        dragging: (group: Int, index: Int),
        fingerY: Double,
        metrics: RailMetrics = .v2
    ) -> RailDropTarget? {
        targets(groupSizes: groupSizes, dragging: dragging, metrics: metrics)
            .min { abs($0.y - fingerY) < abs($1.y - fingerY) }?
            .target
    }

    /// Row positions for the drag preview: every original row except the
    /// dragged one keeps its identity (captions never restructure while
    /// the finger is down), packed with a hole the size of the dragged
    /// row opened at the tentative target.
    public static func previewPositions(
        groupSizes: [Int],
        dragging: (group: Int, index: Int),
        target: RailDropTarget,
        metrics: RailMetrics = .v2
    ) -> [RailRowKind: Double] {
        let layout = RailLayout.build(groupSizes: groupSizes, metrics: metrics)
        let draggedKind = RailRowKind.exercise(group: dragging.group, index: dragging.index)
        let draggedHeight = layout.row(for: draggedKind)?.height ?? metrics.rowHeight

        let remaining = layout.rows.filter { $0.kind != draggedKind }

        // The hole opens before this row of the remaining flow (nil =
        // after the last row).
        let holeBefore: RailRowKind? = {
            switch target {
            case .gap(let gap):
                guard gap < groupSizes.count else { return nil }
                // First remaining row belonging to a group >= gap.
                return remaining.first { row in
                    switch row.kind {
                    case .exercise(let g, _): return g >= gap
                    }
                }?.kind
            case .within(let group, let index):
                // Landing at member position `index` among the remaining
                // members of the group.
                let members = remaining.compactMap { row -> RailRowKind? in
                    if case .exercise(group, _) = row.kind { return row.kind }
                    return nil
                }
                if index < members.count { return members[index] }
                // Past the last member: hole opens before whatever
                // follows the group (or at the end).
                let lastMember = members.last
                guard let lastMember,
                      let lastIndex = remaining.firstIndex(where: { $0.kind == lastMember }),
                      remaining.indices.contains(lastIndex + 1)
                else { return nil }
                return remaining[lastIndex + 1].kind
            }
        }()

        var positions: [RailRowKind: Double] = [:]
        var y = 0.0
        for row in remaining {
            if row.kind == holeBefore {
                y += draggedHeight
            }
            positions[row.kind] = y
            y += row.height
        }
        return positions
    }
}

// MARK: - Ring (long-press a rail dot, drag the loop edge)

public enum RingEdge: Sendable, Equatable {
    case top
    case bottom
}

/// The tentative membership span while a ring edge is being dragged,
/// expressed both as flat exercise indices (for highlighting) and as the
/// structural delta to commit (counts of adjacent solo groups to absorb
/// or edge members to eject).
public struct RingSpan: Equatable, Sendable {
    public let firstFlat: Int
    public let lastFlat: Int
    public let absorbBefore: Int
    public let absorbAfter: Int
    public let ejectFirst: Int
    public let ejectLast: Int

    public var isNoOp: Bool {
        absorbBefore == 0 && absorbAfter == 0 && ejectFirst == 0 && ejectLast == 0
    }
}

public enum RailRing {
    /// Which loop edge a press on (group, index) grabs: the first member
    /// grabs the top, the last (or a solo row) the bottom, middle
    /// members whichever edge is nearer (ties go down).
    public static func grabbedEdge(groupSizes: [Int], group: Int, pressedIndex: Int) -> RingEdge {
        let size = groupSizes[group]
        guard size > 1 else { return .bottom }
        if pressedIndex == 0 { return .top }
        if pressedIndex == size - 1 { return .bottom }
        return pressedIndex < size - 1 - pressedIndex ? .top : .bottom
    }

    /// Consecutive solo groups directly after `group` — the extension
    /// budget for the bottom edge (rings never swallow other rings).
    static func soloRunAfter(groupSizes: [Int], group: Int) -> Int {
        var count = 0
        var next = group + 1
        while next < groupSizes.count, groupSizes[next] == 1 {
            count += 1
            next += 1
        }
        return count
    }

    static func soloRunBefore(groupSizes: [Int], group: Int) -> Int {
        var count = 0
        var previous = group - 1
        while previous >= 0, groupSizes[previous] == 1 {
            count += 1
            previous -= 1
        }
        return count
    }

    /// The tentative span for a finger at `fingerY`, clamped to the
    /// rules: extension absorbs only the adjacent solo run, contraction
    /// stops at a single remaining row.
    public static func span(
        groupSizes: [Int],
        group: Int,
        edge: RingEdge,
        fingerY: Double,
        metrics: RailMetrics = .v2
    ) -> RingSpan {
        let layout = RailLayout.build(groupSizes: groupSizes, metrics: metrics)
        let start = RailLayout.flatIndex(groupSizes: groupSizes, group: group, index: 0)
        let end = start + groupSizes[group] - 1

        guard let hit = layout.exercise(at: fingerY) else {
            return RingSpan(firstFlat: start, lastFlat: end, absorbBefore: 0, absorbAfter: 0, ejectFirst: 0, ejectLast: 0)
        }
        let finger = RailLayout.flatIndex(groupSizes: groupSizes, group: hit.group, index: hit.index)

        switch edge {
        case .bottom:
            let newLast = min(max(finger, start), end + soloRunAfter(groupSizes: groupSizes, group: group))
            return RingSpan(
                firstFlat: start,
                lastFlat: newLast,
                absorbBefore: 0,
                absorbAfter: max(0, newLast - end),
                ejectFirst: 0,
                ejectLast: max(0, end - newLast)
            )
        case .top:
            let newFirst = max(min(finger, end), start - soloRunBefore(groupSizes: groupSizes, group: group))
            return RingSpan(
                firstFlat: newFirst,
                lastFlat: end,
                absorbBefore: max(0, start - newFirst),
                absorbAfter: 0,
                ejectFirst: max(0, newFirst - start),
                ejectLast: 0
            )
        }
    }
}
