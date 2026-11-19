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

    /// Where the dot is at `date`, how fast it goes, and how dim, for the move's pulse to set off
    /// from as the rest ends.
    public func handoff(at date: Date) -> RestHandoff {
        let now = (heldAt ?? date).timeIntervalSinceReferenceDate
        let place = RestDotPlace(travel: self, ends: ends.timeIntervalSinceReferenceDate, now: now)
        return RestHandoff(share: place.share, speed: place.speed, dim: place.dim)
    }
}

/// Where the move's pulse sets off after a rest: the dot's place along the stretch from the node
/// left to the next one's, from 0 to 1, its speed in stretches a second, and how dim its green is.
public struct RestHandoff: Equatable, Sendable {
    public var share: Double
    public var speed: Double
    public var dim: Double
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
    /// How dim the green is, from 0 at full green.
    let dim: Double

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
        } else {
            let gone = ends > setOff
                ? max((min(now, ends + Self.overrun) - setOff) / (ends - setOff), 0) : 1
            share = min(span.lowerBound + (span.upperBound - span.lowerBound) * gone, 0.98)
            speed = crawl
        }
        // The rest's end as it is, not as it glides: the countdown turns to the new time at once,
        // and the beat with it, not once for each second the glide passes.
        let left = travel.ends.timeIntervalSinceReferenceDate - now
        // Since the countdown's figure last turned, as it does on each whole second left: full
        // green as it turns.
        let beat = left > 0 ? CurrentPulse.dim(phase: left.rounded(.up) - left) : 0
        // Out of the node's slow pulse into the rest's, over the leaving leg.
        let into = min(max(sinceLog / SetMotion.restLeave, 0), 1)
        let node = CurrentPulse.dim(at: Date(timeIntervalSinceReferenceDate: now))
        dim = node * (1 - into) + beat * into
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
/// (`PulseShape.Leg.leave`); then a circle at its place in the rest, its size held. Its green
/// dims and comes back as the current node's does, but once a second, full as the countdown's
/// figure turns, read from the same `ends` as the countdown, so they cannot drift; through the
/// leaving leg it moves over from the node's slower pulse. `ends` animates: after a + or −, the
/// dot glides to its new place on the tap's animation.
struct RailTravelDot<ID: Hashable>: View, Animatable {
    let travel: RailTravel<ID>
    let route: RailRoute
    /// `travel.ends`, as it animates.
    var ends: Double
    @ScaledMetric(relativeTo: .body) private var size = currentNodeSize
    @ScaledMetric(relativeTo: .body) private var restingSize = railNodeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isPulseHeld) private var isPulseHeld
    /// Where the node left was at the log, which the leaving leg sets off from.
    @State private var origin: CGPoint?

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
            let dim = reduceMotion || isPulseHeld ? 0 : place.dim
            if place.sinceLog < SetMotion.restLeave {
                dimmed(leaving(place), by: dim)
            } else {
                let point = route.point(at: route.length * place.share)
                dimmed(Circle(center: point, radius: size / 2).path, by: dim)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { origin = route.points.first }
    }

    private typealias Circle = PulseShape.Circle

    /// The leaving leg, from where the node was at the log (`origin`) to where the crawl sets
    /// off, as the rows close and the rest opens: the node rises with its row closing, and taken
    /// from the node as it moves, the dot stalled on the screen as the rows rose under it.
    private func leaving(_ place: RestDotPlace) -> PulseShape {
        let node = route.points.first ?? .zero
        let from = origin ?? node
        let to = route.point(at: route.length * SetMotion.restSpan.lowerBound)
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

    private func dimmed(_ shape: some Shape, by dim: Double) -> some View {
        shape.fill(.pp(.accent))
            .overlay { shape.fill(.pp(.background)).opacity(dim) }
    }
}
