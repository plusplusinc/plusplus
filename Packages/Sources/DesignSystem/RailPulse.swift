import SwiftUI

/// A pulse to run along a rail, from one row's node to another's: a workout moving on from the
/// exercise it was on to the next. Each new `run` plays it once (`SetMotion`).
public struct RailPulse<ID: Hashable>: Equatable {
    public var from: ID
    public var to: ID
    public var way: SetMotion.Way
    public var run: Int

    public init(from: ID, to: ID, way: SetMotion.Way, run: Int) {
        self.from = from
        self.to = to
        self.way = way
        self.run = run
    }
}

/// The way a pulse travels, as a line of points from its start to its end: down the rail from one
/// node to the next, or, back up to a superset's first member, out along its loop and up it.
nonisolated struct RailRoute: Equatable {
    let points: [CGPoint]
    /// How far each point is along the route, from the start.
    private let distances: [CGFloat]

    init(_ points: [CGPoint]) {
        self.points = points
        var distances: [CGFloat] = [0]
        for (from, to) in zip(points, points.dropFirst()) {
            distances.append((distances.last ?? 0) + hypot(to.x - from.x, to.y - from.y))
        }
        self.distances = distances
    }

    /// Straight along the rail.
    static func line(from: CGPoint, to: CGPoint) -> Self {
        Self([from, to])
    }

    /// From a superset's last node `from` up to its first `to`, along its loop as `pen` draws it:
    /// out from the node, round the corner, up the loop's line at `x`, and round into the node.
    static func loop(from: CGPoint, to: CGPoint, x: CGFloat, radius: CGFloat) -> Self {
        // A continuous corner's curve reaches about half as far again as its radius.
        let reach = min(radius * 1.53, abs(from.y - to.y) / 2, max(from.x - x, 0))
        var points = [from]
        points += corner(
            from: CGPoint(x: x + reach, y: from.y),
            at: CGPoint(x: x, y: from.y),
            to: CGPoint(x: x, y: from.y - reach),
        )
        points += corner(
            from: CGPoint(x: x, y: to.y + reach),
            at: CGPoint(x: x, y: to.y),
            to: CGPoint(x: x + reach, y: to.y),
        )
        points.append(to)
        return Self(points)
    }

    /// A corner as a quadratic curve, in short straight pieces.
    private static func corner(from: CGPoint, at control: CGPoint, to: CGPoint) -> [CGPoint] {
        (0 ... 8).map { step in
            let along = CGFloat(step) / 8
            let (start, middle, end) =
                ((1 - along) * (1 - along), 2 * (1 - along) * along, along * along)
            return CGPoint(
                x: start * from.x + middle * control.x + end * to.x,
                y: start * from.y + middle * control.y + end * to.y,
            )
        }
    }

    var length: CGFloat {
        distances.last ?? 0
    }

    /// The point `distance` along the route, held within it.
    func point(at distance: CGFloat) -> CGPoint {
        guard let first = points.first else { return .zero }
        guard distance > 0 else { return first }
        for index in points.indices.dropFirst() where distances[index] >= distance {
            let (start, end) = (distances[index - 1], distances[index])
            let share = end > start ? (distance - start) / (end - start) : 0
            let (from, to) = (points[index - 1], points[index])
            return CGPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share)
        }
        return points.last ?? first
    }

    /// The stretch of the route from `start` to `end`, as a line of points.
    func stretch(from start: CGFloat, to end: CGFloat) -> [CGPoint] {
        let inside = points.indices.filter { distances[$0] > start && distances[$0] < end }
        return [point(at: start)] + inside.map { points[$0] } + [point(at: end)]
    }
}

/// The green pulse traveling a route, as a blob of something viscous, `time` seconds after the
/// slide's log. From the log it is the node it leaves, round; from `SetMotion.travelStart`, that
/// node is pulled out along the route:
/// the mass, a circle at `size`, the current node's, slides off a circle at `restingSize`, the
/// node left behind, and a neck between them (`neck(_:_:)`) thins as they part, until it snaps
/// and only the mass draws. It runs along the route as a capsule drawn out by its speed, thinner
/// the longer it is, its area kept, and once its leading end touches the next node, a circle at
/// `restingSize` there joins it by a neck too. Landed (`SetMotion.landing(_:)`), it is a circle
/// on the node, which squashes and wiggles back to round through `SetMotion.plop`
/// (`SetMotion.squash(at:)`) over the node, lit as it lands; then nothing draws.
nonisolated struct PulseShape: Shape {
    /// Seconds since the log; below 0, as between runs, there is no pulse.
    var time: Double
    let route: RailRoute
    /// The current node's size, the mass's at rest.
    let size: CGFloat
    /// A resting node's size: the one left behind, and the one it joins.
    let restingSize: CGFloat
    /// Which way it goes, which sets its travel's length and curve.
    var way = SetMotion.Way.down

    /// How much longer the mass is for each point a second of its speed.
    static let stretch: CGFloat = 0.03
    /// The longest the mass draws out, against its size.
    static let longest: CGFloat = 3
    /// The radius of the curves a neck's sides follow, against `size`: larger, the neck reaches
    /// farther before it snaps.
    static let goo: CGFloat = 0.6

    /// How long a run lasts, from the log to the plop settled.
    static func runEnd(_ way: SetMotion.Way) -> Double {
        SetMotion.landing(way) + SetMotion.plop
    }

    /// A run's times: the seconds since the log, then nothing.
    @KeyframesBuilder<Double>
    static func run(_ way: SetMotion.Way) -> some Keyframes<Double> {
        MoveKeyframe(0.0)
        LinearKeyframe(runEnd(way), duration: runEnd(way))
        // Then nothing, held for a frame: a timeline ending on a `MoveKeyframe` rests on the value
        // before it, which left the pulse on the node once the run was over.
        MoveKeyframe(-1.0)
        LinearKeyframe(-1.0, duration: 1.0 / 60)
    }

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func path(in _: CGRect) -> Path {
        let start = SetMotion.travelStart
        // From the log, so the node left, gone to its own color, is never seen before the pulse
        // covers it; it waits there, round, until `travelStart`.
        guard time >= 0, time < Self.runEnd(way), route.length > 0,
              let target = route.points.last
        else { return Path() }
        let landed = time - SetMotion.landing(way)
        if landed >= 0 {
            let squash = CGFloat(SetMotion.squash(at: landed))
            let width = size * (1 + CGFloat(SetMotion.plopWiden) * squash)
            let height = size * (1 - CGFloat(SetMotion.plopFlatten) * squash)
            return Path(ellipseIn: CGRect(
                x: target.x - width / 2, y: target.y - height / 2, width: width, height: height,
            ))
        }
        let travel = SetMotion.travel(way)
        let share = min(max((time - start) / travel, 0), 1)
        let total = route.length
        let headAlong = total * CGFloat(SetMotion.distance(at: share, way))
        var length = min(
            size + Self.stretch * CGFloat(SetMotion.speed(at: share, way)) * total / travel,
            size * Self.longest,
        )
        // Up a loop it reaches the node still moving, and gathers into a circle on it.
        let gathered = (time - start - travel) / SetMotion.collapse
        if gathered > 0 {
            length = size + (length - size) * CGFloat(max(1 - gathered, 0))
        }
        let width = Self.width(length: length, size: size)
        let tailAlong = max(headAlong - (length - width), 0)
        let head = Circle(center: route.point(at: headAlong), radius: width / 2)
        let tail = Circle(center: route.point(at: tailAlong), radius: width / 2)
        var mass = Path()
        let points = route.stretch(from: tailAlong, to: headAlong)
        if let first = points.first {
            mass.move(to: first)
            for point in points.dropFirst() {
                mass.addLine(to: point)
            }
        }
        var shape = mass
            .strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .union(head.path)
        let left = Circle(center: route.points[0], radius: restingSize / 2)
        // Attached while the mass still overlaps the node left, its tail held there, or a neck
        // joins them.
        let neck = Self.neck(left, tail, goo: size * Self.goo)
        if neck != nil || left.distance(to: tail) < left.radius + tail.radius {
            shape = shape.union(left.path)
        }
        if let neck {
            shape = shape.union(neck)
        }
        let next = Circle(center: target, radius: restingSize / 2)
        if next.distance(to: head) < next.radius + head.radius {
            shape = shape.union(next.path)
            if let neck = Self.neck(head, next, goo: size * Self.goo) {
                shape = shape.union(neck)
            }
        }
        return shape
    }

    /// The mass's width drawn out to `length`: a capsule with the area of a circle at `size`.
    static func width(length: CGFloat, size: CGFloat) -> CGFloat {
        // A capsule's area is w(l - w) + πw²/4; solved for w, the narrower root.
        let bend = 1 - CGFloat.pi / 4
        let area = CGFloat.pi / 4 * size * size
        guard length > size else { return size }
        return (length - (length * length - 4 * bend * area).squareRoot()) / (2 * bend)
    }

    /// The neck joining two circles, as goo does: the space between them bounded by two curves
    /// of radius `goo`, one each side, each touching both circles. As the circles part, the
    /// curves close in on the line between their centers, and the neck thins to nothing and
    /// snaps once they meet it: nil from then on, and while one circle holds the other.
    static func neck(_ one: Circle, _ other: Circle, goo: CGFloat) -> Path? {
        let along = CGPoint(x: other.center.x - one.center.x, y: other.center.y - one.center.y)
        let apart = hypot(along.x, along.y)
        guard apart > abs(one.radius - other.radius) else { return nil }
        let (reachOne, reachOther) = (one.radius + goo, other.radius + goo)
        let forward = (apart * apart + reachOne * reachOne - reachOther * reachOther) / (2 * apart)
        let side = (reachOne * reachOne - forward * forward).squareRoot()
        guard side > goo else { return nil }
        let (unit, normal) = (
            CGPoint(x: along.x / apart, y: along.y / apart),
            CGPoint(x: -along.y / apart, y: along.x / apart),
        )
        let curves = [1.0, -1.0].map { sign in
            CGPoint(
                x: one.center.x + unit.x * forward + normal.x * side * sign,
                y: one.center.y + unit.y * forward + normal.y * side * sign,
            )
        }
        func touch(_ circle: Circle, _ curve: CGPoint) -> CGPoint {
            let share = circle.radius / (circle.radius + goo)
            return CGPoint(
                x: circle.center.x + (curve.x - circle.center.x) * share,
                y: circle.center.y + (curve.y - circle.center.y) * share,
            )
        }
        var neck = Path()
        neck.addLines([
            touch(one, curves[0]), touch(other, curves[0]),
            touch(other, curves[1]), touch(one, curves[1]),
        ])
        neck.closeSubpath()
        for curve in curves {
            neck = neck.subtracting(Circle(center: curve, radius: goo).path)
        }
        return neck
    }

    /// A circle on the route, for the blob's parts.
    struct Circle {
        let center: CGPoint
        let radius: CGFloat

        var path: Path {
            Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2,
            ))
        }

        func distance(to other: Self) -> CGFloat {
            hypot(other.center.x - center.x, other.center.y - center.y)
        }
    }
}

/// The pulse drawn over a rail, from the rows' nodes as they are on each frame. It plays once
/// for each new `run`, from the log to its plop settled on the node it lands on
/// (`PulseShape.runEnd(_:)`), and draws nothing between runs. It dims with the current node it
/// leaves and becomes (`currentPulse(in:)`), so it takes over from one and hands over to the
/// other without a seam. With Reduce Motion there is none: the move crossfades.
struct RailPulseRun: View {
    let route: RailRoute?
    let way: SetMotion.Way
    let run: Int
    @ScaledMetric(relativeTo: .body) private var size = currentNodeSize
    @ScaledMetric(relativeTo: .body) private var restingSize = railNodeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    var body: some View {
        // Always in place, so the first run is a change it sees: put in with its first run, it
        // started at that run and never played it.
        KeyframeAnimator(initialValue: -1.0, trigger: run) { time in
            let shape = PulseShape(
                time: reduceMotion ? -1 : time,
                route: route ?? RailRoute([]),
                size: size,
                restingSize: restingSize,
                way: way,
            )
            shape.fill(.pp(.accent)).currentPulse(in: shape)
        } keyframes: { _ in
            PulseShape.run(way)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .hotReloadable()
    }
}
