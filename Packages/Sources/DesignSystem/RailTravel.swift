import SwiftUI

/// A rest between two exercises on the rail, from the log to the rest's end: the stretch of rail
/// from the node of the row left to the next row's, which the dot crosses in three legs
/// (`SetMotion.restLeaveShare`). It leaves as a pulse does, from the log; travels at one speed
/// from the leg's end to the rest's, its place a straight line in the time gone; and stops
/// short of the next node as the rest ends, where the move's pulse takes it on
/// (`RailPulse.isAfterRest`). A + or − moves `ends`; while paused (`heldAt`), it holds.
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
}

/// The traveling dot: the current node's size and full green, on its own timeline over the
/// rail, so nothing else redraws. Until the leaving leg is over it is a pulse's leaving leg
/// (`PulseShape.Leg.leave`), its green coming out of the node's dimming; then a circle at its
/// place in the rest, which swells once a second as the countdown's figure turns
/// (`SetMotion.restBeat(at:)`), read from the same `ends` as the countdown, so they cannot drift.
/// `ends` animates: after a + or −, the dot glides to its new place on the tap's animation.
struct RailTravelDot<ID: Hashable>: View, Animatable {
    let travel: RailTravel<ID>
    let route: RailRoute
    /// `travel.ends`, as it animates.
    var ends: Double
    @ScaledMetric(relativeTo: .body) private var size = currentNodeSize
    @ScaledMetric(relativeTo: .body) private var restingSize = railNodeSize

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
            let sinceLog = now - travel.starts.timeIntervalSinceReferenceDate
            let leaving = SetMotion.landing(.down)
            if sinceLog < leaving {
                let shape = PulseShape(
                    time: sinceLog,
                    route: route.part(0 ... SetMotion.restSpan.lowerBound),
                    size: size,
                    restingSize: restingSize,
                    leg: .leave,
                )
                shape.fill(.pp(.accent))
                    .currentPulse(in: shape, share: max(1 - sinceLog / leaving, 0))
            } else {
                dot(at: now, setOff: travel.starts.timeIntervalSinceReferenceDate + leaving)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The dot at `now`, in the rest, which it set off into at `setOff`.
    private func dot(at now: Double, setOff: Double) -> some View {
        let span = SetMotion.restSpan
        let gone = ends > setOff ? min(max((now - setOff) / (ends - setOff), 0), 1) : 1
        let point = route.point(
            at: route.length * (span.lowerBound + (span.upperBound - span.lowerBound) * gone),
        )
        // The rest's end as it is, not as it glides: the countdown turns to the new time at once,
        // and the beat with it, not once for each second the glide passes.
        let left = travel.ends.timeIntervalSinceReferenceDate - now
        // Since the countdown's figure last turned, as it does on each whole second left.
        let sinceTurn = left > 0 ? left.rounded(.up) - left : -1
        let beat = travel.heldAt == nil ? SetMotion.restBeat(at: sinceTurn) : 0
        let width = size * (1 + SetMotion.restBeatGrow * beat)
        return Path(ellipseIn: CGRect(
            x: point.x - width / 2,
            y: point.y - width / 2,
            width: width,
            height: width,
        ))
        .fill(.pp(.accent))
    }
}
