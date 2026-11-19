import SwiftUI

/// A rest between two exercises on the rail, from the log to the rest's end: the stretch of rail
/// from the node of the row left to the next row's, which the dot crosses in three legs
/// (`SetMotion.restLeaveShare`). It leaves as a pulse does, from the log, and eases out over
/// `SetMotion.restLeave` into the crawl's speed; crawls at that one speed to the rest's end, its
/// place a straight line in the time gone; and, as the rest ends, the move's pulse takes it on
/// from where it is, at its speed and brightness (`handoff(at:)`). A + or − moves `ends`; while
/// paused (`heldAt`), it holds.
public struct RailTravel<ID: Hashable>: Equatable {
    public var from: ID
    public var to: ID
    /// The log.
    public var starts: Date
    /// The rest's end.
    public var ends: Date
    public var heldAt: Date?

    public init(from: ID, to: ID, starts: Date, ends: Date, heldAt: Date?) {
        self.from = from
        self.to = to
        self.starts = starts
        self.ends = ends
        self.heldAt = heldAt
    }

    /// Where the dot is at `date` and how fast it goes, for the move's pulse to set off from as
    /// the rest ends.
    public func handoff(at date: Date) -> RestHandoff {
        let now = (heldAt ?? date).timeIntervalSinceReferenceDate
        let place = RestDotPlace(travel: self, ends: ends.timeIntervalSinceReferenceDate, now: now)
        return RestHandoff(share: place.share, speed: place.speed)
    }
}

/// Where the move's pulse sets off after a rest: the dot's place along the stretch from the node
/// left to the next one's, from 0 to 1, and its speed in stretches a second.
public struct RestHandoff: Equatable, Sendable {
    public var share: Double
    public var speed: Double
}

/// The rest's dot at a time `now`, worked out from the log and the rest's end `ends`, both in
/// seconds since the reference date: one place for the drawing and the hand-off, so they agree.
nonisolated struct RestDotPlace {
    /// Seconds since the log.
    let sinceLog: Double
    /// Along the stretch, from 0 to 1.
    let share: Double
    /// In stretches a second.
    let speed: Double
    /// The crawl's speed, in stretches a second.
    let crawl: Double
    /// The crawl's speed, in the leaving leg's lengths over its travel, for its end to meet.
    let leaveEnd: Double
    /// Where the leaving leg hands over to the crawl, from 0 to 1: the crawl's place as the leg
    /// ends, a little past `SetMotion.restSpan`'s start by the share of the rest it took.
    let leaveTo: Double

    /// How long past the rest's end the dot crawls on, for the move's pulse to take it over in
    /// its first frames, where it is, with no stop at 0.
    static let overrun = 0.25

    init(travel: RailTravel<some Hashable>, ends: Double, now: Double) {
        let span = SetMotion.restSpan
        let width = span.upperBound - span.lowerBound
        let starts = travel.starts.timeIntervalSinceReferenceDate
        sinceLog = now - starts
        // The crawl's place is the share of the whole rest gone, from the log, as the bar under
        // the countdown fills (`RestProgress`), so the two always agree: the start of the span
        // at the log, its end at 0:00. Never faster than a crawl over half a second.
        let length = max(ends - starts, 0.5)
        crawl = width / length
        let crawlPlace = { (time: Double) in span.lowerBound + width * (time - starts) / length }
        leaveTo = min(crawlPlace(starts + SetMotion.restLeave), span.upperBound)
        let leaveTravel = SetMotion.restLeave - SetMotion.travelStart
        leaveEnd = crawl * leaveTravel / leaveTo
        if sinceLog < SetMotion.restLeave {
            let time = (sinceLog - SetMotion.travelStart) / leaveTravel
            share = leaveTo * SetMotion.restLeaveDistance(at: time, end: leaveEnd)
            speed = leaveTo / leaveTravel * SetMotion.restLeaveSpeed(at: time, end: leaveEnd)
        } else {
            share = min(max(crawlPlace(min(now, ends + Self.overrun)), span.lowerBound), 0.98)
            speed = crawl
        }
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
        case let .leave(end):
            (
                SetMotion.restLeaveDistance(at: time, end: end),
                SetMotion.restLeaveSpeed(at: time, end: end),
            )
        case let .arrive(start):
            (
                SetMotion.restArriveDistance(at: time, start: start),
                SetMotion.restArriveSpeed(at: time, start: start),
            )
        }
    }
}

/// The traveling dot: the current node's size and green, on its own timeline over the rail, so
/// nothing else redraws. Through the leaving leg it is a pulse's leaving leg
/// (`PulseShape.Leg.leave`); then a circle at its place in the rest, its size held, steady
/// green, read from the same `ends` as the countdown and the rest's bar under it
/// (`RestProgress`), so they cannot drift apart. Nothing else on the rail marks the rest. `ends`
/// animates: after a + or −, the dot glides to its new place on the tap's animation, as the bar
/// does.
struct RailTravelDot<ID: Hashable>: View, Animatable {
    let travel: RailTravel<ID>
    let route: RailRoute
    /// `travel.ends`, as it animates.
    var ends: Double
    @ScaledMetric(relativeTo: .body) private var size = currentNodeSize
    @ScaledMetric(relativeTo: .body) private var restingSize = railNodeSize
    /// Where the node left was at the log, which the leaving leg sets off from.
    @State private var origin: CGPoint?
    /// Where the crawl sets off was at the log, before the rows closed.
    @State private var setOff: CGPoint?

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
            if place.sinceLog < SetMotion.restLeave {
                leaving(place).fill(.pp(.accent))
            } else {
                let point = route.point(at: route.length * place.share)
                Circle(center: point, radius: size / 2).path.fill(.pp(.accent))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            origin = route.points.first
            setOff = route.point(at: route.length * RestDotPlace(
                travel: travel,
                ends: ends,
                now: travel.starts.timeIntervalSinceReferenceDate,
            ).leaveTo)
        }
    }

    private typealias Circle = PulseShape.Circle

    /// The leaving leg, from where the node was at the log (`origin`) to where the crawl sets
    /// off, as the rows close and the rest opens: the node rises with its row closing, and taken
    /// from the node as it moves, the dot stalled on the screen as the rows rose under it.
    private func leaving(_ place: RestDotPlace) -> PulseShape {
        let node = route.points.first ?? .zero
        let from = origin ?? node
        let now = route.point(at: route.length * place.leaveTo)
        // Aimed at where the crawl will set off once the rows have closed, worked out from how far
        // they have come on the close's curve: aimed at where it is on each frame, the dot ran
        // backward on the screen as that point rose past it with the rows.
        let start = setOff ?? now
        let closed = CGFloat(SetMotion.closed(at: place.sinceLog))
        let to = closed < 0.02 ? now : CGPoint(
            x: start.x + (now.x - start.x) / closed,
            y: start.y + (now.y - start.y) / closed,
        )
        let leg = RailRoute.line(from: from, to: to)
        // The crawl's speed, against the leg's own average, so the two meet.
        let end = place.crawl * route.length * (SetMotion.restLeave - SetMotion.travelStart)
            / max(leg.length, 1)
        return PulseShape(
            time: place.sinceLog,
            route: leg,
            size: size,
            restingSize: restingSize,
            leg: .leave(end: end),
            nodeLeft: node,
        )
    }
}
