import SwiftUI

/// A pulse to run along a rail, from one row's node to another's: a workout moving on from the
/// exercise it was on to the next. Each new `run` plays it once (`SetMotion`).
public struct RailPulse<ID: Hashable>: Equatable {
    public var from: ID
    public var to: ID
    public var run: Int

    public init(from: ID, to: ID, run: Int) {
        self.from = from
        self.to = to
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

/// The green pulse traveling a route: a capsule along it whose front edge leads, as the October
/// rail entry's did. It is as wide as the line at the start and `pointScale` times as wide at
/// the landing, on a cubic ease-in, and as long as its width plus a stretch for its speed, at most
/// `longest` of the route, so it stretches most as it shoots off. After it
/// lands, through `SetMotion.collapse`, the stretch collapses back into the dot, on the node.
nonisolated struct PulseShape: Shape {
    /// From 0 as it sets off to 1 as it lands, then on to `end` as it collapses; below 0 there
    /// is no pulse.
    var time: Double
    let route: RailRoute
    let lineWidth: CGFloat

    /// How much wider it is at the landing than the line.
    static let pointScale: CGFloat = 2
    /// How long the stretch is for each point a second of its speed.
    static let stretch: CGFloat = 0.022
    /// The longest it stretches, against the route.
    static let longest: CGFloat = 0.35

    static var end: Double {
        1 + SetMotion.collapse / SetMotion.travel
    }

    /// A run's times, from before it sets off to after its dot is gone.
    @KeyframesBuilder<Double>
    static var run: some Keyframes<Double> {
        MoveKeyframe(-1.0)
        LinearKeyframe(-1.0, duration: SetMotion.travelStart)
        MoveKeyframe(0.0)
        LinearKeyframe(end, duration: SetMotion.travel + SetMotion.collapse)
        // A dot on the node until the node has turned green under it.
        LinearKeyframe(end, duration: SetMotion.dotHold)
        // Then nothing, held for a frame: a timeline ending on a `MoveKeyframe` rests on the value
        // before it, which left the dot on the node once the run was over.
        MoveKeyframe(-1.0)
        LinearKeyframe(-1.0, duration: 1.0 / 60)
    }

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func path(in _: CGRect) -> Path {
        guard time >= 0, route.length > 0 else { return Path() }
        let shot = min(time, 1)
        let width = lineWidth * (1 + (Self.pointScale - 1) * CGFloat(shot * shot * shot))
        let total = route.length
        let front = total * CGFloat(SetMotion.distance(at: shot))
        let speed = CGFloat(SetMotion.speed(at: shot)) * total / CGFloat(SetMotion.travel)
        var length = min(width + Self.stretch * speed, max(total * Self.longest, width))
        if time > 1 {
            let collapse = CGFloat((time - 1) / (Self.end - 1))
            length = width + (length - width) * max(0, 1 - collapse)
        }
        // The round caps add half the width at each end, so the stretch between them is shorter;
        // collapsing, the dot it leaves settles on the node's center.
        let settled = time > 1 ? width / 2 * min(CGFloat((time - 1) / (Self.end - 1)), 1) : 0
        let head = max(front - width / 2 + settled, 0)
        let tail = max(front - length + width / 2 + settled, 0)
        let points = route.stretch(from: min(tail, head), to: head)
        guard let first = points.first else { return Path() }
        var line = Path()
        line.move(to: first)
        for point in points.dropFirst() {
            line.addLine(to: point)
        }
        let dot = Path(ellipseIn: CGRect(
            x: first.x - width / 2, y: first.y - width / 2, width: width, height: width,
        ))
        return line
            .strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .union(dot)
    }
}

/// The pulse drawn over a rail, from the rows' nodes as they are on each frame. It plays once
/// for each new `run`, from `SetMotion.travelStart` after it, holding as a dot on the node it
/// landed on until the node is current, and draws nothing between runs.
/// With Reduce Motion there is none: the move crossfades.
struct RailPulseRun: View {
    let route: RailRoute?
    let run: Int
    @ScaledMetric(relativeTo: .body) private var lineWidth = railLineWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    var body: some View {
        // Always in place, so the first run is a change it sees: put in with its first run, it
        // started at that run and never played it.
        KeyframeAnimator(initialValue: -1.0, trigger: run) { time in
            PulseShape(
                time: reduceMotion ? -1 : time,
                route: route ?? RailRoute([]),
                lineWidth: lineWidth,
            )
            .fill(.pp(.accent))
        } keyframes: { _ in
            PulseShape.run
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .hotReloadable()
    }
}
