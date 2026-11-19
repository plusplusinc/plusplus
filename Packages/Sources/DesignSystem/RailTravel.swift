import SwiftUI

/// A rest between two exercises on the rail, from the log to the rest's end: the stretch of rail
/// from the node of the row left to the next row's, which the dot crosses in three legs
/// (`SetMotion.restLeaveShare`). It leaves as a pulse does, from the log, and eases out over
/// `SetMotion.restLeave` into the crawl's speed; crawls at that one speed to the rest's end, its
/// place a straight line in the time gone; and, as the rest ends, the move's pulse takes it on
/// from where it is, at its speed (`handoff(at:)`). A + or − moves `ends`; while paused
/// (`heldAt`), it holds.
///
/// Between two sets of one exercise (`betweenSets`), `from` and `to` are that exercise, and the
/// rest is a bar beside the rest in its numbers' place, filling from `starts` (`SetRestBar`).
public struct RailTravel<ID: Hashable>: Equatable {
    public var from: ID
    public var to: ID
    /// The log; between sets, when the fill sets off.
    public var starts: Date
    /// The rest's end.
    public var ends: Date
    public var heldAt: Date?
    /// Between two sets of one exercise, where the bar is in its change.
    public var betweenSets: SetRestStage?

    public init(
        from: ID,
        to: ID,
        starts: Date,
        ends: Date,
        heldAt: Date?,
        betweenSets: SetRestStage? = nil,
    ) {
        self.from = from
        self.to = to
        self.starts = starts
        self.ends = ends
        self.heldAt = heldAt
        self.betweenSets = betweenSets
    }

    /// Where the dot is at `date` and how fast it goes, for the move's pulse to set off from as
    /// the rest ends.
    public func handoff(at date: Date) -> RestHandoff {
        let now = (heldAt ?? date).timeIntervalSinceReferenceDate
        let place = RestDotPlace(travel: self, ends: ends.timeIntervalSinceReferenceDate, now: now)
        return RestHandoff(share: place.share, tail: place.tail, speed: place.speed)
    }
}

/// Where the move's pulse sets off after a rest: the green's leading end along the stretch from
/// the node left to the next one's, from 0 to 1, and its tail, the bar's top once it fills; and
/// its speed in stretches a second.
public struct RestHandoff: Equatable, Sendable {
    public var share: Double
    public var tail: Double
    public var speed: Double
}

/// The rest's dot at a time `now`, worked out from the log and the rest's end `ends`, both in
/// seconds since the reference date: one place for the drawing and the hand-off, so they agree.
nonisolated struct RestDotPlace {
    /// Seconds since the log.
    let sinceLog: Double
    /// Along the stretch, from 0 to 1.
    let share: Double
    /// Where its tail is: the leading end's own place while it leaves, the bar's top once it
    /// fills.
    let tail: Double
    /// In stretches a second.
    let speed: Double
    /// The crawl's speed, in stretches a second.
    let crawl: Double
    /// The crawl's speed, in the leaving leg's lengths over its travel, for its end to meet.
    let leaveEnd: Double

    /// How long past the rest's end the dot crawls on, for the move's pulse to take it over in
    /// its first frames, where it is, with no stop at 0.
    static let overrun = 0.25

    init(travel: RailTravel<some Hashable>, ends: Double, now: Double) {
        let span = SetMotion.restSpan
        let starts = travel.starts.timeIntervalSinceReferenceDate
        sinceLog = now - starts
        let setOff = starts + SetMotion.restLeave
        // Never faster than a crawl over half a second, as for a rest shorter than its leaving.
        crawl = (span.upperBound - span.lowerBound) / max(ends - setOff, 0.5)
        let leaveTravel = SetMotion.restLeave - SetMotion.travelStart
        leaveEnd = crawl * leaveTravel / span.lowerBound
        if sinceLog < SetMotion.restLeave {
            let time = (sinceLog - SetMotion.travelStart) / leaveTravel
            share = span.lowerBound * SetMotion.restLeaveDistance(at: time, end: leaveEnd)
            speed = span.lowerBound / leaveTravel
                * SetMotion.restLeaveSpeed(at: time, end: leaveEnd)
            tail = share
        } else {
            tail = span.lowerBound
            let gone = ends > setOff
                ? max((min(now, ends + Self.overrun) - setOff) / (ends - setOff), 0) : 1
            share = min(span.lowerBound + (span.upperBound - span.lowerBound) * gone, 0.98)
            speed = crawl
        }
    }
}

nonisolated extension PulseShape {
    /// The traveling mass: its width, the distance between its ends' centers, and its head's
    /// center along the route.
    struct Mass {
        let width: CGFloat
        let apart: CGFloat
        let head: CGFloat
    }

    /// How blue the mass is at `time`, from 0, green, to 1, the rest's fill (`Leg.blue`).
    var blue: Double {
        let share = min(max((time - leg.start) / leg.travel(way), 0), 1)
        let distance = CGFloat(leg.motion(at: share, way).distance)
        return leg.blue(at: share, distance: distance, total: route.length, size: size)
    }
}

@MainActor
extension PulseShape {
    /// Drawn green, turning to the rest's blue by `blue`. On the main actor, as the colors are,
    /// though the shape is not.
    func tinted(blue: Double) -> some View {
        fill(.pp(.accent)).overlay { fill(.pp(.restFill)).opacity(blue) }
    }
}

nonisolated extension PulseShape.Leg {
    var isLeave: Bool {
        if case .leave = self {
            true
        } else {
            false
        }
    }

    var isArrive: Bool {
        if case .arrive = self {
            true
        } else {
            false
        }
    }

    /// How far along its route the mass sets off, from 0 to 1: an arriving leg's from the bar's
    /// top, where its route starts, to its leading end.
    var lead: Double {
        if case let .arrive(_, lead, _) = self {
            lead
        } else {
            0
        }
    }

    /// An arriving leg's line out of the bar at a share `time` of its travel, on a route `total`
    /// long: the distance from its tail's center to its head's, gathering in an ease out and in
    /// over `gather` of the travel, the tail setting off from the bar's top at rest; the bar's
    /// width it sets off at; and how far it has grown from that width to the dot's own, on the
    /// same ease, so it leaves the bar at the fill's width with no jump. Nil with no line.
    func gathered(_ time: Double, total: CGFloat) -> Gather? {
        guard case let .arrive(_, lead, _) = self, lead > 0 else { return nil }
        let into = min(max(time / Self.gather, 0), 1)
        let eased = CGFloat(into * into * (3 - 2 * into))
        return Gather(line: total * CGFloat(lead) * (1 - eased), grown: eased)
    }

    struct Gather {
        let line: CGFloat
        let grown: CGFloat
    }

    var barWidth: CGFloat {
        switch self {
        case .whole: 0
        case let .leave(_, barWidth), let .arrive(_, _, barWidth): barWidth
        }
    }

    /// The mass for its stretched `length`, at a share `time` of its travel, `distance` along a
    /// route `total` long. An arriving leg's line grows from the bar's width
    /// (`gathered(_:total:)`); a leaving leg pours into the bar (`poured(_:total:size:)`).
    func mass(
        length: CGFloat,
        at time: Double,
        distance: CGFloat,
        total: CGFloat,
        size: CGFloat,
    ) -> PulseShape.Mass {
        var width = PulseShape.width(length: length, size: size)
        var apart = length - width
        if let gather = gathered(time, total: total) {
            apart = max(apart, gather.line)
            width = barWidth + (PulseShape.width(apart: apart, size: size) - barWidth)
                * gather.grown
        }
        let lead = CGFloat(lead)
        let head = total * (lead + (1 - lead) * distance)
        guard isLeave else { return PulseShape.Mass(width: width, apart: apart, head: head) }
        let (edge, narrowed) = poured(distance, total: total, size: size)
        width += (barWidth - width) * narrowed
        let poured = length + ((size + barWidth) / 2 - length) * narrowed
        return PulseShape.Mass(width: width, apart: poured - width, head: edge - width / 2)
    }

    /// A leaving leg `distance` along a route `total` long: its leading edge, and how far it has
    /// poured into the bar, from 0 to 1. The edge, not the center, runs the leg's curve, from the
    /// node's edge to the fill's leading edge as the crawl starts: the center lags as the width
    /// changes, and the edge stalled after the shot as the mass gathered. As the edge comes into
    /// the bar's top it pours in, thinning to the bar's width and its length to the fill's as the
    /// crawl starts, so the two meet.
    func poured(_ distance: CGFloat, total: CGFloat, size: CGFloat) -> (CGFloat, CGFloat) {
        guard isLeave else { return (0, 0) }
        let edge = size / 2 + (total + (barWidth - size) / 2) * distance
        let into = min(max((edge - (total - size / 2)) / ((size + barWidth) / 2), 0), 1)
        return (edge, into * into * (3 - 2 * into))
    }

    /// How blue the green is at a share `time` of its travel, `distance` along a route `total`
    /// long, from 0, green, to 1, the rest's blue: a leaving leg turns blue as it pours into the
    /// bar; an arriving leg back to green as its line gathers into the dot.
    func blue(at time: Double, distance: CGFloat, total: CGFloat, size: CGFloat) -> Double {
        switch self {
        case .whole: 0
        case .leave: Double(poured(distance, total: total, size: size).1)
        case .arrive: Double(1 - (gathered(time, total: total)?.grown ?? 1))
        }
    }

    /// The share of an arriving leg's travel its line takes to gather into the mass.
    static let gather = 0.7

    /// When it sets off, from the log: a whole pulse and a leaving leg wait on the node for
    /// `SetMotion.travelStart`; an arriving leg goes on from the dot at once.
    var start: Double {
        isArrive ? 0 : SetMotion.travelStart
    }

    /// From setting off to reaching its end.
    func travel(_ way: SetMotion.Way) -> Double {
        switch self {
        case .whole: SetMotion.travel(way)
        case .leave: SetMotion.restLeave - SetMotion.travelStart
        case .arrive: SetMotion.travelStart + SetMotion.travel(way)
        }
    }

    /// Its distance and speed, against its average, at a share `time` of its travel.
    func motion(at time: Double, _ way: SetMotion.Way) -> (distance: Double, speed: Double) {
        switch self {
        case .whole:
            (SetMotion.distance(at: time, way), SetMotion.speed(at: time, way))
        case let .leave(end, _):
            (
                SetMotion.restLeaveDistance(at: time, end: end),
                SetMotion.restLeaveSpeed(at: time, end: end),
            )
        case let .arrive(start, _, _):
            (
                SetMotion.restArriveDistance(at: time, start: start),
                SetMotion.restArriveSpeed(at: time, start: start),
            )
        }
    }
}

/// The traveling dot: the current node's size and green, on its own timeline over the rail, so
/// nothing else redraws. Through the leaving leg it is a pulse's leaving leg
/// (`PulseShape.Leg.leave`), turning from green to the rest's blue as it pours into the bar's
/// top; then the bar's fill, a steady blue line the bar's width from its top to the leading end,
/// read from the same `ends` as the countdown, so they cannot drift. `ends` animates: after a +
/// or −, the fill glides to its new place on the tap's animation.
struct RailTravelDot<ID: Hashable>: View, Animatable {
    let travel: RailTravel<ID>
    let route: RailRoute
    /// `travel.ends`, as it animates.
    var ends: Double
    @ScaledMetric(relativeTo: .body) private var size = currentNodeSize
    @ScaledMetric(relativeTo: .body) private var restingSize = railNodeSize
    @ScaledMetric(relativeTo: .body) private var barWidth = RestBar.size
    /// Where the node left was at the log, which the leaving leg sets off from.
    @State private var origin: CGPoint?
    /// Where the bar's top was at the log.
    @State private var barTop: CGPoint?

    init(travel: RailTravel<ID>, route: RailRoute) {
        self.travel = travel
        self.route = route
        ends = travel.ends.timeIntervalSinceReferenceDate
    }

    var animatableData: Double {
        get { ends }
        set { ends = newValue }
    }

    var body: some View {
        let schedule = AnimationTimelineSchedule(
            minimumInterval: 1.0 / 60,
            paused: travel.heldAt != nil,
        )
        TimelineView(schedule) { context in
            let now = (travel.heldAt ?? context.date).timeIntervalSinceReferenceDate
            let place = RestDotPlace(travel: travel, ends: ends, now: now)
            // The bar widens out of the rail as the rest opens, on the opening's time.
            let opened = place.sinceLog / (SetMotion.closeStart + SetMotion.close)
            RestBarView(route: route, grown: min(max(opened, 0), 1))
            if place.sinceLog < SetMotion.restLeave {
                let shape = leaving(place)
                shape.tinted(blue: shape.blue)
            } else {
                PulseShape.fill(
                    route: route,
                    top: route.length * place.tail,
                    along: route.length * place.share,
                    size: size,
                    barWidth: barWidth,
                )
                .fill(.pp(.restFill))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            origin = route.points.first
            barTop = route.point(at: route.length * SetMotion.restSpan.lowerBound)
        }
    }

    private typealias Circle = PulseShape.Circle

    /// The leaving leg, from where the node was at the log (`origin`) to where the crawl sets
    /// off, as the rows close and the rest opens: the node rises with its row closing, and taken
    /// from the node as it moves, the dot stalled on the screen as the rows rose under it.
    private func leaving(_ place: RestDotPlace) -> PulseShape {
        let node = route.points.first ?? .zero
        let from = origin ?? node
        let now = route.point(at: route.length * SetMotion.restSpan.lowerBound)
        // Aimed at where the bar's top will be once the rows have closed, worked out from how
        // far it has come on the close's curve: aimed at where it was, the dot ran backward on
        // the screen as the bar's top rose past it with the rows.
        let start = barTop ?? now
        let closed = CGFloat(SetMotion.closed(at: place.sinceLog))
        let to = closed < 0.02 ? now : CGPoint(
            x: start.x + (now.x - start.x) / closed,
            y: start.y + (now.y - start.y) / closed,
        )
        let leg = RailRoute.line(from: from, to: to)
        // The crawl's speed, against the leg's own average over the way its leading edge runs,
        // so the two meet.
        let end = place.crawl * route.length * (SetMotion.restLeave - SetMotion.travelStart)
            / max(leg.length + (barWidth - size) / 2, 1)
        return PulseShape(
            time: place.sinceLog,
            route: leg,
            size: size,
            restingSize: restingSize,
            leg: .leave(end: end, barWidth: barWidth),
            nodeLeft: node,
        )
    }
}
