import SwiftUI

/// How a superset's loop is drawn at the current text size: a line beside the rail on its leading
/// side, curving into a node at each end on the corner of a continuous rounded rectangle, with a
/// pointed head between each node and the next. A row at rest draws its own stretch of it
/// (`GroupLoop`), and while a row or a node is held the rail draws every loop at once
/// (`HeldLoop`, `RailLoops`), all with this pen, read through `ScaledLoopPen`, so they are the
/// same strokes.
/// The loop's pen at the current text size, the one source of its widths.
@propertyWrapper
struct ScaledLoopPen: DynamicProperty {
    @ScaledMetric(relativeTo: .body) private var offset: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var wrappedValue: LoopPen {
        LoopPen(lineWidth: lineWidth, scale: scale, offset: offset)
    }
}

nonisolated struct LoopPen {
    var lineWidth: CGFloat
    /// The text size's scale against the default.
    var scale: CGFloat
    /// How far out from the node the loop runs.
    var offset: CGFloat

    /// How wide the head is either side of the line, and how long.
    var half: CGFloat {
        3.5 * scale
    }

    var length: CGFloat {
        7 * scale
    }

    /// The open space between the head's tip and the line's round end ahead of it.
    var gap: CGFloat {
        3 * scale
    }

    /// The corner's radius, its curve, as a continuous corner's does, reaching about half as far
    /// again along each side: here short of the node's center, so it meets the node level.
    var radius: CGFloat {
        7 * scale
    }

    /// Where the loop runs beside a node at `nodeX`, `out` of the way out, never so far that it or
    /// its head leaves the rail column.
    func runX(nodeX: CGFloat, out: CGFloat = 1) -> CGFloat {
        max(nodeX - offset * out, half)
    }

    /// The loop's line from `top` down to `bottom`, curving into the node level at each: part of a
    /// continuous rounded rectangle's border, cut square at the node's column, where the node
    /// draws over it.
    func line(top: CGFloat, bottom: CGFloat, nodeX: CGFloat, x: CGFloat) -> Path {
        let border = CGRect(x: x, y: top, width: nodeX - x + radius * 4, height: bottom - top)
        let column = CGRect(
            x: 0,
            y: top - lineWidth,
            width: nodeX,
            height: bottom - top + 2 * lineWidth,
        )
        return Path(roundedRect: border, cornerRadius: radius, style: .continuous)
            .strokedPath(StrokeStyle(lineWidth: lineWidth))
            .intersection(Path(column))
    }

    /// The head pointing up with its middle at `middle`, at `size` of its full size: the stretch
    /// of line it opens, from its base up to `gap` short of its tip, and what it adds, the head
    /// and the line's round end ahead of it.
    func head(middle: CGFloat, x: CGFloat, size: CGFloat = 1) -> (opening: Path, added: Path) {
        let tip = middle - size * length / 2
        let base = middle + size * length / 2
        let end = tip - size * gap - lineWidth / 2
        let cap = Path(ellipseIn: CGRect(
            x: x - lineWidth / 2, y: end - lineWidth / 2, width: lineWidth, height: lineWidth,
        ))
        let head = Path { path in
            path.move(to: CGPoint(x: x + size * half, y: base))
            path.addLine(to: CGPoint(x: x, y: tip))
            path.addLine(to: CGPoint(x: x - size * half, y: base))
            path.closeSubpath()
        }
        let opening = CGRect(x: x - lineWidth, y: end, width: 2 * lineWidth, height: base - end)
        return (Path(opening), cap.union(head))
    }
}

/// The rail's strokes while a row's node is held, drawn once for every row: the line from the
/// first node to the last, and every superset's loop, as the rows show.
///
/// The loops change in the transaction that moves the rows, stretching, shrinking, growing out of
/// a node, or drawing back into one, on its animation; with Reduce Motion, where the rows jump,
/// the old drawing crossfades to the new.
struct RailDrawing: View {
    /// The nodes' column.
    let nodeX: CGFloat
    /// Each row's node, from the first row to the last.
    let nodes: [CGFloat]
    /// Whether each row but the last is joined to the next.
    let joined: [Bool]
    /// The line's top and bottom.
    let spine: ClosedRange<CGFloat>
    /// What the drawing shows, the rows' order and how they are joined: a change of it crossfades
    /// with Reduce Motion.
    let shape: AnyHashable
    @ScaledLoopPen private var pen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    var body: some View {
        Group {
            if reduceMotion {
                ZStack {
                    strokes
                        .id(shape)
                        .transition(.opacity)
                }
                .animation(.snappy(duration: 0.2), value: shape)
            } else {
                strokes
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .hotReloadable()
    }

    private var strokes: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.pp(.rail))
                .frame(width: pen.lineWidth, height: max(spine.upperBound - spine.lowerBound, 0))
                .position(x: nodeX, y: (spine.lowerBound + spine.upperBound) / 2)
            RailLoops(
                nodeX: nodeX,
                nodes: RailVector(nodes.map(Double.init)),
                joins: RailVector(joined.map { $0 ? 1 : 0 }),
                fromBelow: joined.indices.map { index in
                    let above = index > 0 && joined[index - 1]
                    let below = index + 1 < joined.count && joined[index + 1]
                    return !above && below
                },
                pen: pen,
            )
            .fill(.pp(.rail))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Every superset's loop on a rail, from the rows' nodes and which of them are joined to the
/// next. Both animate: a join going from 0 to 1 grows its stretch of loop from the row above
/// down to the next, or, where only the row below's stretch stays joined, from it up; going back
/// it draws in the same way. A loop shorter than its curves draws into its node as it shrinks,
/// and a head shows once its stretch reaches halfway.
nonisolated struct RailLoops: Shape {
    let nodeX: CGFloat
    var nodes: RailVector
    var joins: RailVector
    /// For each join, whether its stretch grows from the row below, the one it ends up attached
    /// to, rather than from the row above.
    let fromBelow: [Bool]
    let pen: LoopPen

    var animatableData: AnimatablePair<RailVector, RailVector> {
        get { AnimatablePair(nodes, joins) }
        set { (nodes, joins) = (newValue.first, newValue.second) }
    }

    func path(in _: CGRect) -> Path {
        let ys = nodes.values.map { CGFloat($0) }
        let loops = loops(ys)
        var line = Path()
        for loop in loops {
            line.addPath(pen.line(top: loop.top, bottom: loop.bottom, nodeX: nodeX, x: loop.x))
        }
        var opening = Path()
        var added = Path()
        for index in ys.indices.dropLast() {
            let join = CGFloat(joins.value(at: index))
            let size = min(max(2 * join - 1, 0), 1)
            let middle = (ys[index] + ys[index + 1]) / 2
            guard size > 0.01, let loop = loops.first(where: { $0.top ... $0.bottom ~= middle })
            else { continue }
            let head = pen.head(middle: middle, x: loop.x, size: size)
            opening.addPath(head.opening)
            added.addPath(head.added)
        }
        return line.subtracting(opening).union(added)
    }

    /// The loops as drawn now: the stretches between joined nodes, each as far along as its join,
    /// run together where they meet.
    private func loops(_ ys: [CGFloat]) -> [LoopRun] {
        var stretches: [(top: CGFloat, bottom: CGFloat)] = []
        for index in ys.indices.dropLast() {
            let join = CGFloat(min(max(joins.value(at: index), 0), 1))
            guard join > 0.001 else { continue }
            let (top, bottom) = (ys[index], ys[index + 1])
            let reach = join * (bottom - top)
            let below = fromBelow.indices.contains(index) && fromBelow[index]
            stretches.append(below ? (bottom - reach, bottom) : (top, top + reach))
        }
        var runs: [(top: CGFloat, bottom: CGFloat)] = []
        for stretch in stretches.sorted(by: { $0.top < $1.top }) {
            if let last = runs.last, stretch.top <= last.bottom + 0.5 {
                runs[runs.count - 1].bottom = max(last.bottom, stretch.bottom)
            } else {
                runs.append(stretch)
            }
        }
        return runs.compactMap { run in
            let length = run.bottom - run.top
            guard length > 0.5 else { return nil }
            let out = min(length / (4 * pen.radius), 1)
            return LoopRun(top: run.top, bottom: run.bottom, x: pen.runX(nodeX: nodeX, out: out))
        }
    }
}

/// A loop as drawn at a moment: its top and bottom, and how far out it runs.
nonisolated struct LoopRun {
    var top: CGFloat
    var bottom: CGFloat
    var x: CGFloat
}

/// Values a shape animates, as many as it has rows: a missing value counts as nothing, so two
/// lists of different lengths still add.
nonisolated struct RailVector: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double]) {
        self.values = values
    }

    static var zero: Self {
        Self([])
    }

    func value(at index: Int) -> Double {
        values.indices.contains(index) ? values[index] : 0
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        combine(lhs, rhs, +)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        combine(lhs, rhs, -)
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private static func combine(
        _ lhs: Self,
        _ rhs: Self,
        _ op: (Double, Double) -> Double,
    ) -> Self {
        let count = max(lhs.values.count, rhs.values.count)
        return Self((0 ..< count).map { op(lhs.value(at: $0), rhs.value(at: $0)) })
    }
}
