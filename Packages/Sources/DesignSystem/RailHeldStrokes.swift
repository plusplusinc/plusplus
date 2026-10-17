import SwiftUI

/// The rail's strokes while a row is held by its content, drawn once for every row: the line
/// from the first node to the last, and every superset's loop. The held row's node is the card's,
/// wherever the finger has it, never its gap's: the gap is empty, so nothing ends at it. A loop
/// the held row is in runs to the card's node, and its heads sit between the nodes as they are,
/// whatever order they pass each other in, so as the rows move and the card follows the finger,
/// every end and head stays on its nodes.
///
/// Each node moves with its row, on the transaction that moves the rows; the card's moves with
/// the finger's, with none. As the held row goes into a superset or out of it, the loop with it
/// and the loop without it crossfade, both drawn to the nodes as they are, so neither ever ends
/// short of one. The held row's card draws the same drawing again over its fill, cut to its shape.
struct HeldRailDrawing: View {
    /// The nodes' column.
    let nodeX: CGFloat
    /// Each row's node, by its place in the rows as they were when the row was held, which stays
    /// the same through the drop, the held row's at the card's.
    let nodes: [Int: CGFloat]
    let held: Int
    /// Whether the line runs to the held row's node: not while it is over a bar, where the card
    /// is under the bar.
    let isHeldOnLine: Bool
    /// Every superset, and every row the held one could join, without the held row.
    let groups: [HeldGroup]
    @ScaledLoopPen private var pen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    var body: some View {
        let ys = RailNodeVector(nodes.mapValues(Double.init))
        ZStack(alignment: .topLeading) {
            HeldSpine(
                nodeX: nodeX,
                ys: ys,
                held: held,
                onLine: isHeldOnLine ? 1 : 0,
                width: pen.lineWidth,
            )
            .fill(.pp(.rail))
            ForEach(groups) { group in
                ZStack {
                    HeldLoop(nodeX: nodeX, members: group.members, ys: ys, pen: pen)
                        .fill(.pp(.rail))
                        .opacity(group.hasHeld ? 0 : 1)
                    HeldLoop(nodeX: nodeX, members: group.members + [held], ys: ys, pen: pen)
                        .fill(.pp(.rail))
                        .opacity(group.hasHeld ? 1 : 0)
                }
                // The slot's own animation; with Reduce Motion the rows move with none, and the
                // loops still crossfade.
                .animation(
                    reduceMotion ? .snappy(duration: 0.2) : RailDrag.gap,
                    value: group.hasHeld,
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .hotReloadable()
    }
}

/// A superset's rows other than the held one, or a row on its own, and whether the held row is in
/// it now.
struct HeldGroup: Identifiable {
    let id: Int
    let members: [Int]
    let hasHeld: Bool
}

/// The line through every node, from the topmost to the bottommost, the held row's node among
/// them as far as `onLine`.
nonisolated struct HeldSpine: Shape {
    let nodeX: CGFloat
    var ys: RailNodeVector
    let held: Int
    var onLine: Double
    let width: CGFloat

    var animatableData: AnimatablePair<RailNodeVector, Double> {
        get { AnimatablePair(ys, onLine) }
        set { (ys, onLine) = (newValue.first, newValue.second) }
    }

    func path(in _: CGRect) -> Path {
        let rows = ys.values.filter { $0.key != held }.map(\.value)
        guard var top = rows.min(), var bottom = rows.max() else { return Path() }
        if let card = ys.values[held] {
            top += onLine * (min(top, card) - top)
            bottom += onLine * (max(bottom, card) - bottom)
        }
        return Path(CGRect(x: nodeX - width / 2, y: top, width: width, height: bottom - top))
    }
}

/// A loop through `members`' nodes, from the topmost to the bottommost, with a head between each
/// node and the next above it, as they are now. A head shrinks away as two nodes meet.
nonisolated struct HeldLoop: Shape {
    let nodeX: CGFloat
    let members: [Int]
    var ys: RailNodeVector
    let pen: LoopPen

    var animatableData: RailNodeVector {
        get { ys }
        set { ys = newValue }
    }

    func path(in _: CGRect) -> Path {
        let points = members.compactMap { ys.values[$0] }.map { CGFloat($0) }.sorted()
        guard points.count > 1, let top = points.first, let bottom = points.last else {
            return Path()
        }
        let out = min((bottom - top) / (4 * pen.radius), 1)
        let x = pen.runX(nodeX: nodeX, out: out)
        let line = pen.line(top: top, bottom: bottom, nodeX: nodeX, x: x)
        var opening = Path()
        var added = Path()
        for (upper, lower) in zip(points, points.dropFirst()) {
            let size = min(max((lower - upper - 2 * pen.length) / (2 * pen.length), 0), 1)
            guard size > 0.01 else { continue }
            let head = pen.head(middle: (upper + lower) / 2, x: x, size: size)
            opening.addPath(head.opening)
            added.addPath(head.added)
        }
        return line.subtracting(opening).union(added)
    }
}

/// Values a shape animates, one for each row by its id: a missing value counts as nothing.
nonisolated struct RailNodeVector: VectorArithmetic {
    var values: [Int: Double]

    init(_ values: [Int: Double]) {
        self.values = values
    }

    static var zero: Self {
        Self([:])
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(lhs.values.merging(rhs.values, uniquingKeysWith: +))
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(lhs.values.merging(rhs.values.mapValues { -$0 }, uniquingKeysWith: +))
    }

    mutating func scale(by rhs: Double) {
        values = values.mapValues { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.values.reduce(0) { $0 + $1 * $1 }
    }
}

/// The rail drawn under the rows with holes: the strokes don't show through the end view, or
/// through a row swiped open, whose text has slid over the column.
nonisolated struct RailCutouts: Shape {
    let holes: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: 0, dy: -10000))
        for hole in holes {
            path.addRect(CGRect(x: rect.minX, y: hole.minY, width: rect.width, height: hole.height))
        }
        return path
    }
}
