import SwiftUI

/// A dot traveling along a rail for the length of a rest, from the node of the row left to the
/// next row's, which it reaches as the rest ends. A + or − moves `starts` and `ends`, so the dot
/// jumps to its new place; while paused (`heldAt`), it holds.
public struct RailTravel<ID: Hashable>: Equatable {
    public var from: ID
    public var to: ID
    public var starts: Date
    public var ends: Date
    public var heldAt: Date?

    public init(from: ID, to: ID, starts: Date, ends: Date, heldAt: Date?) {
        self.from = from
        self.to = to
        self.starts = starts
        self.ends = ends
        self.heldAt = heldAt
    }

    /// How far along, from 0 at the node left to 1 at the next, at `date`.
    func fraction(at date: Date) -> Double {
        let span = ends.timeIntervalSince(starts)
        guard span > 0 else { return 1 }
        return min(max((heldAt ?? date).timeIntervalSince(starts) / span, 0), 1)
    }
}

/// The traveling dot: the current node's size and green, glowing as the current node does
/// (`currentPulse(in:)`), redrawn on its own timeline over the rail, so nothing else redraws.
struct RailTravelDot<ID: Hashable>: View {
    let travel: RailTravel<ID>
    let route: RailRoute
    @ScaledMetric(relativeTo: .body) private var size = currentNodeSize

    var body: some View {
        let schedule = AnimationTimelineSchedule(
            minimumInterval: 1.0 / 30,
            paused: travel.heldAt != nil,
        )
        TimelineView(schedule) { context in
            let point = route.point(at: route.length * travel.fraction(at: context.date))
            let dot = Circle().path(in: CGRect(
                x: point.x - size / 2,
                y: point.y - size / 2,
                width: size,
                height: size,
            ))
            dot.fill(.pp(.accent)).currentPulse(in: dot)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
